# PT1000 Brew Sensor Debug Log

## Problem Statement

Brew PT1000 reads ~363°C instead of room temp (~26°C). Steam PT1000 always reads correctly (26°C). The issue appeared after adding NAU7802 scale support and new solenoid relay boards to the project. The problem persisted across reflashing — flashing standalone PT1000 test code onto an affected Teensy still showed 363°C for brew, leading us to believe the Teensy was permanently damaged.

## Hardware

- Teensy 4.0 (i.MX RT1062)
- 2× MAX31865 boards with 4.3kΩ RREF, PT1000 sensors, 2-wire
- Brew CS: pin 10 (also tried pin 8 — same result)
- Steam CS: pin 6
- SPI bus: pins 11 (MOSI), 12 (MISO), 13 (CLK)
- I2C bus: pins 18 (SDA), 19 (SCL) — ADS1115 (0x48) + NAU7802 (0x2A)
- SparkFun Qwiic Scale NAU7802 breakout (has 2.2kΩ I2C pull-ups, internal AVDD LDO)
- 2× solenoid valve relays via BSS138 MOSFET drivers on pins 20, 21
- 2× SSR heaters on pins 15, 16
- Pump motor driver on pin 9, enable via optoisolator on pin 3
- Potentiometer on A0

## Debug Session — 2026-04-07

### Phase 1: Initial analysis (wrong theory — "permanent silicon damage")

**Observed behavior:**
1. Fresh Teensy + standalone PT1000 test → 26°C, 26°C ✓
2. Flash full Silvia firmware → 363°C, 26°C ✗
3. Flash standalone PT1000 test back → 363°C, 26°C ✗ (still broken!)
4. New fresh Teensy + standalone test → 26°C, 26°C ✓

This pattern looked like permanent I/O cell damage on the Teensy. We initially suspected:
- Pin 9 (pump PWM) physically adjacent to pin 8/10 (brew CS) — substrate coupling
- GPIO latch-up from inductive kickback
- 3.3V rail overload from combined peripheral current draw

**Ruled out early:**
- Pin 10 SPI0 SS conflict — moved brew CS to pin 8, same result, reverted to pin 10
- Software vs hardware SPI — tried both, same result
- I2C bus interference — commented out all I2C init and reads in firmware, same result
- Sensor/PCB hardware — standalone test works on fresh Teensy with same MAX31865 boards
- PT1000 config — RNOMINAL=1000, RREF=4300, 2-wire mode all verified

### Phase 2: Narrowing suspects

**Key clue:** The system was working before two changes:
1. NAU7802 scale library added (SparkFun Qwiic Scale)
2. New relay boards added for solenoid valves (pins 20/21)

This shifted focus from the "old" pins (pump, heaters, pot, ADS1115) to the two new additions.

**Created two isolated test sketches:**
- `pt1000_plus_scale/` — PT1000s + NAU7802 + ADS1115 (no GPIOs, no relays)
- `pt1000_plus_relays/` — PT1000s + valve relays on pins 20/21 (no I2C)

**Result:** `pt1000_plus_scale` FAILED on a fresh Teensy (brew 363°C). **NAU7802 / I2C identified as the culprit.** Relay boards were innocent.

### Phase 3: Investigating the NAU7802

**Checked the SparkFun NAU7802 library source:**
- Constructor is empty — no side effects
- `begin()` is pure I2C — no SPI, no GPIO, no pin 10 interaction
- Library is completely clean

**Hardware checks (on affected Teensy):**
- 3.3V rail: normal, no sag
- SDA to SPI pin resistance: 2.6MΩ — no shorts
- NAU7802 AVDD pin: floating at 3.3V (internal LDO output, no load cell connected)
- Scale works fine standalone on the "damaged" Teensy — I2C is undamaged

**Dead end:** NAU7802 connected vs disconnected made no difference on affected Teensy — brew always 363°C. The damage appeared permanent regardless of wiring state.

### Phase 4: Breakthrough — not permanent damage

