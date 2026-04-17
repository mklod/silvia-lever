# Silvia Lever — Preliminary Testing Setup

## Quick Start (Windows, no hardware)

### Prerequisites
- Python 3.12+ with `PyQt6` and `pyserial` installed
- Mock serial mode enabled in `ui/windows/source/config.py`:
  ```python
  USE_MOCK_SERIAL = True
  ```

### Launch
```
cd ui/windows/source
python main.py
```

The app opens a 960×540 window with mock telemetry streaming. It auto-enters `PRIMING_BREW` on startup.

---

## Quick Start (Windows, with Teensy hardware)

### Prerequisites
- Teensy 4.0 flashed with firmware from `firmware/silvia_lever_main/`
- `COLD_TEST_MODE` uncommented in `firmware/silvia_lever_main/config.h`
- `USE_MOCK_SERIAL = False` in `ui/windows/source/config.py`
- Teensy connected via USB (auto-detects COM port)

### Launch
```
cd ui/windows/source
python main.py
```

---

## Pre-Test Checklist (Cold Test — No Heating)

All tests below assume `COLD_TEST_MODE` is active. SSRs cannot fire.

### 0. Setup
- [ ] `config.h`: `#define COLD_TEST_MODE` is uncommented
- [ ] `config.h`: Pin assignments match physical wiring:
  - `HEATER_BREW_PIN 15` (thermoblock SSR)
  - `HEATER_STEAM_PIN 16` (boiler SSR)
  - `VALVE_PUMP_PIN 21` (VALVE1 — pump routing)
  - `VALVE_THERMOBLOCK_PIN 20` (VALVE2 — thermoblock outlet)
  - `PT1000_BREW_CS 10`, `PT1000_STEAM_CS 6`
  - `PUMP_PWM_PIN 9`, `POT_PIN A0`
  - I2C: `SDA 18`, `SCL 19`
- [ ] Firmware compiles without errors (Teensy 4.0 board selected in Arduino IDE)
- [ ] Firmware flashed to Teensy — serial monitor shows `READY`
- [ ] UI connects — status shows CONNECTED, telemetry streaming `DATA:` lines

### 1. Serial Communication
- [ ] `PING` → `PONG` (< 200ms)
- [ ] `GET_STATUS` → `STATUS:` line with all fields
- [ ] `SET_TEMP BREW 90` → `OK:BREW_TEMP_SET`
- [ ] `SET_TEMP STEAM 125` → `OK:STEAM_TEMP_SET`

### 2. Temperature Sensors (PT1000s at room temp)
- [ ] `brewTemp` reads plausible room temp (18–30°C), not 0.0 or 999
- [ ] `steamTemp` reads plausible room temp
- [ ] Warming sensor with hand → reading increases, returns to ambient
- [ ] Disconnect one PT1000 → `ERROR:PT1000_x_FAULT`, reconnect → fault clears

### 3. Pressure Sensor (ADS1115)
- [ ] At rest, `pressure` ≤ 0.3 bar
- [ ] Zero voltage printed at startup is 0.3–0.7V range

### 4. Scale (NAU7802)
- [ ] `weight` streams stable value at rest (noise ≤ ±0.5g)
- [ ] `TARE_SCALES` → weight resets to ~0g
- [ ] Known weight on scale → reading is in right ballpark (pre-calibration)
- [ ] Remove weight, re-tare → returns to ~0g, no drift over 30s

### 5. Pump + Potentiometer
- [ ] Pot at minimum → `pump%` ≈ 0
- [ ] Pot at maximum → `pump%` ≈ 100
- [ ] `START_FLUSH` → pump runs, water flows pump→thermoblock→drain; `STOP` halts

### 6. Thermoblock Priming + Brew Path
- [ ] Press BREW → `PRIMING_BREW`, overlay appears
  - `valvePump=1`, `valveTB=0`, pump running, `heaterBrew=0`
  - Water: tank → pump → thermoblock → drain
- [ ] Watch drain for overflow, press CONFIRM → pump stops, → `HEATING_BREW`
- [ ] Press CANCEL during priming → `IDLE`, overlay gone
- [ ] (Optional) Let prime timeout (2 min) → `ERROR:PRIME_BREW_TIMEOUT`
- [ ] From `HEATING_BREW`, send `BEGIN_BREW` →
  - `valvePump=1`, `valveTB=1`, pump at pot speed
  - Water: tank → pump → thermoblock → group head (pressure builds)
  - `STOP` → valves close, pump stops, pressure relieves to drain

### 7. Boiler Priming + Steam Path
- [ ] Press STEAM → `PRIMING_STEAM`, overlay appears
  - `valvePump=0`, pump running, `heaterSteam=0`
  - Water: tank → pump → boiler → boiler OPV overflow
- [ ] Watch OPV for overflow, press CONFIRM → pump stops, → `HEATING_STEAM`
- [ ] CANCEL during priming → `IDLE`

### 8. Valve Independence
- [ ] Both valves energized ONLY during `BREWING` state
- [ ] After `STOP`/`ABORT` from any state → both valves de-energize within 100ms

### 9. Communication Watchdog
- [ ] During `BREWING`, disconnect USB → Teensy stops pump/valves within ~10s

### 10. SSR Inhibit (Cold Test Confirmation)
- [ ] Multimeter on `HEATER_BREW_PIN` (D15) → 0V in any heater-active state
- [ ] Multimeter on `HEATER_STEAM_PIN` (D16) → 0V in any heater-active state

---

## Known Issues / Notes

- **Auto-start brew on launch**: The backend (`qml_backend.py:91`) auto-sends `START_BREW` 300ms after connecting. This immediately enters `PRIMING_BREW`. May want to disable for testing or change to start in `IDLE`.
- **Priming safety timeout**: 2 minutes (`PRIME_SAFETY_TIMEOUT_MS` in config.h). If you don't press CONFIRM within 2 min, pump auto-stops.
- **Boiler safety rule**: Never heat without priming first. Firmware enforces this — no code path reaches `HEATING_STEAM` without `PRIMING_STEAM` + `PRIME_DONE`.
