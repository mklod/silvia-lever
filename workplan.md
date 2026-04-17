# Silvia Lever — Hardware Adaptation & Feature Plan

---

## Context

The existing Silvia Lever codebase was built for a single-heater, single-PT100, dual-HX711
machine. The new hardware revision changes all of those components and adds a new water-routing
architecture. This plan covers the full migration from old hardware to new, plus the UI and
profile features listed in the TO DO file. UI sources are now a **single shared tree**
(`ui/source/`) that runs on both Windows (dev) and Raspberry Pi (deployed), differentiated only
by a small `platform_shim.py`.

### New hardware summary
| Component | Old | New |
|-----------|-----|-----|
| Temperature sensors | 1× PT100 via MAX31865 | 2× PT1000 (one per heater, both via MAX31865) |
| Heaters | 1× SSR | 2× SSR — thermoblock (brew) + boiler (steam) |
| Valves | 1× relay | 2× 3-way valves — `VALVE_PUMP` (VALVE1) + `VALVE_THERMOBLOCK` (VALVE2) |
| Scale ADC | 2× HX711 | 1× NAU7802 (I2C, single load cell) |

### Power budget
| Element | Rated power | Peak current (120 V) |
|---------|-------------|----------------------|
| Thermoblock SSR | 1000 W | 8.3 A (measured) |
| Boiler SSR | ~1000 W | 8.3 A (measured) |
| **Combined (100% duty)** | **~2000 W** | **16.6 A** |

A standard US 15 A breaker trips at sustained 15 A (NEC 80% rule means ~12 A recommended
continuous). Running both SSRs at 100% simultaneously would trip the breaker — combined peak
of 16.6 A exceeds it by 11%.

**Measured boiler thermal behaviour (partial — peak confirmed, maintenance TBD):**
- Boiler draws **8.3 A at 100% duty cycle for exactly 5 minutes** from room temperature to
  steam setpoint — the heavy brass boiler full of water has high thermal mass.
- After reaching setpoint, current tapers off significantly. **Maintenance current not yet
  measured** — to be recorded once the machine is running under power (see S9.7b).
- Strategy is safe as long as (boiler maintenance A) + 8.3 A < 15 A.

**Adopted strategy — strict sequential startup:**
1. Heat **boiler only** for ~5 minutes (8.3 A, 0 A thermoblock).
2. Boiler hits setpoint → current tapers to maintenance level (TBD).
3. Begin thermoblock heat-up at full 8.3 A — total draw = 8.3 A + boiler maintenance (TBD).
4. Both elements maintained simultaneously thereafter.

Strategy is confirmed viable in principle; exact safety margin depends on S9.7b measurement.
See Stage 9 for firmware implementation details.

### Valve / water-flow logic
Both valves are 3-way directional control valves driven by a single pump. Both wired so the most-used state is **de-energised** (saves coil power and heat over long use):

| Valve | De-energised (default) | Energised |
|-------|------------------------|-----------|
| **VALVE_PUMP** (VALVE1, pin 21) | pump → thermoblock (heaviest duty) | pump → boiler (intermittent) |
| **VALVE_THERMOBLOCK** (VALVE2, pin 20) | thermoblock → drain (relief) | thermoblock → portafilter (brewing) |

**Priming thermoblock (PRIMING_BREW):** Both valves de-energised (V1 LOW = pump→thermoblock, V2 LOW = thermoblock→drain). Water flows pump→thermoblock→drain. User watches for overflow, presses CONFIRM → pump stops → HEATING_BREW.

**Priming boiler (PRIMING_STEAM):** Energise V1 (pump→boiler), V2 stays off. Water exits at boiler OPV. User watches for overflow, presses CONFIRM → pump stops, V1 de-energises → HEATING_STEAM.

**Brewing:** V1 stays de-energised (pump→thermoblock), energise V2 (thermoblock→portafilter). Pressure builds at portafilter manifold; OPV limits max pressure. STOP → V2 de-energises (thermoblock→drain, instant pressure relief) + pump stops.

**Steaming:** No valve changes — steam delivered via the steam wand.

**Flushing:** Both valves de-energised (V1 LOW = pump→thermoblock, V2 LOW = thermoblock→drain).

---

## Overall Progress

**Estimated overall completion: ~62%**

