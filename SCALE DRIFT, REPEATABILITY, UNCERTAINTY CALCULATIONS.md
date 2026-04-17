# Scale — Stability, Noise, and Uncertainty

Findings from the 2026-04-15 tuning session.

## Hardware

- **Load cell**: replaced during session (previous cell had silently failed; produced noise-floor readings with no response to weight changes)
- **ADC**: NAU7802 over I2C (SparkFun Qwiic Scale breakout at addr 0x2A)
- **Bus**: shared I2C with ADS1115 pressure sensor (addr 0x48), Teensy 4.0 host at 400 kHz
- **Gain**: 128× (NAU7802 library default)
- **Sample rate**: 320 SPS (`NAU7802_SPS_320`)
- **LDO**: 3.3 V (library default via `begin()`)
- **Cal factor**: **2048.91** raw counts per gram (measured with 100 g reference)

## Measured stability

Data captured with 100 g reference weight sitting on a tared + calibrated scale, ~55 seconds of continuous readings from the `DATA:` telemetry field.

### Single-sample read (initial implementation, `scale.getReading()` + manual math)
| Metric | Value |
|---|---|
| Samples | 294 |
| Mean | 100.015 g |
| Min | 99.30 g |
| Max | 100.40 g |
| Range | **1.10 g** |
| Noise | ±0.55 g |
| Cal factor | 2049.51 |

### 32-sample averaging (`scale.getWeight(true, 32)`)
| Metric | Value |
|---|---|
| Samples | 549 |
| Mean | 99.991 g |
| Min | 99.90 g |
| Max | 100.10 g |
| Range | **0.20 g** |
| Noise | **±0.10 g** |
| Cal factor | 2048.91 |

### Summary
- **5.5× noise reduction** from 32-sample averaging, matching the theoretical √32 = 5.66× for white noise
- **Mean accuracy**: 0.009 % error against the 100 g reference (99.991 g measured)
- **Target precision hit**: ±0.1 g stability is sufficient for espresso extraction timing and final shot weight targeting

## Current implementation

File: `firmware/silvia_lever_main/silvia_lever_main.ino`, inside `updateSensors()`:

```cpp
// ── Scale (NAU7802) ─────────────────────────────────────────────────────
// getWeight(true, 32) averages 32 samples → noise reduction ~√32 = 5.7×.
// Single-sample noise ~±0.55g → averaged noise ~±0.1g. Blocks ~100ms at
// 320 SPS; read interval is 80ms so scale drives the main loop timing.
now = millis();
if (now - lastScaleRead >= SCALE_READ_INTERVAL) {
  sys.weight = scale.getWeight(true, 32);
  lastScaleRead = millis();
}
```

### Parameters
- `allowNegativeWeights = true` — important: without it, `getWeight()` clamps any reading below the zero offset to 0 g, which hides the load cell response when the reading oscillates around zero. With noise at ±0.1 g that would mean all sub-zero samples show as 0 g, creating a fake "stickiness" at zero.
- `samplesToTake = 32` — drives the averaging; tunable trade-off between noise and latency
- Default `timeout_ms = 1000` ms — plenty of headroom; 32 samples at 320 SPS take ~100 ms

### Tare and calibrate
```cpp
void tareScales() {
  scale.calculateZeroOffset(32);   // 32 samples → ~100ms averaging
  sys.weight = 0.0f;               // match new zero immediately
  sys.scalesTared = true;
}

void calibrateScale(float knownWeight) {
  scale.calculateCalibrationFactor(knownWeight, 64);  // 64 samples → ~200ms
  float newCal = scale.getCalibrationFactor();
  Serial.print("NEW_CAL:"); Serial.println(newCal, 4);
}
```

Tare uses 32 samples (~100 ms). Calibrate uses 64 samples (~200 ms) — more averaging because a bad cal factor poisons subsequent reads until the next cal.

### Init sequence (order matters)
```cpp
// ── Step 1: I2C bus
Wire.setSDA(I2C_SDA);
Wire.setSCL(I2C_SCL);
Wire.begin();
Wire.setClock(400000);

// ── Step 2: ADS1115 pressure + auto-zero (2.5 seconds of I2C traffic)
// ── Step 3: PT1000 sensors (SPI)

// ── Step 4: NAU7802 init LAST — avoids getting disturbed by other I2C/SPI init
if (!scale.begin()) {
  Serial.println("ERROR:NAU7802_INIT_FAILED");
} else {
  scale.setSampleRate(NAU7802_SPS_320);
  scale.calibrateAFE();
}
```

