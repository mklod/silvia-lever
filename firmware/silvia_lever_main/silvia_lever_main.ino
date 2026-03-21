/*
 * Silvia Lever Coffee Machine Controller
 * Hardware revision: dual PT1000 (MAX31865), dual SSR heaters,
 * dual 3-way valves, NAU7802 scale, ADS1115 pressure sensor, single pump.
 *
 * Serial telemetry (every TELEMETRY_INTERVAL ms):
 *   DATA:state,brewTemp,steamTemp,pressure,weight,pump%,valveThermoblock,valvePump,heaterBrew,heaterSteam,brewTimer,scalesTared
 *
 * Commands accepted from PC:
 *   SET_TEMP BREW <°C>     SET_TEMP STEAM <°C>
 *   START_BREW             START_STEAM     START_FLUSH
 *   BEGIN_BREW / BREW_NOW  BEGIN_STEAM
 *   STOP                   ABORT
 *   TARE_SCALES            CAL_SCALE <grams>    SET_SCALE_CAL <factor>
 *   GET_STATUS             PING
 */

#include <Adafruit_MAX31865.h>
#include <ADS1115_WE.h>
#include <Wire.h>
#include <SparkFun_Qwiic_Scale_NAU7802_Arduino_Library.h>
#include "config.h"

// ─── Hardware objects ─────────────────────────────────────────────────────────
// Two MAX31865 on shared SPI bus, each with its own CS pin
Adafruit_MAX31865 thermoBrew  = Adafruit_MAX31865(PT1000_BREW_CS,  PT1000_MOSI, PT1000_MISO, PT1000_CLK);
Adafruit_MAX31865 thermoSteam = Adafruit_MAX31865(PT1000_STEAM_CS, PT1000_MOSI, PT1000_MISO, PT1000_CLK);

ADS1115_WE adc = ADS1115_WE(ADS1115_ADDRESS);
NAU7802 scale;

// ─── System state ─────────────────────────────────────────────────────────────
enum SystemState {
  STATE_IDLE,
  STATE_PRIMING_BREW,     // Filling thermoblock before heating
  STATE_HEATING_BREW,
  STATE_PRIMING_STEAM,    // Filling boiler before heating
  STATE_HEATING_STEAM,
  STATE_BREWING,
  STATE_STEAMING,
  STATE_FLUSHING
};

struct SystemData {
  SystemState state = STATE_IDLE;

  // Setpoints
  float brewTemp  = DEFAULT_BREW_TEMP;
  float steamTemp = DEFAULT_STEAM_TEMP;

  // Actual sensor readings
  float brewTempActual  = 0.0;
  float steamTempActual = 0.0;
  float pressure        = 0.0;
  float weight          = 0.0;

  // Actuator state
  int  pumpPower           = 0;
  bool valveThermoblockOpen = false;  // VALVE2: thermoblock outlet → group head when true
  bool valvePumpOpen        = false;  // VALVE1: pump → thermoblock when true, → boiler when false
  bool heaterBrewOn         = false;
  bool heaterSteamOn        = false;

  // Brew timer (millis() timestamp of brew start; 0 = not brewing)
  unsigned long brewTimer = 0;

  // Scale state
  bool scalesTared = false;

  // PID state for thermoblock heater
  float pidIntegral  = 0.0;
  float pidLastError = 0.0;
  unsigned long pidLastTime = 0;
} sys;

// ─── Timing ───────────────────────────────────────────────────────────────────
unsigned long lastBrewTempRead  = 0;
unsigned long lastSteamTempRead = 0;
unsigned long lastPressureRead  = 0;
unsigned long lastScaleRead     = 0;
unsigned long lastSerialSend    = 0;

// Auto-prime timing
unsigned long primeStartTime    = 0;

// Communication watchdog
unsigned long lastCommandTime   = 0;
const unsigned long COMM_TIMEOUT_MS = 10000;

// Pressure zero voltage (auto-calibrated in setup)
float calibratedVZero = V_ZERO;