```
Stage 1 – Firmware hardware drivers    ██████████  100 %  DONE
Stage 2 – Firmware system logic        ██████████  100 %  DONE  (incl. PRIME_DONE, safety timeout)
Stage 3 – Python backend               ██████████  100 %  DONE  (incl. primeDone() slot, mock update)
Stage 4 – UI / QML                     ██████████  100 %  DONE  (incl. priming overlays, touch buttons)
Stage 5 – Hardware verification        ██████████  100 %  DONE (alpha — extended testing)
Stage 6A – Scale cold testing          ██████████  100 %  DONE (±0.1 g stability achieved)
Stage 6B – Scale thermal drift         ░░░░░░░░░░    0 %  (requires live heating)
Stage 7 – RPi sync                     ██████████  100 %  DONE (shared tree + platform_shim)
Stage 8 – Profile system               ░░░░░░░░░░    0 %  (deferred)
Stage 9 – Dual-heater simultaneous op  ░░░░░░░░░░    0 %  (deferred, after Stage 5–6)
──────────────────────────────────────────────────
TOTAL                                  ████████░░  ~80 %  (10 stages, 7 done — cross-platform)
```

### What is "done" means here
All software development for the new hardware is complete and testable via mock serial without
physical hardware. The remaining work is hardware-gated: verification, thermal testing, RPi
deployment, and the profile feature.

---

## Cold Test Mode

Before any live heating, flash with `COLD_TEST_MODE` enabled. This disables both SSRs at the
compiler level — all other logic (valves, pump, sensors, serial, state machine) runs normally.

**To enable:** In `config.h`, uncomment:
```c
#define COLD_TEST_MODE
```

**To disable (live operation):** Comment it back out:
```c
// #define COLD_TEST_MODE
```

When `COLD_TEST_MODE` is active, `heaterBrewOn` and `heaterSteamOn` will always read `0` in
telemetry, confirming the SSRs are inhibited. The UI will show them as off regardless of state.

---

## Stage 5 — Hardware Verification (Cold Test)

**Goal:** Confirm every actuator, sensor, and water path works correctly before any live heating.
Run all tests with `#define COLD_TEST_MODE` active so SSRs cannot fire.

### S4.4 — Touch Temperature Buttons ✓ DONE

The settings screen currently uses `SpinBox` widgets for temperature adjustment.
`SpinBox` is fine with a mouse but has small tap targets — difficult on a 7–10" touchscreen.

**S4.4 adds large ±0.5°C increment/decrement buttons** for both brew and steam temperatures:
- Two rows of buttons: `[ − ]  93.0°C  [ + ]` for brew and steam
- Each button is at least 58×58px (same size as the play/stop buttons)
- Tapping `+` or `−` adjusts the setpoint by 0.5°C and immediately calls `controller.setTemperatures()`
- The existing `SpinBox` can be hidden or kept as an alternative; the buttons are primary on touchscreen
- Changes are saved to `settings.json` on each tap (via the existing `setTemperatures` → `save_settings` path)

---

### Hardware Test Checklist

Work through these in order. Each test should pass before moving to the next.

#### Pre-test Setup
- [ ] H0.1 `COLD_TEST_MODE` is uncommented in `config.h` — confirm by checking that the
        serial monitor shows `heaterBrew=0,heaterSteam=0` at all times
- [ ] H0.2 Flash firmware to Teensy 4.0 — serial monitor shows `READY`
- [ ] H0.3 Connect UI (Windows) — status indicator shows **CONNECTED**
- [ ] H0.4 Confirm telemetry is streaming: serial monitor shows `DATA:` lines every ~100 ms

---

#### Serial Communication
- [ ] H1.1 Send `PING` → expect `PONG` response within 200 ms
- [ ] H1.2 Send `GET_STATUS` → expect `STATUS:` line with all named fields
- [ ] H1.3 Send `SET_TEMP BREW 90` → expect `OK:BREW_TEMP_SET`
- [ ] H1.4 Send `SET_TEMP STEAM 125` → expect `OK:STEAM_TEMP_SET`

---

#### Temperature Sensors (both PT1000s at room temperature)
- [ ] H2.1 With machine cold (~20–25°C ambient), confirm `brewTemp` field in `DATA:` reads a
        plausible room temperature (18–30°C). **Not 0.0, not -242, not 999.**
- [ ] H2.2 Same check for `steamTemp` field
- [ ] H2.3 Warm both PT1000 sensors slightly with your hand — both readings should increase
        by a few degrees and return to ambient when released
- [ ] H2.4 Disconnect one PT1000 — expect `ERROR:PT1000_BREW_FAULT` or `PT1000_STEAM_FAULT`
        on serial, then reconnect and confirm fault clears

---