**Key discovery:** After running the standalone NAU7802 calibration test code, then reflashing the PT1000 standalone test, **both sensors read correctly again (26°C, 26°C).** The Teensy was NOT permanently damaged.

However, this "fix" did not repeat reliably on subsequent attempts.

**Second breakthrough:** Flashing the Arduino **Blink** example (no SPI at all), then reflashing the PT1000 test code → **both sensors read correctly.** This was repeatable.

**Conclusion:** The "permanent damage" was actually a **stuck SPI peripheral state** on the Teensy 4.0's LPSPI4 hardware. This state:
- Survives soft resets and USB reflashing (the LPSPI4 registers retain values)
- Does NOT survive flashing a non-SPI sketch (which reinitializes all pins as basic GPIO)
- Is NOT actual silicon damage — all Teensy boards are fine

### Phase 5: Root cause and fix

**Root cause:** When I2C libraries (Wire.h, NAU7802, ADS1115) are linked alongside SPI (Adafruit_MAX31865), the Teensy 4.0's LPSPI4 peripheral can inherit a corrupted configuration from a previous flash. The MAX31865 library's `begin()` method does not fully reset the SPI peripheral before use — it assumes a clean state.

**Fix:** Add an explicit SPI hard-reset at the very top of `setup()`, before any peripheral initialization:

```cpp
#include <SPI.h>

void setup() {
  // Hard-reset SPI peripheral — clears stale state from previous flash
  pinMode(PT1000_BREW_CS, OUTPUT);  digitalWrite(PT1000_BREW_CS, HIGH);
  pinMode(PT1000_STEAM_CS, OUTPUT); digitalWrite(PT1000_STEAM_CS, HIGH);
  pinMode(11, OUTPUT);              digitalWrite(11, LOW);   // MOSI
  pinMode(12, INPUT);                                         // MISO
  pinMode(13, OUTPUT);              digitalWrite(13, LOW);   // SCK
  SPI.end();
  delay(50);
  // ... rest of setup
}
```

**Also required:** NAU7802 needs the full init sequence from the working standalone code:
```cpp
myScale.begin();
myScale.setSampleRate(NAU7802_SPS_320);
myScale.calibrateAFE();  // Resets analog front-end to clean state
```

**Result:** Combined PT1000 + scale test (v2) works reliably with both fixes applied. Brew reads 26°C, steam reads 26°C, scale reports weight values. Survives repeated reflashing without needing blink in between.

### Recovery procedure (if stuck state occurs)

Flash any non-SPI sketch (e.g. File → Examples → Basics → Blink), then reflash the target firmware. The intermediate sketch clears the stale LPSPI4 state.

## What we tried (chronological)

| # | Test | Result |
|---|------|--------|
| 1 | Move brew CS from pin 10 to pin 8 | Same failure |
| 2 | Software SPI vs hardware SPI | Same failure |
| 3 | Disable all I2C in firmware (comment out Wire.begin, ADS1115, NAU7802) | Same failure (stale state already set) |
| 4 | Power cycle affected Teensy (USB unplug 30s) | Did not fix |
| 5 | Incremental debug sketch with compile flags per subsystem | Superseded by focused tests |
| 6 | `pt1000_plus_relays` — PT1000 + valve relays only | PASSED — relays are innocent |
| 7 | `pt1000_plus_scale` — PT1000 + NAU7802 + ADS1115 | FAILED — brew 363°C |
| 8 | Standalone NAU7802 cal code → reflash PT1000 test | Fixed once, not repeatable |
| 9 | Flash Blink → reflash PT1000 test | Fixed — repeatable! |
| 10 | `pt1000_plus_scale_v2` — SPI hard-reset + full NAU init before PT1000 | PASSED — both sensors correct |

## What we learned

1. **Teensy 4.0 LPSPI4 retains register state across reflashing.** This is not documented in the Teensy or NXP i.MX RT1062 Arduino core. A soft reset does not fully reinitialize the SPI peripheral if it was previously configured.

