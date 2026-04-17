# Silvia Lever — Plumbing Design Notes

Captured from debug session on 2026-04-14 during initial flow testing. Documents the water circuit, the pressure relief design, and the safety analysis of running a pressurized thermocoil between extractions.

---

## Water Circuit Topology

```
RESERVOIR
    │
    ▼
  PUMP (Ulka-style vibratory)
    │
    ▼
  CHECK VALVE (one-way, prevents backflow into pump)
    │
    ▼
  VALVE 1 (V1, "pump valve")
    │   DE-ENERGISED → pump → thermoblock path (default, heaviest duty)
    │   ENERGISED    → pump → boiler path (intermittent steam use)
    ▼
  OPV (over-pressure valve, set to 10–11 bar for backflushing)
    │
    ▼
  THERMOCOIL (stainless coil inside aluminum thermoblock,
               PT1000 + cartridge SSR heater attached)
    │
    ▼
  VALVE 2 (V2, "thermoblock valve")
    │   ENERGISED → thermoblock → portafilter manifold
    │   DE-ENERGISED → thermoblock → drain
    ▼
  PORTAFILTER MANIFOLD (vertical column)
    │  └── pressure sensor (Honeywell MIP via ADS1115)
    ▼
  PORTAFILTER / GROUP HEAD
```

A separate path runs from V1 (de-energised state) → boiler → steam wand for the steam side.

---

## V2 Plumbing Mistake (and Fix)

### Symptom
Pump generates pressure to ~5 bar through the brew path. Cutting pump PWM to zero and toggling V2 to "drain" position does **not** relieve portafilter manifold pressure — it stays at 5 bar (and momentarily climbs to 6–7 bar during the switch). The only way to fully bleed pressure is to cut AC power to the entire machine; pressure then bleeds to zero over ~5 seconds.

### Root cause
3-way solenoid valves have three ports: IN (common), OUT1, and OUT2. One outlet is energised-active and the other is de-energised-active. The portafilter manifold was plumbed to the wrong outlet of V2 — specifically, the outlet that **stays connected when V2 de-energises to "drain"**. So switching V2 only diverted the upstream pump pressure between drain and the manifold feed. The manifold itself was on a port that never actually relieved to atmosphere.

### Fix
Swap the V2 OUT1 and OUT2 connections so the portafilter manifold sits on the port that opens to drain when V2 de-energises. After the swap, switching V2 off should connect manifold → drain directly and dump pressure instantly.

### How the pressure sensor reading made it confusing
The pressure sensor is mounted directly on the portafilter manifold. Before the fix, the sensor read manifold pressure — which was decoupled from V2's switching state because the manifold was on the always-connected port. The reading "rising to 6–7 bar" when toggling V2 was a transient back-pressure spike, not actual flow rerouting.

### Diagnostic that nailed it
Cutting AC bled pressure to zero over 5 seconds. This works because the pump's outlet check valve is the only thing holding line pressure when the pump stops; cutting AC fully de-energises the pump solenoid and lets the check valves snap open, allowing slow back-bleed through the pump. If V2 had been correctly plumbed, switching V2 to drain would have bled pressure faster than the pump check valve eventually does.

---

## Standing Pressure Between Extractions

### What happens after the V2 fix
With V2 plumbed correctly, switching V2 to drain dumps **portafilter manifold** pressure to atmosphere instantly. But the line **upstream of V2** — pump check valve → V1 → OPV → thermocoil → V2 inlet — stays pressurised at whatever the pump last left it, capped by the OPV setpoint (10–11 bar in this build). It will sit at that pressure indefinitely between extractions.

The only relief paths upstream of V2 are:
- The OPV (relieves above setpoint, back to inlet/reservoir)
- Cutting AC power to the pump (lets the pump check valve back-bleed slowly)

So after every shot, the thermocoil sits at ~9–11 bar of static water until the next extraction or until thermal cycling pushes the OPV open.

### Is this a "bomb"?
Initial reaction: a thermocoil encased in a metal block, sitting at 9 bar, perpetually — feels dangerous.

