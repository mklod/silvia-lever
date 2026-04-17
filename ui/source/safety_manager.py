# Last modified: 2026-04-17--0050
from PyQt6.QtCore import QObject, pyqtSignal, QTimer
import time

class SafetyManager(QObject):
    emergencyStop = pyqtSignal(str)  # reason
    warningIssued = pyqtSignal(str)  # warning message

    def __init__(self):
        super().__init__()
        self.max_temp = 160.0  # Absolute max temperature
        self.max_brew_time = 300  # 5 minutes max brew
        self.max_steam_time = 600  # 10 minutes max steam
        self.comm_timeout = 10.0  # 10 seconds without data

        self.last_data_time = time.time()
        self.brew_start_time = None
        self.steam_start_time = None

        # Comm watchdog only arms after first telemetry packet arrives. This lets
        # the UI run without a Teensy (navigation / mock mode) without spamming
        # "EMERGENCY STOP: Communication timeout" every second.
        self.armed = False
        self.timeout_fired = False

        # Safety check timer
        self.safety_timer = QTimer()
        self.safety_timer.timeout.connect(self._safety_check)
        self.safety_timer.start(1000)  # Check every second

    def update_data_timestamp(self):
        self.last_data_time = time.time()
        self.armed = True
        self.timeout_fired = False
        
    def start_brew_timer(self):
        self.brew_start_time = time.time()
        
    def start_steam_timer(self):
        self.steam_start_time = time.time()
        
    def stop_brew_timer(self):
        self.brew_start_time = None
        
    def stop_steam_timer(self):
        self.steam_start_time = None
        
    def check_temperature(self, temp):
        if temp > self.max_temp:
            self.emergencyStop.emit(f"OVERHEAT: {temp}°C > {self.max_temp}°C")
            return False
        elif temp > self.max_temp - 10:
            self.warningIssued.emit(f"High temperature warning: {temp}°C")
        return True
        
    def _safety_check(self):
        current_time = time.time()

        # Check communication timeout — only after we've seen at least one packet,
        # and only fire once per disconnect (re-arms when data resumes).
        if self.armed and not self.timeout_fired:
            if current_time - self.last_data_time > self.comm_timeout:
                self.emergencyStop.emit("Communication timeout - no data from hardware")
                self.timeout_fired = True
                self.armed = False
            
        # Check brew timeout
        if self.brew_start_time and (current_time - self.brew_start_time) > self.max_brew_time:
            self.emergencyStop.emit("Brew timeout - maximum brew time exceeded")
            
        # Check steam timeout
        if self.steam_start_time and (current_time - self.steam_start_time) > self.max_steam_time:
            self.emergencyStop.emit("Steam timeout - maximum steam time exceeded")