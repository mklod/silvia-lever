# Silvia Lever — Changelog

## TODO
> [!tip] Queued for next build
> - Extended brew + steam + flush sessions on real hardware
> - PID tuning once thermoblock has reached setpoint a few times
> - Profile system (Stage 8) after a few weeks of real-world use
> - RPi sync (Stage 7) once Windows alpha is confirmed stable

## Build 2026-04-16--2255 — Alpha release

### Scale subsystem
- **Hardware failure resolved**: previous load cell had silently failed; new mechanical assembly installed and verified via `NAU7802_complete_scale` standalone test
- **±0.1 g stability achieved**: switched main firmware to `scale.getWeight(true, 32)` — 32-sample averaging at 320 SPS (~100 ms internal block per read). Stats: range 0.20 g, std dev 0.05 g, mean 99.991 g vs 100 g reference (0.009 % accuracy)
- **Cal factor persists**: stored in `settings.json` as `scale_cal`, restored via `SET_SCALE_CAL` on UI connect. Python guards reject invalid cal results (negative, near-zero, or > 100000) and auto-restore previous good value
- **Cal dialog rewrite**: single modal, auto-tares on open, 1-second cal averaging (32 samples for tare / 64 for cal at 320 SPS)
- **Detailed writeup**: new `SCALE DRIFT, REPEATABILITY, UNCERTAINTY CALCULATIONS.md`

### Plumbing
- **V1 polarity inverted**: de-energised default = pump→thermoblock (heaviest duty); energised = pump→boiler. Saves coil power and heat over time
- **V2 wiring corrected**: IN = portafilter manifold; OUT2 = drain. De-energised default = manifold→drain (instant pressure relief). Energised = manifold↔thermoblock (brewing/flushing)
- **Flush state fixed**: V2 ON during flush (water through portafilter for group rinse / backflush), V2 OFF on stop (immediate pressure release to drain)
- **New docs**: `PLUMBING_NOTES.md` (full water circuit topology, valve port wiring, standing-pressure safety analysis), `silvia VALVES.md`, `silvia PINOUT.md`

### UI overhaul
- **Theme**: black background, white text, white-outline buttons (radius 12) throughout
- **Persistent debug row**: SCALE / PRESS / PUMP / V1 / V2 fields at bottom of every screen, evenly justified, monospace Consolas with fixed-width values (no twitching as digits change)
- **Settings auto-save**: each ±°C tap immediately writes to settings.json + sends `SET_TEMP` to firmware. SAVE button removed
- **Settings UI**: black bg, white outline buttons, back arrow top-left, SCALE section header, ±1°C step (was 0.5)
- **Brew screen**: huge middle tap area starts brew (when ready) or stops brew (when active); no play/stop buttons in header. Mass / Time / Thermoblock at top — Mass left-anchored, Time exactly window-centered, Thermoblock right-anchored, all monospace 48pt with leading-space sign for Mass to keep position constant
- **Charts**: dark grey background, cyan extraction line, purple pressure line, current value top-right of chart, title top-left
- **Cal dialog**: single modal, custom +/− weight selector (visible on black), CALIBRATE button, X close top-right, auto-tares on open
- **Flush + Steam buttons**: single-toggle with depressed/active visual state ("FLUSH" → "FLUSHING" / "STEAM" → "STEAMING")
- **E-stop**: invisible 144×144 tap area at bottom-right corner; fires ABORT + red toast banner top-center for 2.5 s
- **Connection status**: top-right of home screen only (hidden on other screens — assumed stable)
- **Auto-prime on connect removed**: app starts in IDLE; priming only fires when user enters brew screen
- **Cal dialog typo fix**: previously labelled `RECVIEVED` in `data_logger.py` and `visualize_log.py` → `RECEIVED`

