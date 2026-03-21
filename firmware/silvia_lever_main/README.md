# Silvia Lever Coffee Machine Firmware

## Overview
Integrated Arduino/Teensy 4.0 firmware for the Silvia Lever coffee machine project. Controls all hardware components non-blocking and communicates with PyQt desktop application via USB serial.

## Hardware Components
- **Temperature**: PT100 sensor via MAX31865 (SPI)
- **Pressure**: Honeywell MIP sensor via ADS1115 (I2C)
- **Scales**: Dual HX711 load cells
- **Pump**: PWM controlled motor with potentiometer input
- **Heater**: SSR controlled via PWM
- **Valve**: Digital relay control

## Pin Configuration
```
A0  - Potentiometer (pump speed control)
D8  - Valve relay
D9  - Pump PWM output
D10 - PT100 CS (SPI)
D11 - PT100 MOSI (SPI)
D12 - PT100 MISO (SPI)
D13 - PT100 CLK (SPI)
D15 - Heater SSR PWM
D18 - I2C SDA (pressure sensor)
D19 - I2C SCL (pressure sensor)
D20 - Scale 0 data
D21 - Scale clock (shared)
D22 - Scale 1 data
```

## System States
- `STATE_IDLE` (0): Default state, all outputs off
- `STATE_HEATING_BREW` (1): Heating to brew temperature
- `STATE_HEATING_STEAM` (2): Heating to steam temperature
- `STATE_BREWING` (3): Active brewing with pump and valve
- `STATE_STEAMING` (4): Steam mode active
- `STATE_FLUSHING` (5): Flush cycle active

## Serial Communication Protocol

### Commands (PC → Arduino)
```
SET_BREW_TEMP:<temp>    - Set brew temperature (°C)
SET_STEAM_TEMP:<temp>   - Set steam temperature (°C)
START_BREW              - Begin brew heating cycle
START_STEAM             - Begin steam heating cycle
START_FLUSH             - Begin flush cycle
BREW_NOW                - Start actual brewing (from heating state)
STOP                    - Stop current operation
TARE_SCALES             - Zero the scales
GET_STATUS              - Request current status
```

### Responses (Arduino → PC)
```
READY                   - System initialized
OK:<operation>          - Command acknowledged
ERROR:<message>         - Error occurred
```

### Telemetry Data (Arduino → PC, every 250ms)
```
DATA:<state>,<temp>,<pressure>,<weight>,<pump%>,<valve>,<heater>,<timer>
```
Where:
- `state`: Current system state (0-5)
- `temp`: Current temperature (°C, 1 decimal)
- `pressure`: Current pressure (bar, 2 decimals)
- `weight`: Current weight (grams, 1 decimal)
- `pump%`: Pump power percentage (0-100)
- `valve`: Valve state (0=closed, 1=open)
- `heater`: Heater state (0=off, 1=on)
- `timer`: Brew timer in seconds (0 if not brewing)

### Status Response
```
STATUS:state=<n>,temp=<t>,brewTemp=<bt>,steamTemp=<st>,pressure=<p>,weight=<w>,pump=<pu>,valve=<v>,heater=<h>
```

## Key Features
- **Non-blocking operation**: All sensors read asynchronously
- **Safety first**: System starts in safe state, stops on errors
- **Modular design**: Clear separation of concerns
- **Real-time telemetry**: Continuous data streaming for GUI
- **Hardware potentiometer**: Direct pump speed control
- **Temperature control**: Simple thermostat with hysteresis
- **Scale integration**: Dual load cell support with taring
- **Pressure monitoring**: Calibrated bar readings

## Usage Flow
1. System boots to IDLE state
2. GUI sets brew/steam temperatures
3. User initiates brew/steam/flush operation
4. System heats to target temperature
5. User triggers actual brewing with BREW_NOW
6. System manages pump, valve, heating during operation
7. User stops operation, system returns to IDLE

## Dependencies
- Adafruit_MAX31865 library
- ADS1115_WE library
- HX711 library (non-blocking version recommended)

## Calibration Notes
- Pressure sensor zero voltage: 0.5V (adjust V_ZERO constant)
- Scale calibration factors: 420.0983, 421.365 (adjust as needed)
- Temperature sensor: PT100 with 430Ω reference resistor