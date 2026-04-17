/*
 * Flow Test v2 — Pump + Dual Valve Control
 * Last modified: 2026-04-09--0130
 *
 * Quick flow test for checking water paths and plumbing leaks.
 * Pump speed controlled by potentiometer. Valves toggled via serial.
 *
 * ─── VALVE REFERENCE ─────────────────────────────────────────────
 *
 * D21 --- Valve 1, pump valve,
 *         routing from check valve to thermoblock/boiler
 *         switch ON for thermoblock flow
 *
 * D20 --- Valve 2, thermoblock valve,
 *         routing from thermoblock to portafilter/hot water out
 *         switch ON for portafilter flow
 *
 * ─── WATER PATHS ─────────────────────────────────────────────────
 *
 * V1 OFF, V2 OFF → pump → boiler, thermoblock → drain
 *                   (boiler fill / default safe state)
 *
 * V1 ON,  V2 OFF → pump → thermoblock → drain
 *                   (thermoblock prime — flush to drain)
 *
 * V1 ON,  V2 ON  → pump → thermoblock → portafilter
 *                   (brewing — pressure at group head)
 *
 * V1 OFF, V2 ON  → pump → boiler, thermoblock → portafilter
 *                   (not a normal state — avoid)
 *
 * ─── SERIAL COMMANDS ─────────────────────────────────────────────
 *
 *   1  → Toggle valve 1 (pump routing)
 *   2  → Toggle valve 2 (thermoblock outlet)
 *   s  → Stop pump (ENA LOW, PWM 0)
 *   g  → Go pump (ENA HIGH, pot controls speed)
 *   0  → All off — safe state
 *
 * ─── PRESSURE SENSOR ─────────────────────────────────────────────
 *
 * ADS1115 pressure sensor reads continuously and displays bar.
 * Auto-calibrates zero at startup.
 */

#include <ADS1115_WE.h>
#include <Wire.h>

// ── Pin assignments ─────────────────────────────────────────────────
#define PUMP_PWM_PIN           9
#define PUMP_ENA_PIN           3
#define POT_PIN               A0
#define VALVE_PUMP_PIN        21   // Valve 1 — pump routing
#define VALVE_THERMOBLOCK_PIN 20   // Valve 2 — thermoblock outlet

// ── I2C / Pressure ──────────────────────────────────────────────────
#define I2C_SDA  18
#define I2C_SCL  19
ADS1115_WE adc = ADS1115_WE(0x48);

float V_ZERO = 0.0;
#define V_MAX  4.5
#define P_MIN  0.0
#define P_MAX 16.0

// ── State ───────────────────────────────────────────────────────────
bool valve1On = false;   // Valve 1 (pump routing)
bool valve2On = false;   // Valve 2 (thermoblock outlet)
bool pumpEnabled = false;

