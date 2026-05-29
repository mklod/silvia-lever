# Heating — control strategy, PID tuning, power budgeting

Reference doc for everything related to thermal control on the Silvia Lever.
Kept separate from `workplan.md` (which tracks project-wide stages) and
`_status.md` (session log) because heating is a self-contained topic with its
own evolving design.

Last updated: 2026-04-24--0224

---

## 1. Hardware

| Component | Value |
|-----------|-------|
| Thermoblock SSR pin | D15 (`HEATER_BREW_PIN`) |
| Steam boiler SSR pin | D14 (`HEATER_STEAM_PIN`) |
| SSR control | PWM via `analogWrite()`, default Teensy 4.0 freq ~4.4 kHz. Duty 255 → pin constantly HIGH → SSR conducts continuously |
| SSR wiring | **L → SSR T1 → T2 → thermal fuse → heating element → N.** SSR switches the hot side so the element is isolated when off |
| Thermal fuse | Inline with each heater element, thermally coupled to the element body |
| Thermoblock PT1000 | MAX31865 SPI, CS pin D10 |
| Steam boiler PT1000 | MAX31865 SPI (second device) |
| Circuit | Standard US 15 A / 120 V receptacle. NEC 80 % rule → ~12 A recommended continuous |

### Measured currents

| Source | Current | Notes |
|--------|---------|-------|
| Thermoblock peak | **8.3 A @ 120 V** (100 % duty) | measured |
| Thermoblock cold→PID-band warmup | **~58 s** at 8.3 A continuous (25 °C → ~88 °C, where bang-bang hands off to PID) | measured 2026-04-24 02:23-02:24 via WiFi plug; thermoblock is small enough that 1 kW lifts it 60 °C in under a minute |
| Steam boiler peak | **8.3 A @ 120 V** (100 % duty), **~6 min cold (25 °C) → ~121 °C (250 °F, steam setpoint)** | measured 2026-04-23 |
| Combined peak (both full) | **16.6 A** | Exceeds breaker — **must be avoided by staggering** |
| Boiler maintenance (average) | **1.51 A** | 80-sample 6-sec-cadence steady-state capture 2026-04-23 10:08-10:16 (post-warmup portion of a 16 min trend) |
| Boiler maintenance (peak of 6-sec sample) | **3.40 A** | Same capture; plug integrates across bang-bang on-pulses within its sample window |
| Boiler maintenance (instantaneous SSR on) | **8.3 A** | Element always draws 8.3 A when SSR gates it; visible during any brief full-on pulse shorter than the plug's window |

### Concurrent-load arithmetic

| Scenario | Avg current | vs. 15 A breaker | vs. 12 A NEC continuous |
|----------|-------------|------------------|-------------------------|
| Boiler maintenance alone | 1.5 A | ✓ | ✓ |
| Thermoblock full + boiler maintenance | ~9.8 A | ✓ | ✓ |
| Both in maintenance (post-warmup) | ~2-3 A | ✓ | ✓ |
| **Worst instantaneous overlap** (both SSRs gated same tick) | **16.6 A** | ⚠ brief overdraw | ⚠ |

Continuous averages are fine. The breaker risk is only during coincident SSR
on-pulses. Mitigated by a firmware priority mutex (§5).

---

## 2. Current control strategy (2026-04-23)

Only **one SSR is energised at a time**. The firmware state machine enforces
this structurally:

- `STATE_HEATING_BREW` + `STATE_BREWING` + all states "outside steam" → thermoblock
  heater is controlled, boiler SSR left at 0.
- `STATE_HEATING_STEAM` + `STATE_STEAMING` → currently **disabled** for early
  testing; `controlSteamHeater()` is not called. See §5.

Transitions between brew-track and steam-track always go through `STATE_IDLE`,
whose entry calls `safeOff()` which explicitly writes 0 to both SSR pins before
the next mode's heater can be enabled. The command layer also rejects
`START_STEAM` unless state is `IDLE`.

