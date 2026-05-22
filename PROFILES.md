# Brew profiles — current auto preinfuse + future profile system

Reference doc for the brew-cycle automation layer. Today this is just a
single hard-coded auto-preinfuse sequence; the structure is set up to evolve
into a full named-profile system (Stage 8 in `workplan.md`) where each
profile is a recipe of pressure / weight / time targets that the firmware
plays back.

Last updated: 2026-05-22--0115

Related: `HEATING.md` (thermoblock control), `workplan.md` Stage 8 (profile
system), `firmware/silvia_lever_main/silvia_lever_main.ino` (state machine).

---

## 0. Recommended progression — what we learned from the first hot test

The 2026-04-24 brew log (`ui/source/brew_logs/brew_2026-04-24_19-08-16.json`)
exposed concrete failure modes in the original 4-phase design:

| Phase | Original design | Observed | Verdict |
|---|---|---|---|
| PREINFUSE | Closed-loop P → 2.5 bar | 2.53 bar at 5 g exit | ✅ Worked |
| RAMP | **Open-loop PWM ramp** 75 → 254 over 4 s | Pressure exploded 2.5 → **13.97 bar** peak | ❌ Bad |
| HOLD | Closed-loop P-only at 9 bar for 3 s | Slowly pulled 13.87 → 11.13 bar; never reached 9 | ⚠️ Underperformed |
| EXTRACT | Pot-controlled (manual) | 36 % pot = ~91 PWM = pressure decayed to 8 bar | ⚠️ Wrong abstraction |

Root cause: only PREINFUSE was closed-loop on **the variable that actually
matters** (pressure). Open-loop PWM is meaningless for espresso because puck
restriction varies massively with grind, dose, tamp, age of beans, humidity —
the same PWM produces wildly different pressures.

### Stage 0 — slew-rate-limited closed-loop (DONE 2026-05-22)

Took several iterations to get right (see §1 "Why slew-rate-limited"):

1. Open-loop PWM ramp → slammed fine grinds to 14 bar.
2. Closed-loop *linear* RAMP-sweep + separate HOLD → still ~11.5 bar overshoot
   at the RAMP→HOLD boundary (transport lag commits the system to overshoot).
3. **Final:** ONE PI(D) loop with a setpoint that *slews* at `BREW_SLEW_RATE`
   (0.8 bar/sec). Controller always keeps up; integrator self-adapts to puck
   restriction. No overshoot, verified on fine restrictive grind.

- Shared `pumpClosedLoop()` PI(D) helper. Anti-windup on integrator; D-on-
  measurement with low-pass filter. Integrator + D-state reset at brew start.
- RAMP and HOLD are the *same loop* — phase label is telemetry only.
- HOLD is indefinite — user STOPs the brew when cup weight is right.
- Manual takeover: rotate pot >10% during RAMP/HOLD → bumpless handoff to
  pot control (`handoverOffset` captured so there's no pressure step).
- `SET_AUTO_MODE` serial command + `BREW: AUTO/MAN` UI toggle. Firmware
  defaults to MANUAL at boot.
- Chart big-numbers freeze on brew stop (final weight/pressure stay readable).

### Stage 1 — named profile menu (next 2-4 weeks)

Pre-defined profile presets the user picks from on the brew screen:

- **Espresso 9-bar** — current Stage 0 default (2.5 → 9.0 ramp, 9 hold to STOP).
- **Lungo** — same curve, longer ratio target.
- **Light Roast** — 2.5 → 8.5 ramp, *decline* to 6 bar over 25 s (fruity, slow
  extraction; pressure profiling).
- **Ristretto** — 2.5 → 9.5 ramp, 9.5 hold tighter.
- **Custom** — editable curve in UI.

Each profile is a sequence of `(target_bar, slew_rate, exit_condition)`
segments. Concrete plan + Blooming Allongé spec in §3; longer-term JSON
schema in §4.

### Stage 2 — adaptive feedforward (longer term)

- After every brew, `brew_recorder` JSON has the full PWM-vs-pressure trajectory.
- Next brew with the same beans/grind: seed `BASE_PWM` from what worked last
  time. Drastically reduces first-shot overshoot when switching beans.
- Detect grind drift: if last N shots needed monotonically rising PWM to hold
  9 bar, surface a "regrind?" hint in the UI.

### Stage 3 — flow profiling (advanced, optional)

- Decent-style: control on **flow rate** (g/s of weight increase) instead of
  pressure. Useful for natural-process light roasts where pressure-controlled
  shots tend to channel.
- We have the fast scale already (NAU7802 320 SPS). Pressure stays as a safety
  cap; flow is the primary control variable.

### Stage 4 — auto-derive profiles from recordings

- Offline tool reads `brew_logs/*.json`, finds the user's good shots (manual
  annotation: 👍 / 👎), extracts the implicit phase structure, suggests a profile
  JSON the user can save by name.
- Closes the loop: pull manually → recorder captures → analysis suggests
  profile → next brews reproducible.

---

## 1. Today (Stage 0): closed-loop pressure throughout

Every brew is the same 3-phase auto sequence. No user-selectable profiles yet
— that's Stage 1.

### Sub-state machine inside `STATE_BREWING`

`enum BrewPhase { PREINFUSE = 0, RAMP = 1, HOLD = 2, EXTRACT = 3 }`
in `silvia_lever_main.ino`. On `BEGIN_BREW` the phase is set to `PREINFUSE`
if `autoBrewMode` is true, else straight to `EXTRACT` (full manual).

```
BEGIN_BREW (autoBrewMode=true)                            STOP (user)
  │                                                            │
  ▼                                                            ▼
┌─────────────┐ 1 g OR 10 s ┌──────────────┐ setpoint  ┌─────────────┐
│  PREINFUSE  │ ──────────► │     RAMP     │ reaches 9 │    HOLD     │
│ closed-loop │             │ slew-limited │ ────────► │ closed-loop │
│ PI → 1.0 bar│             │ setpoint     │           │ PI → 9 bar  │
│             │             │ 1.0→9.0 bar  │           │ (indefinite)│
└─────────────┘             └──────────────┘           └─────────────┘
       │                           │                          │
       │      pot rotated >10% any time during RAMP/HOLD       │
       │                           ▼                           │
       │                  ┌──────────────────┐                 │
       └────────────────► │     EXTRACT      │ ◄───────────────┘
                          │ pot drives PWM   │
                          │ (bumpless offset)│
                          └──────────────────┘
                all phases → STATE_IDLE on STOP / ABORT

BEGIN_BREW (autoBrewMode=false) → EXTRACT directly = full manual from t=0.
```

### Why slew-rate-limited (the design that finally worked)

Earlier designs failed: an open-loop PWM ramp slammed fine grinds to 14 bar;
a closed-loop *linear* RAMP-target sweep then a separate HOLD phase still
overshot to ~11.5 bar at the RAMP→HOLD boundary. Root cause: the pump→pressure
system has ~200 ms of **transport lag**. Any controller chasing a setpoint
that moves faster than that lag window will commit the system to overshoot —
no PI/PID tuning fixes it.

The fix: **one PI(D) loop, one set of gains, a setpoint that slews slowly**
(`BREW_SLEW_RATE` = 0.8 bar/sec). The controller can always keep up; the
integrator naturally finds whatever PWM the current puck restriction needs.
No per-phase base PWM, no integrator surgery, no bumpless math between RAMP
and HOLD — RAMP and HOLD are the *same loop*, the phase label is telemetry
only (flips when the setpoint reaches `BREW_TARGET_BAR`).

### Shared closed-loop PI(D) controller

`pumpClosedLoop(target, base, kp, ki, kd, min, max)` — single `sys.pumpIntegral`
with anti-windup, plus a D-on-measurement term (low-pass filtered, `PUMP_D_FILTER_TAU`)
that brakes the pump when pressure rises fast. Integrator + D-state reset at
`BEGIN_BREW`.

### Phase 1 — `PREINFUSE`

- **Goal**: gentle 1.0 bar wetting.
- **Control**: `pumpClosedLoop(PREINFUSE_TARGET_BAR, …, PREINFUSE_K{P,I,D}, …)`.
- **Termination**: first of `weight ≥ PREINFUSE_END_WEIGHT_G` (1 g) **or**
  `elapsed ≥ PREINFUSE_MAX_MS` (10 s). The time cap stops a choked puck from
  holding 1 bar forever.
- **Exit emits**: `INFO:BREW_RAMP_START`.

### Phase 2/3 — `RAMP` + `HOLD` (one loop)

- **RAMP**: setpoint slews `PREINFUSE_TARGET_BAR → BREW_TARGET_BAR` at
  `BREW_SLEW_RATE` bar/sec (~10 s for 1→9 bar).
- **HOLD**: setpoint pinned at `BREW_TARGET_BAR`, runs indefinitely.
- The phase flips RAMP→HOLD (telemetry) when the setpoint reaches target;
  emits `INFO:BREW_HOLD_START`. Controller behaviour does not change.
- **Termination**: user STOP, or manual takeover (below).

### Phase 4 — `EXTRACT` (manual)

- Entered either at brew start (`autoBrewMode=false`) or via manual takeover:
  if the pot is rotated more than `MANUAL_TAKEOVER_DELTA` PWM units (~10 %)
  from its brew-start position during RAMP/HOLD, control hands to the pot.
- **Bumpless**: at takeover, `handoverOffset = lastAutoPwm − potValue` is
  captured. Output is then `constrain(pot + handoverOffset, 0, FULL)` — no
  pressure step, user adjusts *relative* to the auto baseline.
- Emits `INFO:BREW_MANUAL_TAKEOVER`.

### AUTO / MANUAL toggle

`sys.autoBrewMode` (firmware) ↔ `SET_AUTO_MODE 0|1` serial command ↔
`BREW: AUTO/MAN` button in the UI debug row. Firmware defaults to MANUAL
at boot. AUTO runs the full sequence above; MANUAL is pot-from-t=0.

### Tunable constants (`config.h`)

| Macro | Default | Tunes |
|-------|---------|-------|
| `PREINFUSE_TARGET_BAR` | `1.0` | Preinfuse pressure setpoint |
| `PREINFUSE_END_WEIGHT_G` | `1.0` | Weight that exits PREINFUSE |
| `PREINFUSE_MAX_MS` | `10000` | Hard time cap on PREINFUSE |
| `PREINFUSE_BASE_PWM` | `60` | Feed-forward PWM |
| `PREINFUSE_KP/KI/KD` | `30/5/0` | PI(D) gains |
| `PREINFUSE_MIN/MAX_PWM` | `30/180` | Output clamps |
| `BREW_TARGET_BAR` | `9.0` | Final OPV-limited line pressure |
| `BREW_SLEW_RATE` | `0.8` | Setpoint climb rate, bar/sec |
| `BREW_BASE_PWM` | `80` | Feed-forward PWM (integrator does the rest) |
| `BREW_KP/KI/KD` | `20/6/10` | PI(D) gains for RAMP+HOLD loop |
| `BREW_MIN/MAX_PWM` | `30/254` | Output clamps |
| `MANUAL_TAKEOVER_DELTA` | `25` | Pot rotation (PWM units) that triggers manual |
| `PUMP_PI_INTEGRAL_MAX` | `50.0` | Anti-windup clamp on integrator (bar·sec) |
| `PUMP_D_FILTER_TAU` | `0.2` | D-term low-pass filter time constant (sec) |

`RAMP_MS`, `HOLD_MS`, and the per-phase `RAMP_*`/`HOLD_*` constants were
**removed** — RAMP and HOLD are one loop with one gain set now.

### Telemetry surface

The DATA packet's 14th field is `brewPhase` (0/1/2/3). Backend parses to
`"preinfuse"|"ramp"|"hold"|"extract"`, exposed as `self._brew_phase`, stamped
on every brew_recorder sample.

---

## 2. Per-brew JSON recordings

Every shot is auto-saved as one JSON file under
`ui/source/brew_logs/brew_YYYY-MM-DD_HH-MM-SS.json` (UTC). Driven by
state-transition hooks in `qml_backend._handle_serial_data`:

- `IDLE → BREWING` → `BrewRecorder.start(...)`
- DATA packet while `BREWING` → `BrewRecorder.add_sample(..., phase=...)`
- `BREWING → anything` → `BrewRecorder.finish(completed_normally=...)`

### Schema v1

```json
{
  "version": 1,
  "started_at": "2026-04-24T12:34:56.789+00:00",
  "ended_at":   "2026-04-24T12:35:30.123+00:00",
  "duration_s": 33.4,
  "setpoints":  {"brew_temp_c": 93.0, "steam_temp_c": 130.0},
  "pid_gains":  [46.94, 0.516, 3155.89],
  "scale_cal":  2050.6499,
  "completed_normally": true,
  "final_weight_g":   36.2,
  "max_pressure_bar":  9.1,
  "max_brew_temp_c":   93.4,
  "min_brew_temp_c":   91.8,
  "sample_count": 284,
  "samples": [
    {"t_s": 0.000, "weight_g": 0.0,  "pressure_bar": 0.0, "brew_temp_c": 93.1, "pump_percent": 60,  "v_pump": false, "v_tb": true, "phase": "preinfuse"},
    {"t_s": 0.100, "weight_g": 0.0,  "pressure_bar": 0.5, "brew_temp_c": 93.0, "pump_percent": 75,  "v_pump": false, "v_tb": true, "phase": "preinfuse"},
    {"t_s": 7.300, "weight_g": 5.1,  "pressure_bar": 2.4, "brew_temp_c": 92.8, "pump_percent": 90,  "v_pump": false, "v_tb": true, "phase": "ramp"},
    {"t_s": 11.4,  "weight_g": 12.7, "pressure_bar": 8.9, "brew_temp_c": 92.5, "pump_percent": 254, "v_pump": false, "v_tb": true, "phase": "extract"},
    "..."
  ]
}
```

Sample rate ≈ 10 Hz (driven by firmware telemetry interval). A 30 s shot is
~300 samples ≈ 50 KB JSON. `.gitignore` excludes `brew_logs/`.

---

## 3. Light-roast profile plan (2026-05-22)

Actionable plan for Stage 1 — a light-roast-focused profile system. Research
sources: the *Espresso Aficionados* profiling guide (PDF in `profiles/`),
Decent's 5-light-roast-profiles blog, Gaggiuino tuning notes, and headspace
guidance from Clive Coffee / Decent. Links at the end of this section.

### 3.1 Finding — Blooming Allongé needs a profile engine

Stage 0 firmware runs **one** hardcoded sequence (preinfuse → slew to 9 bar →
hold). Blooming Allongé is a different *shape* — fill, bloom-down, percolate-up,
decline. It cannot be a config tweak; the machine must play back a
**multi-segment pressure trajectory**. The slew-rate setpoint engine built in
Stage 0 *is* the substrate: a profile is just an ordered list of
`(target, slew_rate, exit)` segments fed to the same `pumpClosedLoop()`.

### 3.2 Minimal profile engine (the gating item)

```
Profile = ordered array of segments. Each segment:
  { target_bar, slew_rate (bar/s, signed), exit_condition }
  exit = first-to-fire of { weight_g, duration_s, pressure_reached }
```

- Built-in profiles as `const` arrays in `config.h` — no JSON parser yet
  (that is the longer-term §4 evolution).
- Current Stage-0 auto sequence becomes **Profile 0 "Standard 9-bar"**
  (2 segments) — regression baseline.
- `SET_PROFILE n` serial command + UI profile picker (extends the AUTO/MAN
  toggle pattern).
- `pumpClosedLoop()` PI(D) controller unchanged — it just receives the active
  segment's slewing setpoint. ~100 lines of firmware.
- Per-profile thermoblock temperature setpoint (light roast wants 94–96 °C).

### 3.3 Blooming Allongé — spec for our hardware

Translated from the Espresso Aficionados pressure-profiler recipe to our
pressure-controlled engine. Ultra-light / nordic filter roasts, fine grind,
~1:3.5+ ratio, thin high-clarity texture.

| Seg | Phase | Target | Slew | Exit |
|-----|-------|--------|------|------|
| 1 | FILL | 4.5 bar | +2.0 bar/s (fast wet) | pressure ≥ 4 bar **or** 4 s |
| 2 | BLOOM | 1.0 bar | −1.5 bar/s then hold | 10 s **or** weight ≥ 4 g |
| 3 | PERCOLATE | 6.0 bar | +0.8 bar/s | pressure ≥ 5.5 bar **or** 5 s |
| 4 | DECLINE | 3.5 bar | −0.12 bar/s (slow taper) | user STOP |

