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

## 2. The model — "do as the Silvia Pro does" (auto-fill to probe)

**Decision:** replicate the Silvia Pro autofill exactly — it already solved this
on this same boiler. **Probe chosen: Rancilio Silvia Pro water-level probe**
(part 10701803, **3/8 BSP**, steam boiler, ~$15).

The Pro keeps the boiler topped up **to the probe tip**, which is set at the
**target water line**:

- Probe **wet** (water at/above tip) → boiler full enough → **pump off**.
- Probe **dry** (water below tip) → **refill** (pump → boiler) until the probe
  is wet → stop.

Two consequences that simplify everything:

1. **The maintained level (probe line) is well above the element, so the element
   is inherently protected** — there is no separate "cut element when low"
   interlock in normal operation, because the level is *never allowed* to fall
   to the element. The autofill tops up at the probe, far above the heater.
2. **This replaces the manual prime.** On cold start the firmware just
   auto-fills to the probe — no "watch for overflow, tap confirm." Turn it on,
   it fills itself, exactly like the Pro.

The probe tip position also **sets the headspace** (everything above the tip is
steam space — see `OG_SILVIA_OPERATION.md` §5b for sizing; aim the tip to leave
~10–25 % headspace).

Backstops unchanged: `MAX_STEAM_TEMP` cut + hardware thermal fuse remain as
independent fail-safes for probe/pump faults. They don't prevent burnout on
their own (§1) — the autofill does — but they catch a failed autofill.

## 3. How the probe is read (conductivity)

The Silvia Pro probe is a stainless rod, **electrically isolated from the boiler
body**, threaded into a 3/8 BSP port at the target water line:

- Boiler body = ground electrode; probe tip = sense electrode.
- Water bridging probe↔body conducts → "wet."
- Water below the tip → open circuit → "dry."

Must be driven with **AC (not DC)** to avoid electrolysis and scale on the probe.
Two ways to wire it to the Teensy:

- **Sense via a level module (closest to "as the Pro does"):** the Pro uses a
  **Gicar** water-level control box that does the AC excitation/anti-scale and
  outputs a clean signal. For *our* architecture we only want the box's
  **sense** (not its pump drive — the Teensy owns the pump + V1 and shares them
  with brewing, so an autonomous Gicar fill would conflict). Use a
  sense-only / dry-contact output → Teensy GPIO. Robust, minimal firmware.
- **DIY sense (cheap):** Teensy drives the probe through a **series resistor +
  coupling capacitor**, toggling a GPIO ~1 kHz (no DC across the probe → no
  electrolysis), reads the divider on an ADC/comparator. ~$10, we own the
  anti-electrolysis + debounce.

Either way the firmware owns the fill logic (§4), because the pump and V1 are
shared with brewing.

**Caveat:** conductivity needs mineral content — **distilled water won't conduct**
(same limitation as the real Silvia Pro). Fine on tap/bottled/filtered.

## 4. Firmware integration plan (auto-fill to probe — Pro model)

- **Input:** one GPIO = probe **wet/dry**. Debounce ~1–2 s (water boils/sloshes,
  so require a stable read before acting).
- **`sys.boilerWaterOk`** (debounced). Default **false** at boot until first
  confirmed wet (fail-safe: unknown = don't heat).
- **Auto-fill state machine** (replaces the manual `PRIME_BOILER` flow): in any
  boiler-relevant state where the pump is free (IDLE / HEATING_STEAM /
  STEAMING — *not* during BREWING/FLUSHING, which own the pump and V1), if the
  probe is **dry**, energize **V1 → boiler + pump** to refill until **wet**, then
  stop. This maintains the level at the probe continuously, like the Pro.
  - On cold start this *is* the prime — it fills to the probe automatically.
  - `boilerPrimed` becomes "probe has read wet at least once" (auto-set), rather
    than a manual overflow-confirm.
- **Element protection is implicit:** the maintained level (probe) is above the
  element, so the element never sees a dry boiler in normal operation. No
  explicit "cut element when low" needed — but keep the element gated on
  `boilerWaterOk` having been established, so a never-filled / probe-fault boiler
  won't heat dry.
- **Refill-during-steam trade-off:** topping up mid-steam injects cold water →
  brief temp dip (the Pro accepts this). Acceptable; the boiler holds ~4–5
  drinks per fill so refills are infrequent anyway (`OG_SILVIA_OPERATION.md` §5b).
- **OPV still backstops overfill:** because the OPV returns overfill to the
  reservoir, a stuck-on fill can't pressure-overfill — but the probe stops the
  pump at the line, so overfill should be rare/minimal.
- **Telemetry:** add `boilerWaterOk` (next free field after the boiler fields)
  → UI shows level state; brief "FILLING" indicator.
- **UI:** PRIME button becomes informational/automatic (or a manual
  force-fill override); boiler gauge shows "FILLING" when topping up.
- Keep `MAX_STEAM_TEMP` cut + thermal fuse as independent fail-safes for
  probe/pump failure.

Until the probe is fitted, the **sensorless interim** (see `OG_SILVIA_OPERATION.md`
§6) is: manual prime + proactive pump top-ups keyed to steam usage, **err full**,
OPV returns the excess. The probe makes it automatic and precise.

## 5. Shopping list
- **1× Rancilio Silvia Pro water-level probe** — part **10701803**, **3/8 BSP**,
  steam boiler, ~$15 (espressocare.com). OEM for this boiler lineage → mounts
  cleanly, probe length sets a sensible water line.
- Sensing: either a **sense-only level module** (Gicar-style, AC excitation →
  dry-contact out) **or** the DIY AC-sense circuit (series R + coupling cap off a
  Teensy GPIO). *Not* the Gicar pump-driving box — the Teensy owns pump + V1.
- PTFE/Teflon insulating gland/washer if needed to isolate the probe from the
  body (the OEM probe is already isolated — confirm on fit).
- Short wire to a spare Teensy GPIO (+ a ground bond from the boiler body).

## 6. Confirm on fit / before wiring
1. Which 3/8 BSP boiler port takes the probe, and the resulting water line
   (probe tip height = maintained level; everything above = headspace, target
   ~10–25 % — `OG_SILVIA_OPERATION.md` §5b).
2. Boiler-body ground bond back to the sense circuit (body is one electrode).
3. Free Teensy GPIO for the probe input (+ note: the manual `PRIME_BOILER`
   command/UI gets superseded by auto-fill, or demoted to a manual override).
