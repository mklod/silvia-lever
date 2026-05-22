// Last modified: 2026-05-01--2320
/*
 * Silvia Lever Coffee Machine Controller
 * Hardware revision: dual PT1000 (MAX31865), dual SSR heaters,
 * dual 3-way valves, NAU7802 scale, ADS1115 pressure sensor, single pump.
 *
 * Serial telemetry (every TELEMETRY_INTERVAL ms):
 *   DATA:state,brewTemp,steamTemp,pressure,weight,pump%,valveThermoblock,valvePump,heaterBrew,heaterSteam,brewTimer,scalesTared,heatersEnabled,brewPhase
 *
 * Commands accepted from PC:
 *   SET_TEMP BREW <°C>     SET_TEMP STEAM <°C>
 *   START_BREW             START_STEAM     START_FLUSH
 *   BEGIN_BREW / BREW_NOW  BEGIN_STEAM
 *   STOP                   ABORT
 *   TARE_SCALES            CAL_SCALE <grams>    SET_SCALE_CAL <factor>
 *   GET_STATUS             PING
 */

#include <SPI.h>
#include <Adafruit_MAX31865.h>
#include <ADS1115_WE.h>
#include <Wire.h>
#include <SparkFun_Qwiic_Scale_NAU7802_Arduino_Library.h>
#include "config.h"

// ─── Hardware objects ─────────────────────────────────────────────────────────
// Two MAX31865 on shared SPI bus, each with its own CS pin
Adafruit_MAX31865 thermoBrew  = Adafruit_MAX31865(PT1000_BREW_CS);
Adafruit_MAX31865 thermoSteam = Adafruit_MAX31865(PT1000_STEAM_CS);

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

// Sub-states inside STATE_BREWING — auto pre-infuse → ramp → manual extract.
// See config.h for the constants that govern transitions.
enum BrewPhase {
  BREW_PHASE_PREINFUSE = 0,
  BREW_PHASE_RAMP      = 1,
  BREW_PHASE_HOLD      = 2,    // closed-loop 9 bar, indefinite, until user STOP
  BREW_PHASE_EXTRACT   = 3     // pot-controlled manual override (not in auto sequence)
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
  // Runtime master switch for both SSRs. Default OFF so power-on never
  // starts heating; UI explicitly enables it before a hot test.
  bool heatersEnabled       = true;   // TEST MODE 2026-04-23: default ON; thermoblock seeks setpoint from boot

  // Brew timer (millis() timestamp of brew start; 0 = not brewing)
  unsigned long brewTimer = 0;

  // Auto pre-infuse sub-state
  BrewPhase    brewPhase     = BREW_PHASE_EXTRACT;  // default = pure manual when not actively in a managed brew
  // Stage 0: single PI(D) loop runs the entire post-preinfuse brew. Setpoint
  // slowly slews from PREINFUSE_TARGET_BAR up to BREW_TARGET_BAR at
  // BREW_SLEW_RATE, then holds. Integrator carries from PREINFUSE through
  // the whole brew — naturally adapts to whatever PWM the puck needs.
  float        brewSetpoint  = PREINFUSE_TARGET_BAR;  // current slewed target
  unsigned long brewSlewLastMs = 0;
  // PI controller state — shared by PREINFUSE and the post-preinfuse loop.
  float        pumpIntegral  = 0.0f;
  unsigned long pumpPiLastMs = 0;
  int          lastPumpPwm   = 0;   // last commanded PWM (telemetry / debug)
  // D-term state — derivative-on-measurement of pressure, low-pass filtered.
  float        pumpDLastMeas = 0.0f;
  float        pumpDFiltered = 0.0f;
  // Manual-takeover bumpless handoff: pot value at brew start (defines the
  // "rest" position) and the PWM offset captured at the moment of takeover.
  // In EXTRACT phase, PWM = constrain(potValue + handoverOffset, 0, FULL).
  int          potAtBrewStart = 0;
  int          handoverOffset = 0;
  // Auto vs manual brew mode. true = full PREINFUSE → RAMP → HOLD auto
  // sequence with manual-takeover by pot rotation. false = brew enters
  // EXTRACT immediately, pot drives PWM directly from t=0. Toggled at
  // runtime via the SET_AUTO_MODE serial command.
  bool         autoBrewMode  = false;   // default MANUAL — see SET_AUTO_MODE

  // Scale state
  bool scalesTared = false;

  // PID state for thermoblock heater
  float pidIntegral  = 0.0;
  float pidLastError = 0.0;                // retained for logging; derivative uses measurement now
  float pidLastMeasurement = 0.0;          // previous sensor reading (for derivative-on-measurement)
  float pidDerivativeFiltered = 0.0;       // low-pass filtered dM/dt
  unsigned long pidLastTime = 0;

  // Runtime-mutable PID gains (seeded from config.h #defines). Autotune writes
  // these on completion; UI can override via SET_PID <kp> <ki> <kd>.
  float kp = PID_KP;
  float ki = PID_KI;
  float kd = PID_KD;
} sys;

// PID derivative low-pass filter time constant (seconds). Limits noise
// amplification when Kd is large — τ_f should be several seconds for a thermal
// plant with multi-minute periods. Typical rule: τ_f = Kd / (Kp · N) with N=5-10;
// with Kp~47, Kd~3000, N=10 → ~6 s. 2 s is more responsive but still filters
// out the ±0.1 °C PT1000 jitter that would otherwise dominate the derivative.
const float PID_D_FILTER_TAU = 2.0;

