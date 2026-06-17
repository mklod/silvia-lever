# Offscreen render of the Precision redesign (main_precision.qml) -> PNGs.
# Run from ui/source: QT_QPA_PLATFORM=offscreen python3 _render_precision.py [outdir]
import os, sys, glob, json
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
import platform_shim; platform_shim.apply_qt_env()
import config; config.USE_MOCK_SERIAL = True
from PyQt6.QtGui import QGuiApplication
from PyQt6.QtQml import (qmlRegisterType, QQmlApplicationEngine, QQmlExpression,
                         QQmlEngine, QQmlProperty)
from PyQt6.QtCore import QUrl, QEventLoop, QTimer, QObject
from PyQt6.QtQuick import QQuickWindow
from PyQt6 import sip
from qml_backend import CoffeeController

SRC = os.path.dirname(os.path.abspath(__file__))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(SRC, "screens_precision")
os.makedirs(OUT, exist_ok=True)

app = QGuiApplication(sys.argv)
qmlRegisterType(CoffeeController, "CoffeeController", 1, 0, "CoffeeController")
engine = QQmlApplicationEngine()
engine.load(QUrl.fromLocalFile(os.path.join(SRC, "main_precision.qml")))
if not engine.rootObjects():
    print("FAILED to load main_precision.qml"); sys.exit(1)
root = engine.rootObjects()[0]
win = sip.cast(root, QQuickWindow)
win.resize(960, 540); win.show()
CTX = QQmlEngine.contextForObject(root)

def pump(ms):
    loop = QEventLoop(); QTimer.singleShot(ms, loop.quit); loop.exec()

def qml(expr, ctx=None, scope=None):
    e = QQmlExpression(ctx or CTX, scope or root, expr)
    v = e.evaluate()
    if isinstance(v, tuple): v = v[0]
    if e.hasError(): print("QML ERR:", expr, "->", e.error().toString())
    return v

pump(900)  # let fonts + mock connect
ctrl = next((c for c in root.findChildren(QObject)
             if c.metaObject().className() == "CoffeeController"), None)
if ctrl is not None and hasattr(ctrl, "serial"):
    try: ctrl.serial.stop(); print("mock stopped")
    except Exception as e: print("stop fail", e)
pump(50)

BASE = [
    'connectionStatus.connected = true',
    'window.boilerPrimed = true',
    'window.heatersEnabled = true',
    'window.autoBrewMode = true',
    'window.profileName = "Standard · 9 bar"',
    'window.brewTargetTemp = 92.78',    # 199F
    'window.brewTempActual = 92.22',    # 198F
    'window.steamTargetTemp = 130.0',   # 266F
    'window.steamTempActual = 127.8',   # 262F
    'window.currentPressure = 0.0',
    'window.currentPumpPower = 0.0',
    'window.currentState = "IDLE"',
    'window.setpointPopup = ""',
]
for ex in BASE: qml(ex)

def grab(name, extra=()):
    for ex in extra: qml(ex)
    pump(160)
    img = win.grabWindow()
    img.save(os.path.join(OUT, name)); print("saved", name)

def load_log(path):
    rec = json.load(open(path)); s = rec.get("samples", [])
    # downsample to ~120 points for speed
    step = max(1, len(s) // 120)
    s = s[::step]
    mass = [{"t": x["t_s"], "v": x["weight_g"]} for x in s]
    press = [{"t": x["t_s"], "v": x["pressure_bar"]} for x in s]
    dur = rec.get("duration_s", s[-1]["t_s"] if s else 0)
    return rec, mass, press, dur

LOGS = os.path.join(SRC, "brew_logs")
alllogs = sorted(glob.glob(os.path.join(LOGS, "*.json")))

grab("01_home.png")
grab("02_settemp.png", ['window.setpointPopup = "brew"'])
qml('window.setpointPopup = ""')

# 03 Brew (live) — inject a real shot
brewlog = os.path.join(LOGS, "brew_2026-06-09_19-16-20.json")
if not os.path.exists(brewlog): brewlog = alllogs[-1]
rec, mass, press, dur = load_log(brewlog)
qml('stackView.push(brewScreen, StackView.Immediate)')
QQmlProperty.write(root, "massSeries", mass)
QQmlProperty.write(root, "pressSeries", press)
finw = rec.get("final_weight_g", mass[-1]["v"] if mass else 0) or 0
maxp = rec.get("max_pressure_bar", 9) or 9
mm, ss = int(dur)//60, int(dur)%60
for ex in [
    'window.currentState = "BREWING"',
    'window.brewDisplayFrozen = true',
    f'window.frozenWeight = {finw}', f'window.frozenPressure = {press[-1]["v"] if press else 0}',
    f'window.currentWeight = {finw}', f'window.currentPressure = {press[-1]["v"] if press else 0}',
    f'window.brewTime = "{mm:02d}:{ss:02d}"',
    f'window.brewMaxT = {max(40, dur*1.05)}',
    f'window.brewMaxMass = {max(50, finw*1.1)}',
    'window.brewTempActual = 93.3',
]: qml(ex)
grab("03_brew.png")

# 04 Profile picker
qml('window.selectedProfile = 0')
qml('stackView.push(profileScreen, StackView.Immediate)')
grab("04_profiles.png")

# 05 Shot history — build entries from several real logs
DOSE = 18.0
def downpts(press, n=40):
    step = max(1, len(press)//n)
    return [[p["t"], p["v"]] for p in press[::step]]
hist = []
labels = [("Today","19:16"),("Today","08:02"),("Yesterday","18:44"),("Yesterday","07:51"),("Jun 14","20:10")]
for i, lg in enumerate(reversed(alllogs[-5:])):
    try:
        rec, mass, press, dur = load_log(lg)
        if not mass:
            continue
    except Exception:
        continue
    finw = rec.get("final_weight_g", 0) or 0
    maxp = rec.get("max_pressure_bar", 0) or 0
    mm, ss = int(dur)//60, int(dur)%60
    pname = (rec.get("metadata") or {}).get("profile") or "Standard 9-bar"
    date, tm = labels[i] if i < len(labels) else ("Shot", "")
    ratio = "1:%.1f" % (finw/DOSE) if DOSE else "—"
    hist.append({
        "date": date, "time": tm,
        "meta": f"{finw:.1f}g · {ratio} · {mm}:{ss:02d} · Standard 9-bar",
        "spark": downpts(press), "profile": "Standard 9-bar",
        "yield": f"{finw:.1f}", "ratio": ratio, "timeStr": f"{mm}:{ss:02d}",
        "peak": f"{maxp:.1f}", "mass": mass, "press": press,
        "maxT": max(40, dur*1.05), "maxMass": max(50, finw*1.1),
    })
QQmlProperty.write(root, "shotHistory", hist)
qml('window.selectedShot = 0')
qml('stackView.push(historyScreen, StackView.Immediate)')
grab("05_history.png")

print("DONE", OUT)