// ─────────────────────────────────────────────────────────────────────────────
void setup() {
  // Safe state first
  pinMode(PUMP_PWM_PIN,          OUTPUT); analogWrite(PUMP_PWM_PIN, 0);
  pinMode(HEATER_BREW_PIN,       OUTPUT); analogWrite(HEATER_BREW_PIN, 0);
  pinMode(HEATER_STEAM_PIN,      OUTPUT); analogWrite(HEATER_STEAM_PIN, 0);
  pinMode(VALVE_PUMP_PIN,        OUTPUT); digitalWrite(VALVE_PUMP_PIN, LOW);        // pump → boiler (safe default)
  pinMode(VALVE_THERMOBLOCK_PIN, OUTPUT); digitalWrite(VALVE_THERMOBLOCK_PIN, LOW); // thermoblock → drain (safe default)
  sys.state = STATE_IDLE;

  Serial.begin(SERIAL_BAUD);

  // ── PT1000 sensors ───────────────────────────────────────────────────────
  thermoBrew.begin(MAX31865_3WIRE);
  delay(200);
  thermoBrew.clearFault();

  thermoSteam.begin(MAX31865_3WIRE);
  delay(200);
  thermoSteam.clearFault();

  // ── I2C bus (ADS1115 + NAU7802) ──────────────────────────────────────────
  Wire.setSDA(I2C_SDA);
  Wire.setSCL(I2C_SCL);
  Wire.begin();
  delay(200);

  // ADS1115 pressure sensor
  if (!adc.init()) {
    Serial.println("ERROR:ADS1115_INIT_FAILED");
  } else {
    adc.setVoltageRange_mV(ADS1115_RANGE_4096);
    adc.setCompareChannels(ADS1115_COMP_0_GND);
    adc.setMeasureMode(ADS1115_SINGLE);
  }

  // NAU7802 scale
  if (!scale.begin()) {
    Serial.println("ERROR:NAU7802_INIT_FAILED");
  } else {
    scale.setCalibrationFactor(SCALE_CALIB);
    scale.calculateZeroOffset(64);  // Average 64 readings for zero
  }

  // ── Pressure zero calibration ────────────────────────────────────────────
  Serial.println("Calibrating pressure zero... keep sensor at rest.");
  float sumV = 0.0;
  for (int i = 0; i < 50; i++) {
    adc.startSingleMeasurement();
    while (adc.isBusy()) { delay(1); }
    sumV += adc.getResult_V();
    delay(50);
  }
  calibratedVZero = sumV / 50.0;
  Serial.print("Pressure zero voltage: ");
  Serial.println(calibratedVZero, 3);

  Serial.println("READY");
}

// ─────────────────────────────────────────────────────────────────────────────
void loop() {
  processSerialCommands();
  updateSensors();
  updateSystemLogic();
  sendTelemetry();
}