// ─── Timing ───────────────────────────────────────────────────────────────────
unsigned long lastBrewTempRead  = 0;
unsigned long lastSteamTempRead = 0;
unsigned long lastPressureRead  = 0;
unsigned long lastSerialSend    = 0;

// Scale: non-blocking 6-sample accumulator for trimmed-mean averaging.
// At NAU7802_SPS_20 each conversion is integrated by the chip's internal sinc
// filter over 50 ms = 3 cycles of 60 Hz / 2.5 cycles of 50 Hz mains. We then
// drop the high+low of every 6-sample window and average the remaining 4 to
// catch any residual outliers (relay clicks, motor brush spikes).
const uint8_t SCALE_BUF_SIZE = 6;
long scaleBuf[SCALE_BUF_SIZE];
uint8_t scaleBufN = 0;

// ─── Autotune (relay-feedback, Åström-Hägglund) ──────────────────────────────
// Pressing AUTOTUNE in settings runs this in place of the PID. Thermoblock
// swings around setpoint under bang-bang control; we measure period Tu and
// oscillation amplitude a, compute Ku = 4h/(π·a), then emit Ziegler-Nichols
// and Tyreus-Luyben gain suggestions. Target setpoint = sys.brewTemp.
struct Autotune {
  bool active        = false;
  bool relayHigh     = true;   // current output state
  uint8_t cycle      = 0;      // completed full cycles (high→low transitions)
  unsigned long phaseStart   = 0;  // wall time of last relay flip
  unsigned long autotuneStart = 0; // hard safety timeout anchor
  float tempPeak     = -1000;  // max during high half-cycle
  float tempTrough   =  1000;  // min during low half-cycle
  float sumPeak      = 0, sumTrough = 0;  // across measured cycles
  float sumPeriod    = 0;                 // ms; sum of EVERY half-period after warmup
  uint8_t nHalfPeriods = 0;               // number of halfPeriod additions to sumPeriod
  uint8_t nMeasured  = 0;                 // full cycles (peaks) counted in peak/trough averages
  unsigned long lastLog = 0;              // serial progress throttle
} autotune;

// Tuned 2026-04-23: with 0.5 °C hysteresis the thermoblock's thermal period
// was ~2.5 min/cycle → 7 cycles couldn't fit in 10 min. Widened the band to
// 1.0 °C to roughly halve the period (faster climb back across), and bumped
// the timeout to 25 min for headroom. Amplitude measurement is still fine at
// ±1 °C — process oscillation is typically several °C wider than hysteresis.
const float AUTOTUNE_HYST     = 1.0;     // ±°C hysteresis around setpoint
const uint8_t AUTOTUNE_CYCLES = 5;       // full cycles to sample (skip first 2 as warmup)
const uint8_t AUTOTUNE_WARMUP = 2;
const unsigned long AUTOTUNE_TIMEOUT_MS = 1500000UL;  // 25 min hard cap

// Auto-prime timing
unsigned long primeStartTime    = 0;

// Communication watchdog
unsigned long lastCommandTime   = 0;
const unsigned long COMM_TIMEOUT_MS = 10000;

// Pressure zero voltage (auto-calibrated in setup)
float calibratedVZero = V_ZERO;

