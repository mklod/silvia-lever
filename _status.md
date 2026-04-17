# Status

## Current milestone
**Alpha — extended testing.** All software stages complete; Stage 5 (hardware verification) functional and ready for sustained use.

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
- Run extended brew + steam + flush sessions; collect logs for any drift / regressions
- Tune PID after warming the thermoblock to setpoint a few times
- Decide on profile system (Stage 8) after a few weeks of real-world use
- RPi sync (Stage 7) once Windows alpha confirmed stable

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
