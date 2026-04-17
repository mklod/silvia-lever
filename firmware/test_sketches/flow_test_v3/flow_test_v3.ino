/*
 * Flow Test v3 — Pump + Dual Valve + Flush Sequence
 * Last modified: 2026-04-09--0230
 *
 * INSTANT pot→pump response is the priority. Everything else is
 * subordinated to that goal:
 *   - analogReadAveraging(1) for fastest ADC
 *   - analogWriteFrequency(pin 9, 36621) for smoother motor PWM
 *   - Pot read + PWM write at the top of every loop iteration
 *   - Serial output and pressure read run from a separate timer slice
 *     and are skipped if loop is busy
 *   - PWM only re-written when value changes (skip redundant writes)
 *
 * ─── VALVE REFERENCE ─────────────────────────────────────────────
 *
 * D21 --- Valve 1, pump valve,
 *         routing from check valve to thermoblock/boiler
 *         switch OFF (de-energised) for thermoblock flow (default, heaviest duty)
 *         switch ON  (energised)    for boiler flow (intermittent steam use)
 *
 * D20 --- Valve 2, thermoblock valve,
 *         routing from thermoblock to portafilter/hot water out
 *         switch ON for portafilter flow (brewing)
 *         switch OFF for drain flow (priming / pressure relief)
 *
 * ─── WATER PATHS ─────────────────────────────────────────────────
 *
 * V1 OFF, V2 OFF → pump → thermoblock → drain (priming / flush)
 * V1 OFF, V2 ON  → pump → thermoblock → portafilter (brewing)
 * V1 ON,  V2 OFF → pump → boiler (boiler fill / steam priming)
 * V1 ON,  V2 ON  → pump → boiler (V2 state irrelevant when V1 routes to boiler)
 *
 * ─── SERIAL COMMANDS ─────────────────────────────────────────────
 *
 *   Manual:
 *     1 = toggle V1   |  2 = toggle V2
 *     g = pump GO     |  s = pump STOP   |  0 = ALL OFF
 *
 *   Sequences:
 *     f = START flush (V1 OFF, V2 ON, pump on)   — pump→thermoblock→portafilter
 *     x = STOP flush  (V2 OFF, V1 stays OFF)     — relieve portafilter pressure
 *     b = BOILER fill (V1 ON, V2 OFF, pump on)   — pump→boiler
 *     p = PRIME brew  (V1 OFF, V2 OFF, pump on)  — pump→thermoblock→drain
 *     h = help
 */

#include <ADS1115_WE.h>
#include <Wire.h>

// ── Pin assignments ─────────────────────────────────────────────────
#define PUMP_PWM_PIN           9
#define PUMP_ENA_PIN           3
#define POT_PIN               A0
#define VALVE_PUMP_PIN        21
#define VALVE_THERMOBLOCK_PIN 20

// ── Pump PWM range ──────────────────────────────────────────────────
// Full pot travel maps directly to 0–PUMP_MAX_PWM. Pot at zero = pump
// stopped even with ENA high — lets you kill the pump with just the knob
// during flow testing without toggling ENA.
#define PUMP_MAX_PWM  254    // Max — never use 255 (constant HIGH, no edges)

// ── I2C / Pressure ──────────────────────────────────────────────────
#define I2C_SDA  18
#define I2C_SCL  19
ADS1115_WE adc = ADS1115_WE(0x48);

float V_ZERO = 0.0;
#define V_MAX  4.5
#define P_MIN  0.0
#define P_MAX 16.0

// ── State ───────────────────────────────────────────────────────────
bool valve1On    = false;
bool valve2On    = false;
bool pumpEnabled = false;
int  lastPwm     = -1;       // Track last written PWM to skip redundant writes
float lastPressure = 0.0;
bool  pressureBusy = false;