#### Pressure Sensor (ADS1115)
- [ ] H3.1 At rest (no pump running), `pressure` field should read ≤ 0.3 bar
- [ ] H3.2 Note the auto-calibrated zero voltage printed in serial monitor during startup —
        it should be in the 0.3–0.7 V range for a healthy Honeywell MIP sensor

---

#### Scale (NAU7802)
- [ ] H4.1 Confirm `weight` field streams a stable value at rest (not 0.0 and not jumping
        ±50 g — some noise is normal, ±0.5 g is acceptable)
- [ ] H4.2 Send `TARE_SCALES` → weight should reset to ~0 g
- [ ] H4.3 Place a known weight (e.g., a 200 g calibration weight) on the scale — check
        that the reading is in the right ballpark (will need calibration, but should be
        within 30% of true weight)
- [ ] H4.4 Remove weight, re-tare — confirm return to ~0 g with no drift over 30 s

---

#### Pump
- [ ] H5.1 Turn potentiometer to minimum — confirm `pump%` in telemetry reads ~0
- [ ] H5.2 Turn potentiometer to maximum — confirm `pump%` reads ~100
- [ ] H5.3 With a container of water connected, run `START_FLUSH`:
        - `VALVE_PUMP` should energise (pump→thermoblock), `VALVE_THERMOBLOCK` stays off (thermoblock→drain)
        - Pump should run at full power; water flows pump→thermoblock→drain
        - Send `STOP` → pump stops, both valves de-energise

---

#### Thermoblock Water Path + Priming Confirmation
- [ ] H6.1 Press **BREW** in the UI:
        - State → `PRIMING_BREW`
        - UI shows the **"PRIMING THERMOBLOCK"** overlay with a pulsing indicator
        - Telemetry: `valvePump=1` (VALVE_PUMP energised → pump→thermoblock), `valveTB=0` (thermoblock→drain), pump running at full, `heaterBrew=0`
- [ ] H6.2 Watch the drain (thermoblock outlet — not group head):
        - Water should fill thermoblock and overflow at the drain
        - Once overflow is confirmed visually, press **CONFIRM — OVERFLOW SEEN** in the UI
        - UI sends `PRIME_DONE` → firmware stops pump, de-energises VALVE_PUMP
        - State → `HEATING_BREW`, overlay disappears; `heaterBrew=0` remains (cold test mode)
- [ ] H6.3 Priming cancel test:
        - Trigger `START_BREW` again → priming overlay appears
        - Press **CANCEL** → `STOP` is sent, state → `IDLE`, overlay disappears
- [ ] H6.4 Priming safety timeout test (optional):
        - Trigger `START_BREW`, disconnect the USB cable (or do not press CONFIRM)
        - After 2 minutes, firmware should abort priming → `ERROR:PRIME_BREW_TIMEOUT`
        - Reconnect; confirm state has returned to `IDLE`
- [ ] H6.5 Send `BEGIN_BREW` (while in `HEATING_BREW` after a successful prime):
        - State → `BREWING`
        - Telemetry: `valvePump=1` AND `valveTB=1` (pump→thermoblock→group head, pressure builds)
        - Pump runs at potentiometer-set power; water flows to group head
        - Weight on scale begins increasing
        - Send `STOP` → pump stops, VALVE_THERMOBLOCK de-energises (thermoblock→drain, pressure relief), state → `IDLE`

---

#### Steam Boiler Water Path + Priming Confirmation
- [ ] H7.1 Press **STEAM** in the UI:
        - State → `PRIMING_STEAM`
        - UI shows the **"PRIMING BOILER"** overlay (red, same layout as brew)
        - Telemetry: `valvePump=0` (VALVE_PUMP de-energised → pump routes to boiler OPV), pump running, `heaterSteam=0`
- [ ] H7.2 Watch the boiler OPV overflow outlet:
        - Water should fill the boiler and eventually drip at the OPV overflow point
        - Press **CONFIRM — OVERFLOW SEEN** → `PRIME_DONE` sent
        - Firmware stops pump; VALVE_PUMP remains de-energised; state → `HEATING_STEAM`
        - Overlay disappears, `heaterSteam=0` remains
- [ ] H7.3 Press **CANCEL** on the steam priming overlay → state → `IDLE`, no heating
- [ ] H7.4 Send `STOP` from any steam state to confirm clean return to `IDLE`

---

#### Valve Independence
- [ ] H8.1 Confirm `VALVE_PUMP` and `VALVE_THERMOBLOCK` are never both energised except during
        `BREWING` (check telemetry `valvePump` and `valveTB` fields across all states)
