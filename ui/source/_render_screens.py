# Offscreen screenshot harness — renders the home + brew UI screens from the
# REAL QML (not a mockup) to PNGs for design iteration. Screen 06 is rendered
# with an ACTUAL historical brew (from brew_logs/) injected into the charts —
# this doubles as a proof-of-concept for a "replay / brew preview" feature.
#
# Run from ui/source:
#   QT_QPA_PLATFORM=offscreen python3 _render_screens.py [outdir] [brew_log.json]
# Temporary tooling; safe to delete.
import os, sys, glob, json

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
# Offscreen rasterizes in software. QtQuick.Shapes paint in software but their
# layer.enabled FBO does not (gauge arcs vanish) — we disable those layers
# before each grab (loses only MSAA antialiasing).

import platform_shim
platform_shim.apply_qt_env()
import config
config.USE_MOCK_SERIAL = True   # never touch the real Teensy / live serial

from PyQt6.QtGui import QGuiApplication
from PyQt6.QtQml import (qmlRegisterType, QQmlApplicationEngine, QQmlExpression,
                         QQmlEngine, QQmlProperty)
from PyQt6.QtCore import QUrl, QEventLoop, QTimer, QObject
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
CTX = QQmlEngine.contextForObject(root)


def pump(ms):
    loop = QEventLoop()
    QTimer.singleShot(ms, loop.quit)
    loop.exec()


def qml(expr, ctx=None, scope=None):
    e = QQmlExpression(ctx or CTX, scope or root, expr)
    v = e.evaluate()
    if isinstance(v, tuple):        # PyQt6 returns (value, isUndefined)
        v = v[0]
    if e.hasError():
        print("QML ERR:", expr, "->", e.error().toString())
    return v


def disable_shape_layers():
    for ch in root.findChildren(QObject):
        if ch.metaObject().className() == "QQuickShape":
            QQmlProperty.write(ch, "layer.enabled", False)


# ── Let the mock connect, then FREEZE its data feed so staged state sticks ────
pump(600)
ctrl = next((c for c in root.findChildren(QObject)
             if c.metaObject().className() == "CoffeeController"), None)
if ctrl is not None and hasattr(ctrl, "serial"):
    try:
        ctrl.serial.stop()
        print("mock serial stopped")
    except Exception as e:
        print("could not stop mock serial:", e)
else:
    print("WARNING: controller not found; mock may overwrite staged state")
pump(50)

# Baseline scene values.
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
    'window.scalesTared = true',
    'window.brewDisplayFrozen = false',
    'window.setpointPopup = ""',
    'window.flushActive = false',
    'window.steamActive = false',
    'window.currentState = "IDLE"',
]
for ex in BASE:
    qml(ex)


def grab(name, extra=()):
    for ex in extra:
        qml(ex)
    disable_shape_layers()
    pump(60)                        # settle bindings (mock is stopped — safe)
    disable_shape_layers()
    img = win.grabWindow()
    path = os.path.join(OUTDIR, name)
    img.save(path)
    print("saved", path)


# ── 01–04 Home + overlays ────────────────────────────────────────────────────
grab("01_home_idle.png")
grab("02_home_setpoint_brew.png",  ['window.setpointPopup = "brew"'])
qml('window.setpointPopup = ""')
grab("03_home_setpoint_steam.png", ['window.setpointPopup = "steam"'])
qml('window.setpointPopup = ""')
grab("04_home_unprimed.png",       ['window.boilerPrimed = false'])
qml('window.boilerPrimed = true')

# ── 05 Brew screen, ready to start ───────────────────────────────────────────
qml('stackView.push(brewScreen, StackView.Immediate)')
grab("05_brew_ready.png", [
    'window.currentState = "HEATING_BREW"',
    'window.brewTime = "00:00"',
    'window.brewTempActual = 93.0',
])

# ── 06 Brew screen, BREWING, with a REAL historical brew on the charts ────────
LOGS = os.path.join(SRC, "brew_logs")
log_arg = sys.argv[2] if len(sys.argv) > 2 else "brew_2026-06-09_19-16-20.json"
log_path = os.path.join(LOGS, log_arg)
if not os.path.exists(log_path):
    cands = sorted(glob.glob(os.path.join(LOGS, "*.json")))
    log_path = cands[-1] if cands else None

if log_path:
    rec = json.load(open(log_path))
    samples = rec.get("samples", [])
    coffee_pts = [{"time": s["t_s"], "weight": s["weight_g"]} for s in samples]
    press_pts = [{"time": s["t_s"], "pressure": s["pressure_bar"]} for s in samples]
    dur = rec.get("duration_s", samples[-1]["t_s"] if samples else 0)
    final_w = rec.get("final_weight_g", 0) or 0
    max_p = rec.get("max_pressure_bar", 0) or 0
    last_p = samples[-1]["pressure_bar"] if samples else 0
    mm, ss = int(dur) // 60, int(dur) % 60
    print(f"brew log: {os.path.basename(log_path)} dur={dur:.0f}s n={len(samples)} "
          f"finW={final_w} maxP={max_p}")

    brew_item = qml('stackView.currentItem')
    ctxB = QQmlEngine.contextForObject(brew_item)
    coffee = qml('coffeeChart', ctxB, brew_item)
    pressure = qml('pressureChart', ctxB, brew_item)
    QQmlProperty.write(coffee, "dataPoints", coffee_pts)
    QQmlProperty.write(pressure, "dataPoints", press_pts)
    qml('coffeeChart.updateScale()', ctxB, brew_item)
    qml('pressureChart.updateScale()', ctxB, brew_item)

    # Stage window state (root scope), then repaint the charts (brew-item scope)
    # so the big-numbers match, then grab — done explicitly because the chart
    # ids live in the brew screen's context, not root.
    for ex in [
        'window.currentState = "BREWING"',
        f'window.brewTime = "{mm:02d}:{ss:02d}"',
        'window.brewDisplayFrozen = true',
        f'window.frozenWeight = {final_w}',
        f'window.frozenPressure = {last_p}',
        f'window.currentWeight = {final_w}',
        f'window.currentPressure = {last_p}',
        'window.brewTempActual = 93.2',
    ]:
        qml(ex)
    qml('coffeeChart.requestPaint()', ctxB, brew_item)
    qml('pressureChart.requestPaint()', ctxB, brew_item)
    disable_shape_layers()
    pump(400)                       # let the Canvas render the curves
    img = win.grabWindow()
    img.save(os.path.join(OUTDIR, "06_brew_brewing.png"))
    print("saved", os.path.join(OUTDIR, "06_brew_brewing.png"))
else:
    print("no brew logs found — skipping 06 real-data shot")

print("DONE", OUTDIR)
