# Offscreen screenshot harness — renders every UI screen/state to PNG so the
# real QML (not a mockup) can be dropped into a design tool. Run from ui/source:
#   QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software python3 _render_screens.py [outdir]
# Temporary tooling; safe to delete.
import os, sys

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
# The offscreen plugin has no GPU context, so it rasterizes in software.
# QtQuick.Shapes DO render in software, but their `layer.enabled` (FBO) does
# not — a layered Shape is dropped entirely (gauge arcs vanish). We disable the
# Shape layers at runtime before each grab so the arcs paint (loses only MSAA
# antialiasing, irrelevant for design references).

import platform_shim
platform_shim.apply_qt_env()
import config
config.USE_MOCK_SERIAL = True   # never touch the real Teensy / live serial

from PyQt6.QtGui import QGuiApplication
from PyQt6.QtQml import (qmlRegisterType, QQmlApplicationEngine, QQmlExpression,
                         QQmlEngine, QQmlProperty)
from PyQt6.QtCore import QUrl, QEventLoop, QTimer
from PyQt6.QtQuick import QQuickWindow
from PyQt6 import sip
from qml_backend import CoffeeController

SRC = os.path.dirname(os.path.abspath(__file__))
OUTDIR = sys.argv[1] if len(sys.argv) > 1 else os.path.join(SRC, "screenshots")
os.makedirs(OUTDIR, exist_ok=True)

app = QGuiApplication(sys.argv)
qmlRegisterType(CoffeeController, "CoffeeController", 1, 0, "CoffeeController")
engine = QQmlApplicationEngine()
engine.load(QUrl.fromLocalFile(os.path.join(SRC, "main.qml")))
if not engine.rootObjects():
    print("FAILED to load QML"); sys.exit(1)
root = engine.rootObjects()[0]
win = sip.cast(root, QQuickWindow)
win.resize(960, 540)
win.show()

# The object's own creation context — this is where the QML ids (window,
# stackView, connectionStatus, brewScreen, …) are registered.
CTX = QQmlEngine.contextForObject(root)


def pump(ms):
    loop = QEventLoop()
    QTimer.singleShot(ms, loop.quit)
    loop.exec()


def qml(expr):
    e = QQmlExpression(CTX, root, expr)
    v = e.evaluate()
    if e.hasError():
        print("QML ERR:", expr, "->", e.error().toString())
    return v


from PyQt6.QtCore import QObject


def disable_shape_layers():
    # Turn off layer.enabled on every QtQuick Shape so the software renderer
    # paints the arcs (FBO-backed layers are dropped in software).
    n = 0
    for ch in root.findChildren(QObject):
        if ch.metaObject().className() == "QQuickShape":
            QQmlProperty.write(ch, "layer.enabled", False)
            n += 1
    return n


# Baseline mock scene values, re-applied before every grab so incoming mock
# telemetry can't overwrite the staged state.
BASE = [
    'connectionStatus.connected = true',
    'window.boilerPrimed = true',
    'window.heatersEnabled = true',
    'window.autoBrewMode = true',
    'window.profileName = "Standard 9-bar"',
    'window.profileIndex = 0',
    'window.brewTargetTemp = 93.0',
    'window.steamTargetTemp = 130.0',
    'window.brewTempActual = 92.0',
    'window.steamTempActual = 128.0',
    'window.currentPressure = 0.0',
    'window.currentWeight = 0.0',
    'window.currentPumpPower = 0.0',
    'window.scalesSettled = true',
    'window.setpointPopup = ""',
    'window.flushActive = false',
    'window.steamActive = false',
    'window.currentState = "IDLE"',
]


def grab(name, extra=()):
    pump(120)                       # let mock tick + any pending render settle
    for ex in BASE:
        qml(ex)
    for ex in extra:
        qml(ex)                     # stage this shot (overrides BASE), synchronous
    disable_shape_layers()          # let the gauge arcs paint in software
    img = win.grabWindow()          # synchronous render+grab; no pump after staging
    path = os.path.join(OUTDIR, name)
    img.save(path)
    print("saved", path, img.width(), "x", img.height())


# ── Home + overlays (initial item) ───────────────────────────────────────────
grab("01_home_idle.png")
grab("02_home_setpoint_brew.png",  ['window.setpointPopup = "brew"'])
grab("03_home_setpoint_steam.png", ['window.setpointPopup = "steam"'])
grab("04_home_unprimed.png",       ['window.setpointPopup = ""', 'window.boilerPrimed = false'])

# ── Brew screen: ready-to-start, then brewing ────────────────────────────────
qml('stackView.push(brewScreen, StackView.Immediate)')
grab("05_brew_ready.png", [
    'window.currentState = "HEATING_BREW"',
    'window.scalesSettled = true',
    'window.brewTime = "00:00"',
    'window.brewTempActual = 93.0',
])
grab("06_brew_brewing.png", [
    'window.currentState = "BREWING"',
    'window.brewTime = "00:23"',
    'window.currentWeight = 22.4',
    'window.currentPressure = 9.0',
    'window.currentPumpPower = 80',
    'window.brewTempActual = 93.2',
])

# ── Steam screen ─────────────────────────────────────────────────────────────
qml('stackView.push(steamScreen, StackView.Immediate)')
grab("07_steam_heating.png", [
    'window.currentState = "HEATING_STEAM"',
    'window.steamTempActual = 118.0',
])
grab("08_steam_ready.png", [
    'window.currentState = "STEAMING"',
    'window.steamActive = true',
    'window.steamTempActual = 130.0',
])

# ── Flush screen ─────────────────────────────────────────────────────────────
qml('stackView.push(flushScreen, StackView.Immediate)')
grab("09_flush.png", ['window.flushActive = true', 'window.currentState = "FLUSHING"'])

# ── Settings screen ──────────────────────────────────────────────────────────
qml('stackView.push(settingsScreen, StackView.Immediate)')
grab("10_settings.png")

print("DONE", OUTDIR)