The honest physics answer: **no, it's not.** Here's why:

1. **Water is essentially incompressible.** Stored energy in pressurised liquid is minimal. A 30–50 ml thermocoil at 9 bar holds roughly **0.5–1 joule** of compression energy. For comparison:
   - Car tire (2.5 bar, ~30 L of *gas*): ~7000 J
   - Compressed air tank (8 bar, several L of gas): tens of thousands of J
   - The thermocoil at 9 bar of water has less stored energy than dropping a coin from desk height.

2. **Failure mode is a leak, not an explosion.** If a fitting cracks at 9 bar of liquid, you get a small spurt and pressure drops to zero in milliseconds. There's no expansion phase, no shrapnel, no over-pressure wave. Liquid systems just don't behave like gas systems on failure.

3. **Stainless tubing is wildly over-rated for this load.** Typical 5–8 mm OD stainless thermocoil tubing has burst pressures of **200–400 bar**. Running it at 9 bar uses 3–5 % of its rated capacity. The tubing is loafing.

4. **Comparable systems sit pressurised continuously without incident:**
   - Home water heaters: 4–6 bar, 100+ liters of water, decades of service
   - Hydraulic systems on machinery: hundreds of bar continuously
   - Industrial process plumbing: routine
   - The brew lines on every commercial espresso machine ever made: this is exactly how they work

5. **Real failure modes are slow and visible:**
   - Seal weep (you see a drip, you replace the seal)
   - Fitting loosening over years (slow leak)
   - Joint fatigue from pressure *cycling* — but you'd cycle through this range during brewing anyway, so static-vs-cycling is moot for total cycle count

6. **The OPV is your safety valve.** If thermal expansion (heater cycling between shots on a dead-headed line) pushes pressure above the OPV setpoint, the OPV bleeds the excess back to the reservoir. The system **cannot** exceed the OPV setting. This is the entire point of the OPV being there.

### The actually scary failure mode (and why it doesn't apply)
The one mode that **would** be dangerous is **dry-firing the heater on an empty thermocoil**. Water → steam is roughly a **1700× volume expansion**, which means real gas-phase energy storage. If the heater ran on an empty coil and somehow trapped steam at high pressure, that *would* be a bomb-like failure.

This doesn't apply to the Silvia Lever because:
- The firmware enforces a **priming sequence** before heating — you can't start a heat cycle without first running the pump and filling the line with water
- The line stays liquid-full as long as plumbing is intact (no air pockets to flash to steam)
- Even if a tiny pocket existed, the OPV would relieve it long before it became dangerous

### Commercial design parallel
Every commercial espresso machine — E61 groups, lever machines, multi-boiler HX setups — uses exactly this pattern: a 3-way solenoid right at the group head, with the line upstream of the solenoid sitting at brew pressure (or at OPV setpoint) between shots. The 3-way valve exists specifically to relieve **puck pressure** instantly while leaving the upstream system at working pressure ready for the next shot. The Silvia Lever build is following standard commercial practice.

---

## Physical Valve Port Wiring (2026-04-14)

After the V1 inversion and V2 port re-plumbing, the actual physical port assignments on each valve are:

### Valve 1 (V1, pin D21)
- **IN**   ← pump check valve outlet
- **OUT1** → boiler inlet
- **OUT2** → thermoblock inlet (via OPV)

V1 is wired so that the **de-energised** state (default, no coil power) routes IN → OUT2 = pump → thermoblock. **Energised** routes IN → OUT1 = pump → boiler.

### Valve 2 (V2, pin D20)
- **IN**   ← portafilter manifold (and pressure sensor)
- **OUT1** → pump line / thermoblock outlet
- **OUT2** → drain

V2 is wired so that the **de-energised** state (default) routes IN → OUT2 = portafilter manifold → drain (pressure relief). **Energised** routes IN → OUT1 = portafilter manifold ↔ thermoblock outlet (brewing).

