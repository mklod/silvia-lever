// Last modified: 2026-06-16--1722
// Silvia Lever — "Precision Instrument" redesign root.
// Reuses the existing CoffeeController backend; pure-UI rewrite of the screens
// per UI.UX/.../Silvia Lever - Design Spec.md. 960x540 logical, 2x panel.
import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import CoffeeController 1.0
import "precision"
import "precision/profiledata.js" as PD

ApplicationWindow {
    id: window
    width: 960
    height: 540
    visible: true
    color: Theme.bg
    title: "Silvia Lever"

    // ── Live state (mirrors firmware via CoffeeController telemetry) ──────────
    property real brewTempActual: 25.0
    property real steamTempActual: 25.0
    property real currentPressure: 0.0
    property real currentWeight: 0.0
    property real frozenWeight: 0.0
    property real frozenPressure: 0.0
    property bool brewDisplayFrozen: false
    property real currentPumpPower: 0.0
    property string currentState: "IDLE"
    property string brewTime: "00:00"
    property bool steamActive: false
    property bool flushActive: false
    property bool scalesSettled: false
    property bool scalesTared: false
    property real brewTargetTemp: 93.0
    property real steamTargetTemp: 121.11
    property bool heatersEnabled: false
    property bool autoBrewMode: true
    property string profileName: "—"
    property int profileIndex: 0
    property bool boilerPrimed: false
    property bool boilerPreheated: false
    property var profiles: []                 // [{index,name}] from firmware
    property real doseGrams: 20.0             // for brew RATIO (yield/dose); set in Settings

    // setpointPopup: "" hidden, "brew" thermoblock, "steam" boiler
    property string setpointPopup: ""

    // Live brew chart series (accumulated while BREWING)
    property var massSeries: []
    property var pressSeries: []
    property real brewMaxT: 40
    property real brewMaxMass: 50
    property real brewMaxPress: 10
    property real _brewSampleT: 0

    // Profile picker selection; shot history
    property int selectedProfile: 0
    property var shotHistory: []
    property int selectedShot: 0
    // Replay: armed when a saved shot's curve is loaded into the firmware and
    // the brew screen should start it (beginReplay) instead of a normal brew.
    property bool replayArmed: false
    property string replayLabel: ""

    Timer {
        interval: 250; repeat: true
        running: window.currentState === "BREWING"
        onTriggered: {
            window._brewSampleT += 0.25
            var m = window.massSeries.slice(); m.push({ t: window._brewSampleT, v: window.currentWeight })
            var p = window.pressSeries.slice(); p.push({ t: window._brewSampleT, v: window.currentPressure })
            window.massSeries = m; window.pressSeries = p
            if (window._brewSampleT > window.brewMaxT) window.brewMaxT = window._brewSampleT * 1.1
            if (window.currentWeight > window.brewMaxMass) window.brewMaxMass = window.currentWeight * 1.1
        }
    }

    // °C (firmware) ↔ °F (display)
    function cToF(c) { return c * 9.0 / 5.0 + 32.0 }
    function fToC(f) { return (f - 32.0) * 5.0 / 9.0 }
    function fmtRatio(yield_g) {
        if (doseGrams <= 0) return "—"
        return "1:" + (yield_g / doseGrams).toFixed(1)
    }

    CoffeeController {
        id: controller
        onBrewTempChanged:  function(t)  { window.brewTempActual = t }
        onSteamTempChanged: function(t)  { window.steamTempActual = t }
        onPressureChanged:  function(p)  { window.currentPressure = p }
        onWeightChanged:    function(w)  { window.currentWeight = isFinite(w) ? w : 0 }
        onPumpPowerChanged: function(p)  { window.currentPumpPower = p }
        onStateChanged: function(st) {
            var wasBrewing = (window.currentState === "BREWING")
            var nowBrewing = (st === "BREWING")
            if (wasBrewing && !nowBrewing) {
                window.frozenWeight = window.currentWeight
                window.frozenPressure = window.currentPressure
                window.brewDisplayFrozen = true
            } else if (!wasBrewing && nowBrewing) {
                window.brewDisplayFrozen = false
                window.massSeries = []; window.pressSeries = []
                window._brewSampleT = 0
                window.brewMaxT = 40; window.brewMaxMass = 50
            }
            window.steamActive = (st === "STEAMING")
            window.currentState = st
        }
        onBrewTimeChanged: function(t) { window.brewTime = t }
        onConnectionStatusChanged: function(c) { connectionStatus.connected = c }
        onScalesSettledChanged: function(s) { window.scalesSettled = s }
        onScalesTaredChanged:   function(s) { window.scalesTared = s }
        onTargetTemperaturesChanged: function(b, s) { window.brewTargetTemp = b; window.steamTargetTemp = s }
        onHeatersEnabledChanged: function(e) { window.heatersEnabled = e }
        onAutoBrewModeChanged:   function(a) { window.autoBrewMode = a }
        onActiveProfileChanged:  function(i, n) { window.profileIndex = i; window.profileName = n }
        onBoilerPrimedChanged:   function(p) { window.boilerPrimed = p }
        onBoilerPreheatedChanged: function(r) { window.boilerPreheated = r }
        onProfilesChanged: function(list) { window.profiles = list }
        onShotsChanged: function(list) { window.shotHistory = list; window.selectedShot = 0 }
        onDoseChanged: function(g) { window.doseGrams = g }
        onErrorOccurred: function(e) {}
        onAutotuneLineReceived: function(line) { autotuneOverlay.append(line) }
    }

    QtObject { id: connectionStatus; property bool connected: false }

    // ── Status line (every screen) ───────────────────────────────────────────
    StatusBar {
        id: statusBar
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        z: 100
        heatersOn: window.heatersEnabled
        brewAuto: window.autoBrewMode
        profName: window.profileName
        pressure: window.currentPressure
        pump: Math.round(window.currentPumpPower)
        connected: connectionStatus.connected
        onHeatTapped: controller.setHeatersEnabled(!window.heatersEnabled)
        onBrewTapped: controller.setAutoBrewMode(!window.autoBrewMode)
        onProfTapped: stackView.push(profileScreen)
    }

    StackView {
        id: stackView
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: statusBar.top
        initialItem: homeScreen
    }

    // ═══ HOME ════════════════════════════════════════════════════════════════
    Component {
        id: homeScreen
        Item {
            // Header
            Item {
                id: homeHeader
                anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                anchors.topMargin: 30; anchors.leftMargin: 40; anchors.rightMargin: 40
                height: 24
                Overline {
                    id: brand
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    text: "SILVIA · LEVER"; tracking: 4
                    MouseArea { anchors.fill: parent; anchors.margins: -10
                                onClicked: { controller.requestShots(); stackView.push(historyScreen) } }
                }
                // Center: tappable entry to Shot history.
                MouseArea {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: histRow.width + 20; implicitHeight: 32
                    onClicked: { controller.requestShots(); stackView.push(historyScreen) }
                    Row { id: histRow; spacing: 7; anchors.centerIn: parent
                        Text { text: "↻"; color: Theme.dim; font.pixelSize: 14
                               anchors.verticalCenter: parent.verticalCenter }
                        Overline { text: "SHOT HISTORY"; tracking: 3
                                   anchors.verticalCenter: parent.verticalCenter }
                    }
                }
                Row {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    spacing: 18
                    Row {
                        spacing: 8; anchors.verticalCenter: parent.verticalCenter
                        Rectangle { width: 7; height: 7; radius: 3.5; color: Theme.red
                                    anchors.verticalCenter: parent.verticalCenter }
                        Overline { text: connectionStatus.connected ? "READY" : "OFFLINE"; tracking: 3
                                   anchors.verticalCenter: parent.verticalCenter }
                    }
                    MouseArea {
                        implicitWidth: 26; implicitHeight: 26
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: stackView.push(settingsScreen)
                        Text { anchors.centerIn: parent; text: "⚙"; color: Theme.dim; font.pixelSize: 20 }
                    }
                }
            }

            // Two instrument columns
            Row {
                anchors.top: parent.top; anchors.topMargin: 92
                anchors.left: parent.left; anchors.right: parent.right
                anchors.leftMargin: 56; anchors.rightMargin: 56
                // space-between via spacing on a width-filling row
                Item {
                    width: (parent.width - 0) / 2
                    height: 360
                    InstrumentCol {
                        anchors.left: parent.left
                        mirrored: false
                        label: "THERMOBLOCK"; sub: "Brew / extraction"
                        meterMin: 140; meterMax: 230
                        valueF: window.cToF(window.brewTempActual)
                        setF: window.cToF(window.brewTargetTemp)
                        btn1Text: "BREW"; btn1Variant: "primary"
                        btn2Text: "FLUSH"; btn2Variant: "plain"
                        btn2Active: window.flushActive          // text white→red while flushing
                        onMeterTapped: window.setpointPopup = "brew"
                        onBtn1: { window.replayArmed = false; controller.heatBrew(); stackView.push(brewScreen) }
                        onBtn2: { if (window.flushActive) { window.flushActive=false; controller.stopFlush() }
                                  else { window.flushActive=true; controller.startFlush() } }
                    }
                }
                Item {
                    width: (parent.width - 0) / 2
                    height: 360
                    InstrumentCol {
                        anchors.right: parent.right
                        mirrored: true
                        label: "STEAM BOILER"; sub: "Milk / steam"
                        meterMin: 230; meterMax: 302
                        valueF: window.cToF(window.steamTempActual)
                        setF: window.cToF(window.steamTargetTemp)
                        btn1Text: "STEAM"; btn1Variant: "primary"
                        btn1Active: window.steamActive          // text white→red while steaming
                        // PRIME is a 3-state: idle → fill → confirm-overflow. While
                        // filling, tapping confirms (primeDone) and STOPS the pump.
                        // Primed = red outline (armed), label stays "PRIME".
                        btn2Text: window.currentState === "PRIMING_STEAM" ? "OVERFLOW? TAP" : "PRIME"
                        btn2Variant: window.currentState === "PRIMING_STEAM" ? "alert"
                                     : (window.boilerPrimed ? "outline" : "plain")
                        onMeterTapped: window.setpointPopup = "steam"
                        onBtn1: { if (window.steamActive) controller.stopSteam(); else controller.beginSteam() }
                        onBtn2: { if (window.currentState === "PRIMING_STEAM") controller.primeDone()
                                  else controller.primeBoiler() }
                    }
                }
            }
        }
    }

    // ═══ SET TEMPERATURE (modal) ═══════════════════════════════════════════════
    Item {
        id: setpointOverlay
        anchors.fill: parent
        z: 200
        visible: window.setpointPopup !== ""
        property bool isSteam: window.setpointPopup === "steam"
        property real curF: isSteam ? Math.round(window.cToF(window.steamTargetTemp))
                                    : Math.round(window.cToF(window.brewTargetTemp))
        property int loF: isSteam ? 230 : 140
        property int hiF: isSteam ? 302 : 230

        function commit() {
            if (isSteam) window.steamTargetTemp = window.fToC(curF)
            else window.brewTargetTemp = window.fToC(curF)
            controller.setTemperatures(window.brewTargetTemp, window.steamTargetTemp)
        }

        // scrim + dimmed home (home reads at ~.18 behind this)
        Rectangle { anchors.fill: parent; color: Qt.rgba(0,0,0,0.86)
                    MouseArea { anchors.fill: parent; onClicked: window.setpointPopup = "" } }

        Rectangle {
            width: 500
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -10
            implicitHeight: spCol.implicitHeight + 80
            color: Theme.popup; radius: 8
            border.width: 1; border.color: Theme.hair

            Column {
                id: spCol
                anchors.fill: parent; anchors.margins: 40; anchors.leftMargin: 44; anchors.rightMargin: 44
                spacing: 26
                Overline { text: (setpointOverlay.isSteam ? "STEAM BOILER · STEAM TARGET" : "THERMOBLOCK · BREW TARGET") }
                Item {
                    width: parent.width; height: 92
                    // − key
                    Rectangle {
                        width: 92; height: 92; radius: 6; color: "transparent"
                        border.width: 1; border.color: Theme.hair
                        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                        Text { anchors.centerIn: parent; text: "−"; color: Theme.ink
                               font.family: Theme.archivo; font.pixelSize: 40; font.weight: Theme.w500 }
                        MouseArea { anchors.fill: parent; onClicked:
                            setpointOverlay.curF = Math.max(setpointOverlay.loF, setpointOverlay.curF - 1) }
                    }
                    // numeral + range
                    Column {
                        anchors.centerIn: parent; spacing: 2
                        Text { anchors.horizontalCenter: parent.horizontalCenter
                               text: setpointOverlay.curF + "°"; color: Theme.ink
                               font.family: Theme.archivo; font.pixelSize: 96; font.weight: Theme.w700
                               font.letterSpacing: -3 }
                        Text { anchors.horizontalCenter: parent.horizontalCenter
                               text: "RANGE " + setpointOverlay.loF + "–" + setpointOverlay.hiF + "°F"
                               color: Theme.dim; font.family: Theme.archivo; font.pixelSize: 14; font.weight: Theme.w500 }
                    }
                    // + key (red)
                    Rectangle {
                        id: plusKey
                        width: 92; height: 92; radius: 6; color: Theme.redFill
                        border.width: 1; border.color: Theme.red
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        Text { anchors.centerIn: parent; text: "+"; color: Theme.red
                               font.family: Theme.archivo; font.pixelSize: 40; font.weight: Theme.w500 }
                        MouseArea { anchors.fill: parent; onClicked:
                            setpointOverlay.curF = Math.min(setpointOverlay.hiF, setpointOverlay.curF + 1) }
                    }
                }
                Rectangle {
                    width: parent.width; height: 72; radius: 4; color: Theme.ink
                    Text { anchors.centerIn: parent; text: "DONE"; color: "#000000"
                           font.family: Theme.archivo; font.pixelSize: 22; font.weight: Theme.w700; font.letterSpacing: 2 }
                    MouseArea { anchors.fill: parent; onClicked: { setpointOverlay.commit(); window.setpointPopup = "" } }
                }
            }
        }
    }

    // ═══ BREW (live) ═══════════════════════════════════════════════════════════
    Component {
        id: brewScreen
        Item {
            Item {
                id: bh
                anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                anchors.topMargin: 26; anchors.leftMargin: 40; anchors.rightMargin: 40
                height: 80
                BackChip { id: bback; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                           onClicked: { controller.stopBrew(); window.replayArmed = false; stackView.pop() } }
                Row {
                    id: statsRow
                    anchors.left: bback.right; anchors.leftMargin: 30; anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    readonly property real cell: (width) / 4
                    Repeater {
                        model: [
                            { l: "MASS", v: (window.brewDisplayFrozen ? window.frozenWeight : window.currentWeight).toFixed(1), u: "g", c: Theme.ink },
                            { l: "TIME", v: window.brewTime, u: "", c: Theme.red },
                            { l: "RATIO", v: window.fmtRatio(window.brewDisplayFrozen ? window.frozenWeight : window.currentWeight), u: "", c: Theme.ink },
                            { l: "BREW TEMP", v: window.cToF(window.brewTempActual).toFixed(0), u: "°F", c: Theme.ink }
                        ]
                        delegate: Item {
                            width: statsRow.cell; height: 80
                            StatItem {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 10
                                label: modelData.l; value: modelData.v; unit: modelData.u
                                valueColor: modelData.c; numeralSize: 54; align: Text.AlignHCenter
                            }
                        }
                    }
                }
            }
            ChartCard {
                id: massCard
                anchors.top: parent.top; anchors.topMargin: 150
                anchors.left: parent.left; anchors.right: parent.right
                anchors.leftMargin: 40; anchors.rightMargin: 40
                height: 168
                title: "COFFEE MASS"
                valueText: (window.brewDisplayFrozen ? window.frozenWeight : window.currentWeight).toFixed(1)
                unit: "g"; traceColor: Theme.mass
                series: window.massSeries; maxT: window.brewMaxT; maxV: window.brewMaxMass
            }
            ChartCard {
                anchors.top: massCard.bottom; anchors.topMargin: 16
                anchors.left: parent.left; anchors.right: parent.right
                anchors.leftMargin: 40; anchors.rightMargin: 40
                height: 168
                title: "PRESSURE"
                valueText: (window.brewDisplayFrozen ? window.frozenPressure : window.currentPressure).toFixed(1)
                unit: "bar"; traceColor: Theme.red
                series: window.pressSeries; maxT: window.brewMaxT; maxV: window.brewMaxPress
            }

            // ── Large STOP target while brewing — a generous band centered on
            //    the TIME clock so stop is easy to hit (not the whole screen, so
            //    chart edges / back chip stay free).
            Item {
                visible: window.currentState === "BREWING"
                z: 25
                anchors.top: parent.top; anchors.topMargin: 8
                anchors.horizontalCenter: parent.horizontalCenter
                width: 460; height: 132
                MouseArea { anchors.fill: parent; onClicked: controller.stopBrew() }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    text: "TAP TIMER TO STOP"; color: Theme.dim
                    font.family: Theme.archivo; font.pixelSize: 12; font.letterSpacing: 1.5
                }
            }

            // ── Start affordance: tap anywhere to begin while heating. Hidden
            //    once BREWING (then the charts show; tap the timer band to stop).
            Item {
                anchors.fill: parent
                anchors.topMargin: 110            // leave the back chip + stats tappable
                visible: window.currentState === "HEATING_BREW"
                z: 30
                MouseArea { anchors.fill: parent
                            onClicked: window.replayArmed ? controller.beginReplay() : controller.beginBrew() }
                Rectangle {
                    anchors.centerIn: parent
                    width: startCol.width + 80; height: startCol.height + 48
                    radius: 8; color: window.replayArmed ? Qt.rgba(1,0.27,0.227,0.05) : Qt.rgba(1,1,1,0.03)
                    border.width: 1; border.color: window.replayArmed ? Theme.red : Theme.hair
                    Column {
                        id: startCol
                        anchors.centerIn: parent; spacing: 10
                        Text { anchors.horizontalCenter: parent.horizontalCenter
                               text: window.replayArmed ? "TAP TO REPLAY" : "TAP TO START"
                               color: window.replayArmed ? Theme.red : Theme.ink
                               font.family: Theme.archivo; font.pixelSize: 30; font.weight: Theme.w700; font.letterSpacing: 2 }
                        Text { anchors.horizontalCenter: parent.horizontalCenter
                               visible: window.replayArmed
                               text: "Repeating " + window.replayLabel + " — pressure curve"
                               color: Theme.dim; font.family: Theme.archivo; font.pixelSize: 14 }
                        Text { anchors.horizontalCenter: parent.horizontalCenter
                               text: window.heatersEnabled
                                     ? (window.cToF(window.brewTempActual).toFixed(0) + "°F → " + window.cToF(window.brewTargetTemp).toFixed(0) + "°F")
                                     : "Heaters OFF — tap HEAT below to warm up"
                               color: window.heatersEnabled ? Theme.dim : Theme.red
                               font.family: Theme.archivo; font.pixelSize: 14 }
                    }
                }
            }
        }
    }

    // ═══ PROFILE PICKER ════════════════════════════════════════════════════════
    Component {
        id: profileScreen
        Item {
            id: profRoot
            property int sel: window.selectedProfile
            property var prof: PD.PROFILES[sel]

            Item {
                id: ph
                anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                anchors.topMargin: 26; anchors.leftMargin: 40; anchors.rightMargin: 40
                height: 56
                BackChip { id: pback; size: 48; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                           onClicked: stackView.pop() }
                Column {
                    anchors.left: pback.right; anchors.leftMargin: 18; anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Overline { text: "PRESSURE PROFILE" }
                    Text { text: "Select extraction curve"; color: Theme.ink
                           font.family: Theme.archivo; font.pixelSize: 24; font.weight: Theme.w600 }
                }
            }

            // List
            Column {
                anchors.top: parent.top; anchors.topMargin: 100
                anchors.left: parent.left; anchors.leftMargin: 40
                width: 312; spacing: 8
                Repeater {
                    model: PD.PROFILES.length
                    delegate: Rectangle {
                        width: 312; height: 72; radius: 5
                        property bool seld: profRoot.sel === index
                        color: seld ? Qt.rgba(1, 0.27, 0.227, 0.06) : "transparent"
                        border.width: 1; border.color: seld ? Theme.red : Theme.hair
                        Column {
                            anchors.left: parent.left; anchors.leftMargin: 14
                            anchors.right: spark.left; anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter; spacing: 3
                            Text { text: PD.PROFILES[index].name; color: Theme.ink
                                   font.family: Theme.archivo; font.pixelSize: 17; font.weight: Theme.w700 }
                            Text { width: parent.width; elide: Text.ElideRight
                                   text: PD.PROFILES[index].desc; color: Theme.dim
                                   font.family: Theme.archivo; font.pixelSize: 12 }
                        }
                        Column {
                            id: spark
                            anchors.right: parent.right; anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter; spacing: 4
                            Text { anchors.right: parent.right; text: PD.PROFILES[index].peak; color: Theme.dim
                                   font.family: Theme.mono; font.pixelSize: 11 }
                            Sparkline { width: 64; height: 26; pts: PD.PROFILES[index].pts
                                        color: (profRoot.sel === index) ? Theme.red : Theme.dim }
                        }
                        MouseArea { anchors.fill: parent; onClicked: {
                            profRoot.sel = index; window.selectedProfile = index
                            controller.setProfile(index)   // activate on firmware
                        } }
                    }
                }
            }

            // Detail
            Rectangle {
                anchors.top: parent.top; anchors.topMargin: 100
                anchors.left: parent.left; anchors.leftMargin: 372
                anchors.right: parent.right; anchors.rightMargin: 36
                anchors.bottom: parent.bottom; anchors.bottomMargin: 12
                radius: 6; color: Theme.card; border.width: 1; border.color: Theme.hair
                Column {
                    anchors.fill: parent; anchors.margins: 16; anchors.leftMargin: 20; anchors.rightMargin: 20
                    spacing: 10
                    // title row
                    Item {
                        width: parent.width; height: 30
                        Row {
                            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; spacing: 12
                            Text { text: profRoot.prof.name; color: Theme.ink
                                   font.family: Theme.archivo; font.pixelSize: 23; font.weight: Theme.w700 }
                            Rectangle { radius: 20; color: "transparent"; border.width: 1; border.color: Theme.hair
                                        anchors.verticalCenter: parent.verticalCenter
                                        implicitWidth: tagT.width + 18; implicitHeight: 22
                                        Text { id: tagT; anchors.centerIn: parent; text: profRoot.prof.tag; color: Theme.dim
                                               font.family: Theme.archivo; font.pixelSize: 11 } }
                        }
                        Row {
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 7
                            visible: profRoot.sel === window.profileIndex
                            Rectangle { width: 6; height: 6; radius: 3; color: Theme.red; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: "ACTIVE"; color: Theme.red
                                   font.family: Theme.archivo; font.pixelSize: 11; font.weight: Theme.w700; font.letterSpacing: 1 }
                        }
                    }
                    Text { width: parent.width; wrapMode: Text.WordWrap; text: profRoot.prof.aim; color: Theme.dim
                           font.family: Theme.archivo; font.pixelSize: 13; lineHeight: 1.3 }
                    PhaseChart { width: parent.width; height: 128; pts: profRoot.prof.pts; phases: profRoot.prof.phases }
                    // phase table
                    Column {
                        width: parent.width; spacing: 0
                        Row {
                            width: parent.width; spacing: 18
                            Text { width: 78; text: "PHASE"; color: Theme.dim; font.family: Theme.archivo; font.pixelSize: 11; font.weight: Theme.w700; font.letterSpacing: 1; font.capitalization: Font.AllUppercase }
                            Text { width: 52; text: "TARGET"; color: Theme.dim; font.family: Theme.archivo; font.pixelSize: 11; font.weight: Theme.w700; font.letterSpacing: 1 }
                            Text { width: 110; text: "RAMP"; color: Theme.dim; font.family: Theme.archivo; font.pixelSize: 11; font.weight: Theme.w700; font.letterSpacing: 1 }
                            Text { text: "EXITS WHEN"; color: Theme.dim; font.family: Theme.archivo; font.pixelSize: 11; font.weight: Theme.w700; font.letterSpacing: 1 }
                        }
                        Repeater {
                            model: profRoot.prof.phases.length
                            delegate: Column {
                                width: parent.width
                                Rectangle { width: parent.width; height: 1; color: Theme.hair }
                                Row {
                                    width: parent.width; spacing: 18; topPadding: 7; bottomPadding: 7
                                    property var ph: profRoot.prof.phases[index]
                                    Text { width: 78; text: parent.ph.name; color: Theme.ink; font.family: Theme.archivo; font.pixelSize: 12; font.weight: Theme.w700 }
                                    Text { width: 52; text: parent.ph.target; color: Theme.ink; font.family: Theme.mono; font.pixelSize: 12 }
                                    Text { width: 110; elide: Text.ElideRight; text: parent.ph.ramp; color: Theme.ink; font.family: Theme.mono; font.pixelSize: 12 }
                                    Text { width: parent.width - 330; elide: Text.ElideRight; text: parent.ph.exit; color: Theme.dim; font.family: Theme.archivo; font.pixelSize: 12 }
                                }
                            }
                        }
                    }
                    // grind
                    Column {
                        width: parent.width; spacing: 3
                        Overline { text: "GRIND" }
                        Text { width: parent.width; wrapMode: Text.WordWrap; text: profRoot.prof.grind
                               color: Qt.rgba(1,1,1,0.62); font.family: Theme.archivo; font.pixelSize: 12 }
                    }
                }
            }
        }
    }

    // ═══ SHOT HISTORY / REPLAY ═════════════════════════════════════════════════
    Component {
        id: historyScreen
        Item {
            id: histRoot
            property var shots: window.shotHistory
            property int sel: window.selectedShot
            property var shot: (shots && shots.length > sel) ? shots[sel] : null

            Item {
                id: hh
                anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                anchors.topMargin: 30; anchors.leftMargin: 40; anchors.rightMargin: 40
                height: 56
                BackChip { id: hback; size: 48; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                           onClicked: stackView.pop() }
                Column {
                    anchors.left: hback.right; anchors.leftMargin: 18; anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Overline { text: "SHOT HISTORY" }
                    Text { text: "Review & replay"; color: Theme.ink
                           font.family: Theme.archivo; font.pixelSize: 24; font.weight: Theme.w600 }
                }
                Overline { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                           text: (histRoot.shots ? histRoot.shots.length : 0) + " SAVED" }
            }

            // List (scrollable / flickable)
            ListView {
                id: shotList
                anchors.top: parent.top; anchors.topMargin: 110
                anchors.left: parent.left; anchors.leftMargin: 40
                anchors.bottom: parent.bottom; anchors.bottomMargin: 14
                width: 392
                clip: true
                spacing: 10
                cacheBuffer: 1200
                boundsBehavior: Flickable.StopAtBounds
                flickDeceleration: 2500
                model: histRoot.shots ? histRoot.shots.length : 0
                delegate: Rectangle {
                    width: 392; height: 64; radius: 5
                    property bool seld: histRoot.sel === index
                    color: seld ? Qt.rgba(1,0.27,0.227,0.06) : "transparent"
                    border.width: 1; border.color: seld ? Theme.red : Theme.hair
                    Column {
                        anchors.left: parent.left; anchors.leftMargin: 14
                        anchors.right: rowSpark.left; anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter; spacing: 4
                        Row { spacing: 6
                            Text { text: histRoot.shots[index].date; color: Theme.ink; font.family: Theme.archivo; font.pixelSize: 17; font.weight: Theme.w600 }
                            Text { text: "· " + histRoot.shots[index].time; color: Theme.dim; font.family: Theme.archivo; font.pixelSize: 14 }
                        }
                        Text { width: parent.width; elide: Text.ElideRight; text: histRoot.shots[index].meta; color: Theme.dim; font.family: Theme.mono; font.pixelSize: 13 }
                    }
                    Sparkline { id: rowSpark; anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter
                                width: 64; height: 26; pts: histRoot.shots[index].spark; color: seld ? Theme.red : Theme.dim }
                    MouseArea { anchors.fill: parent; onClicked: { histRoot.sel = index; window.selectedShot = index } }
                }
            }

            // Detail (mini brew)
            Rectangle {
                id: detail
                anchors.top: parent.top; anchors.topMargin: 110
                anchors.left: parent.left; anchors.leftMargin: 452
                anchors.right: parent.right; anchors.rightMargin: 40
                anchors.bottom: parent.bottom; anchors.bottomMargin: 16
                radius: 6; color: Theme.card; border.width: 1; border.color: Theme.hair
                visible: histRoot.shot !== null

                property real replayClip: 1e9    // full curve by default
                // Reset to full when the selected shot changes.
                Connections { target: window
                    function onSelectedShotChanged() { replayAnim.stop(); detail.replayClip = 1e9 } }
                NumberAnimation {
                    id: replayAnim; target: detail; property: "replayClip"
                    from: 0; to: histRoot.shot ? histRoot.shot.maxT : 40
                    duration: histRoot.shot ? Math.round(histRoot.shot.maxT * 1000) : 40000
                    easing.type: Easing.Linear
                }
                Column {
                    anchors.fill: parent; anchors.margins: 14; anchors.leftMargin: 18; anchors.rightMargin: 18
                    spacing: 12
                    Item {
                        width: parent.width; height: 18
                        Overline { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                   text: histRoot.shot ? (histRoot.shot.date + " · " + histRoot.shot.time + " · " + histRoot.shot.profile) : "" }
                        MouseArea {
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            implicitWidth: replayRow.width; implicitHeight: 24
                            onClicked: {
                                controller.loadReplay(histRoot.sel)
                                window.replayArmed = true
                                window.replayLabel = histRoot.shot ? (histRoot.shot.date + " · " + histRoot.shot.time) : ""
                                stackView.push(brewScreen)
                            }
                            Row { id: replayRow; spacing: 6; anchors.verticalCenter: parent.verticalCenter
                                Text { text: "▶"; color: Theme.red; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
                                Text { text: "REPLAY"; color: Theme.red; font.family: Theme.archivo; font.pixelSize: 12; font.weight: Theme.w700; font.letterSpacing: 1 }
                            }
                        }
                    }
                    Row {
                        width: parent.width
                        readonly property real cell: width / 4
                        Repeater {
                            model: histRoot.shot ? [
                                { l: "YIELD", v: histRoot.shot.yield, u: "g", c: Theme.ink },
                                { l: "RATIO", v: histRoot.shot.ratio, u: "", c: Theme.ink },
                                { l: "TIME", v: histRoot.shot.timeStr, u: "", c: Theme.red },
                                { l: "PEAK", v: histRoot.shot.peak, u: "bar", c: Theme.ink }
                            ] : []
                            delegate: Item {
                                width: parent.cell; height: 46
                                StatItem { anchors.left: parent.left; width: parent.width - 8
                                           label: modelData.l; value: modelData.v
                                           unit: modelData.u; valueColor: modelData.c; numeralSize: 26; tracking: 0 }
                            }
                        }
                    }
                    ChartCard {
                        width: parent.width; height: 112
                        title: "COFFEE MASS"; unit: "g"; traceColor: Theme.mass
                        valueText: histRoot.shot ? histRoot.shot.yield : ""
                        series: histRoot.shot ? histRoot.shot.mass : []
                        maxT: histRoot.shot ? histRoot.shot.maxT : 40
                        maxV: histRoot.shot ? histRoot.shot.maxMass : 50
                        clipT: detail.replayClip
                    }
                    ChartCard {
                        width: parent.width; height: 112
                        title: "PRESSURE"; unit: "bar"; traceColor: Theme.red
                        valueText: histRoot.shot ? histRoot.shot.peak : ""
                        series: histRoot.shot ? histRoot.shot.press : []
                        maxT: histRoot.shot ? histRoot.shot.maxT : 40
                        maxV: 10
                        clipT: detail.replayClip
                    }
                }
            }
        }
    }

    // ═══ SETTINGS ══════════════════════════════════════════════════════════════
    Component {
        id: settingsScreen
        Item {
            Item {
                anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                anchors.topMargin: 30; anchors.leftMargin: 40; anchors.rightMargin: 40
                height: 56
                BackChip { id: sback; size: 48; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                           onClicked: stackView.pop() }
                Column {
                    anchors.left: sback.right; anchors.leftMargin: 18; anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Overline { text: "SETTINGS" }
                    Text { text: "Dose & calibration"; color: Theme.ink
                           font.family: Theme.archivo; font.pixelSize: 24; font.weight: Theme.w600 }
                }
            }

            Column {
                anchors.top: parent.top; anchors.topMargin: 120
                anchors.left: parent.left; anchors.leftMargin: 56
                spacing: 30

                // DOSE
                Column {
                    spacing: 12
                    Overline { text: "DOSE — basket weight, drives RATIO" }
                    Row {
                        spacing: 16
                        Rectangle { width: 72; height: 72; radius: 6; color: "transparent"; border.width: 1; border.color: Theme.hair
                            Text { anchors.centerIn: parent; text: "−"; color: Theme.ink; font.family: Theme.archivo; font.pixelSize: 34 }
                            MouseArea { anchors.fill: parent; onClicked: controller.setDose(window.doseGrams - 0.5) } }
                        Item { width: 150; height: 72
                            Row { anchors.centerIn: parent; spacing: 4
                                Text { id: doseNum; text: window.doseGrams.toFixed(1); color: Theme.ink
                                       font.family: Theme.archivo; font.pixelSize: 48; font.weight: Theme.w700 }
                                Text { text: "g"; color: Theme.dim; anchors.baseline: doseNum.baseline
                                       font.family: Theme.archivo; font.pixelSize: 18 } } }
                        Rectangle { width: 72; height: 72; radius: 6; color: "transparent"; border.width: 1; border.color: Theme.hair
                            Text { anchors.centerIn: parent; text: "+"; color: Theme.ink; font.family: Theme.archivo; font.pixelSize: 34 }
                            MouseArea { anchors.fill: parent; onClicked: controller.setDose(window.doseGrams + 0.5) } }
                    }
                }

                // SCALE
                Column {
                    spacing: 12
                    Row { spacing: 16
                        Overline { text: "SCALE"; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: "live " + window.currentWeight.toFixed(1) + " g"; color: Theme.dim
                               anchors.verticalCenter: parent.verticalCenter
                               font.family: Theme.mono; font.pixelSize: 12 }
                    }
                    Row { spacing: 16
                        PButton { text: "TARE"; variant: "plain"; onClicked: controller.tareScales() }
                        PButton { text: "CALIBRATE"; variant: "primary"; onClicked: calOverlay.shown = true }
                    }
                }

                // PID
                Column {
                    spacing: 12
                    Overline { text: "PID — thermoblock autotune" }
                    PButton { width: 232; text: "AUTOTUNE"; variant: "primary"; onClicked: autotuneOverlay.start() }
                }
            }
        }
    }

    // ── Calibration modal ─────────────────────────────────────────────────────
    Item {
        id: calOverlay
        anchors.fill: parent; z: 210
        property bool shown: false
        property real calWeight: 100
        visible: shown
        onShownChanged: if (shown) controller.tareScales()   // zero before placing weight
        Rectangle { anchors.fill: parent; color: Qt.rgba(0,0,0,0.86)
                    MouseArea { anchors.fill: parent; onClicked: calOverlay.shown = false } }
        Rectangle {
            width: 520; anchors.centerIn: parent
            implicitHeight: calCol.implicitHeight + 80
            color: Theme.popup; radius: 8; border.width: 1; border.color: Theme.hair
            Column {
                id: calCol
                anchors.fill: parent; anchors.margins: 40; spacing: 22
                Overline { text: "SCALE CALIBRATION" }
                Text { width: parent.width; wrapMode: Text.WordWrap
                       text: "Tared on open. Place a known weight, set its mass, then CALIBRATE."
                       color: Theme.dim; font.family: Theme.archivo; font.pixelSize: 14 }
                Text { text: "live " + window.currentWeight.toFixed(1) + " g (uncal)"; color: Theme.dim
                       font.family: Theme.mono; font.pixelSize: 13 }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter; spacing: 16
                    Rectangle { width: 72; height: 72; radius: 6; color: "transparent"; border.width: 1; border.color: Theme.hair
                        Text { anchors.centerIn: parent; text: "−"; color: Theme.ink; font.family: Theme.archivo; font.pixelSize: 34 }
                        MouseArea { anchors.fill: parent; onClicked: calOverlay.calWeight = Math.max(10, calOverlay.calWeight - 10) } }
                    Item { width: 150; height: 72
                        Row { anchors.centerIn: parent; spacing: 4
                            Text { id: calNum; text: calOverlay.calWeight.toFixed(0); color: Theme.ink
                                   font.family: Theme.archivo; font.pixelSize: 48; font.weight: Theme.w700 }
                            Text { text: "g"; color: Theme.dim; anchors.baseline: calNum.baseline
                                   font.family: Theme.archivo; font.pixelSize: 18 } } }
                    Rectangle { width: 72; height: 72; radius: 6; color: "transparent"; border.width: 1; border.color: Theme.hair
                        Text { anchors.centerIn: parent; text: "+"; color: Theme.ink; font.family: Theme.archivo; font.pixelSize: 34 }
                        MouseArea { anchors.fill: parent; onClicked: calOverlay.calWeight = Math.min(2000, calOverlay.calWeight + 10) } }
                }
                Rectangle {
                    width: parent.width; height: 72; radius: 4; color: Theme.ink
                    Text { anchors.centerIn: parent; text: "CALIBRATE"; color: "#000000"
                           font.family: Theme.archivo; font.pixelSize: 22; font.weight: Theme.w700; font.letterSpacing: 2 }
                    MouseArea { anchors.fill: parent; onClicked: { controller.calibrateScales(calOverlay.calWeight); calOverlay.shown = false } }
                }
            }
        }
    }

    // ── Autotune modal ────────────────────────────────────────────────────────
    Item {
        id: autotuneOverlay
        anchors.fill: parent; z: 210
        property bool shown: false
        property bool finished: false
        property string logText: ""
        visible: shown
        function start() { logText = ""; finished = false; shown = true; controller.startAutotune() }
        function append(line) {
            logText += line + "\n"
            if (line.indexOf("AUTOTUNE_RESULT:") === 0 || line.indexOf("AUTOTUNE:FAIL") === 0) finished = true
            logFlick.contentY = Math.max(0, logText.length)   // nudge scroll
        }
        Rectangle { anchors.fill: parent; color: Qt.rgba(0,0,0,0.9) }
        Rectangle {
            width: 620; height: 420; anchors.centerIn: parent
            color: Theme.popup; radius: 8; border.width: 1; border.color: Theme.hair
            Column {
                anchors.fill: parent; anchors.margins: 32; spacing: 16
                Overline { text: autotuneOverlay.finished ? "PID AUTOTUNE · DONE" : "PID AUTOTUNE · RUNNING" }
                Text { width: parent.width; wrapMode: Text.WordWrap
                       text: "Relay autotune of the thermoblock — keep the machine undisturbed until it finishes."
                       color: Theme.dim; font.family: Theme.archivo; font.pixelSize: 14 }
                Rectangle {
                    width: parent.width; height: 240; radius: 6; color: Qt.rgba(1,1,1,0.02)
                    border.width: 1; border.color: Theme.hair; clip: true
                    Flickable {
                        id: logFlick; anchors.fill: parent; anchors.margins: 12
                        contentHeight: logTxt.height; boundsBehavior: Flickable.StopAtBounds
                        Text { id: logTxt; width: parent.width; text: autotuneOverlay.logText
                               color: Theme.dim; font.family: Theme.mono; font.pixelSize: 11; wrapMode: Text.WrapAnywhere }
                    }
                }
                PButton {
                    width: parent.width
                    text: autotuneOverlay.finished ? "CLOSE" : "STOP"
                    variant: autotuneOverlay.finished ? "primary" : "alert"
                    onClicked: { if (!autotuneOverlay.finished) controller.stopAutotune(); autotuneOverlay.shown = false }
                }
            }
        }
    }
}