### Firmware cleanup
- **SPI hard-reset at top of `setup()`** — required for Teensy 4.0 LPSPI4 + I2C coexistence (the 363 °C bug fix)
- **Init order locked**: SPI reset → actuator safe-state → I2C bus → ADS1115 → pressure zero → PT1000 SPI → NAU7802 last
- **Pump ENA pin D3** — optoisolator gates PWM to motor driver, LOW at boot prevents the brief startup glitch where the motor would twitch before Teensy initialized
- **PUMP_PWM_FULL = 254** — `analogWrite(pin, 255)` outputs constant HIGH (no PWM edges) on Teensy 4.0; motor driver ignores constant HIGH
- **`SCALE_ONLY_DEBUG` flag** in config.h — disables all non-scale sensors at compile time for noise isolation testing (left as a #define for future use)

### Tooling
- **`tools/flash_and_run.ps1`** — one-shot script: kills running UI/Arduino IDE → finds Teensy port via arduino-cli → compiles → uploads → relaunches UI with correct cwd
  - `-NoCompile` skips compile (uses last build)
  - `-NoUpload` skips Teensy upload (UI-only iteration)
  - `-NoUi` skips launching UI (debug via Serial Monitor)

### Test sketches added during the session
- `flow_test/`, `flow_test_v2/`, `flow_test_v3/` — pump + valve + pressure interactive tests with serial commands
- `pump_enable_test/` — ENA polarity + PWM combinations
- `scale_noise_debug/` — toggleable subsystem isolation for NAU7802 noise hunting

### Cleanup
- Removed stray `settings.json` at root (real one in `ui/windows/source/`)
- Removed obsolete `SCALE DRIFT, REPEATABILITY, UNCERTAINTY CALCULATIONS.txt` (superseded by `.md`)
- Replaced `silvia VALVES.txt` and `silvia PINOUT.txt` with `.md` versions
- `.gitignore`: added `/logs/`, `/settings.json`

### Testing checklist
> [!warning] Testing Checklist
> - [x] Scale tare → 0.0 g instantly
>   - Notes: confirmed
> - [x] Scale cal with 100 g → reads 100 g ± 0.1 g
>   - Notes: range 0.20 g, std dev 0.05 g over 776 samples
> - [x] Cal factor persists across UI restart
>   - Notes: restored on connect via SET_SCALE_CAL
> - [x] Pump runs at full speed during prime/flush; stops cleanly on stop
>   - Notes: ENA + PWM 254 working
> - [x] V1/V2 valve states correct in all firmware states
>   - Notes: debug row shows correct labels
> - [x] Flush starts water through portafilter; stop drops pressure to drain
>   - Notes: V2 ON during flush, OFF on stop
> - [x] E-stop invisible tap area triggers ABORT + toast
>   - Notes: 144×144 hit area
> - [x] Settings auto-save on each ±°C tap
>   - Notes: confirmed in settings.json after each tap
> - [ ] PID tuning verified after thermoblock reaches setpoint several times
>   - Notes: pending warm-up cycles
> - [ ] Extended session — no regressions over 30+ minute use
>   - Notes: pending

## Build 2026-04-09--0100

### Changes
- **Pump enable signal (pin D3)** added to firmware:
  - New `PUMP_ENA_PIN 3` in config.h — optoisolator gates PWM to motor driver
  - `LOW` at boot prevents pump startup glitch before Teensy initializes
  - `HIGH` in PRIMING_BREW, PRIMING_STEAM, BREWING, FLUSHING states; `LOW` everywhere else
  - Added to `safeOff()`, `PRIME_DONE` handler, and all state machine cases
- **Pump PWM full speed changed from 255 to 254**: `analogWrite(pin, 255)` on Teensy 4.0 produces constant HIGH (no PWM edges), which motor driver ignores. New `PUMP_PWM_FULL 254` in config.h ensures actual PWM output.
- **Auto-prime on startup removed**: `_auto_start_heating()` no longer fires on connect. App starts in IDLE. Priming begins when user taps Brew button and enters brew screen, where the priming overlay with CONFIRM/CANCEL is visible.
- **Mock serial disabled**: `USE_MOCK_SERIAL = False` in config.py for real hardware testing
- **Typo fixed**: RECVIEVED → RECEIVED in data_logger.py and visualize_log.py
- **Actuator safe-state restored to analogWrite**: Reverted pump/heater pins from `digitalWrite(LOW)` back to `analogWrite(pin, 0)` — FlexPWM timer needs to be configured in setup for later analogWrite calls to work
- **Pinout.txt updated**: Added pin 3 pump enable, corrected brew CS to pin 10
- **Test sketch created**: `pump_enable_test/` — cycles through ENA polarity and PWM combinations with priming valve state

### Testing Checklist
> [!warning] Testing Checklist
> - [x] PT1000 brew reads ~26°C with all I2C enabled
>   - Notes: Confirmed 26.4°C
> - [x] PT1000 steam reads ~26°C
>   - Notes: Confirmed 26.2°C
> - [x] NAU7802 scale reports weight values
>   - Notes: Working
> - [x] ADS1115 pressure sensor reports voltage
>   - Notes: Zero calibrated at 0.548V
> - [x] Pump runs during brew priming (ENA HIGH + PWM 254)
>   - Notes: Working after PWM 255→254 fix
> - [x] Valve clicks heard on priming start
>   - Notes: Working
> - [x] App starts in IDLE (no auto-prime)
>   - Notes: Confirmed
> - [ ] Priming overlay visible on brew screen with CONFIRM/CANCEL
>   - Notes:
> - [ ] CONFIRM stops pump, transitions to HEATING_BREW
>   - Notes:
> - [ ] Communication watchdog doesn't abort priming prematurely
>   - Notes:

## Build 2026-04-07--2100

### Changes
- **Two PT1000 bugs found and fixed:**
  - **Bug 1 (363°C)**: Stale SPI peripheral state on Teensy 4.0's LPSPI4 when I2C libraries linked alongside SPI. Fix: SPI hard-reset at top of `setup()`, I2C init before PT1000 init.
  - **Bug 2 (988.8°C)**: `config.h` had `PT1000_BREW_CS 8` from earlier debug — physical wiring is pin 10. Fix: restored to pin 10.
- **Init order changed in main firmware**: SPI reset → actuator safe-state (digitalWrite, not analogWrite) → I2C/NAU7802 → PT1000 last
- **NAU7802 init sequence fixed**: Added `setSampleRate(NAU7802_SPS_320)` + `calibrateAFE()` — required for stable analog front-end
- **I2C re-enabled in main firmware**: Wire.begin, ADS1115 pressure, NAU7802 scale all restored (were disabled during debug)
- **Pressure and scale loop reads re-enabled**: Uncommented ADS1115 and NAU7802 read blocks in `updateSensors()`
- **Added `#include <SPI.h>`** to main firmware for explicit SPI peripheral control
- **Added `Wire.setClock(400000)`** to I2C init (matches working standalone scale code)
- **All sensors verified working**: brew 26.4°C, steam 26.2°C, pressure 0.548V zero, scale reading
- **Comprehensive debug log written**: `firmware/PT1000_DEBUG.md` — full session narrative, what was tried, what was learned
- **Test sketches created during debug** (in `firmware/test_sketches/`):
  - `pt1000_plus_scale/` — confirmed NAU7802 as culprit
  - `pt1000_plus_relays/` — confirmed relays innocent
  - `pt1000_plus_scale_v2/` — working combined test with SPI reset fix
  - `pt1000_incremental_debug/` — multi-level compile-flag test
  - `pt1000_scale_bisect/` — I2C subsystem bisect test
  - `pt1000_cs_swap/` — CS pin swap diagnostic

### Testing Checklist
> [!warning] Testing Checklist
> - [ ] pt1000_plus_scale_v2 survives 3+ consecutive reflashes without blink between
>   - Notes:
> - [ ] Main firmware compiles and flashes cleanly
>   - Notes:
> - [ ] Brew PT1000 reads ~26°C on main firmware (with all I2C enabled)
>   - Notes:
> - [ ] Steam PT1000 reads ~26°C on main firmware
>   - Notes:
> - [ ] NAU7802 scale reports weight values (scale.begin OK, no INIT_FAILED)
>   - Notes:
> - [ ] ADS1115 pressure sensor reports voltage (adc.init OK, no INIT_FAILED)
>   - Notes:
> - [ ] Telemetry DATA: lines show non-zero pressure and weight fields
>   - Notes:
> - [ ] No PT1000_BREW_FAULT or PT1000_STEAM_FAULT errors in serial output
>   - Notes:

## Build 2026-04-06--1747

### Changes
- **QML syntax fix**: Removed extra closing brace at line 493 of `main.qml` that prevented the app from loading
- **Mock serial enabled**: Set `USE_MOCK_SERIAL = True` in config.py for desktop testing
- **Dependencies installed**: PyQt6 6.11.0 + pyserial 3.5 on Python 3.12
- **TESTING.md created**: Full preliminary testing setup guide and cold test checklist
- **App verified running**: Launches successfully in mock mode, telemetry streaming, QML renders

### Testing Checklist
> [!warning] Testing Checklist
> - [ ] App launches with `python main.py` from `ui/windows/source/`
>   - Notes: Confirmed working. Window opens, mock telemetry streams.
> - [ ] All 4 screens accessible (home, brew, steam, settings)
>   - Notes:
> - [ ] Priming overlay appears on home screen (mock auto-enters PRIMING_BREW)
>   - Notes:
> - [ ] CONFIRM and CANCEL buttons work on priming overlay
>   - Notes:
> - [ ] Temperature display shows mock values (~25°C)
>   - Notes:
> - [ ] Settings screen temp buttons (±0.5°C) adjust values
>   - Notes:

## Build 2026-03-12--1535

### Changes
- **Project restructure**: Separated firmware and UI into top-level directories
  - `firmware/silvia_lever_main/` — main Teensy firmware (was nested inside `UI/rpi/pyqt6/`)
  - `firmware/test_sketches/` — component test sketches (was `teensy test code snippets/`)
  - `ui/` — contains `windows/`, `rpi/`, `Documentation/` (was `UI/`)
- **Pin fixes in config.h** (matched to silvia PINOUT.txt):
  - `HEATER_STEAM_PIN`: 14 → 16
  - `VALVE_PUMP_PIN`: 7 → 21
  - `VALVE_THERMOBLOCK_PIN`: 8 → 20
- **PINOUT.txt updated**: Added missing steam PT1000 CS pin 6, corrected PT100→PT1000 label
- **Firmware compile fix**: Corrected NAU7802 library include from `SparkFun_NAU7802_Scale_Arduino_Library.h` to `SparkFun_Qwiic_Scale_NAU7802_Arduino_Library.h`
- **Windows executable built**: `ui/windows/dist/SilviaLever/SilviaLever.exe` via PyInstaller
  - Bundles main.qml, controls/, svgs/, settings.json
  - Build script at `ui/windows/build_exe.py` for rebuilds
- **workplan.md updated**: All file path references updated to new structure, valve pin numbers corrected

### Testing Checklist
- [ ] Firmware compiles in Arduino IDE for Teensy 4.0 without errors
  - Notes:
- [ ] Pin assignments in config.h match physical wiring on the board
  - Notes:
- [ ] `SilviaLever.exe` launches and shows the home screen
  - Notes:
- [ ] QML UI renders correctly (no missing assets/SVGs)
  - Notes:
- [ ] Mock serial mode works in exe (set `USE_MOCK_SERIAL = True` in config.py and rebuild)
  - Notes:
- [ ] Valve logic verified: priming brew energizes VALVE_PUMP only, brewing energizes both, priming steam de-energizes both, flushing energizes VALVE_PUMP only
  - Notes:
