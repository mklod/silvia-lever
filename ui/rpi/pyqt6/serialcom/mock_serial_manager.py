from PyQt6.QtCore import QObject, pyqtSignal, QTimer
import random
import time

class SerialManager(QObject):
    line_received = pyqtSignal(str)
    
    # Mirror Arduino state enum
    STATE_IDLE = 0
    STATE_HEATING_BREW = 1
    STATE_HEATING_STEAM = 2
    STATE_BREWING = 3
    STATE_STEAMING = 4
    STATE_FLUSHING = 5
    
    def __init__(self):
        super().__init__()
        self.connected = False
        
        # Mirror Arduino SystemData struct exactly
        self.state = self.STATE_IDLE
        self.brewTemp = 93.0  # DEFAULT_BREW_TEMP
        self.steamTemp = 150.0  # DEFAULT_STEAM_TEMP
        self.currentTemp = 25.0
        self.pressure = 0.0
        self.weight = 0.0
        self.pumpPower = 0
        self.valveOpen = False
        self.heaterOn = False
        self.brewTimer = 0
        self.scalesTared = False
        
        # Timers
        self.telemetry_timer = QTimer()
        self.telemetry_timer.timeout.connect(self._send_telemetry)
        
        self.update_timer = QTimer()
        self.update_timer.timeout.connect(self._update_system)
        
    def start(self):
        self.connected = True
        self.telemetry_timer.start(100)  # Match Arduino TELEMETRY_INTERVAL
        self.update_timer.start(50)      # Faster system update
        self.line_received.emit("READY")
        
    def stop(self):
        self.connected = False
        self.telemetry_timer.stop()
        self.update_timer.stop()
        
    def send_command(self, command):
        if not self.connected:
            return
            
        cmd = command.strip()
        
        # Mirror Arduino command processing exactly
        if cmd.startswith("SET_TEMP BREW "):
            temp = float(cmd[14:])
            if 60 <= temp <= 110:  # MIN_TEMP to MAX_BREW_TEMP
                self.brewTemp = temp
                self.line_received.emit("OK:BREW_TEMP_SET")
            else:
                self.line_received.emit("ERROR:BREW_TEMP_OUT_OF_RANGE")
                
        elif cmd.startswith("SET_TEMP STEAM "):
            temp = float(cmd[15:])
            if 60 <= temp <= 150:  # MIN_TEMP to MAX_STEAM_TEMP
                self.steamTemp = temp
                self.line_received.emit("OK:STEAM_TEMP_SET")
            else:
                self.line_received.emit("ERROR:STEAM_TEMP_OUT_OF_RANGE")
                
        elif cmd == "START_BREW":
            if self.state == self.STATE_IDLE:
                self.state = self.STATE_HEATING_BREW
                self.line_received.emit("OK:BREW_STARTED")
            else:
                self.line_received.emit("ERROR:NOT_IDLE")
                
        elif cmd == "START_STEAM":
            # Mirror Arduino logic - always allows steam start
            self.state = self.STATE_HEATING_STEAM
            self.line_received.emit("OK:STEAM_STARTED")
                
        elif cmd == "START_FLUSH":
            if self.state == self.STATE_IDLE:
                self.state = self.STATE_FLUSHING
                self.valveOpen = True
                self.line_received.emit("OK:FLUSH_STARTED")
            else:
                self.line_received.emit("ERROR:NOT_IDLE")
                
        elif cmd in ["BEGIN_BREW", "BREW_NOW"]:
            if self.state == self.STATE_HEATING_BREW:
                self.state = self.STATE_BREWING
                self.scalesTared = False
                # Simulate Arduino tareScales() call
                self.weight = 0.0
                QTimer.singleShot(100, lambda: setattr(self, 'scalesTared', True))
                self.brewTimer = int(time.time() * 1000)  # millis()
                self.valveOpen = True
                self.line_received.emit("OK:BREWING_STARTED")
            else:
                self.line_received.emit("ERROR:INVALID_STATE_FOR_BREW_NOW")
                
        elif cmd == "STOP":
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
            
        elif cmd == "ABORT":
            self._stop_current_operation()
            self.line_received.emit("OK:ABORTED")
            
        elif cmd.startswith("CAL_SCALE "):
            try:
                knownWeight = float(cmd[10:])
                if knownWeight > 0:
                    # Simulate calibration
                    self.line_received.emit("OK:SCALES_CALIBRATED")
                else:
                    self.line_received.emit("ERROR:INVALID_WEIGHT")
            except:
                self.line_received.emit("ERROR:INVALID_WEIGHT")
                
        elif cmd.startswith("SET_SCALE_CAL "):
            try:
                parts = cmd[14:].split()
                if len(parts) == 2:
                    cal0 = float(parts[0])
                    cal1 = float(parts[1])
                    self.line_received.emit("OK:SCALE_CAL_SET")
                else:
                    self.line_received.emit("ERROR:INVALID_CAL_FORMAT")
            except:
                self.line_received.emit("ERROR:INVALID_CAL_FORMAT")
                
        elif len(cmd) > 0:
            self.line_received.emit("ERROR:UNKNOWN_COMMAND")
            
    def _update_system(self):
        # Mirror Arduino updateSystemLogic()
        if self.state == self.STATE_HEATING_BREW:
            self._control_heater(self.brewTemp)
        elif self.state == self.STATE_HEATING_STEAM:
            self._control_heater(self.steamTemp)
        elif self.state == self.STATE_BREWING:
            self._control_heater(self.brewTemp)
            self._control_pump(True)
        elif self.state == self.STATE_STEAMING:
            self._control_heater(self.steamTemp)
        elif self.state == self.STATE_FLUSHING:
            self._control_pump(True)
        else:  # STATE_IDLE
            self._control_heater(0)
            self._control_pump(False)
            self.valveOpen = False
            
        # Update sensors
        self._update_sensors()
        
    def _control_heater(self, targetTemp):
        if targetTemp == 0:
            self.heaterOn = False
            # Natural cooling when heater off
            if self.currentTemp > 25:
                self.currentTemp -= random.uniform(0.05, 0.15)
            return
            
        tempDiff = targetTemp - self.currentTemp
        pwmValue = 0
        
        # Mirror Arduino hysteresis logic from config.h
        if tempDiff >= 15.0:  # TEMP_HYSTERESIS_HIGH
            pwmValue = 255  # HEATER_PWM_FULL
        elif tempDiff >= 10.0:  # TEMP_HYSTERESIS_MED
            pwmValue = 50   # HEATER_PWM_MED
        elif tempDiff >= 2.0:  # TEMP_HYSTERESIS_LOW
            pwmValue = 10   # HEATER_PWM_LOW
        else:
            pwmValue = 0
            
        self.heaterOn = (pwmValue > 0)
        
        # Simulate realistic heating based on PWM value
        if pwmValue == 255:
            self.currentTemp += random.uniform(0.8, 1.5)
        elif pwmValue == 50:
            self.currentTemp += random.uniform(0.3, 0.6)
        elif pwmValue == 10:
            self.currentTemp += random.uniform(0.1, 0.3)
        else:
            # Small oscillation around target when heater off
            self.currentTemp += random.uniform(-0.1, 0.1)
            
        self.currentTemp = max(15, min(170, self.currentTemp))
        
    def _control_pump(self, enable):
        if enable and (self.state == self.STATE_BREWING or self.state == self.STATE_FLUSHING):
            if self.state == self.STATE_BREWING:
                # Simulate potentiometer reading (Arduino reads POT_PIN)
                potValue = random.randint(200, 1023)  # 10-bit ADC
                self.pumpPower = potValue // 4  # Arduino: value/4
            elif self.state == self.STATE_FLUSHING:
                self.pumpPower = 255  # Full power for flushing
        else:
            self.pumpPower = 0
            
    def _update_sensors(self):
        # Simulate pressure sensor with realistic behavior
        if self.state == self.STATE_BREWING and self.pumpPower > 0:
            # Pressure builds up based on pump power
            target_pressure = (self.pumpPower / 255.0) * 12.0
            self.pressure += (target_pressure - self.pressure) * 0.3
            self.pressure += random.uniform(-0.2, 0.2)  # Noise
            self.pressure = max(0, min(16, self.pressure))
        else:
            # Pressure drops when pump off
            self.pressure *= 0.8
            self.pressure += random.uniform(-0.1, 0.1)
            self.pressure = max(0, self.pressure)
            
        # Simulate weight sensor - coffee extraction
        if self.state == self.STATE_BREWING and self.brewTimer > 0:
            elapsed = (int(time.time() * 1000) - self.brewTimer) / 1000.0
            # Realistic extraction curve: fast start, then slower
            extraction_rate = max(0.5, 2.0 - elapsed * 0.05)
            self.weight += extraction_rate * 0.1 + random.uniform(-0.1, 0.1)
            self.weight = max(0, min(100, self.weight))
        elif not self.scalesTared:
            # Small drift when not tared
            self.weight += random.uniform(-0.05, 0.05)
            
    def _stop_current_operation(self):
        self.state = self.STATE_IDLE
        self.pumpPower = 0
        self.valveOpen = False
        self.scalesTared = False
        self.brewTimer = 0
        
    def _send_telemetry(self):
        # Mirror Arduino sendTelemetry() format
        brew_time_sec = 0
        if self.state == self.STATE_BREWING and self.brewTimer > 0:
            brew_time_sec = (int(time.time() * 1000) - self.brewTimer) // 1000
            
        pump_percent = int((self.pumpPower / 255.0) * 100)
        
        data_msg = f"DATA:{self.state},{self.currentTemp:.1f},{self.pressure:.2f},{self.weight:.1f},{pump_percent},{1 if self.valveOpen else 0},{1 if self.heaterOn else 0},{brew_time_sec},{1 if self.scalesTared else 0}"
        self.line_received.emit(data_msg)
        
    def _send_status(self):
        # Mirror Arduino sendStatus() format
        pump_percent = int((self.pumpPower / 255.0) * 100)
        status_msg = f"STATUS:state={self.state},temp={self.currentTemp:.1f},brewTemp={self.brewTemp:.1f},steamTemp={self.steamTemp:.1f},pressure={self.pressure:.2f},weight={self.weight:.1f},pump={pump_percent},valve={1 if self.valveOpen else 0},heater={1 if self.heaterOn else 0}"
        self.line_received.emit(status_msg)