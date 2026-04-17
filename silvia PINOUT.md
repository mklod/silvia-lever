# Silvia Lever — Teensy 4.0 Pinout

## GPIO Pin Assignments

| Pin | Type | Function | Config Define | Notes |
|-----|------|----------|---------------|-------|
| A0 (D14) | Analog In | Potentiometer | `POT_PIN` | Manual pump speed control |
| D3 | Digital Out | Pump enable | `PUMP_ENA_PIN` | Optoisolator — HIGH passes PWM to motor driver, LOW blocks signal. Prevents boot-up glitch. |
| D9 | PWM Out | Pump speed | `PUMP_PWM_PIN` | PWM to motor driver. Use 254 max (not 255 — constant HIGH has no edges, driver ignores it). |
| D10 | SPI CS | Brew PT1000 | `PT1000_BREW_CS` | MAX31865 chip-select for thermoblock sensor |
| D6 | SPI CS | Steam PT1000 | `PT1000_STEAM_CS` | MAX31865 chip-select for boiler sensor |
| D11 | SPI MOSI | SPI data out | `PT1000_MOSI` | Shared SPI bus (both MAX31865) |
| D12 | SPI MISO | SPI data in | `PT1000_MISO` | Shared SPI bus |
| D13 | SPI CLK | SPI clock | `PT1000_CLK` | Shared SPI bus |
| D15 | PWM Out | Brew heater | `HEATER_BREW_PIN` | SSR for thermoblock, PID controlled |
| D16 | PWM Out | Steam heater | `HEATER_STEAM_PIN` | SSR for boiler, thermostat with 2°C hysteresis |
| D18 | I2C SDA | I2C data | `I2C_SDA` | Shared bus: ADS1115 (0x48) + NAU7802 (0x2A) |
| D19 | I2C SCL | I2C clock | `I2C_SCL` | 400 kHz, pull-ups on SparkFun NAU7802 breakout (2.2kΩ) |
| D20 | Digital Out | Valve 2 | `VALVE_THERMOBLOCK_PIN` | HIGH → thermoblock→portafilter, LOW → thermoblock→drain |
| D21 | Digital Out | Valve 1 | `VALVE_PUMP_PIN` | LOW → pump→thermoblock (default, heaviest duty), HIGH → pump→boiler |

## I2C Devices

| Address | Device | Breakout Board | Function |
|---------|--------|----------------|----------|
| 0x48 | ADS1115 | Adafruit ADS1115 | Pressure sensor ADC (Honeywell MIP, 0–16 bar) |
| 0x2A | NAU7802 | SparkFun Qwiic Scale | Load cell ADC (single cell, 320 SPS) |

## SPI Devices

| CS Pin | Device | Breakout Board | Function |
|--------|--------|----------------|----------|
| D10 | MAX31865 | Adafruit PT1000 | Thermoblock temperature (brew) |
| D6 | MAX31865 | Adafruit PT1000 | Boiler temperature (steam) |

## Peripheral Summary

| Subsystem | Pins Used | Driver IC | Notes |
|-----------|-----------|-----------|-------|
| Pump | D3 (ENA), D9 (PWM), A0 (pot) | Motor driver + optoisolator | ENA gates PWM; max PWM = 254 |
| Brew heater | D15 | SSR | PID: Kp=30, Ki=0.5, Kd=5 |
| Steam heater | D16 | SSR | Thermostat, 2°C hysteresis |
| Valve 1 (pump routing) | D21 | BSS138 MOSFET → IM01GR relay | LOW = pump→thermoblock (default), HIGH = pump→boiler |
| Valve 2 (thermoblock outlet) | D20 | BSS138 MOSFET → IM01GR relay | LOW = thermoblock→drain (default), HIGH = thermoblock→portafilter |
| Brew PT1000 | D10, D11, D12, D13 | MAX31865 | RREF=4300Ω, RNOMINAL=1000Ω, 2-wire |
| Steam PT1000 | D6, D11, D12, D13 | MAX31865 | Shares SPI bus with brew sensor |
| Pressure | D18, D19 | ADS1115 | Auto-zero calibration at startup |
| Scale | D18, D19 | NAU7802 | Requires setSampleRate(320) + calibrateAFE() |

## Pins NOT Used

D0, D1, D2, D4, D5, D7, D8, D14 (used as A0), D17, D22, D23

## Known Quirks

- **SPI.end() required at boot** — Teensy 4.0 LPSPI4 retains stale state across reflashing when I2C is also linked. Must call `SPI.end()` + reset CS pins before any peripheral init.
- **Init order matters** — SPI reset → actuators → I2C/NAU7802 → PT1000 (last).
- **analogWrite(pin, 255) = constant HIGH** — No PWM edges. Motor driver ignores it. Use 254 max.
- **Pin 10 is SPI0 hardware SS** — Works as CS but has special SPI role on i.MX RT1062.