**Key adaptation:** a needle-valve machine tapers *naturally* as the puck
erodes. We are pressure-controlled — holding 6 bar would make the pump push
*harder* as the puck weakens. So segment 4 actively **declines** the setpoint
(6 → 3.5 bar over ~20 s), mimicking the natural taper of a flow-controlled
shot. Temp 94–96 °C. Manual pot takeover still works at any point.

### 3.4 Additional light-roast profiles (planned)

| Profile | Shape | Use |
|---------|-------|-----|
| **Standard 9-bar** (Profile 0) | preinfuse → slew to 9 → hold | medium/dark; Stage-0 baseline |
| **Gentle & Sweet** | preinfuse → flat **6 bar** hold | Decent's light-roast starter; low pressure = less channeling |
| **Blooming Allongé** | §3.3 above | ultra-light, max clarity, filter-like |
| **Blooming Espresso** | fill → 6-7 bar, bloom-drop to 2 bar, ramp to 9, optional taper | light–medium, more body + blending |
| **Allongé / Turbo** | quick ramp to ~6 bar, hold, short (20-30 s), 1:3–1:5 | light coffees that channel on blooming profiles; highest clarity |
| **Adaptive Bloom** | fill to 6-7 bar, soak (drop to ~2 bar), ramp to taste | coffees that fall apart on classic bloom |

### 3.5 Portafilter / basket / headspace — Ascaso thermoblock group

**General principles (light-roast focus):**
- For light roast, *moderate* headspace is not the enemy — consensus is more
  headspace favours light roast (clarity, higher extraction %), less favours
  dark (body). The real risk of *excess* headspace is **fill turbulence**
  disturbing the dry puck → channeling. Our gentle preinfuse (slow wet at
  1 bar) mitigates turbulence — water never slams the puck.
- **Puck screen** (~$8–12, 1.5–2 mm): sits on the puck, diffuses incoming
  water, keeps the shower screen clean, flattens the puck. Good supplement.
- **Dose to the basket** within 1–2 g of rating. Inspect the puck after a
  dry lock-in: faint shower-screen witness mark = ideal; none = too much
  headspace; deep screw imprint = overdosed.
- A precision basket (IMS / VST 58 mm, available in varying heights) gives
  more even extraction — worth it for light roast.

**Diagnostic — the Ascaso group geometry mismatch (2026-05-22):**

Observed by the user, and it points to a hardware mismatch, not technique:

- Dose: **20 g in a stock Rancilio Silvia double basket**, same Silvia
  portafilter, same beans, same grind, same scale, same puck prep.
- On the **old Silvia group head**: a decent shower-screen witness mark —
  puck nearly touching the screen screw. Headspace was correct.
- On the **new Ascaso thermoblock group**: *massive* headspace, **no witness
  mark at all**. Plus horrid channeling (bottomless-portafilter evidence).
- The **only variable changed is the group head.** Beans/grind/scale/prep
  are static. Grind sanity-checks out (30–40 s, 1:2 ratio on a normal shot).

**Root cause — bayonet-pattern mismatch.** The basket lip sits at the
portafilter's top rim; you dose *to the basket*, so the puck top lands just
below the lip regardless of basket depth (a "taller" basket is just a higher
dose rating). Basket choice does **not** move the lip-to-screen distance —
and the basket/dose/grind/portafilter were identical on both groups, so the
basket cannot explain the difference. The variable is the group.

The Ascaso 58 mm group is an **E61-bayonet** group (every aftermarket
"58 mm E61" portafilter lists Ascaso as compatible). The Rancilio Silvia
portafilter is **not E61** — the Silvia has its own Rancilio group/bayonet.
The Silvia PF locks into the Ascaso E61 group because the patterns are
*close*, but it does not seat at the E61-correct height → basket lip too far
from the shower screen → the massive headspace, which then drives the
channeling.

