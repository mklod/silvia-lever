/*
 * Configuration file for Silvia Lever Coffee Machine
 * Hardware revision: dual PT1000, dual heaters, dual 3-way valves, NAU7802 scale
 * Adjust pin assignments and calibration values to match your wiring.
 */

#ifndef CONFIG_H
#define CONFIG_H

// ─── Pump ────────────────────────────────────────────────────────────────────
#define POT_PIN         A0   // Potentiometer for manual pump speed control
#define PUMP_PWM_PIN     9   // PWM output to pump motor driver
#define PUMP_ENA_PIN     3   // Optoisolator enable — HIGH to pass PWM to motor driver

// ─── Heaters (two separate SSRs) ─────────────────────────────────────────────
#define HEATER_BREW_PIN  15  // Thermoblock SSR (brew / PID controlled)
#define HEATER_STEAM_PIN 16  // Steam boiler SSR (thermostat controlled)

// ─── 3-Way Valves ────────────────────────────────────────────────────────────
// VALVE1 (VALVE_PUMP): de-energised → pump → thermoblock (default, heaviest duty)
//                      energised    → pump → boiler (intermittent steam use)
// VALVE2 (VALVE_THERMOBLOCK): energised    → thermoblock → portafilter manifold
//                             de-energised → thermoblock → drain (pressure relief)
//
// Both valves chosen so the most-used state is de-energised — saves coil power
// and heat. V2 is energised only during brewing/flushing through portafilter.
// V1 is energised only when steaming/filling boiler.
#define VALVE_PUMP_PIN         21  // VALVE1 — routes pump to thermoblock (LOW) vs boiler (HIGH)
#define VALVE_THERMOBLOCK_PIN  20  // VALVE2 — routes thermoblock outlet to drain (LOW) vs portafilter (HIGH)

// ─── PT1000 Temperature Sensors (SPI via MAX31865) ───────────────────────────
// MOSI / MISO / CLK are shared; each sensor has its own CS pin.
#define PT1000_MOSI     11
#define PT1000_MISO     12
#define PT1000_CLK      13
#define PT1000_BREW_CS  10   // Thermoblock PT1000 chip-select
#define PT1000_STEAM_CS  6   // Steam boiler PT1000 chip-select

// PT1000 calibration — verify RREF matches the resistor on your MAX31865 board.
// PT1000 boards typically use a 4.3 kΩ reference resistor (10× the PT100 value).
#define RREF     4300.0   // Reference resistor (Ω) — adjust to your board
#define RNOMINAL 1000.0   // PT1000 nominal resistance at 0°C

// ─── Pressure Sensor (ADS1115 via I2C) ───────────────────────────────────────
#define I2C_SDA         18
#define I2C_SCL         19
#define ADS1115_ADDRESS 0x48

// Pressure sensor voltage→bar mapping (auto-calibrated zero at startup)
#define V_ZERO  0.0    // Zero-pressure voltage — overwritten during setup()
#define V_MAX   4.5    // Full-scale voltage (V)
#define P_MIN   0.0    // Minimum pressure (bar)
#define P_MAX   16.0   // Maximum pressure (bar)

// ─── Scale (NAU7802 via I2C, shares bus with ADS1115) ────────────────────────
#define NAU7802_ADDRESS 0x2A   // Fixed I2C address of NAU7802
// Single calibration factor — tune with a known weight after assembly
#define SCALE_CALIB     420.0  // Placeholder; update after calibration

// ─── Default Temperature Setpoints ───────────────────────────────────────────
#define DEFAULT_BREW_TEMP   93.0   // Thermoblock target (°C)
#define DEFAULT_STEAM_TEMP 130.0   // Steam boiler target (°C)

// ─── Brew Thermoblock PID ─────────────────────────────────────────────────────
// Tune these after testing on the real machine.
#define PID_KP  30.0   // Proportional gain
#define PID_KI   0.5   // Integral gain
#define PID_KD   5.0   // Derivative gain

// ─── Steam Boiler Thermostat ─────────────────────────────────────────────────
#define STEAM_HYSTERESIS  2.0   // Switch off when within 2°C of target; on when 2°C below

// ─── Auto-Prime ──────────────────────────────────────────────────────────────
// Priming runs until the user confirms overflow via the UI (PRIME_DONE command).
// The safety timeout below is a watchdog only — it stops the pump if the UI
// never sends confirmation (e.g. disconnected). Set generously.
#define PRIME_SAFETY_TIMEOUT_MS  120000   // 2 minutes hard abort

// ─── Heater PWM ──────────────────────────────────────────────────────────────
// Used by the steam boiler thermostat (PID drives brew heater directly).
#define HEATER_PWM_FULL  255

// ─── Pump PWM ────────────────────────────────────────────────────────────────
// Max pump speed for priming/flushing. Use 254 (not 255) to ensure Teensy 4.0
// outputs actual PWM edges — analogWrite(pin, 255) produces constant HIGH
// which some motor drivers don't respond to.
#define PUMP_PWM_FULL  254

// ─── Cold Test Mode ───────────────────────────────────────────────────────────
// Uncomment to disable both SSRs completely for dry / water-flow-only testing.
// All other logic (valves, pump, sensors, serial) runs normally.
// IMPORTANT: comment this line out again before live heating use.
#define COLD_TEST_MODE

// ─── Scale-only debug ─────────────────────────────────────────────────────────
// Temporarily disables PT1000, ADS1115, and pot reads in updateSensors() to
// isolate NAU7802 scale noise. Comment out for normal operation.
// #define SCALE_ONLY_DEBUG

// ─── Timing Intervals (milliseconds) ─────────────────────────────────────────
#define TEMP_READ_INTERVAL      500   // Both PT1000s read every 500 ms
#define PRESSURE_READ_INTERVAL  130   // ADS1115 pressure read interval
#define SCALE_READ_INTERVAL      80   // NAU7802 scale read interval (can run at ~80 SPS)
#define TELEMETRY_INTERVAL      100   // DATA: packet send interval

// ─── Serial Communication ─────────────────────────────────────────────────────
#define SERIAL_BAUD 115200

// ─── Safety Limits ───────────────────────────────────────────────────────────
#define MAX_BREW_TEMP   105.0   // Firmware hard-limit for thermoblock
#define MAX_STEAM_TEMP  160.0   // Firmware hard-limit for steam boiler
#define MIN_TEMP         10.0   // Minimum plausible temperature (fault detect)

#endif // CONFIG_H