2. **Mixed SPI + I2C projects need explicit SPI reset.** The Adafruit_MAX31865 library assumes a clean SPI state. When Wire.h and I2C device libraries are linked in the same sketch, the SPI peripheral may start in a corrupted state.

3. **NAU7802 requires full init sequence.** `scale.begin()` alone is insufficient — `setSampleRate()` and `calibrateAFE()` are needed to put the analog front-end into a stable state. The SparkFun example code does this but doesn't document it as mandatory.

4. **"Permanent hardware damage" should be questioned.** What appeared to be blown I/O cells was actually a stuck peripheral register. Always try flashing an unrelated sketch (blink) before concluding silicon damage.

5. **The SparkFun NAU7802 library is clean.** No SPI interaction, no GPIO side effects, empty constructor. The issue is at the Teensy hardware abstraction layer, not the library.

## Files created during debug

| File | Purpose |
|------|---------|
| `test_sketches/pt1000_incremental_debug/` | Multi-level compile-flag test (superseded) |
| `test_sketches/pt1000_plus_scale/` | Isolated PT1000 + NAU7802 test — confirmed failure |
| `test_sketches/pt1000_plus_relays/` | Isolated PT1000 + relay test — confirmed relays innocent |
| `test_sketches/pt1000_scale_bisect/` | Bisect test for I2C subsystems (not needed after blink discovery) |
| `test_sketches/pt1000_cs_swap/` | CS pin swap diagnostic (not needed after blink discovery) |
| `test_sketches/pt1000_plus_scale_v2/` | **Working combined test** with SPI reset fix |

## Two bugs found

### Bug 1: Stale SPI peripheral state (the 363°C bug)
- Teensy 4.0 LPSPI4 retains register state across reflashing
- When I2C libraries are linked alongside SPI, brew PT1000 reads 363°C
- Fix: SPI hard-reset at top of setup(), I2C init before PT1000 init
- Recovery: flash Blink sketch to clear stale state

### Bug 2: config.h pin mismatch (the 988.8°C bug)
- `config.h` had `PT1000_BREW_CS 8` from an earlier debug attempt to move off pin 10
- Physical wiring was on pin 10, test sketches hardcoded pin 10
- Main firmware used config.h → tried to talk to pin 8 → no device → 0xFF fault, 988.8°C on BOTH sensors
- Fix: restored `PT1000_BREW_CS 10` in config.h
- This also explains why "disabling I2C in main firmware" didn't fix it previously — the pin was wrong regardless

## Changes applied to main firmware

In `silvia_lever_main.ino`:
1. Added `#include <SPI.h>`
2. Added SPI hard-reset block at top of `setup()` (before safe-state GPIO init)
3. Changed init order: SPI reset → actuator safe-state → I2C/NAU7802 → PT1000 last
4. Actuator safe-state uses `analogWrite(pin, 0)` for PWM pins (needed to configure FlexPWM timer) and `digitalWrite(pin, LOW)` for digital pins
5. Re-enabled I2C bus init (was disabled for debug)
6. Added `Wire.setClock(400000)`, `scale.setSampleRate(NAU7802_SPS_320)`, `scale.calibrateAFE()` to NAU7802 init
7. Re-enabled pressure and scale reads in `loop()`
8. Added `PUMP_ENA_PIN 3` — optoisolator enable for pump motor driver (HIGH to run, LOW at boot)
9. Added `PUMP_PWM_FULL 254` — Teensy 4.0 `analogWrite(pin, 255)` outputs constant HIGH with no PWM edges; motor driver needs actual toggling, so use 254

In `config.h`:
10. Restored `PT1000_BREW_CS` from 8 back to 10 (matching physical wiring)
11. Added `PUMP_ENA_PIN 3` and `PUMP_PWM_FULL 254`

In `qml_backend.py`:
12. Removed auto-start priming on connect (`_auto_start_heating` no longer fires)
13. App starts in IDLE; priming triggered by user entering brew screen
