from PyQt6.QtCore import QObject, pyqtSignal, QTimer

class TemperatureController(QObject):
    heaterStateChanged = pyqtSignal(bool)  # True = heating, False = off
    targetReached = pyqtSignal(str)  # "BREW" or "STEAM"
    
    def __init__(self):
        super().__init__()
        self.brew_target = 93.0
        self.steam_target = 130.0
        self.current_temp = 25.0
        self.mode = "IDLE"  # IDLE, BREW, STEAM
        self.hysteresis = 2.0  # Temperature hysteresis in °C
        self.heating = False
        
        # Control timer
        self.control_timer = QTimer()
        self.control_timer.timeout.connect(self._control_loop)
        self.control_timer.start(1000)  # Run every second
        
    def set_brew_target(self, temp):
        self.brew_target = max(60, min(110, temp))  # Safety limits
        
    def set_steam_target(self, temp):
        self.steam_target = max(110, min(150, temp))  # Safety limits
        
    def update_temperature(self, temp):
        self.current_temp = temp
        
    def set_mode(self, mode):
        """Set control mode: IDLE, BREW, STEAM"""
        self.mode = mode
        if mode == "IDLE":
            self._set_heater(False)
            
    def _control_loop(self):
        if self.mode == "IDLE":
            return
            
        target = self.brew_target if self.mode == "BREW" else self.steam_target
        
        # Simple thermostat with hysteresis
        if not self.heating and self.current_temp < target - self.hysteresis:
            self._set_heater(True)
        elif self.heating and self.current_temp >= target:
            self._set_heater(False)
            self.targetReached.emit(self.mode)
            
    def _set_heater(self, state):
        if self.heating != state:
            self.heating = state
            self.heaterStateChanged.emit(state)
            
    def get_status(self):
        return {
            'current_temp': self.current_temp,
            'target_temp': self.brew_target if self.mode == "BREW" else self.steam_target,
            'mode': self.mode,
            'heating': self.heating,
            'temp_diff': abs(self.current_temp - (self.brew_target if self.mode == "BREW" else self.steam_target))
        }