- [ ] H8.2 After `STOP` or `ABORT` from any state, confirm both valves de-energise within one
        telemetry cycle (~100 ms)

---

#### Communication Watchdog
- [ ] H9.1 Start a brew (reach `BREWING` state), then disconnect the USB cable (or close
        the UI). After ~10 seconds, confirm the Teensy stops the pump and closes valves
        (observe directly or via serial monitor on reconnect showing `STATE_IDLE`)

---

#### SSR Inhibit Verification (Cold Test Mode confirmation)
- [ ] H10.1 In any heater-active state (`HEATING_BREW`, `HEATING_STEAM`, `BREWING`),
         connect a multimeter or LED to `HEATER_BREW_PIN` (D15) — it must read 0 V
- [ ] H10.2 Same check on `HEATER_STEAM_PIN` (D14)
- [ ] H10.3 These two checks confirm the SSRs cannot fire during cold testing

---

### Post Cold-Test: Ready for Live Heating
Once all H-series checks pass:
1. Comment out `#define COLD_TEST_MODE` in `config.h`
2. Re-flash firmware
3. Proceed to Stage 6 (scale validation with actual brew)

---

## Stage 6 — Scale Validation

Stage 6 is split into two parts. Part A can be run during or immediately after cold testing —
no heating required. Part B requires the machine to reach operating temperature.

---

### Stage 6A — Cold Scale Testing (no heating needed)

**Goal:** Confirm the NAU7802 driver, tare, calibration, and basic repeatability work correctly
before any brew is attempted.

#### Basic Function
- [ ] S6A.1 Confirm scale reads a stable non-zero value with nothing on it — not 0.0 flat,
        not erratic ±50 g. Small noise (±0.5 g) is normal; large jumps indicate a wiring issue.
- [ ] S6A.2 Send `TARE_SCALES` (or press TARE in settings screen) — weight field should
        settle to 0.0 ± 0.3 g within two seconds.
- [ ] S6A.3 Place a known reference weight (e.g. a 100 g or 200 g calibration weight) on the
        scale. Note the raw reading — it will be wrong until calibrated, but it should be
        stable and proportional (heavier weight → larger reading).

#### Calibration
- [ ] S6A.4 With the reference weight on the scale, press **CAL** in the settings screen and
        enter the true weight in grams. The firmware runs `calibrateScale(knownWeight)`,
        computes a new factor, and emits `NEW_CAL:<factor>`. The UI saves this to
        `settings.json` automatically.
- [ ] S6A.5 Remove the reference weight, tare, then replace it — confirm the displayed weight
        now reads the true value ± 1 g.
- [ ] S6A.6 Restart the Teensy (or power-cycle). The UI restores the saved calibration factor
        on reconnect via `SET_SCALE_CAL`. Confirm the same weight still reads correctly after
        restart.

#### Repeatability
- [ ] S6A.7 With the calibrated scale, record 20 consecutive readings of the same weight
        (watch the `weight` field in telemetry). Compute the range (max − min).
        **Target: range ≤ 1.0 g** for a static load.
- [ ] S6A.8 Remove and replace the reference weight 5 times, recording each reading.
        **Target: all readings within ± 1.5 g of true value.**

#### Auto-tare in brew flow (cold)
- [ ] S6A.9 Run `START_BREW` → wait for prime to finish → send `BEGIN_BREW`. The firmware
        calls `tareScales()` at the moment `BEGIN_BREW` is processed. Confirm the weight
        field resets to ~0 g immediately after `BEGIN_BREW` and the `scalesTared` flag
        goes to `1` in telemetry.

---

### Stage 6B — Thermal Drift (live heating required)

**Goal:** Confirm scale readings remain stable under machine operating temperature.
Run only after cold testing passes and `COLD_TEST_MODE` is disabled.

- [ ] S6B.1 Heat the machine to brew setpoint. With nothing on the scale, tare, then record
        the weight reading every 30 s for 5 minutes. **Target: drift < 2 g over 5 minutes.**
- [ ] S6B.2 Run a full brew (prime → heat → `BEGIN_BREW` → extract into portafilter basket).
        Confirm the weight reading tracks the increasing mass of liquid meaningfully — rising
        curve, no sudden jumps or resets.
- [ ] S6B.3 Update `SCALE_CALIB` in `config.h` and `scale_cal` default in
        `settings_manager.py` with the final confirmed calibration factor.

---

