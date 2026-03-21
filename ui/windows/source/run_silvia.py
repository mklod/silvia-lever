#!/usr/bin/env python3
"""
Silvia Coffee Machine Startup Script
Handles both mock and real hardware modes
"""

import sys
import os
import argparse
from PyQt6.QtGui import QGuiApplication
from PyQt6.QtQml import qmlRegisterType, QQmlApplicationEngine
from PyQt6.QtCore import QUrl
from qml_backend import CoffeeController
import config

def main():
    parser = argparse.ArgumentParser(description='Silvia Coffee Machine Controller')
    parser.add_argument('--mock', action='store_true', help='Use mock serial communication')
    parser.add_argument('--port', type=str, help='Serial port (e.g., COM3 on Windows, /dev/ttyUSB0 on Linux)')
    parser.add_argument('--fullscreen', action='store_true', help='Run in fullscreen mode')
    
    args = parser.parse_args()
    
    # Override config based on command line arguments
    if args.mock:
        config.USE_MOCK_SERIAL = True
    if args.port:
        config.SERIAL_PORT = args.port
        config.USE_MOCK_SERIAL = False
    if args.fullscreen:
        config.FULLSCREEN = True
    
    print(f"Starting Silvia Coffee Machine...")
    print(f"Mock Serial: {config.USE_MOCK_SERIAL}")
    if not config.USE_MOCK_SERIAL:
        print(f"Serial Port: {config.SERIAL_PORT or 'Auto-detect'}")
    
    app = QGuiApplication(sys.argv)
    
    # Register the backend with QML
    qmlRegisterType(CoffeeController, "CoffeeController", 1, 0, "CoffeeController")
    
    # Create QML engine
    engine = QQmlApplicationEngine()
    qml_file = os.path.join(os.path.dirname(__file__), "main.qml")
    engine.load(QUrl.fromLocalFile(qml_file))
    
    if not engine.rootObjects():
        print("Failed to load QML file")
        sys.exit(-1)
    
    # Set fullscreen if requested
    if config.FULLSCREEN:
        root = engine.rootObjects()[0]
        root.showFullScreen()
    
    print("Silvia Coffee Machine started successfully!")
    sys.exit(app.exec())

if __name__ == "__main__":
    main()