// ─────────────────────────────────────────────────────────────────────────────
// Serial command handler
// ─────────────────────────────────────────────────────────────────────────────
void processSerialCommands() {
  if (!Serial.available()) return;

  lastCommandTime = millis();
  String cmd = Serial.readStringUntil('\n');
  cmd.trim();

  if (cmd.startsWith("SET_TEMP BREW ")) {
    float t = cmd.substring(14).toFloat();
    if (t >= MIN_TEMP && t <= MAX_BREW_TEMP) {
      sys.brewTemp = t;
      Serial.println("OK:BREW_TEMP_SET");
    } else {
      Serial.println("ERROR:BREW_TEMP_OUT_OF_RANGE");
    }
  }
  else if (cmd.startsWith("SET_TEMP STEAM ")) {
    float t = cmd.substring(15).toFloat();
    if (t >= MIN_TEMP && t <= MAX_STEAM_TEMP) {
      sys.steamTemp = t;
      Serial.println("OK:STEAM_TEMP_SET");
    } else {
      Serial.println("ERROR:STEAM_TEMP_OUT_OF_RANGE");
    }
  }
  else if (cmd == "START_BREW") {
    if (sys.state == STATE_IDLE || sys.state == STATE_HEATING_BREW || sys.state == STATE_PRIMING_BREW) {
      startPrimingBrew();
      Serial.println("OK:PRIMING_BREW");
    } else {
      Serial.println("ERROR:NOT_IDLE");
    }
  }
  else if (cmd == "START_STEAM") {
    if (sys.state == STATE_IDLE) {
      startPrimingSteam();
      Serial.println("OK:PRIMING_STEAM");
    } else {
      Serial.println("ERROR:NOT_IDLE");
    }
  }
  else if (cmd == "START_FLUSH") {
    if (sys.state == STATE_IDLE) {
      sys.state = STATE_FLUSHING;
      setValve(VALVE_PUMP_PIN, true);         // pump → thermoblock
      setValve(VALVE_THERMOBLOCK_PIN, false);  // thermoblock → drain (flush path)
      Serial.println("OK:FLUSH_STARTED");
    } else {
      Serial.println("ERROR:NOT_IDLE");
    }
  }
  else if (cmd == "PRIME_DONE") {
    // User confirmed overflow — stop pump, de-energise routing valve, advance to heating
    analogWrite(PUMP_PWM_PIN, 0);
    if (sys.state == STATE_PRIMING_BREW) {
      // VALVE_THERMOBLOCK was already off (→drain); de-energise VALVE_PUMP to stop routing
      setValve(VALVE_PUMP_PIN, false);
      sys.state = STATE_HEATING_BREW;
      Serial.println("OK:BREW_PRIMED_HEATING");
    } else if (sys.state == STATE_PRIMING_STEAM) {
      // VALVE_PUMP was already off (→boiler by default); just stop pump and heat
      sys.state = STATE_HEATING_STEAM;
      Serial.println("OK:STEAM_PRIMED_HEATING");
    } else {
      Serial.println("ERROR:NOT_PRIMING");
    }
  }
  else if (cmd == "BEGIN_BREW" || cmd == "BREW_NOW") {
    if (sys.state == STATE_HEATING_BREW) {
      sys.state = STATE_BREWING;
      tareScales();
      sys.brewTimer = millis();
      sys.pidIntegral   = 0.0;
      sys.pidLastError  = 0.0;
      sys.pidLastTime   = millis();
      setValve(VALVE_PUMP_PIN, true);        // pump → thermoblock
      setValve(VALVE_THERMOBLOCK_PIN, true); // thermoblock → group head (pressure builds)
      Serial.println("OK:BREWING_STARTED");
    } else {
      Serial.println("ERROR:INVALID_STATE_FOR_BREW_NOW");
    }
  }
  else if (cmd == "BEGIN_STEAM") {
    if (sys.state == STATE_HEATING_STEAM) {
      sys.state = STATE_STEAMING;
      // No valve change — steam is delivered via the steam wand (no relay-controlled valve)
      Serial.println("OK:STEAMING_STARTED");
    } else {
      Serial.println("ERROR:INVALID_STATE_FOR_BEGIN_STEAM");
    }
  }
  else if (cmd == "STOP" || cmd == "ABORT") {
    stopCurrentOperation();
    Serial.println("OK:STOPPED");
  }
  else if (cmd == "TARE_SCALES") {
    tareScales();
    Serial.println("OK:SCALES_TARED");
  }
  else if (cmd.startsWith("CAL_SCALE ")) {
    float knownWeight = cmd.substring(10).toFloat();
    if (knownWeight > 0) {
      calibrateScale(knownWeight);
      Serial.println("OK:SCALES_CALIBRATED");
    } else {
      Serial.println("ERROR:INVALID_WEIGHT");
    }
  }
  else if (cmd.startsWith("SET_SCALE_CAL ")) {
    float cal = cmd.substring(14).toFloat();
    if (cal != 0.0) {
      scale.setCalibrationFactor(cal);
      Serial.println("OK:SCALE_CAL_SET");
    } else {
      Serial.println("ERROR:INVALID_CAL_FORMAT");
    }
  }
  else if (cmd == "GET_STATUS") {
    sendStatus();
  }
  else if (cmd == "PING") {
    Serial.println("PONG");
  }
  else if (cmd.length() > 0) {
    Serial.println("ERROR:UNKNOWN_COMMAND");
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sensor reads (non-blocking)
// ─────────────────────────────────────────────────────────────────────────────
void updateSensors() {
  unsigned long now = millis();

  // ── Thermoblock PT1000 ───────────────────────────────────────────────────
  if (now - lastBrewTempRead >= TEMP_READ_INTERVAL) {
    sys.brewTempActual = thermoBrew.temperature(RNOMINAL, RREF);
    uint8_t fault = thermoBrew.readFault();
    if (fault) {
      Serial.print("ERROR:PT1000_BREW_FAULT:0x"); Serial.println(fault, HEX);
      thermoBrew.clearFault();
    }
    lastBrewTempRead = millis();
  }

  // ── Steam boiler PT1000 ──────────────────────────────────────────────────
  now = millis();
  if (now - lastSteamTempRead >= TEMP_READ_INTERVAL) {
    sys.steamTempActual = thermoSteam.temperature(RNOMINAL, RREF);
    uint8_t fault = thermoSteam.readFault();
    if (fault) {
      Serial.print("ERROR:PT1000_STEAM_FAULT:0x"); Serial.println(fault, HEX);
      thermoSteam.clearFault();
    }
    lastSteamTempRead = millis();
  }

  // ── Pressure (ADS1115) ───────────────────────────────────────────────────
  now = millis();
  if (now - lastPressureRead >= PRESSURE_READ_INTERVAL) {
    adc.startSingleMeasurement();
    while (adc.isBusy()) { /* non-blocking alternative: skip if isBusy(); accept one cycle delay */ }
    float v = adc.getResult_V();
    sys.pressure = mapPressure(v);
    lastPressureRead = millis();
  }

  // ── Scale (NAU7802, non-blocking) ────────────────────────────────────────
  now = millis();
  if (now - lastScaleRead >= SCALE_READ_INTERVAL) {
    if (scale.available()) {
      sys.weight = scale.getWeight();
    }
    lastScaleRead = millis();
  }

  // ── Potentiometer for manual pump speed ─────────────────────────────────
  int potValue = analogRead(POT_PIN);
  sys.pumpPower = potValue / 4;  // 0–1023 → 0–255
}

// ─────────────────────────────────────────────────────────────────────────────
// System logic (state machine)
// ─────────────────────────────────────────────────────────────────────────────
void updateSystemLogic() {
  // Hold everything off until PC connects
  if (lastCommandTime == 0) {
    safeOff();
    return;
  }
  // Communication watchdog
  if (millis() - lastCommandTime > COMM_TIMEOUT_MS) {
    stopCurrentOperation();
    return;
  }

  switch (sys.state) {

    case STATE_PRIMING_BREW:
      // VALVE_PUMP on → pump routes to thermoblock; VALVE_THERMOBLOCK off → thermoblock routes to drain.
      // Water flows pump→thermoblock→drain; user watches for overflow at drain, then sends PRIME_DONE.
      setValve(VALVE_PUMP_PIN, true);
      setValve(VALVE_THERMOBLOCK_PIN, false);
      analogWrite(PUMP_PWM_PIN, HEATER_PWM_FULL);
      // Safety watchdog: abort if confirmation never arrives
      if (millis() - primeStartTime >= PRIME_SAFETY_TIMEOUT_MS) {
        analogWrite(PUMP_PWM_PIN, 0);
        setValve(VALVE_PUMP_PIN, false);
        sys.state = STATE_IDLE;
        Serial.println("ERROR:PRIME_BREW_TIMEOUT");
      }
      break;

    case STATE_PRIMING_STEAM:
      // VALVE_PUMP off (de-energised) → pump routes to boiler OPV by default.
      // Water flows pump→boiler; user watches for overflow at boiler OPV, then sends PRIME_DONE.
      setValve(VALVE_PUMP_PIN, false);
      setValve(VALVE_THERMOBLOCK_PIN, false);
      analogWrite(PUMP_PWM_PIN, HEATER_PWM_FULL);
      // Safety watchdog
      if (millis() - primeStartTime >= PRIME_SAFETY_TIMEOUT_MS) {
        analogWrite(PUMP_PWM_PIN, 0);
        sys.state = STATE_IDLE;
        Serial.println("ERROR:PRIME_STEAM_TIMEOUT");
      }
      break;

    case STATE_HEATING_BREW:
      controlBrewHeater();
      analogWrite(PUMP_PWM_PIN, 0);
      break;

    case STATE_HEATING_STEAM:
      controlSteamHeater();
      analogWrite(PUMP_PWM_PIN, 0);
      break;

    case STATE_BREWING:
      controlBrewHeater();
      analogWrite(PUMP_PWM_PIN, sys.pumpPower);
      break;

    case STATE_STEAMING:
      controlSteamHeater();
      analogWrite(PUMP_PWM_PIN, 0);
      break;

    case STATE_FLUSHING:
      // pump→thermoblock→drain (group head path, no pressure at group head)
      setValve(VALVE_PUMP_PIN, true);
      setValve(VALVE_THERMOBLOCK_PIN, false);
      analogWrite(PUMP_PWM_PIN, HEATER_PWM_FULL);
      break;

    case STATE_IDLE:
    default:
      safeOff();
      break;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Heater control
// ─────────────────────────────────────────────────────────────────────────────

// PID controller for the thermoblock (brew) heater
void controlBrewHeater() {
#ifdef COLD_TEST_MODE
  analogWrite(HEATER_BREW_PIN, 0);
  sys.heaterBrewOn = false;
  return;
#endif

  float target = sys.brewTemp;
  float actual = sys.brewTempActual;

  if (actual >= MAX_BREW_TEMP) {
    analogWrite(HEATER_BREW_PIN, 0);
    sys.heaterBrewOn = false;
    return;
  }

  unsigned long now = millis();
  float dt = (now - sys.pidLastTime) / 1000.0;
  if (dt <= 0.0 || dt > 5.0) dt = 0.5;
  sys.pidLastTime = now;

  float error = target - actual;
  sys.pidIntegral += error * dt;
  sys.pidIntegral = constrain(sys.pidIntegral, -100.0, 100.0);
  float derivative = (error - sys.pidLastError) / dt;
  sys.pidLastError = error;

  float output = PID_KP * error + PID_KI * sys.pidIntegral + PID_KD * derivative;
  int pwm = (int)constrain(output, 0, 255);
  analogWrite(HEATER_BREW_PIN, pwm);
  sys.heaterBrewOn = (pwm > 0);
}

// Simple thermostat for the steam boiler
void controlSteamHeater() {
#ifdef COLD_TEST_MODE
  analogWrite(HEATER_STEAM_PIN, 0);
  sys.heaterSteamOn = false;
  return;
#endif

  float actual = sys.steamTempActual;

  if (actual >= MAX_STEAM_TEMP) {
    analogWrite(HEATER_STEAM_PIN, 0);
    sys.heaterSteamOn = false;
    return;
  }

  bool shouldHeat = sys.heaterSteamOn
    ? (actual < sys.steamTemp)
    : (actual < sys.steamTemp - STEAM_HYSTERESIS);

  analogWrite(HEATER_STEAM_PIN, shouldHeat ? HEATER_PWM_FULL : 0);
  sys.heaterSteamOn = shouldHeat;
}

// ─────────────────────────────────────────────────────────────────────────────
// Valve control
// ─────────────────────────────────────────────────────────────────────────────
void setValve(int pin, bool open) {
  digitalWrite(pin, open ? HIGH : LOW);
  if (pin == VALVE_THERMOBLOCK_PIN) sys.valveThermoblockOpen = open;
  if (pin == VALVE_PUMP_PIN)        sys.valvePumpOpen        = open;
}

// ─────────────────────────────────────────────────────────────────────────────
// Scale operations
// ─────────────────────────────────────────────────────────────────────────────
void tareScales() {
  scale.calculateZeroOffset(32);
  sys.scalesTared = true;
}

void calibrateScale(float knownWeight) {
  scale.calculateCalibrationFactor(knownWeight, 64);
  float newCal = scale.getCalibrationFactor();
  Serial.print("NEW_CAL:"); Serial.println(newCal, 4);
}

// ─────────────────────────────────────────────────────────────────────────────
// Auto-prime helpers
// ─────────────────────────────────────────────────────────────────────────────
void startPrimingBrew() {
  sys.state      = STATE_PRIMING_BREW;
  primeStartTime = millis();
}

void startPrimingSteam() {
  sys.state      = STATE_PRIMING_STEAM;
  primeStartTime = millis();
}

// ─────────────────────────────────────────────────────────────────────────────
// Stop / safe-off helpers
// ─────────────────────────────────────────────────────────────────────────────
void stopCurrentOperation() {
  sys.state = STATE_IDLE;
  safeOff();
  sys.scalesTared = false;
  sys.brewTimer   = 0;
  sys.pidIntegral  = 0.0;
  sys.pidLastError = 0.0;
}

void safeOff() {
  analogWrite(PUMP_PWM_PIN,     0);
  analogWrite(HEATER_BREW_PIN,  0);
  analogWrite(HEATER_STEAM_PIN, 0);
  setValve(VALVE_THERMOBLOCK_PIN, false);  // thermoblock → drain
  setValve(VALVE_PUMP_PIN,        false);  // pump → boiler (safe default; boiler OPV provides back-pressure relief)
  sys.heaterBrewOn  = false;
  sys.heaterSteamOn = false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Pressure mapping
// ─────────────────────────────────────────────────────────────────────────────
float mapPressure(float voltage) {
  if (voltage < calibratedVZero) voltage = calibratedVZero;
  return ((voltage - calibratedVZero) / (V_MAX - calibratedVZero)) * (P_MAX - P_MIN) + P_MIN;
}

// ─────────────────────────────────────────────────────────────────────────────
// Telemetry output
// Fields: state,brewTemp,steamTemp,pressure,weight,pump%,valveThermoblock,
//         valvePump,heaterBrew,heaterSteam,brewTimer,scalesTared
// ─────────────────────────────────────────────────────────────────────────────
void sendTelemetry() {
  unsigned long now = millis();
  if (now - lastSerialSend < TELEMETRY_INTERVAL) return;
  lastSerialSend = now;

  Serial.print("DATA:");
  Serial.print(sys.state);                                       Serial.print(",");
  Serial.print(sys.brewTempActual,  1);                          Serial.print(",");
  Serial.print(sys.steamTempActual, 1);                          Serial.print(",");
  Serial.print(sys.pressure,        2);                          Serial.print(",");
  Serial.print(sys.weight,          1);                          Serial.print(",");
  Serial.print(map(sys.pumpPower, 0, 255, 0, 100));              Serial.print(",");
  Serial.print(sys.valveThermoblockOpen ? 1 : 0);                Serial.print(",");  // VALVE2
  Serial.print(sys.valvePumpOpen        ? 1 : 0);                Serial.print(",");  // VALVE1
  Serial.print(sys.heaterBrewOn         ? 1 : 0);                Serial.print(",");
  Serial.print(sys.heaterSteamOn        ? 1 : 0);                Serial.print(",");

  if (sys.state == STATE_BREWING && sys.brewTimer > 0) {
    Serial.print((now - sys.brewTimer) / 1000);
  } else {
    Serial.print(0);
  }
  Serial.print(",");
  Serial.print(sys.scalesTared ? 1 : 0);
  Serial.println();
}

// ─────────────────────────────────────────────────────────────────────────────
// Status response
// ─────────────────────────────────────────────────────────────────────────────
void sendStatus() {
  Serial.print("STATUS:");
  Serial.print("state=");      Serial.print(sys.state);               Serial.print(",");
  Serial.print("brewTemp=");   Serial.print(sys.brewTempActual,  1);  Serial.print(",");
  Serial.print("steamTemp=");  Serial.print(sys.steamTempActual, 1);  Serial.print(",");
  Serial.print("brewSP=");     Serial.print(sys.brewTemp,        1);  Serial.print(",");
  Serial.print("steamSP=");    Serial.print(sys.steamTemp,       1);  Serial.print(",");
  Serial.print("pressure=");   Serial.print(sys.pressure,        2);  Serial.print(",");
  Serial.print("weight=");     Serial.print(sys.weight,          1);  Serial.print(",");
  Serial.print("pump=");       Serial.print(map(sys.pumpPower, 0, 255, 0, 100)); Serial.print(",");
  Serial.print("valveTB=");    Serial.print(sys.valveThermoblockOpen ? 1 : 0);   Serial.print(",");
  Serial.print("valvePump=");  Serial.print(sys.valvePumpOpen        ? 1 : 0);   Serial.print(",");
  Serial.print("heaterBrew="); Serial.print(sys.heaterBrewOn   ? 1 : 0);         Serial.print(",");
  Serial.print("heaterSteam=");Serial.print(sys.heaterSteamOn  ? 1 : 0);
  Serial.println();
}
