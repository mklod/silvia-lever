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
    
    def save_settings(self, brew_temp, steam_temp, scale_cal=None):
        """Save settings to file"""
        try:
            current_settings = self.load_settings()
            current_settings["brew_temp"] = brew_temp
            current_settings["steam_temp"] = steam_temp
            if scale_cal is not None:
                current_settings["scale_cal"] = scale_cal
            with open(self.settings_file, 'w') as f:
                json.dump(current_settings, f, indent=2)
            return True
        except Exception:
            return False