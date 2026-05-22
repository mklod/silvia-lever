import json
import os

class SettingsManager:
    def __init__(self, settings_file="settings.json"):
        self.settings_file = settings_file
        self.default_settings = {
            "brew_temp": 93.0,
            "steam_temp": 130.0,
            "scale_cal": 420.0,   # NAU7802 single calibration factor
            "profiles": []
        }
    
    def load_settings(self):
        """Load settings from file, return defaults if file doesn't exist"""
        try:
            if os.path.exists(self.settings_file):
                with open(self.settings_file, 'r') as f:
                    return json.load(f)
        except Exception:
            pass
        return self.default_settings.copy()
    
    def save_settings(self, brew_temp, steam_temp, scale_cal=None, pid=None):
        """Save settings to file. `pid` is an optional (kp, ki, kd) tuple."""
        try:
            current_settings = self.load_settings()
            current_settings["brew_temp"] = brew_temp
            current_settings["steam_temp"] = steam_temp
            if scale_cal is not None:
                current_settings["scale_cal"] = scale_cal
            if pid is not None:
                current_settings["pid_kp"] = pid[0]
                current_settings["pid_ki"] = pid[1]
                current_settings["pid_kd"] = pid[2]
            with open(self.settings_file, 'w') as f:
                json.dump(current_settings, f, indent=2)
            return True
        except Exception:
            return False