**Fix — cheap, not the $300 OEM:**
1. **Buy a 58 mm E61 bottomless portafilter** (~$20–50: KNODOS, Normcore
   Lay-Flat, Lastaforest, generic eBay — all list Ascaso compatibility).
   E61-pattern = matches the Ascaso E61 group's seating. Bottomless also
   gives the channeling diagnostics. The genuine Ascaso PF (~$300) is not
   needed.
2. **Verify the group gasket.** This build used a parts-only Ascaso group —
   confirm the group-head gasket is installed and the right one. Ascaso
   58 mm gaskets: **7.8 mm** (Dream PID + all Steel), **8.3 mm** (Bar
   2012-15, Steel Uno/Duo/Trio ~2016+), 8.5 mm old, 5.0 mm pre-2009. The
   portafilter seats against this gasket — wrong/missing gasket is itself a
   seating-height error. The 7.8↔8.3 spread is also a ~0.5 mm fine-tune.
3. **Puck screen** supplements once headspace is in normal range (1.5–3 mm).

Basket size/depth stays a free choice — dose to whatever basket you run.
Scale re-check before grinding remains a cheap sanity item.

### 3.6 Build order

1. **Profile engine** — segment-table playback, `SET_PROFILE`, UI picker.
2. **Profile 0** = current Standard 9-bar re-expressed as segments
   (regression check vs Stage 0 behaviour).
3. **Blooming Allongé** — segment table §3.3.
4. Layer in Gentle & Sweet, Blooming Espresso, Allongé/Turbo, Adaptive Bloom.
5. Per-profile temperature setpoint.
6. `brew_recorder` already logs everything — compare profiles from JSON.

### 3.7 Sources

- *Espresso Profiling* — Espresso Aficionados: <https://espressoaf.com/guides/profiling.html>
  (full PDF archived in `profiles/`)
- Decent — 5 light-roast profiles: <https://decentespresso.com/blog/5_espresso_profiles_for_light_roasted_coffee_beans>
- Papel Espresso — Gaggiuino roast-level tuning: <https://www.papelespresso.com/tuning-your-gaggiuino-for-different-roast-levels-and-bean-densities/>
- Clive Coffee — espresso headspace: <https://clivecoffee.com/blogs/learn/headspace-espressos-invisible-enemy>
- Decent — headspace reduction kit: <https://decentespresso.com/blog/new_headspace_reduction_kit_with_surprising_refractometer_results>

---

## 4. Longer-term: JSON profile system (workplan Stage 8)

The §3 minimal engine uses `const` segment arrays compiled into firmware.
The longer-term evolution generalises it: JSON-defined profiles the user can
pick from and save, with a UI editor.

### Profile schema (proposed)

```json
{
  "name": "Blooming Allongé",
  "description": "Long bloom, low-then-high ramp; suits light roasts",
  "brew_temp_c": 93.0,
  "phases": [
    {
      "name": "preinfuse",
      "control": "pressure",
      "target_bar": 2.5,
      "exit": {"weight_g": 5.0}
    },
    {
      "name": "bloom",
      "control": "pressure",
      "target_bar": 1.5,
      "exit": {"duration_s": 8}
    },
    {
      "name": "ramp",
      "control": "pwm_ramp",
      "from_pct": null,           // null = continue from current
      "to_pct": 100,
      "exit": {"duration_s": 4}
    },
    {
      "name": "extract",
      "control": "manual",
      "exit": {"user_stop": true}
    }
  ],
  "stop_conditions": {
    "max_weight_g": 50,
    "max_duration_s": 60,
    "max_pressure_bar": 11
  }
}
```

Each phase is `{control, target, exit_condition}`. Control modes:
- `pressure` — closed-loop P (or PI/PID later) on pressure sensor
- `pwm` — direct PWM hold
- `pwm_ramp` — linear interpolation PWM `from→to` over duration
- `weight_flow` — closed-loop on weight rate (mass flow)
- `manual` — pot takes over

Exit conditions are AND'd: any whose value is non-null is checked, first
to trigger wins. Examples: `{"weight_g": 5.0}`, `{"duration_s": 8}`,
`{"weight_g": 36, "duration_s": 45}` (whichever first).