## Stage 7 — RPi Sync ✓ DONE

**Approach adopted:** single shared source tree at `ui/source/` + small `platform_shim.py` for
Windows-vs-RPi differences. No separate RPi tree to keep in sync.

- [x] S7.1 Rename `ui/windows/source/` → `ui/source/`; delete stale `ui/rpi/pyqt6/`
- [x] S7.2 Add `ui/source/platform_shim.py` — RPi detection, 2× scale factor, fullscreen default
- [x] S7.3 Wire shim into `main.py` + `run_silvia.py` (sets `QT_SCALE_FACTOR` before Qt init)
- [x] S7.4 `ui/rpi/setup_rpi.sh` (apt deps + dialout) and `ui/rpi/run_silvia.sh` (launcher)
- [x] S7.5 Update `tools/flash_and_run.ps1` paths
- [x] S7.6 Live-deployed to RPi 4B (192.168.1.33, gram) — fullscreen 1080p @ 2× scale verified
- [x] S7.7 Desktop shortcut: `ui/rpi/silvia.desktop.in` → rendered to `~/Desktop/silvia.desktop` by setup; pcmanfm `single_click=1` + `quick_exec=1` for true one-tap launch
- [x] S7.8 Teensy udev rule (`ui/rpi/99-teensy.rules`) — ignores ModemManager, forces dialout:0660
- [x] S7.9 `SafetyManager` arm-on-first-telemetry — navigation works without Teensy; no spurious emergency-stop dialogs
- [x] S7.10 `qml_backend.py` lazy SerialManager import — `--mock` flag now functional
- [x] S7.11 Top-right invisible exit tap zone (`main.qml`) — `Qt.quit()` mirror of E-stop so user can leave fullscreen
- [ ] S7.12 Autostart at boot (labwc-pi autostart entry or systemd --user unit) — deferred

**Cross-platform serial**: `serialcom/real_serial_manager.py` already used Teensy VID (0x16C0)
via `pyserial.tools.list_ports` — auto-detects `/dev/ttyACM*` on Linux and `COM*` on Windows
with no platform code. No change needed.

---

## Stage 8 — Profile System (deferred)

**Goal:** Save/load named brew profiles; two factory presets.

New file: `ui/windows/source/profile_manager.py`
Modify: `ui/windows/source/qml_backend.py`, `ui/windows/source/main.qml`

Steps:
1. **ProfileManager** class:
   - `load_profiles()` — reads `profiles.json`; injects factory presets if missing
   - `save_profile(name, data)`, `delete_profile(name)`
   - Profile schema:
     ```json
     {
       "name": "Blooming Allonge",
       "brew_temp": 93.0,
       "pressure_ramp": [
         {"time_s": 0,  "bar": 0},
         {"time_s": 5,  "bar": 4.5},
         {"time_s": 15, "bar": 1.5},
         {"time_s": 20, "bar": 6.0}
       ],
       "target_weight_g": 40,
       "max_pressure_bar": 6.0
     }
     ```

2. **Factory presets**:
   - **Blooming Allongé**: ramp 0→4.5 bar, down to 1.5 bar, up to 6 bar, hold; max 6 bar
   - **Bloom Espresso**: ramp 0→7 bar, down to 2 bar, back to 9 bar, hold

3. **QML Profile screen** — list view with LOAD / SAVE / DELETE

4. **Profile execution** in `qml_backend.py`:
   - `loadProfile(name)` sets temperatures and stores ramp table
   - During brewing, a `QTimer` walks the ramp table and sends pump/pressure commands

---

## Stage 9 — Dual-Heater Simultaneous Operation (Power Management)

**Goal:** Enable both thermoblock and boiler to maintain their setpoints concurrently after the
sequenced startup, so the user can pull a shot and immediately steam milk without a long re-heat wait.

**Constraint:** Both elements draw 8.3 A at 100% duty — combined peak of 16.6 A exceeds the
15 A breaker limit. Solution is strict sequential startup so the boiler has tapered to
maintenance current before the thermoblock starts. Safety margin confirmed once S9.7b is measured.

### Proposed firmware design

The measured boiler behaviour makes the design simple: strict sequential startup with an
**auto-trigger** — no interleaving, no power limiting.

Add two boolean flags to `SystemData`:
```cpp
bool boilerPrimed      = false;  // true after PRIME_DONE from PRIMING_STEAM
bool thermoblockPrimed = false;  // true after PRIME_DONE from PRIMING_BREW
```

In `updateSystemLogic()`, after the state-machine switch, add a **background heater pass**:

```cpp
// Background heater maintenance — runs regardless of primary state.
// Safe because: boiler maintenance current is low (TBD measurement); thermoblock PID controls its own duty cycle.
if (sys.boilerPrimed && sys.state != STATE_PRIMING_STEAM && sys.state != STATE_HEATING_STEAM
    && sys.state != STATE_STEAMING) {
  controlSteamHeater();  // maintain boiler setpoint as background task
}
if (sys.thermoblockPrimed && sys.state == STATE_IDLE) {
  controlBrewHeater();   // keep thermoblock warm while idle, ready for next shot
}
```

**Auto-trigger thermoblock heat when boiler reaches setpoint:**
```cpp
// In updateSystemLogic(), inside STATE_HEATING_STEAM case, after controlSteamHeater():
if (sys.steamTempActual >= sys.steamTemp && sys.thermoblockPrimed
    && sys.state == STATE_HEATING_STEAM) {
  // Boiler is at setpoint and tapering to maintenance current — safe to ramp thermoblock.
  // Transition to HEATING_BREW; background pass will continue maintaining boiler.
  sys.state = STATE_HEATING_BREW;
  Serial.println("INFO:BOILER_READY_HEATING_BREW");
}
```

**Note:** `controlBrewHeater()` already runs inside `STATE_HEATING_BREW` and `STATE_BREWING`.
`controlSteamHeater()` already runs inside `STATE_HEATING_STEAM` and `STATE_STEAMING`. The
background pass only fires for states that don't already call these functions.

**Reset flags** only on `ABORT` (full reset), not on normal `STOP` — a completed brew must not
forget that the boiler is primed and hot.

### Startup workflow (once Stage 9 is implemented)
1. Power on → UI auto-connects
2. Press **STEAM** → prime boiler → CONFIRM → `STATE_HEATING_STEAM` → boiler heats (~5 min, 8.3 A)
3. Press **BREW** any time → prime thermoblock → CONFIRM → `thermoblockPrimed = true`
   *(thermoblock heater does NOT start yet — boiler still drawing full current)*
4. Boiler hits setpoint → tapers to maintenance current → firmware auto-transitions to `STATE_HEATING_BREW`
   → thermoblock heats at full 8.3 A → UI notifies "Brew temperature ready"
5. Both elements at setpoint simultaneously; combined draw = 8.3 A + boiler maintenance (TBD)
6. Pull shot (`BEGIN_BREW`) → steam immediately after — no re-prime or re-heat needed

### Checklist
- [x] S9.7a **Boiler peak current measured** — 8.3 A (100% duty cycle) for exactly 5 minutes
        from room temperature to steam setpoint. High thermal mass of heavy brass boiler full
        of water accounts for the long ramp time.
- [ ] S9.7b **Boiler maintenance current** — measure steady-state current after setpoint is
        reached and held for 5+ minutes. Must confirm (maintenance A) + 8.3 A < 15 A before
        enabling concurrent thermoblock heat-up.
- [ ] S9.1 Add `boilerPrimed` / `thermoblockPrimed` flags to `SystemData` struct
- [ ] S9.2 Set `boilerPrimed = true` in `PRIME_DONE` (steam branch); reset only on `ABORT`
- [ ] S9.3 Set `thermoblockPrimed = true` in `PRIME_DONE` (brew branch); reset only on `ABORT`
- [ ] S9.4 Add background heater pass in `updateSystemLogic()` (see design above)
- [ ] S9.5 Add auto-trigger: when `steamTempActual >= steamTemp` during `HEATING_STEAM` and
        `thermoblockPrimed`, transition to `HEATING_BREW` and emit `INFO:BOILER_READY_HEATING_BREW`
- [ ] S9.6 Update `sendTelemetry()` / `sendStatus()` to expose `boilerPrimed` / `thermoblockPrimed`
- [ ] S9.7 Update Python `_handle_serial_data()` to handle `INFO:BOILER_READY_HEATING_BREW`
        and update mock to simulate the 5-min sequential startup
- [ ] S9.8 Bench-verify: measure combined current during thermoblock ramp with boiler at setpoint
- [ ] S9.9 Validate UI workflow end-to-end: shot → steam immediately, no re-prime needed

---

## Full Checklist