// ─────────────────────────────────────────────────────────────────────
void setup() {
  Serial.begin(115200);
  while (!Serial && millis() < 3000) {}

  // ── Pump ────────────────────────────────────────────────────────
  pinMode(PUMP_ENA_PIN, OUTPUT);
  digitalWrite(PUMP_ENA_PIN, LOW);
  pinMode(PUMP_PWM_PIN, OUTPUT);
  analogWrite(PUMP_PWM_PIN, 0);

  // ── Valves (both OFF = safe state: pump→boiler, thermoblock→drain)
  pinMode(VALVE_PUMP_PIN, OUTPUT);
  digitalWrite(VALVE_PUMP_PIN, LOW);
  pinMode(VALVE_THERMOBLOCK_PIN, OUTPUT);
  digitalWrite(VALVE_THERMOBLOCK_PIN, LOW);

  // ── I2C / Pressure sensor ──────────────────────────────────────
  Wire.setSDA(I2C_SDA);
  Wire.setSCL(I2C_SCL);
  Wire.begin();

  if (!adc.init()) {
    Serial.println("ADS1115 not connected!");
  } else {
    adc.setVoltageRange_mV(ADS1115_RANGE_4096);
    adc.setCompareChannels(ADS1115_COMP_0_GND);
    adc.setMeasureMode(ADS1115_SINGLE);

    // Auto-calibrate pressure zero
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

  // ── Print help ─────────────────────────────────────────────────
  Serial.println();
  Serial.println("=== Flow Test v2 ===");
  Serial.println("Commands:");
  Serial.println("  1 = toggle valve 1 (pump→thermoblock/boiler)");
  Serial.println("  2 = toggle valve 2 (thermoblock→portafilter/drain)");
  Serial.println("  g = pump GO (enable, pot controls speed)");
  Serial.println("  s = pump STOP");
  Serial.println("  0 = ALL OFF (safe state)");
  Serial.println();
  printState();
}

// ─────────────────────────────────────────────────────────────────────
void loop() {
  // ── Handle serial commands ─────────────────────────────────────
  if (Serial.available()) {
    char cmd = Serial.read();

    switch (cmd) {
      case '1':
        valve1On = !valve1On;
        digitalWrite(VALVE_PUMP_PIN, valve1On ? HIGH : LOW);
        break;

      case '2':
        valve2On = !valve2On;
        digitalWrite(VALVE_THERMOBLOCK_PIN, valve2On ? HIGH : LOW);
        break;

      case 'g':
        pumpEnabled = true;
        digitalWrite(PUMP_ENA_PIN, HIGH);
        break;

      case 's':
        pumpEnabled = false;
        digitalWrite(PUMP_ENA_PIN, LOW);
        analogWrite(PUMP_PWM_PIN, 0);
        break;

      case '0':
        // All off — safe state
        pumpEnabled = false;
        valve1On = false;
        valve2On = false;
        digitalWrite(PUMP_ENA_PIN, LOW);
        analogWrite(PUMP_PWM_PIN, 0);
        digitalWrite(VALVE_PUMP_PIN, LOW);
        digitalWrite(VALVE_THERMOBLOCK_PIN, LOW);
        break;

      default:
        break;
    }

    if (cmd == '1' || cmd == '2' || cmd == 'g' || cmd == 's' || cmd == '0') {
      printState();
    }
  }

  // ── Pump speed from potentiometer ──────────────────────────────
  if (pumpEnabled) {
    int potValue = analogRead(POT_PIN);
    int pwm = potValue / 4;  // 0–1023 → 0–255
    if (pwm > 254) pwm = 254;  // Cap at 254 for PWM edges
    analogWrite(PUMP_PWM_PIN, pwm);
  }

  // ── Pressure reading ───────────────────────────────────────────
  static unsigned long lastPrint = 0;
  if (millis() - lastPrint >= 250) {
    lastPrint = millis();

    adc.startSingleMeasurement();
    while (adc.isBusy()) { delay(1); }
    float voltage = adc.getResult_V();
    float pressure = mapPressure(voltage);

    int potValue = analogRead(POT_PIN);

    Serial.print("P:");
    Serial.print(pressure, 2);
    Serial.print(" bar  pot:");
    Serial.print(potValue);
    Serial.print("  V1:");
    Serial.print(valve1On ? "ON " : "OFF");
    Serial.print("  V2:");
    Serial.print(valve2On ? "ON " : "OFF");
    Serial.print("  pump:");
    Serial.println(pumpEnabled ? "RUN" : "OFF");
  }

  delay(5);
}

// ─────────────────────────────────────────────────────────────────────
float mapPressure(float voltage) {
  if (voltage < V_ZERO) voltage = V_ZERO;
  return ((voltage - V_ZERO) / (V_MAX - V_ZERO)) * (P_MAX - P_MIN) + P_MIN;
}

// ─────────────────────────────────────────────────────────────────────
void printState() {
  Serial.println("────────────────────────────────");
  Serial.print("Valve 1 (pump routing):       ");
  Serial.println(valve1On ? "ON  → pump→thermoblock" : "OFF → pump→boiler");
  Serial.print("Valve 2 (thermoblock outlet): ");
  Serial.println(valve2On ? "ON  → thermoblock→portafilter" : "OFF → thermoblock→drain");
  Serial.print("Pump:                         ");
  Serial.println(pumpEnabled ? "RUNNING (pot controls speed)" : "STOPPED");

  // Describe current water path
  Serial.print("Water path: pump → ");
  if (valve1On) {
    Serial.print("thermoblock → ");
    Serial.println(valve2On ? "PORTAFILTER (brewing)" : "DRAIN (priming)");
  } else {
    Serial.println("boiler (fill)");
    if (valve2On) {
      Serial.println("  ⚠ V2 ON with V1 OFF — unusual state");
    }
  }
  Serial.println("────────────────────────────────");
}