Global `stop_conditions` are safety cutouts that abort the whole shot.

### Built-in factory profiles (planned)

From the original TO-DO list (`workplan.md`):

- **Blooming Allongé**: ramp 0→4.5 bar, drop to 1.5 bar (bloom), back to
  6 bar, hold. Light roasts.
- **Bloom Espresso**: ramp 0→7 bar, drop to 2 bar, back to 9 bar, hold.
  Standard espresso with a brief bloom.
- (current code = effectively a stripped-down "Auto Preinfuse" with
  preinfuse + ramp + manual)

### Player loop (firmware)

A profile interpreter inside `STATE_BREWING` that walks the phase array.
Per loop tick:

1. Update phase elapsed-time / sample weight + pressure.
2. Check current phase's exit condition. If met → advance index, capture
   transition state (current PWM, current pressure) for the next phase to
   reference.
3. Run current phase's control function with the current target.
4. Check global `stop_conditions`. If any triggers → ABORT.

Profile JSON parsed once at brew start, walked at runtime. ~200 lines of
firmware code, comparable in scope to today's `autotuneStep()`.

### Profile derivation from recordings

Because every brew is recorded (§2), we can later add an offline analysis
tool that:

- Reads `brew_logs/*.json`
- Identifies user-driven shots that produced good results (manual
  annotation field in JSON, or filter by final_weight + duration)
- Extracts the implicit phase structure (where pressure was steady vs
  ramping vs tapering)
- Suggests a profile JSON that approximates that recording

This is the long-term arc: user pulls shots manually → recorder captures →
analysis suggests profiles → user saves their best profiles by name → next
brews are reproducible.

### UI integration (Stage 8)

- New screen: profile picker (list, preview the phase plot, LOAD)
- Profile editor (add/remove/reorder phases, adjust targets)
- "Save current shot as profile" button on brew screen
- Persist user profiles in `settings.json` under `profiles: []`

---

## 5. File reference

| File | Role |
|------|------|
| `firmware/silvia_lever_main/silvia_lever_main.ino` | `BrewPhase` enum, `STATE_BREWING` sub-state machine, BEGIN_BREW init |
| `firmware/silvia_lever_main/config.h` | All `PREINFUSE_*` + `RAMP_MS` tunables |
| `ui/source/brew_recorder.py` | `BrewRecorder` class — per-shot JSON capture |
| `ui/source/qml_backend.py` | State-transition hooks that drive the recorder; parses `brewPhase` from telemetry |
| `ui/source/brew_logs/` | Output dir (gitignored) |

---

## 6. Revision log

- **2026-05-22 (02:03)**: §3.5 headspace diagnosis finalised — **bayonet-
  pattern mismatch**. The Ascaso 58 mm group is E61-bayonet; the Rancilio
  Silvia portafilter is Rancilio-pattern, not E61. The Silvia PF locks in
  but seats at the wrong height → massive headspace → channeling. Fix: a
  ~$30 aftermarket 58 mm E61 bottomless portafilter (not the $300 Ascaso
  OEM, not the Silvia PF) + the correct Ascaso group gasket (7.8 mm for
  Steel/Dream PID). Earlier basket-depth theories in this section's history
  were wrong — basket is irrelevant; you dose to the basket.
- **2026-05-22 (00:36)**: §3 added — light-roast profile plan, minimal
  profile-engine design, Blooming Allongé spec for our hardware, and the
  Ascaso-group headspace/basket mismatch diagnostic. Old JSON-profile-system
  section renumbered to §4.
- **2026-04-23 (23:28)**: Added HOLD phase (closed-loop 9 bar for 3 s)
  between RAMP and EXTRACT. Lets pump speed settle to steady-state pressure
  before manual takeover. `brewPhase` enum is now 0-3 (added `HOLD = 2`,
  shifted `EXTRACT` to 3); backend `phase_names` tuple updated.
- **2026-04-23 (21:09)**: Initial PROFILES.md.
  - Documents the just-landed hard-coded auto preinfuse (preinfuse → ramp
    → extract), tunable constants, telemetry field 14, brew JSON schema v1.
  - Sketches Stage 8 named-profile system (schema, control modes, player
    loop, derivation from recordings).
