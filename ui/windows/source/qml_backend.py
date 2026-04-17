from PyQt6.QtCore import QObject, pyqtSignal, pyqtSlot, QTimer
import config
from safety_manager import SafetyManager
from data_logger import DataLogger
from temperature_controller import TemperatureController
from settings_manager import SettingsManager
import atexit

# Import appropriate serial manager based on configuration
if config.USE_MOCK_SERIAL:
    from serialcom.mock_serial_manager import SerialManager
else:
    from serialcom.real_serial_manager import SerialManager

class CoffeeController(QObject):
    # Signals to QML
    brewTempChanged = pyqtSignal(float)    # Thermoblock actual temperature
    steamTempChanged = pyqtSignal(float)   # Steam boiler actual temperature
    pressureChanged = pyqtSignal(float)
    weightChanged = pyqtSignal(float)
    pumpPowerChanged = pyqtSignal(float)
    valvePumpChanged = pyqtSignal(bool)         # V1: false=thermoblock, true=boiler
    valveThermoblockChanged = pyqtSignal(bool)  # V2: false=drain, true=portafilter
    stateChanged = pyqtSignal(str)
    brewTimeChanged = pyqtSignal(str)
    errorOccurred = pyqtSignal(str)
    warningIssued = pyqtSignal(str)
    connectionStatusChanged = pyqtSignal(bool)
    heatingStatusChanged = pyqtSignal(bool)
    scalesSettledChanged = pyqtSignal(bool)
    scalesTaredChanged = pyqtSignal(bool)
    targetTemperaturesChanged = pyqtSignal(float, float)
    
    def __init__(self, parent=None):
        super().__init__(parent)
        
        # Initialize components
        self.logger = DataLogger()
        self.safety = SafetyManager()
        self.temp_controller = TemperatureController()
        
        # Serial communication
        if config.USE_MOCK_SERIAL:
            self.serial = SerialManager()
        else:
            self.serial = SerialManager(port=config.SERIAL_PORT, baud_rate=config.SERIAL_BAUD)
        self.serial.line_received.connect(self._handle_serial_data)
        self.connected = False
        self._current_state = "IDLE"
        
        # Connect safety signals
        self.safety.emergencyStop.connect(self._emergency_stop)
        self.safety.warningIssued.connect(self._handle_warning)
        
        # Connect temperature controller
        self.temp_controller.heaterStateChanged.connect(self._handle_heater_change)
        self.temp_controller.targetReached.connect(self._handle_target_reached)
        
        # Brew timer
        self._brew_start_time = None
        self._timer = QTimer()
        self._timer.timeout.connect(self._update_brew_time)
        
        # Scales settling detection
        self._weight_history = []
        self._scales_settled = False
        
        # Load saved settings
        self.settings_manager = SettingsManager()
        saved_settings = self.settings_manager.load_settings()
        self._brew_target_temp = saved_settings["brew_temp"]
        self._steam_target_temp = saved_settings["steam_temp"]
        self._scale_cal = saved_settings.get("scale_cal", 420.0)
        # Guard: cal must be positive and in a plausible range.
        # Negative → raw/weight polarity inverted (library bug or bad cal).
        # <1 or >100000 → not a real cal factor for this load cell.
        if not self._scale_cal or self._scale_cal <= 0 or self._scale_cal > 100000:
            self._scale_cal = 420.0
        
        # Connection watchdog
        self._connection_timer = QTimer()
        self._connection_timer.timeout.connect(self._check_connection)
        self._connection_timer.start(5000)  # Check every 5 seconds
        
        # Register shutdown handler
        atexit.register(self._shutdown)
        
        try:
            self.serial.start()
            self.connected = True
            self.logger.log_command("System started")
            
            # Delay signal emission to ensure QML is ready
            QTimer.singleShot(100, lambda: self.connectionStatusChanged.emit(True))
            QTimer.singleShot(200, lambda: self.targetTemperaturesChanged.emit(self._brew_target_temp, self._steam_target_temp))
            
            # Priming is triggered from QML when user enters brew screen

            # Restore scale calibration
            QTimer.singleShot(400, self._restore_scale_calibration)
        except Exception as e:
            self.logger.log_error(f"Failed to start serial: {e}")
            self.connected = False
            QTimer.singleShot(100, lambda: self.connectionStatusChanged.emit(False))
        
    @pyqtSlot(float, float)
    def setTemperatures(self, brew_temp, steam_temp):
        # Apply safety limits
        brew_temp = max(60, min(110, brew_temp))
        steam_temp = max(110, min(150, steam_temp))
        
        self._brew_target_temp = brew_temp
        self._steam_target_temp = steam_temp
        
        self.temp_controller.set_brew_target(brew_temp)
        self.temp_controller.set_steam_target(steam_temp)
        
        # Save settings to file
        self.settings_manager.save_settings(brew_temp, steam_temp)
        
        self.targetTemperaturesChanged.emit(brew_temp, steam_temp)
        
        if self.connected:
            self.serial.send_command(f"SET_TEMP BREW {brew_temp}")
            self.serial.send_command(f"SET_TEMP STEAM {steam_temp}")
            self.logger.log_command(f"SET_TEMP BREW {brew_temp} STEAM {steam_temp}")
        else:
            self.logger.log_error("Cannot set temperature - not connected")
        
    @pyqtSlot()
    def startBrew(self):
        if not self.connected:
            self.errorOccurred.emit("Cannot start brew - not connected")
            return
            
        # Stop current operation first
        if hasattr(self, '_current_state') and self._current_state != "IDLE":
            self.serial.send_command("STOP")
            self.logger.log_command("Stopping current operation for brew")
            # Delay to allow Arduino state transition
            QTimer.singleShot(100, self._delayed_start_brew)
        else:
            self._delayed_start_brew()
            
    def _delayed_start_brew(self):
        self.temp_controller.set_mode("BREW")
        self.safety.start_brew_timer()
        
        self.serial.send_command("START_BREW")
        self.logger.log_command("START_BREW")
        
    @pyqtSlot()
    def beginBrew(self):
        """Called when user presses BREW NOW - implements exact sequence"""
        if not self.connected:
            self.errorOccurred.emit("Cannot begin brew - not connected")
            return
            
        self.logger.log_command("BREW NOW Button pressed - starting sequence")
        
        self._tare_and_start_brewing()
        
    def _tare_and_start_brewing(self):
        """Step 2: TARE scales, then begin brewing with all simultaneous actions"""
        
        # Step 3: Begin brewing (valve opens, pump starts)
        self.serial.send_command("BEGIN_BREW")
        
        # Step 4: Timer begins counting
        import time
        self._brew_start_time = time.time()
        self._timer.start(500)
        
        # # Step 5: Live data reporting begins (charts already updating via telemetry)
        # self.logger.log_command("Brewing started - timer running, valve open, pump active, live data reporting")
        
    @pyqtSlot()
    def stopBrew(self):
        if self.connected:
            self.serial.send_command("STOP")
            self.logger.log_command("STOP")
            
        self.temp_controller.set_mode("IDLE")
        self.safety.stop_brew_timer()
        self._timer.stop()
        
        # Log brew session if we have data
        if self._brew_start_time:
            import time
            duration = int(time.time() - self._brew_start_time)
            self.logger.log_brew_session(duration, 0, 0)  # TODO: Add actual weight/pressure
            
        # Keep brew time displayed, don't reset to 00:00
        # self._brew_start_time = None
        # self.brewTimeChanged.emit("00:00")
        
    @pyqtSlot()
    def startSteam(self):
        if not self.connected:
            self.errorOccurred.emit("Cannot start steam - not connected")
            return
            
        # Stop current operation first
        if hasattr(self, '_current_state') and self._current_state != "IDLE":
            self.serial.send_command("STOP")
            self.logger.log_command("Stopping current operation for steam")
            # Delay to allow Arduino state transition
            QTimer.singleShot(100, self._delayed_start_steam)
        else:
            self._delayed_start_steam()
            
    def _delayed_start_steam(self):
        self.temp_controller.set_mode("STEAM")
        self.safety.start_steam_timer()
        
        self.serial.send_command("START_STEAM")
        self.logger.log_command("START_STEAM")
        
    @pyqtSlot()
    def stopSteam(self):
        if self.connected:
            self.serial.send_command("STOP")
            self.logger.log_command("STOP")
            
        self.temp_controller.set_mode("IDLE")
        self.safety.stop_steam_timer()
        
    @pyqtSlot()
    def startFlush(self):
        if not self.connected:
            self.errorOccurred.emit("Cannot start flush - not connected")
            return
            
        # Stop current operation first
        if hasattr(self, '_current_state') and self._current_state != "IDLE":
            self.serial.send_command("STOP")
            self.logger.log_command("Stopping current operation for flush")
            # Delay to allow Arduino state transition
            QTimer.singleShot(100, self._delayed_start_flush)
        else:
            self._delayed_start_flush()
            
    def _delayed_start_flush(self):
        self.serial.send_command("START_FLUSH")
        self.logger.log_command("START_FLUSH")
        
    @pyqtSlot()
    def stopFlush(self):
        if self.connected:
            self.serial.send_command("STOP")
            self.logger.log_command("STOP")
            
    @pyqtSlot()
    def beginSteam(self):
        """Called when steam temperature is ready and user presses BEGIN STEAM"""
        if not self.connected:
            self.errorOccurred.emit("Cannot begin steam - not connected")
            return
            
        self.serial.send_command("BEGIN_STEAM")
        self.logger.log_command("BEGIN_STEAM")
        
    def _handle_serial_data(self, line):
        self.safety.update_data_timestamp()
        self.logger.log_response(line)
        
        if line.startswith("DATA:"):
            # New packet format (12 fields):
            # DATA:state,brewTemp,steamTemp,pressure,weight,pump%,valveTB,valveBoiler,heaterBrew,heaterSteam,brewTimer,scalesTared
            try:
                parts = line[5:].split(',')
                if len(parts) < 10:
                    return

                state_num    = int(parts[0])
                brew_temp    = float(parts[1])
                steam_temp   = float(parts[2])
                pressure     = float(parts[3])
                weight       = float(parts[4])
                pump_percent = int(parts[5])
                valve_tb     = bool(int(parts[6])) if len(parts) > 6 else False
                valve_pump   = bool(int(parts[7])) if len(parts) > 7 else False
                brew_time    = int(parts[10]) if len(parts) > 10 else 0
                scales_tared = bool(int(parts[11])) if len(parts) > 11 else False

                state_names = [
                    "IDLE",
                    "PRIMING_BREW", "HEATING_BREW",
                    "PRIMING_STEAM", "HEATING_STEAM",
                    "BREWING", "STEAMING", "FLUSHING"
                ]
                state = state_names[state_num] if state_num < len(state_names) else "UNKNOWN"
                self._current_state = state

                # Safety checks on both temperatures
                if not self.safety.check_temperature(brew_temp):
                    return
                if not self.safety.check_temperature(steam_temp):
                    return

                # Update temperature controller with both readings
                self.temp_controller.update_brew_temperature(brew_temp)
                self.temp_controller.update_steam_temperature(steam_temp)

                # Log sensor data (use brew temp as primary for logging)
                self.logger.log_sensor_data(brew_temp, pressure, weight, state, pump_percent)

                # Check scales settling
                self._check_scales_settling(weight)

                # Emit to QML
                self.stateChanged.emit(state)
                self.brewTempChanged.emit(brew_temp)
                self.steamTempChanged.emit(steam_temp)
                self.pressureChanged.emit(pressure)
                self.weightChanged.emit(weight)
                self.pumpPowerChanged.emit(float(pump_percent))
                self.valvePumpChanged.emit(valve_pump)
                self.valveThermoblockChanged.emit(valve_tb)
                self.scalesTaredChanged.emit(scales_tared)

            except Exception as e:
                self.logger.log_error(f"Failed to parse DATA: {line} - {e}")
        elif line.startswith("NEW_CAL:"):
            # Handle NAU7802 calibration response: NEW_CAL:<factor>
            # Valid range: positive, ≥1, ≤100000.
            try:
                new_cal = float(line[8:])
                if new_cal <= 0 or new_cal < 1.0 or new_cal > 100000:
                    reason = ("negative" if new_cal < 0
                              else "too small" if abs(new_cal) < 1.0
                              else "too large")
                    self.logger.log_error(f"Cal result invalid ({new_cal}, {reason}) — rejected, restoring {self._scale_cal}")
                    self.serial.send_command(f"SET_SCALE_CAL {self._scale_cal}")
                    self.errorOccurred.emit(f"Cal failed: factor {new_cal:.3f} {reason}. Previous cal {self._scale_cal:.1f} restored.")
                else:
                    self._scale_cal = new_cal
                    self.settings_manager.save_settings(self._brew_target_temp, self._steam_target_temp, self._scale_cal)
                    self.logger.log_command(f"Scale calibration updated: {self._scale_cal}")
            except Exception as e:
                self.logger.log_error(f"Failed to parse calibration: {line} - {e}")
        elif line.startswith("STATUS:"):
            # STATUS: key=value,... response — parse for logging only
            try:
                self.logger.log_response(line)
            except Exception as e:
                self.logger.log_error(f"Failed to parse STATUS: {line} - {e}")
        elif line.startswith("ERROR"):
            self.logger.log_error(line)
            self.errorOccurred.emit(line)
        elif line.startswith("READY") or line.startswith("PONG"):
            self.logger.log_command(f"Received: {line}")
                    
    def _update_brew_time(self):
        if self._brew_start_time:
            import time
            elapsed_ms = int((time.time() - self._brew_start_time) * 1000)
            total_seconds = elapsed_ms // 1000
            minutes = total_seconds // 60
            seconds = total_seconds % 60
            self.brewTimeChanged.emit(f"{minutes:02}:{seconds:02}")
            
    def _emergency_stop(self, reason):
        """Handle emergency stop from safety manager"""
        self.logger.log_safety_event(f"EMERGENCY STOP: {reason}")
        self.errorOccurred.emit(f"EMERGENCY STOP: {reason}")
        
        # Stop all operations
        if self.connected:
            self.serial.send_command("ABORT")
            
        self.temp_controller.set_mode("IDLE")
        self.safety.stop_brew_timer()
        self.safety.stop_steam_timer()
        self._timer.stop()
        
    def _handle_warning(self, warning):
        self.logger.log_warning(warning)
        self.warningIssued.emit(warning)
        
    def _handle_heater_change(self, heating):
        self.heatingStatusChanged.emit(heating)
        # Arduino controls heater internally based on temperature
            
    def _handle_target_reached(self, mode):
        self.logger.log_command(f"Target temperature reached for {mode}")
        
    def _check_connection(self):
        if self.connected and self.serial:
            try:
                self.serial.send_command("PING")
                # Should wait for PONG response or implement timeout
            except Exception as e:
                self.connected = False
                self.connectionStatusChanged.emit(False)
                self.logger.log_error(f"Connection lost: {e}")
                self._attempt_reconnection()
                
    def _attempt_reconnection(self):
        """Try to reconnect after connection loss"""
        try:
            self.logger.log_command("Attempting reconnection...")
            if self.serial:
                self.serial.stop()
            if config.USE_MOCK_SERIAL:
                self.serial = SerialManager()
            else:
                self.serial = SerialManager(port=config.SERIAL_PORT, baud_rate=config.SERIAL_BAUD)
            self.serial.line_received.connect(self._handle_serial_data)
            if self.serial.start():
                self.connected = True
                self.connectionStatusChanged.emit(True)
                self.logger.log_command("Reconnection successful")
            else:
                self.logger.log_error("Reconnection failed")
        except Exception as e:
            self.logger.log_error(f"Reconnection error: {e}")

    def _shutdown(self):
        """Clean shutdown procedure"""
        try:
            if hasattr(self, 'logger') and self.logger:
                self.logger.log_command("Initiating shutdown")

            # Stop all operations
            if hasattr(self, 'connected') and self.connected and hasattr(self, 'serial') and self.serial:
                self.serial.send_command("ABORT")
                self.serial.stop()
                
            if hasattr(self, 'temp_controller') and self.temp_controller:
                self.temp_controller.set_mode("IDLE")
            if hasattr(self, '_timer') and self._timer:
                self._timer.stop()
            if hasattr(self, '_connection_timer') and self._connection_timer:
                self._connection_timer.stop()
            
            if hasattr(self, 'logger') and self.logger:
                self.logger.shutdown()
        except RuntimeError:
            # Qt objects already deleted, ignore
            pass
    def _check_scales_settling(self, weight):
        """Check if scales have settled to a stable reading"""
        self._weight_history.append(weight)
        
        # Keep only last 10 readings
        if len(self._weight_history) > 10:
            self._weight_history.pop(0)
            
        # Check if we have enough readings
        if len(self._weight_history) < 5:
            return
            
        # Check if weight is stable (within 0.2g for last 5 readings)
        recent_weights = self._weight_history[-5:]
        weight_range = max(recent_weights) - min(recent_weights)
        settled = weight_range <= 5
        
        if settled != self._scales_settled:
            self._scales_settled = settled
            self.scalesSettledChanged.emit(settled)
        
    @pyqtSlot()
    def primeDone(self):
        """User confirmed overflow — tell firmware to stop pump and start heating."""
        if self.connected:
            self.serial.send_command("PRIME_DONE")
            self.logger.log_command("PRIME_DONE")
        else:
            self.errorOccurred.emit("Cannot confirm prime - not connected")

    @pyqtSlot()
    def tareScales(self):
        """Tare the scales"""
        if self.connected:
            self.serial.send_command("TARE_SCALES")
            self.logger.log_command("TARE_SCALES")
        else:
            self.errorOccurred.emit("Cannot tare scales - not connected")
            
    @pyqtSlot(float)
    def calibrateScales(self, knownWeight):
        """Calibrate scales with known weight"""
        if self.connected:
            self.serial.send_command(f"CAL_SCALE {knownWeight}")
            self.logger.log_command(f"CAL_SCALE {knownWeight}")
        else:
            self.errorOccurred.emit("Cannot calibrate scales - not connected")
            
    def _restore_scale_calibration(self):
        """Restore saved NAU7802 calibration on startup"""
        if self.connected:
            self.serial.send_command(f"SET_SCALE_CAL {self._scale_cal}")
            self.logger.log_command(f"Restored scale calibration: {self._scale_cal}")
    
    @pyqtSlot()
    def emergencyStop(self):
        """Manual emergency stop from UI"""
        self.logger.log_safety_event("Manual emergency stop")
        
        # Stop all operations without showing error dialog
        if self.connected:
            self.serial.send_command("ABORT")
            
        self.temp_controller.set_mode("IDLE")
        self.safety.stop_brew_timer()
        self.safety.stop_steam_timer()
        self._timer.stop()