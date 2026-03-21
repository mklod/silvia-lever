import logging
import os
from datetime import datetime
from PyQt6.QtCore import QObject

class DataLogger(QObject):
    def __init__(self):
        super().__init__()
        
        # Create logs directory
        log_dir = "logs"
        os.makedirs(log_dir, exist_ok=True)
        
        # Setup main logger
        self.logger = logging.getLogger('silvia_coffee')
        self.logger.setLevel(logging.INFO)
        
        # File handler with timestamp
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        log_file = os.path.join(log_dir, f"silvia_{timestamp}.log")
        
        file_handler = logging.FileHandler(log_file)
        file_handler.setLevel(logging.INFO)
        
        # Console handler for debugging
        console_handler = logging.StreamHandler()
        console_handler.setLevel(logging.INFO)
        
        # Formatter
        formatter = logging.Formatter('%(asctime)s - %(levelname)s - %(message)s')
        file_handler.setFormatter(formatter)
        console_handler.setFormatter(formatter)
        
        self.logger.addHandler(file_handler)
        self.logger.addHandler(console_handler)
        
        self.logger.info("=== Silvia Coffee Machine Started ===")
        
    def log_sensor_data(self, temp, pressure, weight, state, pump_pwm):
        self.logger.info(f"SENSORS: T={temp}°C P={pressure}bar W={weight}g S={state} PWM={pump_pwm}")
        
    def log_command(self, command):
        self.logger.info(f"CMD_SENT: {command}")
        
    def log_response(self, response):
        self.logger.info(f"RECVIEVED: {response}")
        
    def log_error(self, error_msg):
        self.logger.error(f"ERROR: {error_msg}")
        
    def log_warning(self, warning_msg):
        self.logger.warning(f"WARNING: {warning_msg}")
        
    def log_safety_event(self, event):
        self.logger.critical(f"SAFETY: {event}")
        
    def log_brew_session(self, duration, final_weight, max_pressure):
        self.logger.info(f"BREW_COMPLETE: Duration={duration}s Weight={final_weight}g MaxPressure={max_pressure}bar")
        
    def shutdown(self):
        self.logger.info("=== Silvia Coffee Machine Shutdown ===")
        for handler in self.logger.handlers:
            handler.close()