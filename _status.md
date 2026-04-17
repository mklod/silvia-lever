# Status

## Current milestone
**Alpha — cross-platform deployed.** Stage 7 done: Windows dev + RPi touchscreen running the same `ui/source/` tree. UI launches from tap on RPi desktop, runs cleanly with or without Teensy.

## Session 2026-04-17 (01:00) — Tap-exit, Teensy hotplug hardening, pcmanfm UX
- **Exit tap zone** (`main.qml`): invisible 144×144 top-right MouseArea fires `Qt.quit()` — mirror of bottom-right E-stop. Lets the user leave fullscreen on the RPi without a keyboard.
- **pcmanfm `quick_exec=1`**: added to `~/.config/libfm/libfm.conf` so tapping a `.desktop` icon executes directly instead of popping the "Execute / Execute in Terminal" dialog. Together with `single_click=1` → true one-tap launch.
- **Teensy udev rule** (`ui/rpi/99-teensy.rules` → `/etc/udev/rules.d/`): `SUBSYSTEM=="tty", ATTRS{idVendor}=="16c0", ENV{ID_MM_DEVICE_IGNORE}="1", GROUP="dialout", MODE="0660"`. Prevents ModemManager from AT-probing the Teensy for ~5 s on hotplug (would block first UI connection). Also pins group/perms.
- **`setup_rpi.sh`** now idempotently: upserts libfm `[config]` keys, installs the udev rule + reloads, renders + trusts the desktop shortcut, runs `gdk-pixbuf-query-loaders --update-cache`.
- Verified: after all fixes, tapping the shortcut single-tap launches fullscreen with 0 dialogs.

## Session 2026-04-17 (00:52) — Tap-to-launch + disconnected navigation
- **UI runs cleanly without Teensy** — `safety_manager.py` now arm-on-first-telemetry (flag stays False until first packet), so no "EMERGENCY STOP: Communication timeout" spam when no hardware connected. Fires exactly once per disconnect event when previously armed.
- **Fixed `--mock` bug**: `qml_backend.py` now picks Mock vs Real SerialManager inside `__init__` via `_get_serial_manager_class()` helper. Previously bound at module load before CLI args parsed.
- **pcmanfm single-click**: `~/.config/libfm/libfm.conf` `single_click=1`. Touchscreen tap now launches instead of selecting/renaming.
- **Verified**: home screen rendered cleanly with RANCILIO logo visible, 0 error dialogs over 15s.

## Session 2026-04-17 (00:43) — Desktop shortcut on RPi
- Added `ui/rpi/silvia.desktop.in` template; `setup_rpi.sh` renders it to `~/Desktop/silvia.desktop` with correct paths, chmods +x, marks trusted via `gio`.
- Installed `qt6-svg-plugins` + `librsvg2-common` + ran `gdk-pixbuf-query-loaders --update-cache` → fixes both Qt's QML SVG rendering (for logo inside the app) AND pcmanfm's desktop-icon SVG rendering. Added to `setup_rpi.sh`.
- Desktop now shows "Silvia Lever" icon with logo; `dex` test confirmed shortcut launches the UI.

## Session 2026-04-17 (00:20) — RPi live deployment
- **Deployed to RPi 4B at 192.168.1.33** (user `gram`, Pi OS Bookworm, aarch64, labwc/Wayland).
- `scp`'d `ui/source/` and `ui/rpi/` to `/home/gram/silvia-lever/ui/`, ran `setup_rpi.sh`.
- **Additional packages discovered needed** (added to `setup_rpi.sh`): `qt6-wayland`, `libxcb-cursor0`, `libqt6svg6`, and the full set of `qml6-module-qtquick-*` runtime modules. `python3-pyqt6` alone is insufficient on Bookworm.
- `run_silvia.sh` updated to export Wayland env vars (XDG_RUNTIME_DIR, WAYLAND_DISPLAY, QT_QPA_PLATFORM) with fallbacks so SSH launches work.
- **Verified fullscreen 1080p rendering**: screenshot via `grim` shows BREW/STEAM/FLUSH buttons, 25°C gauge arc, DISCONNECTED indicator top-right, full debug row (SCALE/PRESS/PUMP/V1/V2) at bottom — all at correct 2× font scale. Platform shim reports `raspberry-pi`, scale 2.0, fullscreen True.
- **Pre-existing bug surfaced**: `--mock` flag ineffective because `qml_backend.py` imports `SerialManager` at module load before argparse runs. Not blocking real deployment (Teensy will be plugged in). Fix deferred.
- **SVG logo**: `libqt6svg6` installed but main.qml:339 still logs "Unsupported image format" on `logo.svg` — deferred (cosmetic only).