**Runtime master switch**: `sys.heatersEnabled` (serial command
`SET_HEATERS_ENABLE <0|1>`, toggled from the HEAT cell in the UI debug row).
When false, `controlBrewHeater()` gates PWM to 0 regardless of PID output.
Currently defaults **true** at boot (test-mode override; originally defaulted
false for safety).

### Thermoblock: layered control

`controlBrewHeater()` (silvia_lever_main.ino) picks one of two regimes based
on the error:

```text
error > WARMUP_BAND_C (5 °C)  → full PWM, integrator reset    [bang-bang]
error ≤ WARMUP_BAND_C         → PID with sys.kp/ki/kd         [tracking]
```

Rationale: a single PID tune cannot simultaneously minimise warmup overshoot
AND give tight disturbance rejection during brews — the goals are in conflict
because the thermoblock has ~several seconds of thermal lag. The bang-bang
layer handles the cold-start climb at maximum hardware rate without
integrator wind-up; PID takes over for the last 5 °C (and for recovery
during brew shots when cold water is pumped through).

This is standard practice in commercial espresso-machine controllers.

### Boiler (steam): thermostat

`controlSteamHeater()` is a simple bang-bang with hysteresis
(`STEAM_HYSTERESIS`). No PID needed — boiler thermal mass is enormous and
steam temp doesn't need to be precise.

Currently **not called** during test phase. Re-enable by restoring the
`controlSteamHeater()` calls in `STATE_HEATING_STEAM` and `STATE_STEAMING`
cases of `updateSystemLogic()`.

---

## 3. PID tuning — relay-feedback autotune

