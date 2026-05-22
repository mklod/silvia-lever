# Last modified: 2026-04-24--0250
"""
BrewRecorder — captures every brew cycle to a JSON file in ui/source/brew_logs/.

Each brew = one file `brew_YYYY-MM-DD_HH-MM-SS.json` with metadata + per-tick
samples. Driven by state transitions in qml_backend._handle_serial_data:
  start  on  IDLE→BREWING
  sample while BREWING (one per DATA packet, ~10 Hz)
  finish on  BREWING→anything

Designed as the substrate for the upcoming auto-profile system: profiles will
be derived from / replayed against these recordings.
"""
import json
import os
from datetime import datetime, timezone


class BrewRecorder:
    SCHEMA_VERSION = 1

    def __init__(self, output_dir):
        self.output_dir = output_dir
        os.makedirs(output_dir, exist_ok=True)
        self.recording = False
        self._samples = []
        self._start_time = None
        self._metadata = {}

    def start(self, brew_temp_setpoint, steam_temp_setpoint, pid_gains=None,
              scale_cal=None):
        """Called when state transitions IDLE→BREWING."""
        self.recording = True
        self._samples = []
        self._start_time = datetime.now(timezone.utc)
        self._metadata = {
            "version": self.SCHEMA_VERSION,
            "started_at": self._start_time.isoformat(),
            "setpoints": {
                "brew_temp_c": brew_temp_setpoint,
                "steam_temp_c": steam_temp_setpoint,
            },
            "pid_gains": pid_gains,        # tuple/list (kp, ki, kd) or None
            "scale_cal": scale_cal,
        }

    def add_sample(self, weight_g, pressure_bar, brew_temp_c, pump_percent,
                   valve_pump=None, valve_thermoblock=None, phase=None):
        """Called once per DATA packet while recording."""
        if not self.recording or self._start_time is None:
            return
        elapsed = (datetime.now(timezone.utc) - self._start_time).total_seconds()
        sample = {
            "t_s": round(elapsed, 3),
            "weight_g": round(weight_g, 2),
            "pressure_bar": round(pressure_bar, 2),
            "brew_temp_c": round(brew_temp_c, 1),
            "pump_percent": int(pump_percent),
        }
        if valve_pump is not None:
            sample["v_pump"] = bool(valve_pump)
        if valve_thermoblock is not None:
            sample["v_tb"] = bool(valve_thermoblock)
        if phase is not None:
            sample["phase"] = phase
        self._samples.append(sample)

    def finish(self, completed_normally=True):
        """Called when state leaves BREWING. Returns saved filepath or None."""
        if not self.recording or self._start_time is None:
            return None

        end_time = datetime.now(timezone.utc)
        duration = (end_time - self._start_time).total_seconds()

        record = dict(self._metadata)
        record["ended_at"] = end_time.isoformat()
        record["duration_s"] = round(duration, 2)
        record["completed_normally"] = bool(completed_normally)
        if self._samples:
            record["final_weight_g"] = self._samples[-1]["weight_g"]
            record["max_pressure_bar"] = max(s["pressure_bar"] for s in self._samples)
            record["max_brew_temp_c"] = max(s["brew_temp_c"] for s in self._samples)
            record["min_brew_temp_c"] = min(s["brew_temp_c"] for s in self._samples)
        else:
            record["final_weight_g"] = 0
            record["max_pressure_bar"] = 0
            record["max_brew_temp_c"] = None
            record["min_brew_temp_c"] = None
        record["sample_count"] = len(self._samples)
        record["samples"] = self._samples

        filename = "brew_" + self._start_time.strftime("%Y-%m-%d_%H-%M-%S") + ".json"
        filepath = os.path.join(self.output_dir, filename)
        try:
            with open(filepath, "w") as f:
                json.dump(record, f, indent=2)
        except OSError:
            filepath = None

        self.recording = False
        self._samples = []
        self._start_time = None
        return filepath

    def cancel(self):
        """Discard the in-progress recording without writing."""
        self.recording = False
        self._samples = []
        self._start_time = None
