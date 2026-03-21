from PyQt6.QtGui import QGuiApplication
from PyQt6.QtQml import qmlRegisterType, QQmlApplicationEngine
from PyQt6.QtCore import QUrl
from qml_backend import CoffeeController
import sys
import os

app = QGuiApplication(sys.argv)

# Register the backend with QML
qmlRegisterType(CoffeeController, "CoffeeController", 1, 0, "CoffeeController")

# Create QML engine
engine = QQmlApplicationEngine()
qml_file = os.path.join(os.path.dirname(__file__), "main.qml")
engine.load(QUrl.fromLocalFile(qml_file))

if not engine.rootObjects():
    sys.exit(-1)

sys.exit(app.exec())