### Firmware ✓ Complete
- [x] S1.1 Update `config.h` — new pins, PID constants, NAU7802 address
- [x] S1.2 Replace HX711 with NAU7802 (non-blocking I2C)
- [x] S1.3 Add second MAX31865 for boiler PT1000 (`RNOMINAL=1000`)
- [x] S1.4 Dual valve pin init and `setValve(pin, state)` function
- [x] S1.5 Dual heater pin init and `controlBrewHeater()` / `controlSteamHeater()`
- [x] S1.6 Update `SystemData` struct with new fields
- [x] S2.1 Add `STATE_PRIMING_BREW` and `STATE_PRIMING_STEAM`
- [x] S2.2 Priming runs until user confirms overflow — `PRIME_DONE` command exits prime state
- [x] S2.3 Implement PID `controlBrewHeater()` for thermoblock
- [x] S2.4 Update `updateSystemLogic()` for new states and dual heaters
- [x] S2.5 Update `sendTelemetry()` — 12-field `DATA:` packet
- [x] S2.6 Update `sendStatus()` for new fields
- [x] S2.7 Flush via `VALVE_THERMOBLOCK_PIN`
- [x] S2.8 Add `COLD_TEST_MODE` compile flag to disable both SSRs
- [x] S2.9 `PRIME_SAFETY_TIMEOUT_MS` watchdog (120 s) aborts to `IDLE` with error if UI disconnects

### Python Backend ✓ Complete
- [x] S3.1 Add `brewTempChanged`, `steamTempChanged` signals to `CoffeeController`
- [x] S3.2 Parse new 12-field `DATA:` packet in `_handle_serial_data()`
- [x] S3.3 Add priming states to `state_names` list
- [x] S3.4 Update `temperature_controller.py` for dual-sensor tracking
- [x] S3.5 Update `settings_manager.py` schema (single NAU7802 cal, profiles key)
- [x] S3.6 Update mock serial manager — new state enum, dual temps, dual valves, 12-field packet
- [x] S3.7 Add `primeDone()` slot — sends `PRIME_DONE` to firmware
- [x] S3.8 Mock serial handles `PRIME_DONE` and safety timeout (120 s)

### UI / QML ✓ Complete
- [x] S4.1 Brew screen — XL mass (≥48px) and timer (≥48px) in top bar
- [x] S4.2 Add `brewTempActual` / `steamTempActual` QML properties + signal wiring
- [x] S4.3 Fix chart X-axis: start 30 s, auto-grow, no shrink mid-brew
- [x] S4.4 Settings screen — large ±0.5°C touch buttons (64×64px), live value, clamped to limits
- [x] S4.5 Show thermoblock temp on brew screen, boiler temp on home/steam
- [x] S4.6 Brew screen priming overlay — shown during `PRIMING_BREW`, pulsing dot, CONFIRM + CANCEL
- [x] S4.7 Home screen steam priming overlay — shown during `PRIMING_STEAM`, same layout in red

### Hardware Verification (Stage 5)
- [ ] H0.1–H0.4 Pre-test setup (cold test mode active, firmware flashed, UI connected)
- [ ] H1.1–H1.4 Serial communication
- [ ] H2.1–H2.4 Both PT1000 temperature sensors
- [ ] H3.1–H3.2 Pressure sensor
- [ ] H4.1–H4.4 NAU7802 scale
- [ ] H5.1–H5.3 Pump and potentiometer
- [ ] H6.1–H6.5 Thermoblock water path + priming confirmation UI
- [ ] H7.1–H7.4 Steam boiler water path + priming confirmation UI
- [ ] H8.1–H8.2 Valve independence
- [ ] H9.1 Communication watchdog
- [ ] H10.1–H10.3 SSR inhibit confirmation

### Scale Validation — Part A: Cold (no heating needed, run with Stage 5)
- [ ] S6A.1 Stable non-zero reading at rest (noise ≤ ±0.5 g)
- [ ] S6A.2 TARE → weight settles to 0.0 ± 0.3 g within 2 s
- [ ] S6A.3 Raw reading moves proportionally with added weight (pre-cal sanity check)
- [ ] S6A.4 CAL with known weight → `NEW_CAL:` received, saved to `settings.json`
- [ ] S6A.5 Remove/re-add reference weight → reads true value ± 1 g
- [ ] S6A.6 Power-cycle Teensy → calibration restored via `SET_SCALE_CAL` on reconnect
- [ ] S6A.7 20 consecutive readings of static load → range ≤ 1.0 g
- [ ] S6A.8 5× remove/replace reference weight → all readings within ± 1.5 g
- [ ] S6A.9 `BEGIN_BREW` fires auto-tare → `weight` resets to ~0 g, `scalesTared=1`

