# Last modified: 2026-04-16--2346
"""
Cross-platform shim for Windows dev + Raspberry Pi deployment.

The UI is laid out at 960x540 on Windows (dev). On RPi the target display
is 1080p touchscreen, so we tell Qt to scale the whole UI 2x — fonts stay
crisp because Qt rasterises at the scaled size.

Must be imported BEFORE PyQt6 so QT_SCALE_FACTOR takes effect.
"""
import os
import sys


def is_rpi() -> bool:
    if sys.platform != "linux":
        return False
    try:
        with open("/proc/device-tree/model", "rb") as f:
            return b"Raspberry Pi" in f.read()
    except OSError:
        return False


def is_windows() -> bool:
    return sys.platform == "win32"


def ui_scale_factor() -> float:
    """2.0 on RPi (960x540 -> 1920x1080), 1.0 elsewhere."""
    return 2.0 if is_rpi() else 1.0


def default_fullscreen() -> bool:
    return is_rpi()


def apply_qt_env() -> None:
    """Set Qt scaling env vars. Call before QGuiApplication is constructed."""
    if "QT_SCALE_FACTOR" not in os.environ:
        os.environ["QT_SCALE_FACTOR"] = f"{ui_scale_factor():.2f}"
    os.environ.setdefault("QT_ENABLE_HIGHDPI_SCALING", "1")


def platform_name() -> str:
    if is_rpi():
        return "raspberry-pi"
    if is_windows():
        return "windows"
    return sys.platform
