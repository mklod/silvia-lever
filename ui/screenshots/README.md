# UI screenshots — for design / UX iteration

Rendered straight from the live QML (`ui/source/main.qml`) via the offscreen
harness `ui/source/_render_screens.py` — these are the **real** screens, not
mockups. Drop them into a design tool for a superficial redesign pass.

- **Resolution:** 1920×1080 (the UI is laid out at a logical 960×540; the grab
  is 2× device-pixel-ratio).
- **Regenerate:** on the Pi, `cd ~/silvia-lever/ui/source && QT_QPA_PLATFORM=offscreen python3 _render_screens.py`
  then `pscp` the `screenshots/` folder back. Edit the staged property values /
  scenarios at the bottom of the harness to taste.
- Gauges are `QtQuick.Shapes`; the harness disables their FBO `layer` so the
  arcs paint under the software renderer (costs only MSAA antialiasing — the
  live machine renders them smooth on the GPU).

| File | Screen / state |
|------|----------------|
| `01_home_idle.png` | Home — both gauges, BREW/FLUSH/STEAM, boiler PRIMED |
| `02_home_setpoint_brew.png` | Home + thermoblock setpoint popup (−/+ °F, DONE) |
| `03_home_setpoint_steam.png` | Home + steam-boiler setpoint popup |
| `04_home_unprimed.png` | Home with boiler not primed (PRIME button glowing) |
| `05_brew_ready.png` | Brew screen, HEATING_BREW — "tap to start" |
| `06_brew_brewing.png` | Brew screen, BREWING — amber clock "tap clock to stop", live charts |
| `07_steam_heating.png` | Steam screen, HEATING_STEAM |
| `08_steam_ready.png` | Steam screen, STEAMING |
| `09_flush.png` | Flush screen, flushing |
| `10_settings.png` | Settings (temp setpoints, scale TARE/CAL, PID AUTOTUNE) — currently still °C, and unreachable until a re-entry gesture is wired |

> Note: the home/brew screens display °F; the settings screen is still °C
> (it's not reachable in normal use yet — see CHANGELOG TODO).