NAU7802 is initialized **last** in `setup()`. Earlier attempts that initialized it first left the chip in a bad state after the subsequent ADS1115 init / pressure zero loop — reason not fully understood, but empirically the "init last" order is reliable.

## Known constraints and concerns

### Blocking read
`getWeight(true, 32)` blocks the main loop for ~100 ms per call, while the read interval is 80 ms. Effectively the scale read is the dominant consumer of loop time:
- Loop frequency drops to ~10 Hz during active scale reads
- Other sensors (PT1000, ADS1115) are read between scale reads and get enough bandwidth at their 500 ms / 130 ms intervals
- Pot read runs every loop iteration so pump responsiveness is ultimately gated by the scale read time (~100 ms)

For brewing this is fine — 100 ms pot latency is imperceptible to a user turning a knob. For very fast pressure profiling or closed-loop flow control it would need revisiting.

### Calibration factor persistence
- Cal factor is stored in `ui/windows/source/settings.json` as `scale_cal`
- Python `_restore_scale_calibration` sends `SET_SCALE_CAL <value>` ~400 ms after connect
- The firmware does not persist cal factor across reboots itself — it lives in the UI settings file
- Guards in `qml_backend.py` reject invalid cal factors (negative, ≤0, ≥100000, or absolute value < 1.0) and auto-restore the previous good value to the firmware via `SET_SCALE_CAL`

### Zero offset persistence
- **Not persisted.** Zero offset is set on user tare (`TARE_SCALES` command) and lives only in the NAU7802 library's RAM state.
- A reboot wipes it; the user must tare after each start-up.
- If a production feature is desired, add a `scale_zero` field to `settings.json` and send `SET_SCALE_ZERO <offset>` on startup (not currently implemented).

### Hardware mode
- Running the NAU7802 at library default gain **128×** (maximum)
- Further noise reduction would need either more averaging (higher `samplesToTake`), slower sample rate (more internal integration per sample), or better mechanical isolation of the load cell
- Physical limits are already close: the NAU7802 at 128× gain with a 2 mV/V load cell and 3.3 V excitation has a theoretical 1-sigma noise around 5-10 nV, which is already within factor ~2 of what we're seeing

### Interference during other activity
Not yet characterized under:
- Pump running (motor PWM at 36 kHz on pin 9)
- SSRs firing (not tested; `COLD_TEST_MODE` still on)
- Valve relays switching
- Vibration from the lever arm

Expect some additional noise during extraction. If it becomes a problem, possible mitigations:
- Switch to a higher `samplesToTake` value only during brewing
- Software median filter on top of the library average
- Accept temporary noise while motor is active and rely on pre-brew tare as ground truth

## Further optimization paths (not pursued)

Listed in roughly increasing order of effort:
1. **Increase `samplesToTake` to 64 or 128** — more averaging, longer lag. 64 = √2 more reduction (0.07 g noise target). 128 = full 400 ms block per read, loop frequency drops to ~2.5 Hz.
2. **Lower sample rate to 80 SPS** — each sample is integrated 4× longer internally. Need to verify the init still works reliably (earlier testing had issues with slower rates).
3. **Running IIR filter** on top of library average — smoother display, adds lag in brew tracking.
4. **Custom calibration factor tuning** — currently calibrated against a single 100 g weight. Using multiple reference weights (10 g, 50 g, 200 g) and fitting a line could improve linearity across the espresso shot weight range (10 – 60 g).
5. **Mechanical damping** — vibration isolation mount for the load cell reduces noise during pump operation.

## Test protocol for regression

1. Flash main firmware with cal routine intact
2. Tare with empty scale
3. Place reference weight (100 g or 50 g)
4. Run full calibration via UI cal dialog
5. Collect ~60 seconds of `DATA:` telemetry at rest
6. Extract weight field from log, compute min/max/range/mean/std
7. Acceptance: range ≤ 0.3 g, mean within ±0.1 g of reference

One-liner for the stats from a log file (bash/git bash):
```bash
sed -n '<CAL_LINE>,$p' <LOG> | grep -oE 'W=-?[0-9]+\.[0-9]+' | awk -F= '{print $2}' | \
  awk 'BEGIN{min=1e9;max=-1e9;sum=0;n=0}
       {if($1<min)min=$1;if($1>max)max=$1;sum+=$1;n++}
       END{printf "n=%d min=%.2f max=%.2f range=%.2f mean=%.3f\n",n,min,max,max-min,sum/n}'
```
