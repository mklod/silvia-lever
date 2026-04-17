from PyQt6.QtCore import QObject, pyqtSignal, QTimer
import random
import time

class SerialManager(QObject):
    line_received = pyqtSignal(str)

    # Mirror Arduino state enum (new hardware revision)
    STATE_IDLE          = 0
    STATE_PRIMING_BREW  = 1
    STATE_HEATING_BREW  = 2
    STATE_PRIMING_STEAM = 3
    STATE_HEATING_STEAM = 4
    STATE_BREWING       = 5
    STATE_STEAMING      = 6
    STATE_FLUSHING      = 7

    def __init__(self):
        super().__init__()
        self.connected = False

        # Mirror Arduino SystemData struct
        self.state = self.STATE_IDLE
        self.brewTemp  = 93.0
        self.steamTemp = 130.0

        # Dual temperature readings (thermoblock + boiler)
        self.brewTempActual  = 25.0
        self.steamTempActual = 25.0

        self.pressure             = 0.0
        self.weight               = 0.0
        self.pumpPower            = 0
        # VALVE2: energised → thermoblock coil → group head; de-energised → thermoblock coil → drain
        self.valveThermoblockOpen = False
        # VALVE1: energised → pump → thermoblock OPV; de-energised → pump → boiler OPV
        self.valvePumpOpen        = False
        self.heaterBrewOn         = False
        self.heaterSteamOn        = False
        self.brewTimer            = 0
        self.scalesTared          = False

        # Prime timing (safety watchdog only — priming runs until PRIME_DONE)
        self._primeStart = 0

        self.telemetry_timer = QTimer()
        self.telemetry_timer.timeout.connect(self._send_telemetry)

        self.update_timer = QTimer()
        self.update_timer.timeout.connect(self._update_system)

    def start(self):
        self.connected = True
        self.telemetry_timer.start(100)
        self.update_timer.start(50)
        self.line_received.emit("READY")
        return True

    def stop(self):
        self.connected = False
        self.telemetry_timer.stop()
        self.update_timer.stop()

    def send_command(self, command):
        if not self.connected:
            return
        cmd = command.strip()

        if cmd.startswith("SET_TEMP BREW "):
            temp = float(cmd[14:])
            if 10 <= temp <= 105:
                self.brewTemp = temp
                self.line_received.emit("OK:BREW_TEMP_SET")
            else:
                self.line_received.emit("ERROR:BREW_TEMP_OUT_OF_RANGE")

        elif cmd.startswith("SET_TEMP STEAM "):
            temp = float(cmd[15:])
            if 10 <= temp <= 160:
                self.steamTemp = temp
                self.line_received.emit("OK:STEAM_TEMP_SET")
            else:
                self.line_received.emit("ERROR:STEAM_TEMP_OUT_OF_RANGE")

        elif cmd == "START_BREW":
            if self.state in (self.STATE_IDLE, self.STATE_HEATING_BREW, self.STATE_PRIMING_BREW):
                self.state = self.STATE_PRIMING_BREW
                self._primeStart = time.time()
                # VALVE_PUMP on → pump → thermoblock; VALVE_THERMOBLOCK off → thermoblock → drain
                self.valvePumpOpen = True
                self.valveThermoblockOpen = False
                self.line_received.emit("OK:PRIMING_BREW")
            else:
                self.line_received.emit("ERROR:NOT_IDLE")

        elif cmd == "START_STEAM":
            if self.state == self.STATE_IDLE:
                self.state = self.STATE_PRIMING_STEAM
                self._primeStart = time.time()
                # VALVE_PUMP off (de-energised) → pump → boiler OPV by default
                self.valvePumpOpen = False
                self.valveThermoblockOpen = False
                self.line_received.emit("OK:PRIMING_STEAM")
            else:
                self.line_received.emit("ERROR:NOT_IDLE")

        elif cmd == "START_FLUSH":
            if self.state == self.STATE_IDLE:
                self.state = self.STATE_FLUSHING
                # pump → thermoblock → drain (group head flush, no pressure at group head)
                self.valvePumpOpen = True
                self.valveThermoblockOpen = False
                self.line_received.emit("OK:FLUSH_STARTED")
            else:
                self.line_received.emit("ERROR:NOT_IDLE")

        elif cmd == "PRIME_DONE":
            if self.state == self.STATE_PRIMING_BREW:
                self.pumpPower = 0
                self.valvePumpOpen = False       # stop routing pump to thermoblock
                # VALVE_THERMOBLOCK was already off (drain path)
                self.state = self.STATE_HEATING_BREW
                self.line_received.emit("OK:BREW_PRIMED_HEATING")
            elif self.state == self.STATE_PRIMING_STEAM:
                self.pumpPower = 0
                # VALVE_PUMP was already off (boiler path by default); nothing to change
                self.state = self.STATE_HEATING_STEAM
                self.line_received.emit("OK:STEAM_PRIMED_HEATING")
            else:
                self.line_received.emit("ERROR:NOT_PRIMING")

        elif cmd in ["BEGIN_BREW", "BREW_NOW"]:
            if self.state == self.STATE_HEATING_BREW:
                self.state = self.STATE_BREWING
                self.weight = 0.0
                self.scalesTared = False
                QTimer.singleShot(200, lambda: setattr(self, 'scalesTared', True))
                self.brewTimer = time.time()
                # pump → thermoblock → group head (pressure builds)
                self.valvePumpOpen = True
                self.valveThermoblockOpen = True
                self.line_received.emit("OK:BREWING_STARTED")
            else:
                self.line_received.emit("ERROR:INVALID_STATE_FOR_BREW_NOW")

        elif cmd == "BEGIN_STEAM":
            if self.state == self.STATE_HEATING_STEAM:
                self.state = self.STATE_STEAMING
                # No valve change — steam delivered via steam wand (no relay-controlled valve)
                self.line_received.emit("OK:STEAMING_STARTED")
            else:
                self.line_received.emit("ERROR:INVALID_STATE_FOR_BEGIN_STEAM")

        elif cmd in ["STOP", "ABORT"]:
            self._stop_current_operation()
            self.line_received.emit("OK:STOPPED")

        elif cmd == "TARE_SCALES":
            self.weight = 0.0
            self.scalesTared = True
            self.line_received.emit("OK:SCALES_TARED")

        elif cmd == "GET_STATUS":
            self._send_status()

        elif cmd == "PING":
            self.line_received.emit("PONG")

        elif cmd.startswith("CAL_SCALE "):
            try:
                known = float(cmd[10:])
                if known > 0:
                    new_cal = round(random.uniform(410, 430), 4)
                    self.line_received.emit(f"NEW_CAL:{new_cal}")
                    self.line_received.emit("OK:SCALES_CALIBRATED")
                else:
                    self.line_received.emit("ERROR:INVALID_WEIGHT")
            except Exception:
                self.line_received.emit("ERROR:INVALID_WEIGHT")

        elif cmd.startswith("SET_SCALE_CAL "):
            self.line_received.emit("OK:SCALE_CAL_SET")

        elif len(cmd) > 0:
            self.line_received.emit("ERROR:UNKNOWN_COMMAND")

    def _update_system(self):
        now = time.time()

        if self.state == self.STATE_PRIMING_BREW:
            # pump → thermoblock → drain; runs until PRIME_DONE; 120 s safety timeout
            self.pumpPower = 255
            self.valvePumpOpen = True
            self.valveThermoblockOpen = False
            if now - self._primeStart >= 120.0:
                self.pumpPower = 0
                self.valvePumpOpen = False
                self.state = self.STATE_IDLE
                self.line_received.emit("ERROR:PRIME_BREW_TIMEOUT")

        elif self.state == self.STATE_PRIMING_STEAM:
            # pump → boiler OPV (VALVE_PUMP de-energised by default); runs until PRIME_DONE
            self.pumpPower = 255
            self.valvePumpOpen = False
            self.valveThermoblockOpen = False
            if now - self._primeStart >= 120.0:
                self.pumpPower = 0
                self.state = self.STATE_IDLE
                self.line_received.emit("ERROR:PRIME_STEAM_TIMEOUT")

        elif self.state == self.STATE_HEATING_BREW:
            self._heat_brew()
            self.pumpPower = 0

        elif self.state == self.STATE_HEATING_STEAM:
            self._heat_steam()
            self.pumpPower = 0

        elif self.state == self.STATE_BREWING:
            self._heat_brew()
            self.pumpPower = random.randint(180, 255)

        elif self.state == self.STATE_STEAMING:
            self._heat_steam()
            self.pumpPower = 0

        elif self.state == self.STATE_FLUSHING:
            self.pumpPower = 255
            self.valvePumpOpen = True
            self.valveThermoblockOpen = False

        else:  # IDLE
            self.pumpPower = 0
            self.heaterBrewOn         = False
            self.heaterSteamOn        = False
            self.valveThermoblockOpen = False
            self.valvePumpOpen        = False

        self._update_sensors()

    def _heat_brew(self):
        diff = self.brewTemp - self.brewTempActual
        if diff >= 15:
            self.brewTempActual += random.uniform(0.8, 1.5)
            self.heaterBrewOn = True
        elif diff >= 2:
            self.brewTempActual += random.uniform(0.1, 0.4)
            self.heaterBrewOn = True
        elif diff > 0:
            self.brewTempActual += random.uniform(-0.05, 0.15)
            self.heaterBrewOn = True
        else:
            self.brewTempActual += random.uniform(-0.1, 0.05)
            self.heaterBrewOn = False
        self.brewTempActual = max(15, min(110, self.brewTempActual))

    def _heat_steam(self):
        diff = self.steamTemp - self.steamTempActual
        if diff > 2:
            self.steamTempActual += random.uniform(0.5, 1.2)
            self.heaterSteamOn = True
        elif diff > 0:
            self.steamTempActual += random.uniform(-0.05, 0.3)
            self.heaterSteamOn = True
        else:
            self.steamTempActual += random.uniform(-0.1, 0.05)
            self.heaterSteamOn = False
        self.steamTempActual = max(15, min(160, self.steamTempActual))

    def _update_sensors(self):
        # Pressure
        if self.state == self.STATE_BREWING and self.pumpPower > 0:
            target_p = (self.pumpPower / 255.0) * 10.0
            self.pressure += (target_p - self.pressure) * 0.3 + random.uniform(-0.2, 0.2)
            self.pressure = max(0, min(16, self.pressure))
        else:
            self.pressure = max(0, self.pressure * 0.8 + random.uniform(-0.05, 0.05))

        # Weight during brewing
        if self.state == self.STATE_BREWING and self.brewTimer > 0:
            elapsed = time.time() - self.brewTimer
            rate = max(0.3, 2.0 - elapsed * 0.04)
            self.weight += rate * 0.05 + random.uniform(-0.05, 0.05)
            self.weight = max(0, min(100, self.weight))
        elif not self.scalesTared:
            self.weight += random.uniform(-0.03, 0.03)

    def _stop_current_operation(self):
        self.state = self.STATE_IDLE
        self.pumpPower = 0
        self.valveThermoblockOpen = False
        self.valvePumpOpen        = False
        self.heaterBrewOn  = False
        self.heaterSteamOn = False
        self.scalesTared   = False
        self.brewTimer     = 0

    def _send_telemetry(self):
        # Match firmware 12-field DATA: packet
        # Fields: state,brewTemp,steamTemp,pressure,weight,pump%,valveThermoblock,valvePump,
        #         heaterBrew,heaterSteam,brewTimer,scalesTared
        brew_time_sec = 0
        if self.state == self.STATE_BREWING and self.brewTimer > 0:
            brew_time_sec = int(time.time() - self.brewTimer)

        pump_percent = int((self.pumpPower / 255.0) * 100)

        msg = (
            f"DATA:{self.state},"
            f"{self.brewTempActual:.1f},"
            f"{self.steamTempActual:.1f},"
            f"{self.pressure:.2f},"
            f"{self.weight:.1f},"
            f"{pump_percent},"
            f"{1 if self.valveThermoblockOpen else 0},"
            f"{1 if self.valvePumpOpen else 0},"
            f"{1 if self.heaterBrewOn else 0},"
            f"{1 if self.heaterSteamOn else 0},"
            f"{brew_time_sec},"
            f"{1 if self.scalesTared else 0}"
        )
        self.line_received.emit(msg)

    def _send_status(self):
        pump_percent = int((self.pumpPower / 255.0) * 100)
        msg = (
            f"STATUS:state={self.state},"
            f"brewTemp={self.brewTempActual:.1f},"
            f"steamTemp={self.steamTempActual:.1f},"
            f"brewSP={self.brewTemp:.1f},"
            f"steamSP={self.steamTemp:.1f},"
            f"pressure={self.pressure:.2f},"
            f"weight={self.weight:.1f},"
            f"pump={pump_percent},"
            f"valveTB={1 if self.valveThermoblockOpen else 0},"
            f"valvePump={1 if self.valvePumpOpen else 0},"
            f"heaterBrew={1 if self.heaterBrewOn else 0},"
            f"heaterSteam={1 if self.heaterSteamOn else 0}"
        )
        self.line_received.emit(msg)