// ─────────────────────────────────────────────────────────────────────
void setup() {
  Serial.begin(115200);
  while (!Serial && millis() < 3000) {}

  // ── Pump (safe state) ──────────────────────────────────────────
  pinMode(PUMP_ENA_PIN, OUTPUT);
  digitalWrite(PUMP_ENA_PIN, LOW);
  pinMode(PUMP_PWM_PIN, OUTPUT);
  analogWriteFrequency(PUMP_PWM_PIN, 36621);  // ~36 kHz — smooth motor PWM
  analogWrite(PUMP_PWM_PIN, 0);

  // ── Fastest analogRead — no averaging, fewest cycles ──────────
  analogReadResolution(10);
  analogReadAveraging(1);

  // ── Valves (safe state) ────────────────────────────────────────
  pinMode(VALVE_PUMP_PIN, OUTPUT);
  digitalWrite(VALVE_PUMP_PIN, LOW);
  pinMode(VALVE_THERMOBLOCK_PIN, OUTPUT);
  digitalWrite(VALVE_THERMOBLOCK_PIN, LOW);

  // ── I2C / Pressure sensor ──────────────────────────────────────
  Wire.setSDA(I2C_SDA);
  Wire.setSCL(I2C_SCL);
  Wire.begin();
  Wire.setClock(400000);

  if (!adc.init()) {
    Serial.println("ADS1115 not connected!");
  } else {
    adc.setVoltageRange_mV(ADS1115_RANGE_4096);
    adc.setCompareChannels(ADS1115_COMP_0_GND);
    adc.setMeasureMode(ADS1115_SINGLE);

    Serial.println("Calibrating pressure zero...");
    float sumV = 0.0;
    for (int i = 0; i < 50; i++) {
      adc.startSingleMeasurement();
      while (adc.isBusy()) { delay(1); }
      sumV += adc.getResult_V();
      delay(50);
    }
    V_ZERO = sumV / 50.0;
    Serial.print("Zero voltage: ");
    Serial.println(V_ZERO, 3);
  }

  printHelp();
  printState();
}

// ─────────────────────────────────────────────────────────────────────
void loop() {
  // ════════════════════════════════════════════════════════════════
  // PUMP UPDATE — absolute first priority, runs every iteration
  // Pot 0–1023 maps linearly to PWM 0–254. Pot at zero = pump off.
  // ════════════════════════════════════════════════════════════════
  if (pumpEnabled) {
    int potValue = analogRead(POT_PIN);
    int pwm = potValue >> 2;            // 0–1023 → 0–255 (bit-shift = faster)
    if (pwm > PUMP_MAX_PWM) pwm = PUMP_MAX_PWM;
    if (pwm != lastPwm) {
      analogWrite(PUMP_PWM_PIN, pwm);
      lastPwm = pwm;
    }
  }

  // ════════════════════════════════════════════════════════════════
  // SERIAL COMMANDS — cheap, runs every iteration
  // ════════════════════════════════════════════════════════════════
  if (Serial.available()) {
    handleCommand(Serial.read());
  }

  // ════════════════════════════════════════════════════════════════
  // PRESSURE READ — non-blocking, kicks off every 200ms
  // ════════════════════════════════════════════════════════════════
  static unsigned long lastPressureStart = 0;
  if (!pressureBusy && millis() - lastPressureStart >= 200) {
    lastPressureStart = millis();
    adc.startSingleMeasurement();
    pressureBusy = true;
  }
  if (pressureBusy && !adc.isBusy()) {
    lastPressure = mapPressure(adc.getResult_V());
    pressureBusy = false;
  }

  // ════════════════════════════════════════════════════════════════
  // STATUS PRINT — every 100ms
  // ════════════════════════════════════════════════════════════════
  static unsigned long lastPrint = 0;
  if (millis() - lastPrint >= 100) {
    lastPrint = millis();
    Serial.print("P:");
    Serial.print(lastPressure, 2);
    Serial.print(" pwm:");
    Serial.print(lastPwm);
    Serial.print(" V2:");
    Serial.println(valve2On ? "THERMOBLOCK" : "DRAIN");
  }
}