## Session 2026-04-16 (late) — RPi port via platform shim
- **Shared source tree**: `ui/windows/source/` → `ui/source/`. Same Python/QML runs on Windows dev and RPi.
- **`platform_shim.py`**: detects RPi via `/proc/device-tree/model`, sets `QT_SCALE_FACTOR=2.00` (1080p target = 2× the 960×540 Windows dev layout) and enables fullscreen by default. Qt renders natively at scaled size so fonts stay crisp — no QML edits required.
- **Wired into both entry points**: `main.py` (flash-and-run) and `run_silvia.py` (CLI with `--mock`/`--port`/`--fullscreen`). `apply_qt_env()` runs before `QGuiApplication` is constructed.
- **RPi launchers**: `ui/rpi/setup_rpi.sh` (apt deps, dialout group) + `ui/rpi/run_silvia.sh`.
- **Serial already cross-platform**: `serialcom/real_serial_manager.py` uses Teensy VID (0x16C0) via `pyserial`; auto-detects `COM*` on Win, `/dev/ttyACM*` on Linux. Zero code change.
- **Stale tree removed**: `ui/rpi/pyqt6/` (diverged pre-alpha), plus old `.txt`/`.rar` build notes.
- **Tooling**: `tools/flash_and_run.ps1` paths updated to `ui/source/`; `.gitignore` updated.
- **Docs**: workplan Stage 7 → DONE (80% total); key file table updated; CHANGELOG entry.
- **Verified on Windows**: `python main.py` loads QML, backend imports, Teensy auto-connects on COM9 — confirmed rename + shim didn't break anything.

## Last session (2026-04-16)
- **Scale subsystem solved end-to-end**:
  - Old load cell had silently failed (replaced with new mechanical assembly)
  - Switched to `getWeight(true, 32)` for 32-sample averaging → ±0.1g stability with cal factor 2050.65
  - Cal factor persists in `settings.json`; restored automatically on UI startup
  - Tare must still be done after each session (not persisted in firmware)
  - Scale stats writeup: `SCALE DRIFT, REPEATABILITY, UNCERTAINTY CALCULATIONS.md`
- **Plumbing finalized**:
  - Inverted V1 polarity so de-energised default = pump→thermoblock (heaviest duty)
  - V2 wiring: portafilter manifold on V2 IN; OUT2=drain (de-energised default → instant pressure relief)
  - Flush state corrected: V2 ON during flush (water through portafilter); V2 OFF on stop (drains pressure)
  - Plumbing notes + safety analysis: `PLUMBING_NOTES.md`
- **UI overhaul**:
  - Black background, white text, white-outline buttons throughout
  - Auto-save settings on each ±°C tap (no SAVE button)
  - Persistent debug row (SCALE / PRESS / PUMP / V1 / V2) at bottom of all screens with monospace, fixed-width values
  - Cal dialog: single modal, auto-tares on open, 1-second cal averaging (was 6.4 s at low SPS)
  - Brew screen: tap-anywhere-in-middle to start/stop brew, no play/pause buttons
  - Flush + Steam buttons converted to single-toggle with active "depressed" state
  - E-stop: invisible 144×144 bottom-right tap area, fires ABORT + red toast banner
- **Firmware cleanup**:
  - SPI hard-reset at top of `setup()` (Teensy 4.0 LPSPI4 stale-state fix)
  - Pump ENA on D3 (optoisolator gate, prevents boot glitch)
  - PUMP_PWM_FULL = 254 (255 outputs constant HIGH on Teensy 4.0)
  - NAU7802 init order: I2C → ADS1115 → pressure cal → PT1000 SPI → NAU7802 last
- **Tooling**:
  - `tools/flash_and_run.ps1` — one-shot compile/upload/launch via arduino-cli with `-NoCompile -NoUpload` flags for UI-only iteration
- **Doc cleanup**: removed stray `.txt` duplicates and root `settings.json`; `.gitignore` updated for `logs/`

## Next immediate task
- Plug Teensy into RPi → verify `/dev/ttyACM0` enumerates, UI flips to CONNECTED, telemetry streams
- Extended brew + steam + flush sessions on real hardware; collect logs for drift / regressions
- Tune PID after warming the thermoblock to setpoint a few times
- Autostart silvia on RPi boot (labwc-pi autostart entry or systemd --user unit)
- Decide on profile system (Stage 8) after a few weeks of real-world use

## Blockers
- None

## Key decisions
- SPI hard-reset at top of `setup()` is mandatory for SPI+I2C on Teensy 4.0
- NAU7802 init must include `setSampleRate` + `calibrateAFE`; init last in setup()
- Use `getWeight(true, 32)` for the scale read — single-call averaging gives ±0.1 g
- Both 3-way valves wired so the de-energised default is the most-used state (saves coil power and heat)
- V2 IN = portafilter manifold (NOT thermoblock outlet) — puts pressure sensor and relief path on the same physical port
- Cal factor lives in UI `settings.json` (not EEPROM); restored via SET_SCALE_CAL on connect
- Zero offset is firmware-RAM only; user re-tares each session (deliberate, simple)
- Pump ENA gate on D3 + PUMP_PWM_FULL = 254 are both required for the FG300 motor driver
- RPi port uses single shared `ui/source/` tree + `platform_shim.py` (not a separate RPi fork). Qt's native `QT_SCALE_FACTOR=2` handles 1080p scaling — no per-widget font edits needed.
- RPi Teensy access: udev rule `/etc/udev/rules.d/99-teensy.rules` is mandatory on Bookworm to stop ModemManager from hijacking the port on hotplug.
- Safety manager watchdog is arm-on-first-telemetry: never fires until a real packet has been received, so navigation-without-hardware is silent.
