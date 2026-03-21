"""
Build script for Silvia Lever Windows executable.
Run from this directory:  python build_exe.py
Output: dist/SilviaLever/SilviaLever.exe
"""
import subprocess
import sys
import os

SOURCE_DIR = os.path.join(os.path.dirname(__file__), "source")

# Collect all data files that need to be bundled
data_args = []

# QML files
data_args += ["--add-data", f"{SOURCE_DIR}/main.qml;."]
data_args += ["--add-data", f"{SOURCE_DIR}/controls;controls"]

# SVG assets
data_args += ["--add-data", f"{SOURCE_DIR}/svgs;svgs"]

# Default settings
data_args += ["--add-data", f"{SOURCE_DIR}/settings.json;."]

cmd = [
    sys.executable, "-m", "PyInstaller",
    "--name", "SilviaLever",
    "--windowed",                # No console window
    "--noconfirm",               # Overwrite previous build
    "--distpath", os.path.join(os.path.dirname(__file__), "dist"),
    "--workpath", os.path.join(os.path.dirname(__file__), "build"),
    "--specpath", os.path.dirname(__file__),
    # Hidden imports that PyInstaller may miss
    "--hidden-import", "PyQt6.QtCore",
    "--hidden-import", "PyQt6.QtGui",
    "--hidden-import", "PyQt6.QtQml",
    "--hidden-import", "PyQt6.QtQuick",
    "--hidden-import", "PyQt6.QtQuickControls2",
    "--hidden-import", "serial",
    "--hidden-import", "serial.tools.list_ports",
    *data_args,
    os.path.join(SOURCE_DIR, "main.py"),
]

print("Building Silvia Lever executable...")
print(" ".join(cmd))
subprocess.run(cmd, check=True)
print("\nDone! Executable is at: ui/windows/dist/SilviaLever/SilviaLever.exe")