// ─────────────────────────────────────────────────────────────────────
void handleCommand(char cmd) {
  bool changed = false;

  switch (cmd) {
    case '1':
      valve1On = !valve1On;
      digitalWrite(VALVE_PUMP_PIN, valve1On ? HIGH : LOW);
      changed = true;
      break;

    case '2':
      valve2On = !valve2On;
      digitalWrite(VALVE_THERMOBLOCK_PIN, valve2On ? HIGH : LOW);
      changed = true;
      break;

    case 'g':
      pumpEnabled = true;
      digitalWrite(PUMP_ENA_PIN, HIGH);
      lastPwm = -1;  // force PWM rewrite on next loop
      changed = true;
      break;

    case 's':
      pumpEnabled = false;
      digitalWrite(PUMP_ENA_PIN, LOW);
      analogWrite(PUMP_PWM_PIN, 0);
      lastPwm = 0;
      changed = true;
      break;

    case '0':
      pumpEnabled = false;
      valve1On = false;
      valve2On = false;
      digitalWrite(PUMP_ENA_PIN, LOW);
      analogWrite(PUMP_PWM_PIN, 0);
      digitalWrite(VALVE_PUMP_PIN, LOW);
      digitalWrite(VALVE_THERMOBLOCK_PIN, LOW);
      lastPwm = 0;
      changed = true;
      break;

    case 'f':
      Serial.println(">>> START FLUSH (V1 OFF, V2 ON, pump on) — pump→thermoblock→portafilter");
      valve1On = false;
      valve2On = true;
      pumpEnabled = true;
      digitalWrite(VALVE_PUMP_PIN, LOW);
      digitalWrite(VALVE_THERMOBLOCK_PIN, HIGH);
      digitalWrite(PUMP_ENA_PIN, HIGH);
      lastPwm = -1;
      changed = true;
      break;

    case 'x':
      Serial.println(">>> STOP FLUSH (V2 OFF) — relieve portafilter pressure");
      valve2On = false;
      digitalWrite(VALVE_THERMOBLOCK_PIN, LOW);
      changed = true;
      break;

    case 'b':
      Serial.println(">>> BOILER FILL (V1 ON, V2 OFF, pump on) — pump→boiler");
      valve1On = true;
      valve2On = false;
      pumpEnabled = true;
      digitalWrite(VALVE_PUMP_PIN, HIGH);
      digitalWrite(VALVE_THERMOBLOCK_PIN, LOW);
      digitalWrite(PUMP_ENA_PIN, HIGH);
      lastPwm = -1;
      changed = true;
      break;

    case 'p':
      Serial.println(">>> PRIME BREW (V1 OFF, V2 OFF, pump on) — pump→thermoblock→drain");
      valve1On = false;
      valve2On = false;
      pumpEnabled = true;
      digitalWrite(VALVE_PUMP_PIN, LOW);
      digitalWrite(VALVE_THERMOBLOCK_PIN, LOW);
      digitalWrite(PUMP_ENA_PIN, HIGH);
      lastPwm = -1;
      changed = true;
      break;

    case 'h':
    case '?':
      printHelp();
      break;

    default:
      break;
  }

  if (changed) printState();
}

// ─────────────────────────────────────────────────────────────────────
float mapPressure(float voltage) {
  if (voltage < V_ZERO) voltage = V_ZERO;
  return ((voltage - V_ZERO) / (V_MAX - V_ZERO)) * (P_MAX - P_MIN) + P_MIN;
}

// ─────────────────────────────────────────────────────────────────────
void printHelp() {
  Serial.println();
  Serial.println("=== Flow Test v3 ===");
  Serial.println("  1=V1 toggle  2=V2 toggle");
  Serial.println("  g=pump GO   s=pump STOP   0=ALL OFF");
  Serial.println("  f=flush start  x=flush stop");
  Serial.println("  b=boiler fill  p=prime brew");
  Serial.println("  h=help");
  Serial.println();
}

// ─────────────────────────────────────────────────────────────────────
void printState() {
  Serial.print("V1:");
  Serial.print(valve1On ? "ON " : "OFF");
  Serial.print(" V2:");
  Serial.print(valve2On ? "ON " : "OFF");
  Serial.print(" pump:");
  Serial.print(pumpEnabled ? "RUN" : "OFF");
  Serial.print(" path: pump → ");
  if (valve1On) {
    // V1 ON = pump→boiler (V2 irrelevant)
    Serial.println("boiler");
  } else {
    // V1 OFF = pump→thermoblock; V2 routes the thermoblock outlet
    Serial.print("thermoblock → ");
    Serial.println(valve2On ? "PORTAFILTER" : "DRAIN");
  }
}
