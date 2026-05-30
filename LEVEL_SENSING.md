# Steam boiler water-level sensing — design + parts

Why we need it, the probe options, the firmware interlock, and a wiring-ready
plan for when a probe is fitted. Companion to `OG_SILVIA_OPERATION.md` (which
explains the boiler/OPV behavior) and `HEATING.md` §5 (heater arbitration).

Status: **planned, not yet wired.** Firmware hooks to be stubbed so adding the
probe is a small change.

Last updated: 2026-05-29.

---

## 1. Why — the fuse and the PT1000 can't prevent element burnout

Our steam boiler is a **repurposed OG Silvia boiler, steam-only** — and unlike a
stock Silvia it is **never refilled by brewing**, so every steam depletes it and
nothing tops it up. The classic kill is long successive steams with no refill →
boiler runs dry → element burns out. (Happened on the donor machine years ago.)

Neither existing safety actually prevents that:

- **Thermal fuse** — senses the **boiler body**, slow. On dry-fire the
  **element surface** spikes far faster than the body the fuse is taped to; the
  element is often already gone before the body cooks the fuse. Fire backstop,
  not element protection.
- **PT1000 + firmware `MAX_STEAM_TEMP` cut** — same flaw. It reads **body/water**
  temp, not element-surface temp; dry, the element→body heat transfer collapses
  so the PT1000 **lags or reads plausibly low while the element cooks.**

**Conclusion:** the only reliable burnout prevention is **not letting it run
dry** — active water-level sensing with a hard element interlock. Temperature
sensing is structurally too slow/indirect (wrong location, wrong timing).

## 2. The interlock principle

> **The steam element may only fire when water is confirmed above the probe.**

- Water present (probe wet) → heating allowed (subject to all the existing
  arbitration/prime rules).
- Water low (probe dry) → **cut the steam element immediately**, and pulse the
  pump to refill (V1 → boiler) until the probe is wet again, then resume.
- Probe is set at the **minimum safe water level** — above the element, with
  enough margin that "dry probe" still leaves the element submerged while the
  refill runs.

This is a closed-loop hard guard, independent of temperature. Pairs with — does
not replace — the prime gate (`boilerPrimed`), the `MAX_STEAM_TEMP` cut, and the
hardware thermal fuse (all stay as backstops).

## 3. Probe options

### 3a. Conductivity probe — RECOMMENDED (espresso standard)
What the Silvia **Pro** and every dual-boiler/HX machine use, on essentially
this same boiler. A stainless rod, **electrically isolated from the boiler
body**, threaded into a boiler port at the min-safe level:

- Boiler body = ground electrode; probe tip = sense electrode.
- Water bridging probe↔body conducts → "water present."
- Water below the tip → open circuit → "low."

Must drive it with **AC (not DC)** to avoid electrolysis and scale build-up on
the probe. Two ways to wire to the Teensy:

- **Off-the-shelf (robust, my pick):** espresso **autofill probe** + a
  **Gicar / CEME water-level relay module**. The module handles AC excitation +
  anti-scaling and gives the Teensy a clean **dry-contact "low water" signal**
  on a GPIO. ~$30–50, minimal firmware. Proven in thousands of machines.
- **DIY (cheap):** stainless rod + **PTFE compression gland** into a port;
  Teensy does the sensing — toggle a GPIO ~1 kHz through a **series resistor +
  coupling capacitor** (so there's no DC across the probe → no electrolysis),
  read the divider on an ADC or comparator. ~$10 but you own the
  anti-electrolysis / debouncing details.

**Caveat:** conductivity needs mineral content — **distilled water won't
conduct** (same limitation as the Silvia Pro). Fine on tap/bottled/filtered.

### 3b. Float switch — alternative
Magnetic float + reed switch → clean dry contact, works with distilled water.
But mechanical (can scale/stick in a hot boiler) and needs a port that fits the
float. Less favored in espresso steam boilers.

### 3c. Capacitive — overkill
Non-contact, works with distilled, senses through wall or via probe. More
complex, uncommon in espresso. Not worth it here.

## 4. Firmware integration plan (stub now, wire later)

- **Input:** one GPIO = `WATER_LOW` (dry contact from the level module, or the
  result of the DIY sense). Debounce (water sloshes/boils — require the signal
  stable for ~1–2 s before acting).
- **`sys.boilerWaterOk`** flag (debounced). Default **false** until first
  confirmed wet (fail-safe: unknown = don't heat).
- **`arbitrateHeaters()` gate:** add `boilerWaterOk` to the steam-heat
  conditions — exactly like `boilerPrimed`. Element off whenever water isn't
  confirmed.
- **Auto-refill:** when `!boilerWaterOk` during/after steam, pulse the pump
  (V1 → boiler) to refill until wet, then resume. Because the OPV returns
  overfill to the reservoir, **over-pumping can't overfill** — so erring long on
  the refill pulse is safe.
- **Telemetry:** add a `waterLow` / `boilerWaterOk` field (next free slot after
  the boiler fields) → UI shows boiler level state; STEAM disabled when low.
- **UI:** boiler gauge / STEAM control reflects low-water (e.g. amber "LOW —
  refilling"); optional steam-time budget readout.
- Keep `MAX_STEAM_TEMP` cut + thermal fuse as independent backstops.

Until the probe is fitted, the **sensorless interim** (see `OG_SILVIA_OPERATION.md`
§6) is: proactive pump top-ups keyed to steam usage, **err full**, OPV returns
the excess. Less precise (needless temp-dropping top-ups) but keeps off the dry
limit.

## 5. Shopping list (when ready)
- 1× espresso **steam-boiler autofill/level probe** (stainless, threaded — match
  the boiler port; the OG Silvia / Silvia Pro probe lineage fits this boiler).
- 1× **Gicar (or CEME) water-level relay module** with dry-contact output —
  *or* go DIY with a stainless rod + PTFE gland + the AC-excitation circuit.
- PTFE/Teflon insulating gland or washer set to isolate the probe from the body.
- Short wire to a spare Teensy GPIO.

## 6. Open hardware questions (confirm before ordering)
1. Which boiler port can take the probe, and at what height does it land
   (= the min-safe water level; must keep the element submerged)?
2. Boiler-body electrical ground path back to the sensing circuit (the body is
   one electrode — needs a reliable bond).
3. Water type in normal use (rules out distilled-only → conductivity is fine).
