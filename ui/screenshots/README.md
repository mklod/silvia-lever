# UI screenshots — for design / UX iteration

Rendered straight from the live QML (`ui/source/main.qml`) via the offscreen
harness `ui/source/_render_screens.py` — these are the **real** screens, not
mockups. Drop them into a design tool for a superficial redesign pass.

- **Resolution:** 1920×1080 (the UI is laid out at a logical 960×540; the grab
  is 2× device-pixel-ratio).
- **Regenerate:** on the Pi, `cd ~/silvia-lever/ui/source && QT_QPA_PLATFORM=offscreen python3 _render_screens.py`
  then `pscp` the `screenshots/` folder back. Optional 2nd arg = a brew-log
  filename to feed screen 06.
- The harness stops the mock serial feed after connect so staged state sticks,
  and disables the gauges' FBO `layer` so the `QtQuick.Shapes` arcs paint under
  the software renderer (costs only MSAA antialiasing — the live machine
  renders them smooth on the GPU).

| File | Screen / state |
|------|----------------|
| `01_home_idle.png` | Home — both gauges, BREW/FLUSH/STEAM, boiler PRIMED |
| `02_home_setpoint_brew.png` | Home + thermoblock setpoint popup (−/+ °F, DONE) |
| `03_home_setpoint_steam.png` | Home + steam-boiler setpoint popup |
| `04_home_unprimed.png` | Home with boiler not primed (PRIME button glowing) |
| `05_brew_ready.png` | Brew screen, HEATING_BREW — "tap to start" |
| `06_brew_brewing.png` | Brew screen, BREWING — **real historical brew** on the charts (`brew_2026-06-09_19-16-20`: 46 s, 9-bar shot, 42 g), amber clock "tap clock to stop" |

Screen 06's charts are a real recorded shot replayed from `brew_logs/` — this is
also the proof-of-concept for a future "replay / brew preview" feature (render a
saved brew's weight+pressure curves on the brew chart).

> All shown screens display °F.
