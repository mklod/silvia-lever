# Last modified: 2026-04-16--2346
import platform_shim
platform_shim.apply_qt_env()

from PyQt6.QtGui import QGuiApplication
from PyQt6.QtQml import qmlRegisterType, QQmlApplicationEngine
from PyQt6.QtCore import QUrl
from qml_backend import CoffeeController
import sys
import os

app = QGuiApplication(sys.argv)

qmlRegisterType(CoffeeController, "CoffeeController", 1, 0, "CoffeeController")

engine = QQmlApplicationEngine()
qml_file = os.path.join(os.path.dirname(__file__), "main.qml")
engine.load(QUrl.fromLocalFile(qml_file))

if not engine.rootObjects():
    sys.exit(-1)

if platform_shim.default_fullscreen():
    engine.rootObjects()[0].showFullScreen()

sys.exit(app.exec())