// ─────────────────────────────────────────────────────────────────────────────
void setup() {
  // ── Hard-reset SPI peripheral before anything else ─────────────────
  // The SPI peripheral retains stale state across reflashing. When I2C
  // libraries initialise alongside SPI, the MAX31865 can read garbage
  // (brew 363°C) unless the bus is explicitly cleaned first.
  // ── Step 0: Hard-reset SPI peripheral (matches working v2 test) ────
  pinMode(PT1000_BREW_CS, OUTPUT);  digitalWrite(PT1000_BREW_CS, HIGH);
  pinMode(PT1000_STEAM_CS, OUTPUT); digitalWrite(PT1000_STEAM_CS, HIGH);
  pinMode(PT1000_MOSI, OUTPUT);     digitalWrite(PT1000_MOSI, LOW);
  pinMode(PT1000_MISO, INPUT);
  pinMode(PT1000_CLK, OUTPUT);      digitalWrite(PT1000_CLK, LOW);
  delay(100);
  SPI.end();
  delay(50);

  // Safe state for actuators
  pinMode(PUMP_ENA_PIN,          OUTPUT); digitalWrite(PUMP_ENA_PIN, LOW);   // Pump gated OFF at boot
  pinMode(PUMP_PWM_PIN,          OUTPUT); analogWrite(PUMP_PWM_PIN, 0);
  pinMode(HEATER_BREW_PIN,       OUTPUT); analogWrite(HEATER_BREW_PIN, 0);
  pinMode(HEATER_STEAM_PIN,      OUTPUT); analogWrite(HEATER_STEAM_PIN, 0);
  pinMode(VALVE_PUMP_PIN,        OUTPUT); digitalWrite(VALVE_PUMP_PIN, LOW);
  pinMode(VALVE_THERMOBLOCK_PIN, OUTPUT); digitalWrite(VALVE_THERMOBLOCK_PIN, LOW);
  sys.state = STATE_IDLE;

  Serial.begin(SERIAL_BAUD);

  // ── Step 1: I2C bus ─────────────────────────────────────────────────
  Wire.setSDA(I2C_SDA);
  Wire.setSCL(I2C_SCL);
  Wire.begin();
  Wire.setClock(400000);
  delay(200);

  #ifndef SCALE_ONLY_DEBUG
  // ADS1115 pressure sensor
  if (!adc.init()) {
    Serial.println("ERROR:ADS1115_INIT_FAILED");
  } else {
    adc.setVoltageRange_mV(ADS1115_RANGE_4096);
    adc.setCompareChannels(ADS1115_COMP_0_GND);
    adc.setMeasureMode(ADS1115_SINGLE);
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
  #endif

  #ifndef SCALE_ONLY_DEBUG
  // ── Step 2: PT1000 sensors (SPI) ─────────────────────────────────────
  thermoBrew.begin(MAX31865_2WIRE);
  delay(200);
  thermoBrew.clearFault();

  thermoSteam.begin(MAX31865_2WIRE);
  delay(200);
  thermoSteam.clearFault();
  #endif

  // ── Step 3: NAU7802 scale — match standalone test init exactly ─────
  if (!scale.begin()) {
    Serial.println("ERROR:NAU7802_INIT_FAILED");
  } else {
    scale.setSampleRate(NAU7802_SPS_20);  // mains-aligned (50 ms = 3 cycles 60 Hz)
    scale.calibrateAFE();
    Serial.println("NAU7802 OK");
  }

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
      setValve(VALVE_PUMP_PIN, false);         // V1 LOW = pump → thermoblock
      setValve(VALVE_THERMOBLOCK_PIN, false);  // V2 LOW = thermoblock → drain
      Serial.println("OK:FLUSH_STARTED");
    } else {
      Serial.println("ERROR:NOT_IDLE");
    }
  }
  else if (cmd == "PRIME_DONE") {
    // User confirmed overflow — stop pump, advance to heating
    digitalWrite(PUMP_ENA_PIN, LOW);
    analogWrite(PUMP_PWM_PIN, 0);
    if (sys.state == STATE_PRIMING_BREW) {
      // V1 stays LOW (pump→thermoblock default) — nothing to change
      sys.state = STATE_HEATING_BREW;
      Serial.println("OK:BREW_PRIMED_HEATING");
    } else if (sys.state == STATE_PRIMING_STEAM) {
      // V1 stays HIGH (pump→boiler) — nothing to change, just stop pump and heat
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
      // Reset pump pressure controller state for a fresh brew.
      sys.pumpIntegral   = 0.0f;
      sys.pumpPiLastMs   = millis();
      sys.pumpDLastMeas  = 0.0f;
      sys.pumpDFiltered  = 0.0f;
      sys.brewSetpoint   = PREINFUSE_TARGET_BAR;
      sys.brewSlewLastMs = millis();
      // Snapshot pot position so manual takeover detection can compare
      // against it. handoverOffset stays at 0 until takeover fires.
      sys.potAtBrewStart = sys.pumpPower;
      sys.handoverOffset = 0;
      setValve(VALVE_PUMP_PIN, false);        // V1 LOW = pump → thermoblock
      setValve(VALVE_THERMOBLOCK_PIN, true);  // V2 HIGH = thermoblock → portafilter (pressure builds)
      // Stage 0: PREINFUSE → RAMP (pressure-target sweep) → HOLD (closed-loop
      // forever until user STOP) when autoBrewMode is true. Manual takeover
      // via pot rotation switches to EXTRACT mid-brew. When autoBrewMode is
      // false, brew enters EXTRACT immediately = full manual / pot control
      // from t=0. Toggle at runtime via SET_AUTO_MODE.
      sys.brewPhase = sys.autoBrewMode ? BREW_PHASE_PREINFUSE
                                        : BREW_PHASE_EXTRACT;
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
  else if (cmd.startsWith("SET_PID ")) {
    // SET_PID <kp> <ki> <kd> — overwrite runtime PID gains. Backend calls this
    // after autotune to persist gains, and on reconnect to restore saved gains.
    // Space-delimited manual parse to avoid pulling sscanf's float formatter
    // (≈20 KB) into flash.
    String rest = cmd.substring(8);
    rest.trim();
    int sp1 = rest.indexOf(' ');
    int sp2 = sp1 > 0 ? rest.indexOf(' ', sp1 + 1) : -1;
    float kp = (sp1 > 0) ? rest.substring(0, sp1).toFloat() : 0;
    float ki = (sp2 > 0) ? rest.substring(sp1 + 1, sp2).toFloat() : 0;
    float kd = (sp2 > 0) ? rest.substring(sp2 + 1).toFloat() : 0;
    // Bounds match the autotune sanity ranges — thermal plants with long Tu
    // legitimately produce large Kd via TL's Ku·Tu/6.3. Reject only garbage.
    bool sane = (sp2 > 0 && kp > 0 && kp < 500 && ki >= 0 && ki < 50 && kd >= 0 && kd < 5000);
    if (sane) {
      sys.kp = kp;
      sys.ki = ki;
      sys.kd = kd;
      sys.pidIntegral  = 0;
      sys.pidLastError = 0;
      Serial.print("OK:PID_SET:"); Serial.print(kp, 3);
      Serial.print(","); Serial.print(ki, 3);
      Serial.print(","); Serial.println(kd, 3);
    } else {
      Serial.println("ERROR:PID_GAINS_OUT_OF_RANGE");
    }
  }
  else if (cmd == "AUTOTUNE_START") {
    // Reset autotune state and kick relay cycling.
    autotune = Autotune{};  // reset to defaults
    autotune.active = true;
    autotune.autotuneStart = millis();
    autotune.phaseStart = millis();
    autotune.relayHigh = (sys.brewTempActual < sys.brewTemp);
    autotune.lastLog = 0;
    Serial.println("AUTOTUNE:STARTED");
  }
  else if (cmd == "AUTOTUNE_STOP") {
    if (autotune.active) {
      autotune.active = false;
      analogWrite(HEATER_BREW_PIN, 0);
      sys.heaterBrewOn = false;
      Serial.println("AUTOTUNE:CANCELLED");
    }
  }
  else if (cmd == "HEAT_BREW") {
    // Enter thermoblock heating without pumping water. UI calls this when the
    // user opens the brew screen; priming is optional (pump → START in overlay).
    if (sys.state == STATE_IDLE || sys.state == STATE_HEATING_BREW
        || sys.state == STATE_PRIMING_BREW) {
      sys.state = STATE_HEATING_BREW;
      Serial.println("OK:HEATING_BREW");
    } else {
      Serial.println("ERROR:BAD_STATE_FOR_HEAT_BREW");
    }
  }
  else if (cmd == "HEAT_STEAM") {
    // Enter boiler heating without pumping water.
    if (sys.state == STATE_IDLE || sys.state == STATE_HEATING_STEAM
        || sys.state == STATE_PRIMING_STEAM) {
      sys.state = STATE_HEATING_STEAM;
      Serial.println("OK:HEATING_STEAM");
    } else {
      Serial.println("ERROR:BAD_STATE_FOR_HEAT_STEAM");
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
  else if (cmd.startsWith("SET_HEATERS_ENABLE ")) {
    int v = cmd.substring(19).toInt();
    sys.heatersEnabled = (v != 0);
    if (!sys.heatersEnabled) {
      // Kill both SSRs immediately — don't wait for next PID tick
      analogWrite(HEATER_BREW_PIN,  0);
      analogWrite(HEATER_STEAM_PIN, 0);
      sys.heaterBrewOn  = false;
      sys.heaterSteamOn = false;
    }
    Serial.print("OK:HEATERS_"); Serial.println(sys.heatersEnabled ? "ENABLED" : "DISABLED");
  }
  else if (cmd.startsWith("SET_AUTO_MODE ")) {
    // SET_AUTO_MODE 1 = full PREINFUSE→RAMP→HOLD sequence on next BEGIN_BREW.
    // SET_AUTO_MODE 0 = brew enters EXTRACT immediately (full manual / pot).
    // Takes effect on the NEXT brew (mid-brew toggling not supported).
    int v = cmd.substring(14).toInt();
    sys.autoBrewMode = (v != 0);
    Serial.print("OK:AUTO_MODE_"); Serial.println(sys.autoBrewMode ? "ON" : "OFF");
  }
  else if (cmd.length() > 0) {
    Serial.print("ERROR:UNKNOWN_COMMAND:\"");
    Serial.print(cmd);
    Serial.println("\"");
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sensor reads (non-blocking)
// ─────────────────────────────────────────────────────────────────────────────
void updateSensors() {
  unsigned long now = millis();

  // ── SCALE_ONLY_DEBUG ─ all other sensors disabled to isolate scale noise
  #ifndef SCALE_ONLY_DEBUG
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
    while (adc.isBusy()) {}
    float v = adc.getResult_V();
    sys.pressure = mapPressure(v);
    lastPressureRead = millis();
  }
  #endif

  // ── Scale (NAU7802) ─────────────────────────────────────────────────────
  // Non-blocking trimmed-mean: pull a raw reading whenever the chip flags one
  // ready, accumulate 6, then drop high+low and average the middle 4. With
  // SPS=20 each output is a fresh 6×50 ms = 300 ms window, sinc-filtered and
  // outlier-trimmed. Empty-tray deadband suppresses last-digit twitch.
  if (scale.available()) {
    scaleBuf[scaleBufN++] = scale.getReading();
    if (scaleBufN >= SCALE_BUF_SIZE) {
      // insertion sort — fine for n=6
      for (uint8_t i = 1; i < SCALE_BUF_SIZE; i++) {
        long key = scaleBuf[i];
        int8_t j = i - 1;
        while (j >= 0 && scaleBuf[j] > key) {
          scaleBuf[j + 1] = scaleBuf[j];
          j--;
        }
        scaleBuf[j + 1] = key;
      }
      long sum = 0;
      for (uint8_t i = 1; i < SCALE_BUF_SIZE - 1; i++) sum += scaleBuf[i];
      long avg = sum / (SCALE_BUF_SIZE - 2);
      float w = (float)(avg - scale.getZeroOffset()) / scale.getCalibrationFactor();
      if (fabsf(w) < 0.15f) w = 0.0f;
      sys.weight = w;
      scaleBufN = 0;
    }
  }

  #ifndef SCALE_ONLY_DEBUG
  // ── Potentiometer for manual pump speed ─────────────────────────────────
  int potValue = analogRead(POT_PIN);
  sys.pumpPower = potValue / 4;  // 0–1023 → 0–255
  #endif
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
      // V1 LOW (de-energised default) → pump → thermoblock
      // V2 LOW → thermoblock → drain
      // Water flows pump→thermoblock→drain; user watches for overflow, sends PRIME_DONE.
      setValve(VALVE_PUMP_PIN, false);
      setValve(VALVE_THERMOBLOCK_PIN, false);
      digitalWrite(PUMP_ENA_PIN, HIGH);
      analogWrite(PUMP_PWM_PIN, PUMP_PWM_FULL);
      // Safety watchdog: abort if confirmation never arrives
      if (millis() - primeStartTime >= PRIME_SAFETY_TIMEOUT_MS) {
        digitalWrite(PUMP_ENA_PIN, LOW);
        analogWrite(PUMP_PWM_PIN, 0);
        sys.state = STATE_IDLE;
        Serial.println("ERROR:PRIME_BREW_TIMEOUT");
      }
      break;

    case STATE_PRIMING_STEAM:
      // V1 HIGH (energised) → pump → boiler
      // Water flows pump→boiler; user watches for overflow at boiler OPV, then PRIME_DONE.
      setValve(VALVE_PUMP_PIN, true);
      setValve(VALVE_THERMOBLOCK_PIN, false);
      digitalWrite(PUMP_ENA_PIN, HIGH);
      analogWrite(PUMP_PWM_PIN, PUMP_PWM_FULL);
      // Safety watchdog
      if (millis() - primeStartTime >= PRIME_SAFETY_TIMEOUT_MS) {
        digitalWrite(PUMP_ENA_PIN, LOW);
        analogWrite(PUMP_PWM_PIN, 0);
        setValve(VALVE_PUMP_PIN, false);
        sys.state = STATE_IDLE;
        Serial.println("ERROR:PRIME_STEAM_TIMEOUT");
      }
      break;

    case STATE_HEATING_BREW:
      // Heater handled continuously below; this case just parks the pump.
      digitalWrite(PUMP_ENA_PIN, LOW);
      analogWrite(PUMP_PWM_PIN, 0);
      break;

    case STATE_HEATING_STEAM:
      // TEST MODE 2026-04-23: boiler heater disabled (controlSteamHeater
      // not called). Pump off.
      digitalWrite(PUMP_ENA_PIN, LOW);
      analogWrite(PUMP_PWM_PIN, 0);
      break;

    case STATE_BREWING:
      // Stage 0 (slew-rate-limited single-loop):
      //   PREINFUSE: PI to 2.5 bar, exit on weight.
      //   POST-PREINFUSE: ONE PI(D) loop tracks a setpoint that slowly slews
      //   from PREINFUSE_TARGET_BAR up to BREW_TARGET_BAR at BREW_SLEW_RATE,
      //   then holds. RAMP vs HOLD is telemetry-only — controller behavior
      //   is identical. Integrator naturally adapts to whatever PWM the puck
      //   needs. Slow setpoint avoids dead-time-induced overshoot.
      digitalWrite(PUMP_ENA_PIN, HIGH);
      switch (sys.brewPhase) {
        case BREW_PHASE_PREINFUSE: {
          int pwm = pumpClosedLoop(PREINFUSE_TARGET_BAR, PREINFUSE_BASE_PWM,
                                   PREINFUSE_KP, PREINFUSE_KI, PREINFUSE_KD,
                                   PREINFUSE_MIN_PWM, PREINFUSE_MAX_PWM);
          analogWrite(PUMP_PWM_PIN, pwm);
          // Exit on first of: enough weight in cup OR elapsed > PREINFUSE_MAX_MS.
          // Time cap protects against a choked puck that never releases the
          // 1 g threshold — keeps total brew time bounded.
          unsigned long preinfuseElapsed = millis() - sys.brewTimer;
          if (sys.weight >= PREINFUSE_END_WEIGHT_G
              || preinfuseElapsed >= PREINFUSE_MAX_MS) {
            sys.brewSetpoint   = PREINFUSE_TARGET_BAR;  // slew starts here
            sys.brewSlewLastMs = millis();
            sys.brewPhase      = BREW_PHASE_RAMP;
            Serial.println("INFO:BREW_RAMP_START");
          }
          break;
        }
        case BREW_PHASE_RAMP:
        case BREW_PHASE_HOLD: {
          // Manual takeover: if the pot has been rotated past the threshold
          // since brew start, capture a bumpless PWM offset and hand control
          // to the pot. Threshold prevents jitter from triggering accidentally.
          if (abs(sys.pumpPower - sys.potAtBrewStart) > MANUAL_TAKEOVER_DELTA) {
            sys.handoverOffset = sys.lastPumpPwm - sys.pumpPower;
            sys.brewPhase = BREW_PHASE_EXTRACT;
            Serial.println("INFO:BREW_MANUAL_TAKEOVER");
            // Fall through to EXTRACT case to write PWM this iteration.
            int pwm = constrain(sys.pumpPower + sys.handoverOffset,
                                0, PUMP_PWM_FULL);
            analogWrite(PUMP_PWM_PIN, pwm);
            break;
          }
          // Slew the setpoint up at BREW_SLEW_RATE bar/sec until it reaches
          // BREW_TARGET_BAR. Once there, the phase flips to HOLD (telemetry)
          // but the controller keeps running the same loop.
          unsigned long now = millis();
          float dtSlew = (now - sys.brewSlewLastMs) * 0.001f;
          sys.brewSlewLastMs = now;
          if (dtSlew > 0.0f && dtSlew < 0.5f
              && sys.brewSetpoint < BREW_TARGET_BAR) {
            sys.brewSetpoint += BREW_SLEW_RATE * dtSlew;
            if (sys.brewSetpoint >= BREW_TARGET_BAR) {
              sys.brewSetpoint = BREW_TARGET_BAR;
              if (sys.brewPhase == BREW_PHASE_RAMP) {
                sys.brewPhase = BREW_PHASE_HOLD;
                Serial.println("INFO:BREW_HOLD_START");
              }
            }
          }
          int pwm = pumpClosedLoop(sys.brewSetpoint, BREW_BASE_PWM,
                                   BREW_KP, BREW_KI, BREW_KD,
                                   BREW_MIN_PWM, BREW_MAX_PWM);
          analogWrite(PUMP_PWM_PIN, pwm);
          break;
        }
        case BREW_PHASE_EXTRACT:
        default: {
          // Manual: pot drives PWM with bumpless offset captured at takeover.
          // pot moves down → PWM drops by the same amount (pressure tapers).
          // pot moves up   → PWM rises (more flow).
          int pwm = constrain(sys.pumpPower + sys.handoverOffset,
                              0, PUMP_PWM_FULL);
          analogWrite(PUMP_PWM_PIN, pwm);
          sys.lastPumpPwm = pwm;
          break;
        }
      }
      break;

    case STATE_STEAMING:
      // TEST MODE 2026-04-23: boiler heater disabled.
      digitalWrite(PUMP_ENA_PIN, LOW);
      analogWrite(PUMP_PWM_PIN, 0);
      break;

    case STATE_FLUSHING:
      // V1 LOW → pump → thermoblock; V2 HIGH → thermoblock → portafilter.
      // Flushes hot water through the group head for warm-up or backflushing.
      // On STOP/ABORT, safeOff() drops V2 LOW → portafilter pressure to drain.
      setValve(VALVE_PUMP_PIN, false);
      setValve(VALVE_THERMOBLOCK_PIN, true);
      digitalWrite(PUMP_ENA_PIN, HIGH);
      analogWrite(PUMP_PWM_PIN, PUMP_PWM_FULL);
      break;

    case STATE_IDLE:
    default:
      safeOff();
      break;
  }

  // TEST MODE 2026-04-23: thermoblock seeks setpoint continuously, regardless
  // of state. safeOff() above writes 0 to HEATER_BREW_PIN each IDLE tick, but
  // this call re-energises immediately per PID. Integrator reset lives in
  // stopCurrentOperation() so STOP still clears accumulated error.
  // Autotune (if active) replaces PID with relay-feedback.
  if (autotune.active) {
    autotuneStep();
  } else {
    controlBrewHeater();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Heater control
// ─────────────────────────────────────────────────────────────────────────────

// Relay-feedback autotune step. Runs at main-loop rate; bypasses PID and drives
// HEATER_BREW_PIN directly based on temp-vs-setpoint with hysteresis. Emits
// AUTOTUNE:... progress lines (throttled 1 Hz) and a final AUTOTUNE_RESULT:...
// on success or AUTOTUNE:FAIL:<reason> on timeout / out-of-range.
void autotuneStep() {
  float temp = sys.brewTempActual;
  float setpoint = sys.brewTemp;
  unsigned long now = millis();

  // Safety: hard timeout
  if (now - autotune.autotuneStart > AUTOTUNE_TIMEOUT_MS) {
    analogWrite(HEATER_BREW_PIN, 0);
    sys.heaterBrewOn = false;
    autotune.active = false;
    Serial.println("AUTOTUNE:FAIL:TIMEOUT");
    return;
  }
  // Safety: over-temp (>MAX_BREW_TEMP during autotune is same as normal)
  if (temp >= MAX_BREW_TEMP) {
    analogWrite(HEATER_BREW_PIN, 0);
    sys.heaterBrewOn = false;
    autotune.active = false;
    Serial.print("AUTOTUNE:FAIL:OVERTEMP,"); Serial.println(temp, 1);
    return;
  }

  // Track peak/trough within current half-cycle
  if (autotune.relayHigh) {
    if (temp > autotune.tempPeak) autotune.tempPeak = temp;
  } else {
    if (temp < autotune.tempTrough) autotune.tempTrough = temp;
  }

  // Relay switching logic (Schmitt trigger around setpoint)
  bool switched = false;
  if (autotune.relayHigh && temp >= setpoint + AUTOTUNE_HYST) {
    autotune.relayHigh = false;
    switched = true;
  } else if (!autotune.relayHigh && temp <= setpoint - AUTOTUNE_HYST) {
    autotune.relayHigh = true;
    switched = true;
  }

  if (switched) {
    unsigned long halfPeriod = now - autotune.phaseStart;
    autotune.phaseStart = now;

    // Count a cycle on each high→low transition (peak detected).
    if (!autotune.relayHigh) autotune.cycle++;

    // After warmup, accumulate EVERY half-period so Tu correctly sums both
    // heating and cooling halves (they're asymmetric on a thermal plant —
    // heating is fast under full 8.3 A, cooling is slow via ambient losses).
    if (autotune.cycle > AUTOTUNE_WARMUP) {
      autotune.sumPeriod += halfPeriod;
      autotune.nHalfPeriods++;

      // Snapshot peak/trough only at peak transitions (once per full cycle).
      if (!autotune.relayHigh) {
        autotune.sumPeak   += autotune.tempPeak;
        autotune.sumTrough += autotune.tempTrough;
        autotune.nMeasured++;
      }
    }

    if (!autotune.relayHigh) autotune.tempTrough = 1000;
    else                     autotune.tempPeak   = -1000;
  }

  // Drive heater
  analogWrite(HEATER_BREW_PIN, autotune.relayHigh ? HEATER_PWM_FULL : 0);
  sys.heaterBrewOn = autotune.relayHigh;

  // Progress log (1 Hz)
  if (now - autotune.lastLog >= 1000) {
    autotune.lastLog = now;
    Serial.print("AUTOTUNE:RUNNING,cycle=");
    Serial.print(autotune.cycle); Serial.print("/");
    Serial.print(AUTOTUNE_WARMUP + AUTOTUNE_CYCLES);
    Serial.print(",temp="); Serial.print(temp, 1);
    Serial.print(",relay="); Serial.println(autotune.relayHigh ? "HIGH" : "LOW");
  }

  // Completion
  if (autotune.nMeasured >= AUTOTUNE_CYCLES) {
    analogWrite(HEATER_BREW_PIN, 0);
    sys.heaterBrewOn = false;
    autotune.active = false;

    float avgPeak    = autotune.sumPeak   / autotune.nMeasured;
    float avgTrough  = autotune.sumTrough / autotune.nMeasured;
    float a          = (avgPeak - avgTrough) / 2.0f;         // °C
    // Tu = full period = sum of BOTH half-periods / number of full cycles.
    // sumPeriod holds nHalfPeriods half-periods; each full cycle has 2 halves.
    float Tu         = autotune.nHalfPeriods > 0
                         ? (autotune.sumPeriod / (autotune.nHalfPeriods / 2.0f)) / 1000.0f
                         : 0.0f;
    float h          = (float)HEATER_PWM_FULL / 2.0f;        // relay half-amplitude
    float Ku         = (4.0f * h) / (3.14159265f * a);

    // Classic Ziegler-Nichols (more aggressive)
    float kpZN = 0.6f * Ku;
    float kiZN = 1.2f * Ku / Tu;
    float kdZN = 0.075f * Ku * Tu;
    // Tyreus-Luyben (gentler — recommended for thermal plants)
    float kpTL = Ku / 3.2f;
    float kiTL = Ku / (2.2f * Tu);
    float kdTL = Ku * Tu / 6.3f;

    // Sanity-check Tyreus-Luyben gains before auto-applying. Bounds are loose
    // — thermal plants with long Tu legitimately produce large Kd via TL's
    // Ku·Tu/6.3 formula. Reject only actual garbage (NaN, sub-zero, etc.).
    bool sane = (isfinite(Ku) && isfinite(Tu) && isfinite(a)
                 && Ku > 0.1 && Ku < 5000
                 && Tu > 0.5 && Tu < 600
                 && a > 0.2
                 && kpTL > 0 && kpTL < 500
                 && kiTL > 0 && kiTL < 50
                 && kdTL > 0 && kdTL < 5000);

    Serial.print("AUTOTUNE_RESULT:");
    Serial.print("Ku="); Serial.print(Ku, 3);
    Serial.print(",Tu="); Serial.print(Tu, 2);
    Serial.print(",a="); Serial.print(a, 2);
    Serial.print(",ZN="); Serial.print(kpZN, 2); Serial.print("/");
    Serial.print(kiZN, 3); Serial.print("/"); Serial.print(kdZN, 2);
    Serial.print(",TL="); Serial.print(kpTL, 2); Serial.print("/");
    Serial.print(kiTL, 3); Serial.print("/"); Serial.print(kdTL, 2);
    Serial.print(",applied="); Serial.println(sane ? "TL" : "NONE");

    if (sane) {
      sys.kp = kpTL;
      sys.ki = kiTL;
      sys.kd = kdTL;
      sys.pidIntegral  = 0;
      sys.pidLastError = 0;
    }
  }
}

// PID controller for the thermoblock (brew) heater, with bang-bang warmup layer.
// Control strategy:
//   error > WARMUP_BAND → full PWM, integrator reset (no wind-up during climb)
//   error ≤ WARMUP_BAND → standard PID (gains from sys.kp/ki/kd, auto-tunable)
// This matches commercial espresso-controller practice: avoid PID saturation
// during the cold-start climb, then let PID handle the last 5 °C + disturbance
// rejection during brews.
const float WARMUP_BAND_C = 5.0;

// Stage 0: shared closed-loop PI controller for pump pressure. Used by all
// three managed brew phases (PREINFUSE / RAMP / HOLD) — only the target,
// gains, and clamps differ. Anti-windup: integrator only accumulates when
// the output is unsaturated, which prevents wind-up after a pressure spike
// that causes the loop to floor at minPwm for a few hundred ms.
int pumpClosedLoop(float targetBar, int basePwm, float kp, float ki, float kd,
                   int minPwm, int maxPwm) {
  unsigned long now = millis();
  float dt = (now - sys.pumpPiLastMs) * 0.001f;
  if (dt <= 0.0f || dt > 0.5f) dt = 0.0f;  // ignore first call / huge gaps
  sys.pumpPiLastMs = now;

  // D-on-measurement: derivative of pressure, low-pass filtered. Negative
  // contribution when pressure is rising → brakes pump preemptively, fights
  // pump→pressure transport lag that otherwise causes post-RAMP overshoot.
  // (D-on-measurement avoids a derivative kick on setpoint changes.)
  float dCorrection = 0.0f;
  if (kd != 0.0f && dt > 0.0f) {
    float dMeas = (sys.pressure - sys.pumpDLastMeas) / dt;
    // First-order low-pass: y += (alpha) * (x - y), alpha = dt / (tau + dt)
    float alpha = dt / (PUMP_D_FILTER_TAU + dt);
    sys.pumpDFiltered += alpha * (dMeas - sys.pumpDFiltered);
    dCorrection = -kd * sys.pumpDFiltered;  // rising pressure → negative ΔPWM
  }
  sys.pumpDLastMeas = sys.pressure;

  float err = targetBar - sys.pressure;
  float pCorrection = kp * err;
  float iCorrection = ki * sys.pumpIntegral;
  int pwm = basePwm + (int)(pCorrection + iCorrection + dCorrection);

  // Anti-windup: only integrate when output isn't saturated, OR when the
  // error would push the output back into the linear range.
  bool saturatedHigh = (pwm >= maxPwm) && (err > 0.0f);
  bool saturatedLow  = (pwm <= minPwm) && (err < 0.0f);
  if (!saturatedHigh && !saturatedLow) {
    sys.pumpIntegral += err * dt;
    sys.pumpIntegral = constrain(sys.pumpIntegral,
                                 -PUMP_PI_INTEGRAL_MAX, PUMP_PI_INTEGRAL_MAX);
  }

  int output = constrain(pwm, minPwm, maxPwm);
  sys.lastPumpPwm = output;  // for bumpless phase transitions
  return output;
}

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

  float error = target - actual;
  unsigned long now = millis();

  // Warmup: bang-bang full on until within WARMUP_BAND of setpoint.
  if (error > WARMUP_BAND_C) {
    int pwm = sys.heatersEnabled ? HEATER_PWM_FULL : 0;
    analogWrite(HEATER_BREW_PIN, pwm);
    sys.heaterBrewOn = (pwm > 0);
    sys.pidIntegral           = 0;       // no wind-up
    sys.pidLastError          = error;
    sys.pidLastMeasurement    = actual;  // so first derivative after handoff is 0
    sys.pidDerivativeFiltered = 0;
    sys.pidLastTime           = now;
    return;
  }

  // PID zone: within ±WARMUP_BAND of setpoint.
  float dt = (now - sys.pidLastTime) / 1000.0;
  if (dt <= 0.0 || dt > 5.0) dt = 0.5;
  sys.pidLastTime = now;

  sys.pidIntegral += error * dt;
  sys.pidIntegral = constrain(sys.pidIntegral, -100.0, 100.0);

  // Derivative on measurement (not error) — avoids setpoint-step kick — and
  // low-passed to suppress PT1000 noise. Sign: rising measurement should
  // reduce output (we're approaching setpoint), so the PID output term is
  // -Kd * dM/dt (equivalent to +Kd · d(error)/dt in steady-state because
  // d(error) = d(setpoint - measurement) = -dM when setpoint is constant).
  float dMeasRaw = (actual - sys.pidLastMeasurement) / dt;
  sys.pidLastMeasurement = actual;
  float alpha = dt / (PID_D_FILTER_TAU + dt);
  sys.pidDerivativeFiltered = alpha * dMeasRaw
                            + (1.0f - alpha) * sys.pidDerivativeFiltered;
  sys.pidLastError = error;

  float output = sys.kp * error
               + sys.ki * sys.pidIntegral
               - sys.kd * sys.pidDerivativeFiltered;
  int pwm = (int)constrain(output, 0, 255);
  if (!sys.heatersEnabled) pwm = 0;
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

  if (!sys.heatersEnabled) shouldHeat = false;
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
  // 16 samples at 20 SPS ≈ 800 ms of averaging for a clean zero.
  scale.calculateZeroOffset(16);
  sys.weight = 0.0f;  // reset state to match new zero immediately
  sys.scalesTared = true;
  scaleBufN = 0;      // discard partial window captured before tare
}

void calibrateScale(float knownWeight) {
  // 32 samples at 20 SPS ≈ 1.6 s averaging — enough to suppress noise.
  scale.calculateCalibrationFactor(knownWeight, 32);
  float newCal = scale.getCalibrationFactor();
  Serial.print("NEW_CAL:"); Serial.println(newCal, 4);
  scaleBufN = 0;
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
  digitalWrite(PUMP_ENA_PIN,    LOW);   // Gate pump OFF first
  analogWrite(PUMP_PWM_PIN,     0);
  analogWrite(HEATER_BREW_PIN,  0);
  analogWrite(HEATER_STEAM_PIN, 0);
  setValve(VALVE_THERMOBLOCK_PIN, false);  // thermoblock → drain
  setValve(VALVE_PUMP_PIN,        false);  // V1 LOW (de-energised); pump is off so routing doesn't matter
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
//         valvePump,heaterBrew,heaterSteam,brewTimer,scalesTared,heatersEnabled
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
  Serial.print(",");
  Serial.print(sys.heatersEnabled ? 1 : 0);
  Serial.print(",");
  Serial.print((int)sys.brewPhase);  // 0=preinfuse, 1=ramp, 2=extract
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
