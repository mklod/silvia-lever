import json
import os

class SettingsManager:
    def __init__(self, settings_file="settings.json"):
        self.settings_file = settings_file
        self.default_settings = {
            "brew_temp": 93.0,
            "steam_temp": 130.0,
            "scale_cal_0": 420.0983,
            "scale_cal_1": 421.365
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
    
    def save_settings(self, brew_temp, steam_temp, scale_cal_0=None, scale_cal_1=None):
        """Save settings to file"""
        try:
            current_settings = self.load_settings()
            current_settings["brew_temp"] = brew_temp
            current_settings["steam_temp"] = steam_temp
            if scale_cal_0 is not None:
                current_settings["scale_cal_0"] = scale_cal_0
            if scale_cal_1 is not None:
                current_settings["scale_cal_1"] = scale_cal_1
            with open(self.settings_file, 'w') as f:
                json.dump(current_settings, f)
            return True
        except Exception:
            return False