Note: V2 IN is the portafilter manifold side, not the thermoblock side. This is intentional — it puts the pressure sensor and the relief path on the same physical port, so de-energising V2 instantly bleeds manifold pressure to drain regardless of upstream pump state. The thermoblock outlet feeds in via OUT1 only when V2 is energised for brewing.

---

## V1 Polarity Inversion (2026-04-14)

Both V1 and V2 are wired so the **most-used state is de-energised**. This minimises:
- Solenoid coil power consumption (continuous duty cycle when machine is on)
- Coil heating (saves the windings over years of use)
- Wear on valve internals from constant magnetic actuation

Specifically:
- **V1 default (de-energised) = pump → thermoblock.** The brew path is the heaviest duty cycle. Every shot, every flush, every prime uses this path. Default state should be free.
- **V1 energised = pump → boiler.** Only used when filling the boiler or priming the steam side. Intermittent.
- **V2 default (de-energised) = thermoblock → drain.** This is also the pressure-relief state. Every brew ends with V2 dropping back to drain to relieve puck pressure. Safe default.
- **V2 energised = thermoblock → portafilter.** Only during active brewing/flushing. Intermittent.

State table for both valves:

| V1 | V2 | Path |
|----|----|------|
| OFF | OFF | pump → thermoblock → drain (priming, flushing) |
| OFF | ON  | pump → thermoblock → portafilter (brewing) |
| ON  | OFF | pump → boiler (boiler fill, steam priming) |
| ON  | ON  | pump → boiler (V2 state irrelevant) |

The all-off state is also the default at boot and the safe state after `safeOff()`. With the pump disabled, the routing doesn't matter functionally, but de-energised is electrically safer and matches the most-frequent operating state.

---

## Pump Behavior Notes

### Pot dead zone
The pot's full travel maps linearly to PWM 0–254. But the motor doesn't actually start producing useful flow until PWM is roughly 80+. Result: the bottom ~30 % of pot travel is a dead zone where nothing happens, and all the usable speed range is compressed into the top ~70 % of the pot's rotation. Fix: remap the pot in software so 0–1023 maps to `PUMP_MIN_PWM`–254 instead of 0–254. Drops the bottom dead zone in exchange for a proportional control across the whole pot range.

### Pressure relief and the pump check valve
The pump's outlet check valve holds line pressure indefinitely when the pump stops. This is normal vibratory pump behaviour and necessary to prevent backflow damage. The consequence is that the line upstream of V2 cannot bleed by stopping the pump alone — it bleeds only when the OPV setpoint is exceeded (thermal expansion) or when AC power is fully cut (pump solenoid relaxes and check valves snap open). Operationally this is fine because V2 handles all the pressure relief that matters during brewing.

### PWM frequency and motor responsiveness
Default Arduino `analogWrite` runs at ~4.4 kHz on Teensy 4.0. This is audible and somewhat coarse for motor control. The flow_test sketch uses `analogWriteFrequency(PUMP_PWM_PIN, 36621)` to set ~36 kHz — ultrasonic and smoother. Motor responds more linearly to PWM changes at this frequency.

### Why analogWrite(pin, 255) doesn't work
On Teensy 4.0 (and standard Arduino), `analogWrite(pin, 255)` outputs a constant HIGH with no PWM edges. Some motor drivers — including the one in this build — need actual switching edges to produce output. Use `PUMP_PWM_FULL = 254` for full speed instead.

---

## Pinout Reference (relevant subset)

| Pin | Function | Notes |
|-----|----------|-------|
| D3  | `PUMP_ENA_PIN` | Optoisolator enable; gates PWM to motor driver, prevents boot glitch |
| D9  | `PUMP_PWM_PIN` | PWM to motor driver, max 254 |
| A0  | `POT_PIN` | Potentiometer input |
| D20 | `VALVE_THERMOBLOCK_PIN` (V2) | LOW (default) = thermoblock → drain, HIGH = thermoblock → portafilter |
| D21 | `VALVE_PUMP_PIN` (V1) | LOW (default) = pump → thermoblock, HIGH = pump → boiler |

Pressure sensor: Honeywell MIP via ADS1115 on I2C, mounted on portafilter manifold.