### Scale Validation — Part B: Thermal drift (live heating required)
- [ ] S6B.1 At brew temp, 5-minute drift test → total drift < 2 g
- [ ] S6B.2 Full brew extraction — weight rises continuously with no jumps or resets
- [ ] S6B.3 Update `SCALE_CALIB` in `config.h` and `scale_cal` in `settings_manager.py`

### RPi Sync (Stage 7) ✓ Complete
- [x] S7.1 Rename to shared `ui/source/` tree; delete stale `ui/rpi/pyqt6/`
- [x] S7.2 Add `platform_shim.py` (RPi detection, 2× scale, fullscreen default)
- [x] S7.3 Wire shim into `main.py` + `run_silvia.py`
- [x] S7.4 Add `setup_rpi.sh` + `run_silvia.sh` launchers
- [x] S7.5 Update `tools/flash_and_run.ps1` paths
- [ ] S7.6 End-to-end verify on actual RPi hardware (deferred)

### Profile System (Stage 8 — deferred)
- [ ] S8.1 Create `profile_manager.py` with load/save/delete + factory presets
- [ ] S8.2 Expose profile slots on `CoffeeController`
- [ ] S8.3 Add profile screen in `main.qml`
- [ ] S8.4 Implement pressure ramp execution timer during brewing

### Dual-Heater Simultaneous Operation (Stage 9 — deferred, after hardware verification)
- [x] S9.7a Boiler peak current measured: 8.3 A for 5 min cold→setpoint
- [ ] S9.7b Boiler maintenance current: measure steady-state A after setpoint held 5+ min
- [ ] S9.1 Add `boilerPrimed` / `thermoblockPrimed` flags to `SystemData`
- [ ] S9.2 Set `boilerPrimed` in `PRIME_DONE` steam branch; reset only on `ABORT`
- [ ] S9.3 Set `thermoblockPrimed` in `PRIME_DONE` brew branch; reset only on `ABORT`
- [ ] S9.4 Background heater pass in `updateSystemLogic()` (boiler maintenance + idle thermoblock)
- [ ] S9.5 Auto-trigger: boiler at setpoint + `thermoblockPrimed` → transition to `HEATING_BREW`
- [ ] S9.6 Expose `boilerPrimed` / `thermoblockPrimed` in telemetry and status
- [ ] S9.7 Update Python backend to handle `INFO:BOILER_READY_HEATING_BREW`; update mock
- [ ] S9.8 Bench-verify combined current during thermoblock ramp with boiler at setpoint
- [ ] S9.9 Validate UI end-to-end: shot → steam immediately, no re-prime needed

---

## Next Actions

1. **Enable cold test mode** — uncomment `#define COLD_TEST_MODE` in `config.h`, flash firmware
2. **Work through H0–H10 hardware checklist** in order
3. **Run Stage 6A scale tests in parallel** — no heating needed, do alongside H4 and H6
4. After all H-series + 6A checks pass: comment out `COLD_TEST_MODE`, re-flash, proceed to Stage 6B
5. After 6B: implement Stage 9 (dual-heater), then RPi sync (Stage 7), then Profile system (Stage 8)

---

## Key File Reference

| File | Role |
|------|------|
| `firmware/silvia_lever_main/silvia_lever_main.ino` | Main firmware |
| `firmware/silvia_lever_main/config.h` | Firmware constants, pins, `COLD_TEST_MODE`, `PUMP_ENA_PIN`, `PUMP_PWM_FULL` |
| `firmware/PT1000_DEBUG.md` | PT1000 debug investigation log and root cause analysis |
| `firmware/test_sketches/` | Individual component test sketches |
| `ui/source/qml_backend.py` | Python↔QML bridge (`CoffeeController`) |
| `ui/source/platform_shim.py` | Windows/RPi detection + Qt scaling + fullscreen defaults |
| `ui/source/temperature_controller.py` | Python-side dual temp tracking |
| `ui/source/settings_manager.py` | Persist settings to `settings.json` |
| `ui/source/config.py` | Python constants (ports, limits) |
| `ui/source/main.qml` | Full UI (home, brew, steam, settings screens) |
| `ui/source/serialcom/mock_serial_manager.py` | Dev mock (no hardware needed) |
| `ui/source/controls/CircularSlider.qml` | Reusable gauge component |
| `ui/rpi/setup_rpi.sh` | One-time RPi deps + dialout group setup |
| `ui/rpi/run_silvia.sh` | RPi launcher (fullscreen + 2× scale via shim) |
