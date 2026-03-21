# Silvia Lever — Changelog

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