Algorithm: **Åström-Hägglund relay feedback** (1984). Runs only on the
thermoblock (the boiler doesn't need PID).

### Theory

With the plant at steady-state near setpoint, replace the PID with a bang-bang
"relay" that swings the heater between 0 and `HEATER_PWM_FULL` based on
temperature vs setpoint ± hysteresis. The plant oscillates; measure the
period Tu and the half-amplitude a of that oscillation:

```text
Ku = 4 · h / (π · a)
```

where `h = HEATER_PWM_FULL / 2` (the relay half-amplitude in output units).

Then apply a tuning rule. Two common choices:

| Rule | Kp | Ki | Kd | Notes |
|------|------|------|------|------|
| Ziegler-Nichols classic | 0.6·Ku | 1.2·Ku/Tu | 0.075·Ku·Tu | ~25 % overshoot, aggressive |
| **Tyreus-Luyben** | Ku/3.2 | Ku/(2.2·Tu) | Ku·Tu/6.3 | Gentler, recommended for thermal plants |

Firmware currently auto-applies **TL** on successful completion (with sanity
bounds on Ku / Tu / amplitude / each gain). Both sets are reported.

### Asymmetric-period handling (bug fix 2026-04-23)

Thermal plants have very asymmetric half-cycles: heating is fast under full
8.3 A, cooling is slow via ambient losses only. Early autotune code assumed
symmetry and doubled the heating half-period → Tu underestimated by ~3×,
resulting in over-large Kd via `Ku·Tu/6.3`. Current code sums every
half-period after warmup (both heating and cooling halves) and divides by
half the number of half-periods to get the true Tu.

### Sanity bounds (widened 2026-04-23)

TL on long-Tu thermal plants legitimately produces Kp/Kd values far higher
than general-purpose PID tunes. Firmware accepts:

- `0.1 < Ku < 5000` (PWM/°C)
- `0.5 s < Tu < 600 s`
- `a > 0.2 °C`
- `0 < Kp < 500`
- `0 < Ki < 50`
- `0 < Kd < 5000`

These bounds apply to both autotune auto-apply and the runtime `SET_PID`
command, so gains accepted by autotune are always re-accepted on reconnect.

### Prerequisites for a valid autotune

1. Thermoblock must be **at or very near setpoint** (within ~1 °C), **settled**
   (no active brew, no recent large disturbance), for at least a minute.
2. Heaters must be enabled.
3. Thermoblock must be primed (water present) — empty thermoblock has wildly
   different thermal mass and tune is useless.

**Do not** start autotune from cold — the first measurement cycles would
be biased by the warmup momentum, `a` inflated → `Ku` underestimated →
gains too sluggish. Firmware skips 2 warmup cycles and averages 5 measured
cycles, but this does not rescue a cold start.

### Procedure

1. Power on. Bang-bang climbs thermoblock to setpoint.
2. Wait 1-2 min for oscillation around setpoint to settle with current PID.
3. Settings → PID → **AUTOTUNE**.
4. Dialog shows live `AUTOTUNE:RUNNING,cycle=N/7,temp=X.X,relay=HIGH/LOW`
   updates (1 Hz). Expect ~3-5 min total (depends on thermal period).
5. On completion: `AUTOTUNE_RESULT:Ku=…,Tu=…,a=…,ZN=kp/ki/kd,TL=kp/ki/kd,applied=TL`.
6. Firmware auto-applies TL gains. Python backend persists to `settings.json`.
7. On next reconnect / reboot, Python resends `SET_PID` with the saved gains.

### Retuning triggers

- Thermoblock physical change (new element, different mount, different mass)
- Setpoint changed by more than a few °C (PID is strictly valid for the
  operating point it was tuned at)
- Plumbing change that alters thermal dynamics (new valve, new thermoblock,
  big flow-rate change)
- New brew behaviour that wasn't present during tune

### Runtime commands

| Command | Effect |
|---------|--------|
| `AUTOTUNE_START` | Begin relay-feedback autotune |
| `AUTOTUNE_STOP` | Abort running autotune, heater off |
| `SET_PID <kp> <ki> <kd>` | Overwrite runtime PID gains; resets integrator |
| `SET_HEATERS_ENABLE <0\|1>` | Master switch — gates both SSRs |

### Derivative-on-measurement + low-pass filter

TL tuning for a thermal plant with multi-minute Tu produces large Kd
(`Ku·Tu/6.3` → Kd ≈ 3000 in our case). Raw Kd × raw sensor jitter would
cause chunky SSR gating and noise amplification. Two standard PID
refinements handle this:

1. **Derivative on measurement** instead of derivative on error. `d(error)/dt
   = -d(measurement)/dt` in steady-state (setpoint constant), but on a
   setpoint step `d(error)/dt` spikes; using `d(measurement)/dt` avoids the
   "derivative kick" on setpoint changes. Sign convention: PID output term
   is `-Kd · dM/dt` (rising temp → reduce output).

2. **First-order low-pass filter** on the derivative term with time constant
   `PID_D_FILTER_TAU = 2.0 s`:
   ```
   α = dt / (τ_f + dt)
   dM_filt = α · dM_raw + (1 - α) · dM_filt_prev
   ```
   With `dt=0.1 s`, `α≈0.048` → 95 % of a sensor noise spike is rejected
   while thermal trends (which evolve over tens of seconds) pass through
   intact. Rule of thumb: `τ_f ≈ Kd / (Kp · N)` with `N=5-10`; for
   Kp=47/Kd=3000, N=10 gives τ_f ≈ 6 s — we use 2 s for faster response
   since the PT1000 is reasonably low-noise.

State variables (`sys.pidLastMeasurement`, `sys.pidDerivativeFiltered`) are
reset to current temp / 0 every tick that the bang-bang warmup layer is
active, so the first derivative sample after handoff is 0 (no false
"derivative kick" when temp has been climbing at full power and PID suddenly
takes over at `error = 5 °C`).

### Known limits

- Autotune assumes **first-order + dead-time dynamics** — standard for
  thermal plants, fine for this thermoblock.
- ±1.0 °C hysteresis (widened from 0.5 °C on 2026-04-23): tighter →
  more accurate amplitude but slower thermal period and more susceptible to
  sensor noise; wider → faster cycles but amplitude measurement is coarser.
  1.0 °C is the compromise that got full tunes completing in ~8-12 min at
  our thermoblock's dynamics.
- Output is symmetric relay (0 ↔ `HEATER_PWM_FULL`). If the plant's
  steady-state needs >50 % duty to hold temp, the oscillation will be
  asymmetric (longer ON phase, shorter OFF) which biases `Ku`. Our
  thermoblock at 93 °C in normal room temp holds at maybe 15-30 % duty so
  this isn't a concern.
- Timeout 25 min (was 10 min): thermoblock period at 1 °C hysteresis is
  ~1-2.5 min/cycle; 2 warmup + 5 measured = 7 cycles needs ~10-18 min.

---

## 4. Runtime / UI interface

- **HEAT cell** in the persistent debug row (bottom-left): tap to toggle
  `heatersEnabled`. Red bold when ON, dim grey when OFF.
- **Settings → PID → AUTOTUNE** button: opens modal with live log and
  suggested gains.
- Autotuned gains persist in `ui/source/settings.json` keys
  `pid_kp / pid_ki / pid_kd`. Backend resends `SET_PID` on every reconnect
  since firmware RAM gains reset to `config.h` defaults at each Teensy boot.

---

## 5. Stage 9 — simultaneous boiler + thermoblock (IMPLEMENTED 2026-05-29, pending hot test)

> **Status:** firmware implemented on branch `boiler-stage9`. Task-switch model
> (user brews OR steams, never both) + dry-fire prime gate + single-circuit
> heater arbitration. NOT yet hot-tested. `master`/tag `brew-only-stable` is
> the fallback. Summary of what shipped below; original design rationale follows.
>
> **Implemented model (no current-monitor hardware — firmware only):**
> - **Dry-fire prime gate.** `sys.boilerPrimed` (RAM, false every cold boot).
>   `arbitrateHeaters()` blocks ALL heating until the boiler is primed. Prime =
>   cold-fill via `PRIME_BOILER` → pump→boiler→overflow → `PRIME_DONE` sets the
>   flag. Cold fill needs no steam purge.
> - **`arbitrateHeaters()`** replaces the old unconditional `controlBrewHeater()`
>   call. Rules: steaming → boiler active + thermoblock HARD CUT; cold start →
>   boiler preheats first, thermoblock inhibited until boiler hits target
>   (`boilerPreheatComplete` latches, emits `INFO:BOILER_READY_HEATING_BREW`);
>   normal brew/idle → thermoblock active, boiler maintains only on ticks the
>   thermoblock didn't fire (1-tick mutex → SSRs never both on → ≤8.3 A).
> - **Steam target = `steamTemp + STEAM_PREHEAT_OVERSHOOT` (5 °C)** — banks
>   margin so the boiler stays at usable steam temp after coasting through a shot.
> - **Telemetry fields 15/16** = `boilerPrimed`, `boilerPreheatComplete`.
>   New commands `PRIME_BOILER`; `BEGIN_STEAM` now requires primed.
> - **UI:** home screen reorganised to two gauges (thermoblock + boiler), each
>   with its two controls (BREW/FLUSH, STEAM/PRIME). PRIME glows until primed.
>
> Current-monitor hardware (CT clamp + measured load manager for true
> concurrency / background-shot-while-steaming) deferred indefinitely — see
> §5 "Phase 2" discussion in git history / PROFILES work. The task-switch model
> makes it unnecessary for the primary flow.

### Stage 9 — simultaneous boiler + thermoblock (original design notes)

### Goal

User should be able to pull a shot and **immediately steam milk** without
waiting for either element to heat up. Currently boiler is disabled for
single-heater testing; once Stage 5/6/8 are stable, re-enable and stagger.

### Constraint

Combined peak current = 16.6 A. Exceeds 15 A breaker by 11 %. Continuous
load should stay under 12 A (NEC 80 % rule).

### Strategy — strict sequential startup with auto-handoff

Confirmed viable by 2026-04-23 measurement: boiler draws 8.3 A for ~6 min
climbing from 25 °C → 250 °F, then current tapers "dramatically" at setpoint.
User's observed workflow is a natural fit for this staging.

1. **Boiler first** (~6 min at 8.3 A). Thermoblock heater inhibited.
2. **Boiler reaches setpoint** → current tapers to maintenance level. Firmware
   auto-emits `INFO:BOILER_READY_HEATING_BREW` and transitions to the
   thermoblock-warmup phase.
3. **Thermoblock warm-up** at 8.3 A — measured only **~58 s** of continuous
   draw to reach the PID-band handoff temp (88 °C from 25 °C cold).
   During this minute, total draw = `8.3 + boiler_maintenance_A` ≈ 9.8 A,
   safely under 12 A NEC continuous.
4. **Both at setpoint**: each maintains independently at its own PID /
   thermostat duty cycle. Total < 12 A because both are in low-duty
   maintenance.
5. **Pull a shot**: thermoblock PID ramps up to handle disturbance (cold
   water). Boiler continues in background at maintenance duty. Still safely
   < 12 A because thermoblock disturbance recovery rarely needs sustained
   full duty.
6. **Post-shot**: **steam is immediately available** — boiler has been at
   setpoint the whole time. This is the headline UX win over the factory
   Silvia's serial single-element machine.

### Net cold-start budget (estimated)

| Phase | Duration | Comment |
|-------|----------|---------|
| Boiler 25 °C → 121 °C | ~6 min | Sequential — thermoblock inhibited |
| Thermoblock 25 °C → 88 °C (PID band) | ~1 min | Concurrent with boiler maintenance |
| Thermoblock PID lock 88 → 93 °C | TBD | Depends on autotuned gains |
| **Total cold → ready-to-brew + steam** | **~7 min** | Vs. ~6 min serial boiler-only with no thermoblock at all |

The thermoblock warmup is essentially free in this scheme — it overlaps the
back end of the boiler warmup or runs after, taking less than a minute.
Worst case is initial parallel concurrent start where boiler-warmup-current
(8.3 A peak) + thermoblock-warmup-current (8.3 A peak) = 16.6 A → exceeds
breaker. The strict-sequential strategy in steps 1-3 above avoids this.

### Design hooks (already sketched)

Per `workplan.md §Stage 9`:

- `sys.boilerPrimed` and `sys.thermoblockPrimed` flags (persist across brews,
  reset only on `ABORT` / full power cycle)
- Background heater pass in `updateSystemLogic()` that runs
  `controlSteamHeater()` in any state that's NOT a steam-track state but
  where boiler was primed
- Auto-trigger: when `steamTempActual >= steamTemp` and `thermoblockPrimed`
  and current state is `HEATING_STEAM`, transition to `HEATING_BREW` +
  emit `INFO:BOILER_READY_HEATING_BREW`

### Pending measurements

| # | What | How | Blocker for |
|---|------|-----|-------------|
| S9.7b | Boiler maintenance current | Clamp ammeter on line at 5+ min past setpoint, held steady | Concurrent heating go/no-go |
| S9.x | Thermoblock heat-up with boiler at maintenance | Clamp ammeter during overlap; confirm sum < 12 A | Sizing duty-cycle limits if needed |

### Priority mutex (recommended concurrent-operation safeguard)

With 1.5 A average boiler maintenance, concurrent operation is safe on
average — the only risk is coincident SSR on-pulses during the same
firmware tick (thermoblock + boiler both demanding heat simultaneously →
16.6 A instantaneous). Cheap fix: a priority lock in `updateSystemLogic()`.

```text
if (thermoblock wants heat this tick)
  gate thermoblock, inhibit boiler
else if (boiler wants heat this tick)
  gate boiler
```

- Thermoblock always wins because it's the one under PID control — can't
  tolerate jitter during brew disturbance recovery.
- Boiler delayed by at most one tick (~ loop period). Boiler bang-bang is
  slow (many-second cycles); one tick of delay is thermally invisible.
- Guarantees total instantaneous current ≤ 8.3 A regardless of coincidence.

### Fallback options if mutex isn't sufficient

1. **Time-slice** — boiler and thermoblock alternate 100 % duty on a 2-4 s
   cycle. Total instantaneous power stays at one element's worth. Only cost
   is slower convergence on both, and SSR wear (more on/off cycles).
2. **Duty-cycle limiting** — cap each SSR at 50 % duty so combined
   instantaneous never exceeds 8.3 A. Halves heating speed but always safe.

---

## 6. Firmware file reference

| File | Role |
|------|------|
| `firmware/silvia_lever_main/silvia_lever_main.ino` | `controlBrewHeater()`, `controlSteamHeater()`, `autotuneStep()`, command handlers |
| `firmware/silvia_lever_main/config.h` | `PID_KP/KI/KD` (defaults), `WARMUP_BAND_C`, `MAX_BREW_TEMP`, `HEATER_PWM_FULL`, `COLD_TEST_MODE` (compile-time disable, normally off) |

## 7. Revision log

- **2026-04-24 (02:24)**: Thermoblock cold-start ramp measured —
  **~58 s at 8.3 A continuous** to reach the bang-bang→PID handoff band
  (~88 °C from 25 °C cold). Refines §5 Stage 9 budget: thermoblock warmup
  is essentially free in the staged sequence, total cold → ready ≈ 7 min
  (boiler 6 min + thermoblock 1 min concurrent with boiler maintenance).
- **2026-04-23 (17:19)**: First successful autotune.
  - Result: `Ku=142.9, Tu=139 s, a=1.14 °C → TL: Kp=46.94, Ki=0.516, Kd=3155.89`.
  - Applied to firmware + persisted to `settings.json`; backend re-sends
    `SET_PID` on every reconnect.
  - Fixed asymmetric-period bug: was summing only heating halves ×2,
    underestimating Tu by ~3× → Kd came out proportionally wrong. Now sums
    every half-period (both heating and cooling).
  - Widened autotune + `SET_PID` sanity bounds to match (Kp<500, Ki<50,
    Kd<5000) — TL formula legitimately produces large Kd for long-Tu
    thermal plants.
  - Widened hysteresis 0.5 °C → 1.0 °C, timeout 10 min → 25 min.
  - **Derivative on measurement** + first-order low-pass filter
    (`PID_D_FILTER_TAU=2 s`) to make Kd=3156 tolerable. Filter state resets
    on bang-bang→PID handoff.
- **2026-04-23 (03:15)**: Boiler maintenance current quantified via WiFi plug
  trend (15 min capture, Home Assistant history CSV export, 6 s cadence,
  160 samples total). Post-setpoint steady-state (80 samples, 10:08-10:16):
  **avg 1.51 A, min 0.01 A, max 3.40 A**. Closes workplan S9.7b.
  Concurrent operation confirmed safe on average; residual risk is
  coincident SSR on-ticks (16.6 A instantaneous) → handled by
  priority-mutex design in §5.
- **2026-04-23 (later)**: Boiler cold → 250 °F measured at ~6 min (was 5 min
  estimate); maintenance current confirmed to drop "dramatically" at
  setpoint, so concurrent thermoblock heating is safe pending exact
  margin number from S9.7b.
- **2026-04-23**: initial HEATING.md; bang-bang warmup layer + relay-feedback
  autotune + auto-apply TL gains + `SET_PID` runtime command. Boiler
  disabled for single-heater testing. `heatersEnabled` default flipped to
  `true` for test convenience (change to `false` before shipping).
- **2026-04-22**: `heatersEnabled` master runtime switch added (UI HEAT tap).
  SSR wiring confirmed on hot side (L → SSR → fuse → element → N).
- Earlier: `COLD_TEST_MODE` for dry / flow-only bring-up; `controlBrewHeater`
  PID originally Kp=30 → dropped to 8 after first hot test showed
  excessive overshoot with saturated output.
