from PyQt6.QtCore import QObject, pyqtSignal, QTimer

class TemperatureController(QObject):
    heaterStateChanged = pyqtSignal(bool)  # True = heating, False = off (brew heater)
    targetReached = pyqtSignal(str)        # "BREW" or "STEAM"

    def __init__(self):
        super().__init__()
        self.brew_target  = 93.0
        self.steam_target = 130.0

        self.brew_temp_actual  = 25.0
        self.steam_temp_actual = 25.0

        self.mode = "IDLE"   # IDLE, BREW, STEAM
        self._brew_target_notified  = False
        self._steam_target_notified = False

        # Monitor timer — checks if target has been reached
        self._monitor_timer = QTimer()
        self._monitor_timer.timeout.connect(self._check_targets)
        self._monitor_timer.start(1000)

    def set_brew_target(self, temp):
        self.brew_target = max(60, min(110, temp))
        self._brew_target_notified = False

    def set_steam_target(self, temp):
        self.steam_target = max(110, min(150, temp))
        self._steam_target_notified = False

    def update_brew_temperature(self, temp):
        self.brew_temp_actual = temp

    def update_steam_temperature(self, temp):
        self.steam_temp_actual = temp

    def set_mode(self, mode):
        """Set control mode: IDLE, BREW, STEAM"""
        self.mode = mode
        self._brew_target_notified  = False
        self._steam_target_notified = False
        if mode == "IDLE":
            self.heaterStateChanged.emit(False)

    def _check_targets(self):
        if self.mode == "BREW" and not self._brew_target_notified:
            if self.brew_temp_actual >= self.brew_target - 1.0:
                self._brew_target_notified = True
                self.targetReached.emit("BREW")
                self.heaterStateChanged.emit(False)

        elif self.mode == "STEAM" and not self._steam_target_notified:
            if self.steam_temp_actual >= self.steam_target - 1.0:
                self._steam_target_notified = True
                self.targetReached.emit("STEAM")

    def get_status(self):
        target = self.brew_target if self.mode == "BREW" else self.steam_target
        actual = self.brew_temp_actual if self.mode == "BREW" else self.steam_temp_actual
        return {
            'brew_temp_actual':  self.brew_temp_actual,
            'steam_temp_actual': self.steam_temp_actual,
            'brew_target':       self.brew_target,
            'steam_target':      self.steam_target,
            'mode':              self.mode,
            'temp_diff':         abs(actual - target),
        }
