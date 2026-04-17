# Silvia Lever — Changelog

## TODO
> [!tip] Queued for next build
> - Plug Teensy into RPi (via udev rule, should auto-detect as `/dev/ttyACM0` with no ModemManager interference) and verify end-to-end telemetry on the touchscreen
> - Extended brew + steam + flush sessions on real hardware
> - PID tuning once thermoblock has reached setpoint a few times
> - Profile system (Stage 8) after a few weeks of real-world use
> - Autostart silvia on RPi boot (systemd user unit or labwc-pi autostart) so no tap needed at power-on

## Build 2026-04-17--0100 — Invisible exit tap zone

- **Top-right 144×144 invisible tap area** (`exitAppBtn` in main.qml) — mirror of the bottom-right E-stop zone; tap calls `Qt.quit()` to leave fullscreen on the RPi touchscreen.

## Build 2026-04-17--0056 — Teensy hotplug hardening + pcmanfm `quick_exec=1`

- **No more "Execute / Execute in Terminal" prompt** on tap: added `quick_exec=1` to `~/.config/libfm/libfm.conf`. Both `single_click=1` and `quick_exec=1` are now upserted into `[config]` by `setup_rpi.sh` (idempotent).
- **Teensy udev rule `ui/rpi/99-teensy.rules`** → installed to `/etc/udev/rules.d/`: `SUBSYSTEM=="tty", ATTRS{idVendor}=="16c0", ENV{ID_MM_DEVICE_IGNORE}="1", GROUP="dialout", MODE="0660"`. Stops ModemManager from probing the Teensy as a cellular modem on hotplug (it would AT-command the port for several seconds and block the first UI connection). Also ensures dialout access + 0660 perms.
- `setup_rpi.sh` installs the rule and runs `udevadm control --reload-rules` + `udevadm trigger --subsystem-match=tty`.

## Build 2026-04-17--0050 — Tap-to-launch UX + disconnected navigation

- **`SafetyManager` arm-on-first-telemetry**: previously `_safety_check()` fired `emergencyStop("Communication timeout")` every tick from startup when no data had arrived — now a new `armed` flag stays False until the first telemetry packet bumps `last_data_time`, then stays armed until one timeout fires (so exactly one alert per disconnect instead of 60/min). Lets the UI launch cleanly without a Teensy attached for navigation / dev
- **`qml_backend.py` lazy SerialManager import**: introduced `_get_serial_manager_class()` helper called inside `__init__` and `_attempt_reconnection()`. Fixes pre-existing bug where `--mock` was parsed after `from qml_backend import CoffeeController` had already bound the real SerialManager
- **pcmanfm single-click launch**: `~/.config/libfm/libfm.conf` `single_click=1` — one tap on the desktop icon now launches instead of selecting-then-renaming on second tap. Touchscreen-friendly
- **Verified on RPi**: UI launched without Teensy, 0 emergency-stop dialogs in 15s, home screen rendered with RANCILIO logo (SVG now decoding after `qt6-svg-plugins`)

## Build 2026-04-17--0033 — Desktop shortcut

- **Tap-to-launch on RPi desktop**: installed `/home/gram/Desktop/silvia.desktop` that pcmanfm-pi renders as "Silvia Lever" with the logo.svg icon
- **`ui/rpi/silvia.desktop.in`** — template with `@PROJECT_DIR@` placeholder
- **`setup_rpi.sh`** now: (a) renders the template into `$HOME/Desktop/silvia.desktop`, `chmod +x`, and `gio set metadata::trusted true`; (b) installs `qt6-svg-plugins` + `librsvg2-common` and runs `gdk-pixbuf-query-loaders --update-cache` so both Qt's QML `Image` and pcmanfm's desktop icon can render SVGs
- **Verified on RPi**: desktop now shows the "Silvia Lever" label with rendered logo; `dex ~/Desktop/silvia.desktop` launches `run_silvia.py` (confirms tap will work)

## Build 2026-04-17--0020 — RPi live deployment

### Deployed + verified on RPi 4B (192.168.1.33, `gram`)
- **apt install bookworm defaults weren't sufficient** — `setup_rpi.sh` extended to include the Qt/QML runtime modules that don't come with `python3-pyqt6` alone:
  - `qt6-wayland` (Qt Wayland platform plugin — Pi OS Bookworm uses labwc/Wayland by default)
  - `libxcb-cursor0` (XWayland fallback dep)
  - `libqt6svg6` (SVG image decode for `logo.svg`)
  - `qml6-module-qtqml`, `-qtquick`, `-qtquick-window`, `-qtquick-controls`, `-qtquick-layouts`, `-qtquick-shapes`, `-qtquick-templates`, `-qtquick-effects`, `-qtquick-nativestyle`
- **`run_silvia.sh`**: exports `XDG_RUNTIME_DIR` / `WAYLAND_DISPLAY` / `QT_QPA_PLATFORM=wayland` with fallbacks so launches from SSH (without the desktop session env) still reach the compositor
- **Verified fullscreen 1920×1080 on actual touchscreen**: shim reported `raspberry-pi` / scale 2.0 / fullscreen True; QML loaded cleanly after the extra modules; debug row + buttons + gauge all rendered at correct 2× scale
- **Known limitation**: `--mock` flag on `run_silvia.py` is ineffective due to pre-existing import-order bug in `qml_backend.py` (`SerialManager` chosen at module-import time, before args parse). Not blocking — real deployment has Teensy connected

## Build 2026-04-16--2346 — Cross-platform (RPi port via shim)

### Structure
- **Single shared source tree**: renamed `ui/windows/source/` → `ui/source/` — both Windows dev and RPi deployment now run the same Python/QML code
- **Removed stale RPi tree**: `ui/rpi/pyqt6/` (pre-current-architecture — had separate `safety_manager.py`, `temperature_controller.py`, `controls/`, and an outdated `main.qml`) + the old `.txt`/`.rar` build notes
- **`ui/rpi/` now contains only launcher scripts**: `setup_rpi.sh`, `run_silvia.sh`

### Platform shim (`ui/source/platform_shim.py`)
- Detects RPi via `/proc/device-tree/model` (contains "Raspberry Pi")
- Exposes `ui_scale_factor()` → 2.0 on RPi, 1.0 on Windows
- Exposes `default_fullscreen()` → True on RPi
- `apply_qt_env()` sets `QT_SCALE_FACTOR` + `QT_ENABLE_HIGHDPI_SCALING` **before** `QGuiApplication` is constructed — Qt renders the UI at 1920×1080 with crisp fonts instead of scaling a 960×540 bitmap
- Wired into both `main.py` (flash-and-run entry) and `run_silvia.py` (CLI entry with `--mock` / `--port` / `--fullscreen` flags)

### Serial cross-platform (already was, documented)
- `serialcom/real_serial_manager.py` uses Teensy VID (0x16C0) via `pyserial` — same auto-detection works for `COM*` on Windows and `/dev/ttyACM*` on Linux. No code change needed

### RPi deployment scripts
- **`ui/rpi/setup_rpi.sh`** — one-time: `apt install python3-pyqt6 python3-pyqt6.qtquick python3-pyqt6.qtqml python3-serial`, adds user to `dialout` group
- **`ui/rpi/run_silvia.sh`** — launcher that `cd`s to `ui/source/` and execs `python3 run_silvia.py`; shim auto-applies fullscreen + 2× scale

### Tooling
- **`tools/flash_and_run.ps1`**: updated `$UiScript` / `$UiCwd` to `ui/source/`

### Docs
- **workplan.md**: Stage 7 marked DONE; key file reference table updated from `ui/windows/source/` → `ui/source/`
- **`.gitignore`**: `ui/windows/source/logs/` → `ui/source/logs/`; removed dead `ui/rpi/pyqt6/logs/` entry

### Testing checklist
> [!warning] Testing Checklist
> - [ ] Windows: `python main.py` in `ui/source/` → UI launches at 960×540 exactly as before
>   - Notes:
> - [ ] Windows: `tools/flash_and_run.ps1 -NoUpload -NoCompile` launches UI
>   - Notes:
> - [ ] RPi: `setup_rpi.sh` installs deps without error on fresh Bookworm
>   - Notes:
> - [ ] RPi: `run_silvia.sh` launches fullscreen 1920×1080 with 2× font scaling
>   - Notes:
> - [ ] RPi: Teensy auto-detected on `/dev/ttyACM0` via VID 0x16C0
>   - Notes:
> - [ ] RPi touchscreen: all tap targets hittable (brew tap area, E-stop corner, settings ±°C)
>   - Notes:

---

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
