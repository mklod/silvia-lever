import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import CoffeeController 1.0

import "controls"

ApplicationWindow {
    id: window
    width: 1920/4*2
    height: 1080/4*2

    // Add these properties after the window title to center the window
    Component.onCompleted: {
        x = Screen.width / 2 - width / 2
        y = Screen.height / 2 - height / 2
    }

    visible: true
    color: "#2c3e50"
    title: "Silvia Coffee Controller"
    
    property string currentScreen: "home"

    // Dual temperature readings from new hardware
    property real brewTempActual: 25.0    // Thermoblock PT1000
    property real steamTempActual: 25.0   // Steam boiler PT1000

    property real currentPressure: 0.0
    property real currentWeight: 0.0
    property real currentPumpPower: 0.0
    property bool valvePumpEnergised: false        // V1: false=thermoblock, true=boiler
    property bool valveThermoblockEnergised: false // V2: false=drain, true=portafilter
    property string currentState: "IDLE"
    property string brewTime: "00:00"
    property bool steamActive: false
    property bool flushActive: false
    property bool scalesSettled: false
    property bool scalesTared: false
    property real brewTargetTemp: 93.0
    property real steamTargetTemp: 130.0
    
    CoffeeController {
        id: controller
        
        onBrewTempChanged:   function(temp)  { window.brewTempActual  = temp  }
        onSteamTempChanged:  function(temp)  { window.steamTempActual = temp  }
        onPressureChanged:   function(press) { window.currentPressure = press }
        onWeightChanged:     function(wt)    {
            // Guard against Infinity/NaN from firmware when cal factor is bad
            if (isFinite(wt)) {
                window.currentWeight = wt
            } else {
                window.currentWeight = 0
            }
        }
        onPumpPowerChanged:  function(power) { window.currentPumpPower = power }
        onValvePumpChanged:        function(on) { window.valvePumpEnergised = on }
        onValveThermoblockChanged: function(on) { window.valveThermoblockEnergised = on }
        onStateChanged:      function(st)    { window.currentState    = st    }
        onBrewTimeChanged:   function(time)  { window.brewTime        = time  }
        
        onErrorOccurred: function(error) {
            errorDialog.text = error
            errorDialog.open()
        }
        
        onWarningIssued: function(warning) {
            warningDialog.text = warning
            warningDialog.open()
        }
        
        onConnectionStatusChanged: function(connected) {
            connectionStatus.connected = connected
        }
        
        onScalesSettledChanged: function(settled) {
            window.scalesSettled = settled
        }
        
        onScalesTaredChanged: function(tared) {
            window.scalesTared = tared
        }
        
        onTargetTemperaturesChanged: function(brewTemp, steamTemp) {
            window.brewTargetTemp = brewTemp
            window.steamTargetTemp = steamTemp
        }
    }
    
    StackView {
        id: stackView
        anchors.fill: parent
        initialItem: homeScreen
    }

    // Persistent debug row — bottom, all live sensor values + valve states.
    // Visible on all screens (window-level), high z so it floats above content.
    // Each field is fixed-width with right-justified numbers so values don't
    // shift position when digit count or sign changes ("0.00" → "-0.10").
    RowLayout {
        id: debugRow
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottomMargin: 12
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        z: 1000
        spacing: 0

        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            color: "#ffffff"
            font.pixelSize: 14
            font.family: "Consolas"
            text: "SCALE: " + (isFinite(window.currentWeight)
                                ? (window.currentWeight >= 0 ? " " : "") + window.currentWeight.toFixed(2) + " g"
                                : "—")
        }
        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            color: "#ffffff"
            font.pixelSize: 14
            font.family: "Consolas"
            text: "PRESS: " + (isFinite(window.currentPressure)
                                ? (window.currentPressure >= 0 ? " " : "") + window.currentPressure.toFixed(2) + " bar"
                                : "—")
        }
        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            color: "#ffffff"
            font.pixelSize: 14
            font.family: "Consolas"
            text: {
                var p = window.currentPumpPower.toFixed(0)
                while (p.length < 3) p = " " + p
                return "PUMP: " + p + "%"
            }
        }
        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            color: "#ffffff"
            font.pixelSize: 14
            font.family: "Consolas"
            text: "V1: " + (window.valvePumpEnergised ? "boiler     " : "thermoblock")
        }
        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            color: "#ffffff"
            font.pixelSize: 14
            font.family: "Consolas"
            text: "V2: " + (window.valveThermoblockEnergised ? "portafilter" : "drain      ")
        }
    }

    // Connection Status — top-right of home screen, plain white text.
    // Hidden on other screens (only meaningful at startup glance).
    Text {
        id: connectionStatus
        property bool connected: false

        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 12
        text: connectionStatus.connected ? "CONNECTED" : "DISCONNECTED"
        color: "#ffffff"
        font.pixelSize: 14
        font.family: "Consolas"
        visible: stackView.depth <= 1
        z: 1000
    }

    // Emergency Stop — invisible bottom-right tap area, 144×144.
    // Tap → triggers emergency stop and shows toast.
    MouseArea {
        id: emergencyStopBtn
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        width: 144
        height: 144
        z: 1001
        onClicked: {
            controller.emergencyStop()
            toast.show("EMERGENCY STOP")
        }
    }

    // Exit app — invisible top-right tap area, 144×144.
    // Tap → quit (used to leave fullscreen on RPi touchscreen).
    MouseArea {
        id: exitAppBtn
        anchors.top: parent.top
        anchors.right: parent.right
        width: 144
        height: 144
        z: 1001
        onClicked: Qt.quit()
    }

    // Toast — transient banner used for E-stop and other quick notifications.
    // Top-center, fades out after 2.5s.
    Rectangle {
        id: toast
        property string message: ""

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 80
        width: toastText.implicitWidth + 40
        height: 52
        color: "#e74c3c"
        radius: 4
        opacity: 0
        z: 2000

        Behavior on opacity { NumberAnimation { duration: 250 } }

        Text {
            id: toastText
            anchors.centerIn: parent
            text: toast.message
            color: "#ffffff"
            font { pixelSize: 18; bold: true }
        }

        Timer {
            id: toastTimer
            interval: 2500
            onTriggered: toast.opacity = 0
        }

        function show(msg) {
            message = msg
            opacity = 1.0
            toastTimer.restart()
        }
    }
    
    // Error Dialog
    Dialog {
        id: errorDialog
        property alias text: errorText.text
        
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 400)
        height: 200
        modal: true
        
        Rectangle {
            anchors.fill: parent
            color: "#2c3e50"
            radius: 10
            border.color: "#e74c3c"
            border.width: 2
            
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                
                Text {
                    text: "ERROR"
                    color: "#e74c3c"
                    font.pixelSize: 18
                    font.bold: true
                    Layout.alignment: Qt.AlignHCenter
                }
                
                Text {
                    id: errorText
                    color: "white"
                    font.pixelSize: 14
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignHCenter
                }
                
                Button {
                    text: "OK"
                    Material.background: "#e74c3c"
                    Layout.alignment: Qt.AlignHCenter
                    onClicked: errorDialog.close()
                }
            }
        }
    }
    
    // Warning Dialog
    Dialog {
        id: warningDialog
        property alias text: warningText.text
        
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 400)
        height: 200
        modal: true
        
        Rectangle {
            anchors.fill: parent
            color: "#2c3e50"
            radius: 10
            border.color: "#f39c12"
            border.width: 2
            
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                
                Text {
                    text: "WARNING"
                    color: "#f39c12"
                    font.pixelSize: 18
                    font.bold: true
                    Layout.alignment: Qt.AlignHCenter
                }
                
                Text {
                    id: warningText
                    color: "white"
                    font.pixelSize: 14
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignHCenter
                }
                
                Button {
                    text: "OK"
                    Material.background: "#f39c12"
                    Layout.alignment: Qt.AlignHCenter
                    onClicked: warningDialog.close()
                }
            }
        }
    }
    
    // Home Screen
    Component {
        id: homeScreen
        
        Rectangle {
            //color: "#2c3e50"
            color: "#101318"
                            
                Image {
                    id: runcilio_logo
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 30
                    source: "svgs/logo.svg"
                    //fillMode: Image.PreserveAspectFit
                    smooth: true
                }

                
                RowLayout{
                    
                    spacing: 100
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: runcilio_logo.bottom
                    anchors.bottom: parent.bottom
                    width: Math.min(800, parent.width*0.9)

                    ColumnLayout {

                        Layout.leftMargin: 30
                        Layout.alignment: Qt.AlignLeft

                        spacing: 10
                        
                        Button {
                            text: qsTr("BREW")

                            contentItem: Text {
                                text: parent.text
                                font.pixelSize: 28
                                opacity: enabled ? 1.0 : 0.3
                                color: "#ffffff"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                            }

                            background: Rectangle {
                                implicitWidth: 190
                                implicitHeight: 58
                                opacity: enabled ? 1 : 0.3
                                color: parent.down ? Qt.rgba(1,1,1,0.15) : "transparent"
                                border.color: "#ffffff"
                                border.width: 1
                                radius: 12
                            }

                            enabled: connectionStatus.connected
                            onClicked: {
                                window.brewTime = "00:00"
                                controller.startBrew()
                                stackView.push(brewScreen)
                            }
                        }
                        
                        // ── STEAM toggle button ─────────────────────────────
                        // Same toggle behaviour and styling as FLUSH:
                        // tap to start, tap again to stop. Active = depressed.
                        Rectangle {
                            id: steamBtn
                            Layout.preferredWidth: 190
                            Layout.preferredHeight: 58
                            radius: 12

                            color: window.steamActive
                                   ? "#ffffff"
                                   : (steamArea.pressed ? Qt.rgba(1,1,1,0.15) : "transparent")
                            border.color: "#ffffff"
                            border.width: 1
                            opacity: connectionStatus.connected ? 1.0 : 0.3

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 1
                                color: "transparent"
                                border.color: window.steamActive ? Qt.rgba(0,0,0,0.25) : "transparent"
                                border.width: 1
                                radius: parent.radius - 1
                                visible: window.steamActive
                            }

                            Text {
                                anchors.centerIn: parent
                                text: window.steamActive ? "STEAMING" : "STEAM"
                                font.pixelSize: window.steamActive ? 22 : 28
                                font.bold: window.steamActive
                                color: window.steamActive ? "#000000" : "#ffffff"
                            }

                            MouseArea {
                                id: steamArea
                                anchors.fill: parent
                                enabled: connectionStatus.connected
                                onClicked: {
                                    if (window.steamActive) {
                                        window.steamActive = false
                                        controller.stopSteam()
                                    } else {
                                        window.steamActive = true
                                        controller.startSteam()
                                    }
                                }
                            }
                        }
                        
                        // ── FLUSH toggle button ─────────────────────────────
                        // Single button: tap to start flush, tap again to stop.
                        // Active state = depressed look (filled white bg, dark text).
                        Rectangle {
                            id: flushBtn
                            Layout.preferredWidth: 190
                            Layout.preferredHeight: 58
                            radius: 12

                            // Visual states:
                            // - inactive + idle    → transparent fill, white outline, white text
                            // - inactive + pressed → faint white fill (touch feedback)
                            // - active             → solid white fill, dark text (depressed look)
                            color: window.flushActive
                                   ? "#ffffff"
                                   : (flushArea.pressed ? Qt.rgba(1,1,1,0.15) : "transparent")
                            border.color: "#ffffff"
                            border.width: 1
                            opacity: connectionStatus.connected ? 1.0 : 0.3

                            // Subtle inner shadow when active for neumorphic depressed feel
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 1
                                color: "transparent"
                                border.color: window.flushActive ? Qt.rgba(0,0,0,0.25) : "transparent"
                                border.width: 1
                                radius: parent.radius - 1
                                visible: window.flushActive
                            }

                            Text {
                                anchors.centerIn: parent
                                text: window.flushActive ? "FLUSHING" : "FLUSH"
                                font.pixelSize: window.flushActive ? 22 : 28
                                font.bold: window.flushActive
                                color: window.flushActive ? "#000000" : "#ffffff"
                            }

                            MouseArea {
                                id: flushArea
                                anchors.fill: parent
                                enabled: connectionStatus.connected
                                onClicked: {
                                    if (window.flushActive) {
                                        window.flushActive = false
                                        controller.stopFlush()
                                    } else {
                                        window.flushActive = true
                                        controller.startFlush()
                                    }
                                }
                            }
                        }
                    }

                    CircularSlider {
                        id: tempGauge
                        Layout.alignment: Qt.AlignRight
                        Layout.rightMargin: 30
                        width: 120
                        height: 120

                        property real displayTemp: window.steamActive ? window.steamTempActual : window.brewTempActual
                        property real displayTarget: window.steamActive ? window.steamTargetTemp : window.brewTargetTemp

                        minValue: 0
                        maxValue: Math.max(displayTemp, displayTarget)
                        value: displayTemp
                        interactive: false
                        progressColor: "#2290e7"
                        trackColor: "#34495e"

                        startAngle: 30.0
                        endAngle: 330
                        rotation: 180

                        Text {
                            anchors.centerIn: parent
                            text: tempGauge.displayTemp.toFixed(1) + "°C"
                            color: tempGauge.displayTemp > tempGauge.displayTarget ? "#ff0000" : "white"
                            font.pixelSize: 24
                            font.bold: true
                            rotation: 180
                        }
                        MouseArea {
                            id: mouseArea
                            anchors.fill: parent
                            onClicked: {
                                stackView.push(settingsScreen)
                            }
                            // Optional: Visual feedback on hover
                            onEntered: tempGauge.scale = 1.05
                            onExited: tempGauge.scale = 1.0
                        }
                    }
                }

            // ── Steam priming overlay ──────────────────────────────────────
            // Visible while firmware is in STATE_PRIMING_STEAM.
            Rectangle {
                anchors.fill: parent
                z: 10
                visible: window.currentState === "PRIMING_STEAM"
                color: Qt.rgba(0, 0, 0, 0.80)

                Rectangle {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 40, 420)
                    height: steamPrimingCol.implicitHeight + 56
                    color: Qt.rgba(1, 1, 1, 0.08)
                    radius: 18
                    border.color: "#e74c3c"
                    border.width: 2

                    ColumnLayout {
                        id: steamPrimingCol
                        anchors.centerIn: parent
                        width: parent.width - 56
                        spacing: 18

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "PRIMING BOILER"
                            color: "#e74c3c"
                            font { pixelSize: 22; bold: true }
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignHCenter
                            text: "Water is pumping into the steam boiler.\n" +
                                  "Watch the boiler overflow outlet for the first drops of water.\n" +
                                  "Press CONFIRM once you see overflow."
                            color: "#dddddd"
                            font.pixelSize: 15
                            wrapMode: Text.WordWrap
                            horizontalAlignment: Text.AlignHCenter
                            lineHeight: 1.4
                        }

                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            width: 12; height: 12; radius: 6
                            color: "#e74c3c"
                            SequentialAnimation on opacity {
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.2; duration: 600 }
                                NumberAnimation { to: 1.0; duration: 600 }
                            }
                        }

                        // CONFIRM button
                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            width: 280; height: 68
                            radius: 16
                            color: steamPrimeConfirmArea.pressed ? "#922b21" : "#e74c3c"

                            Text {
                                anchors.centerIn: parent
                                text: "CONFIRM — OVERFLOW SEEN"
                                color: "white"
                                font { pixelSize: 17; bold: true }
                            }
                            MouseArea {
                                id: steamPrimeConfirmArea
                                anchors.fill: parent
                                onClicked: controller.primeDone()
                            }
                        }

                        // CANCEL button
                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            width: 160; height: 52
                            radius: 12
                            color: steamPrimeCancelArea.pressed ? "#555555" : "#7f8c8d"

                            Text {
                                anchors.centerIn: parent
                                text: "CANCEL"
                                color: "white"
                                font { pixelSize: 15; bold: true }
                            }
                            MouseArea {
                                id: steamPrimeCancelArea
                                anchors.fill: parent
                                onClicked: {
                                    window.steamActive = false
                                    controller.stopSteam()
                                }
                            }
                        }
                    }
                }
            }
            // ── End steam priming overlay ──────────────────────────────────
        }
    }

    // Brew Screen
    Component {
        id: brewScreen

        Rectangle {
            color: "#000000"

            // ── Priming overlay ────────────────────────────────────────────
            // Visible while firmware is in STATE_PRIMING_BREW.
            // Pump and valve are already running; user watches for overflow
            // then taps CONFIRM to stop the pump and begin heating.
            Rectangle {
                anchors.fill: parent
                z: 10
                visible: window.currentState === "PRIMING_BREW"
                color: Qt.rgba(0, 0, 0, 0.80)

                Rectangle {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 40, 420)
                    height: brewPrimingCol.implicitHeight + 56
                    color: Qt.rgba(1, 1, 1, 0.08)
                    radius: 18
                    border.color: "#3498db"
                    border.width: 2

                    ColumnLayout {
                        id: brewPrimingCol
                        anchors.centerIn: parent
                        width: parent.width - 56
                        spacing: 18

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "PRIMING THERMOBLOCK"
                            color: "#3498db"
                            font { pixelSize: 22; bold: true }
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignHCenter
                            text: "Water is pumping through the thermoblock.\n" +
                                  "Watch the group head outlet for the first drops of water.\n" +
                                  "Press CONFIRM once you see overflow."
                            color: "#dddddd"
                            font.pixelSize: 15
                            wrapMode: Text.WordWrap
                            horizontalAlignment: Text.AlignHCenter
                            lineHeight: 1.4
                        }

                        // Pulsing indicator
                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            width: 12; height: 12; radius: 6
                            color: "#3498db"
                            SequentialAnimation on opacity {
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.2; duration: 600 }
                                NumberAnimation { to: 1.0; duration: 600 }
                            }
                        }

                        // CONFIRM button
                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            width: 280; height: 68
                            radius: 16
                            color: brewPrimeConfirmArea.pressed ? "#1a6b38" : "#27ae60"

                            Text {
                                anchors.centerIn: parent
                                text: "CONFIRM — OVERFLOW SEEN"
                                color: "white"
                                font { pixelSize: 17; bold: true }
                            }
                            MouseArea {
                                id: brewPrimeConfirmArea
                                anchors.fill: parent
                                onClicked: controller.primeDone()
                            }
                        }

                        // CANCEL button
                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            width: 160; height: 52
                            radius: 12
                            color: brewPrimeCancelArea.pressed ? "#555555" : "#7f8c8d"

                            Text {
                                anchors.centerIn: parent
                                text: "CANCEL"
                                color: "white"
                                font { pixelSize: 15; bold: true }
                            }
                            MouseArea {
                                id: brewPrimeCancelArea
                                anchors.fill: parent
                                onClicked: {
                                    controller.stopBrew()
                                    stackView.pop()
                                }
                            }
                        }
                    }
                }
            }
            // ── End priming overlay ────────────────────────────────────────

            // ── Back arrow — top-left, matches settings screen style ─────
            Item {
                anchors.top: parent.top
                anchors.left: parent.left
                width: 72
                height: 72
                z: 50

                Text {
                    anchors.centerIn: parent
                    text: "←"
                    color: "#ffffff"
                    font.pixelSize: 34
                    font.bold: true
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        stackView.pop()
                        controller.stopBrew()
                    }
                }
            }

            // ── Huge middle tap area: start brew when ready, stop when brewing ──
            // Covers most of screen. Excludes top 90px (back arrow), bottom 150px
            // (debug row + E-stop), 80px each side.
            MouseArea {
                id: brewStartTapArea
                anchors.top: parent.top
                anchors.topMargin: 90
                anchors.left: parent.left
                anchors.leftMargin: 80
                anchors.right: parent.right
                anchors.rightMargin: 80
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 150
                enabled: connectionStatus.connected && (
                         (window.currentState === "HEATING_BREW" && window.scalesSettled) ||
                         window.currentState === "BREWING")
                z: 5
                onClicked: {
                    if (window.currentState === "BREWING") {
                        controller.stopBrew()
                    } else {
                        // Start brew: clear charts, begin
                        coffeeChart.dataPoints   = []
                        pressureChart.dataPoints = []
                        coffeeChart.startTime    = null
                        pressureChart.startTime  = null
                        coffeeChart.maxTime      = 30
                        pressureChart.maxTime    = 30
                        coffeeChart.requestPaint()
                        pressureChart.requestPaint()
                        controller.beginBrew()
                    }
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.topMargin: 20
                anchors.leftMargin: 40
                anchors.rightMargin: 40
                anchors.bottomMargin: 60
                spacing: 20

                // Top-info row — transparent, white text.
                // Padded 80px on each side so Mass/Time/Thermoblock don't
                // overlap the back arrow (top-left) or E-stop (top-right).
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 80

                    // Anchor-based layout: Time is locked to window horizontal
                    // center; Mass aligned to far left of content area;
                    // Thermoblock to far right. Symmetric and predictable.
                    Item {
                        anchors.fill: parent

                        // ── Mass — left column ─────────────────────────
                        ColumnLayout {
                            anchors.left: parent.left
                            anchors.leftMargin: 80
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "Mass"
                                color: "#888888"
                                font.pixelSize: 13
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                horizontalAlignment: Text.AlignHCenter
                                text: {
                                    if (!isFinite(window.currentWeight)) return "—"
                                    var n = window.currentWeight
                                    var sign = (n < 0 ? "−" : " ")
                                    return sign + Math.abs(n).toFixed(1) + " g"
                                }
                                color: "#ffffff"
                                font { pixelSize: 48; bold: true; family: "Consolas" }
                            }
                        }

                        // ── Time — exactly centered in window ──────────
                        // (the window centers on stackView; this Item fills
                        // its parent, which fills the brew screen, so the
                        // horizontalCenter aligns with window center)
                        ColumnLayout {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "Time"
                                color: "#888888"
                                font.pixelSize: 13
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                horizontalAlignment: Text.AlignHCenter
                                text: window.brewTime
                                color: "#ffffff"
                                font { pixelSize: 48; bold: true; family: "Consolas" }
                            }
                        }

                        // ── Thermoblock temp — right column ─────────────
                        ColumnLayout {
                            anchors.right: parent.right
                            anchors.rightMargin: 80
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "Thermoblock"
                                color: "#888888"
                                font.pixelSize: 13
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                horizontalAlignment: Text.AlignHCenter
                                text: window.brewTempActual.toFixed(1) + "°C"
                                color: "#ffffff"
                                font { pixelSize: 48; bold: true; family: "Consolas" }
                            }
                        }
                    }
                }
                
                // Charts row
                ColumnLayout {
                    Layout.fillWidth: true
                    //Layout.fillHeight: true
                    spacing: 20
                    
                    // Coffee extraction chart
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: "#1a1a1a"
                        radius: 5
                        
                        Item {
                            anchors.fill: parent
                            anchors.margins: 5
                            
                            Text {
                                text: "Coffee (g)"
                                color: "white"
                                font.pixelSize: 12
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.leftMargin: 4
                                anchors.topMargin: 4
                            }
                            
                            Canvas {
                                id: coffeeChart
                                width: parent.width
                                height: parent.height - 1.9

                                property var dataPoints: []
                                property real maxWeight: 100
                                property real maxTime: 30   // Start at 30 s; grows, never shrinks mid-brew
                                property var startTime: null

                                function updateScale() {
                                    if (dataPoints.length > 0) {
                                        var maxW = 100
                                        var maxT = maxTime  // Never shrink below current axis
                                        for (var i = 0; i < dataPoints.length; i++) {
                                            if (dataPoints[i].weight > maxW) maxW = dataPoints[i].weight
                                            if (dataPoints[i].time   > maxT) maxT = dataPoints[i].time
                                        }
                                        maxWeight = Math.max(maxW * 1.1, 1)
                                        maxTime   = Math.max(maxT * 1.1, 30)
                                    }
                                }
                                
                                onPaint: {
                                    var ctx = getContext("2d")
                                    ctx.clearRect(0, 0, width, height)
                                    
                                    // Draw grid and labels
                                    ctx.strokeStyle = "#7f8c8d"
                                    ctx.lineWidth = 0.5
                                    ctx.fillStyle = "#bdc3c7"
                                    ctx.font = "10px Arial"
                                    for (var i = 0; i <= 5; i++) {
                                        var y = (height / 5) * i
                                        ctx.beginPath()
                                        ctx.moveTo(0, y)
                                        ctx.lineTo(width, y)
                                        ctx.stroke()
                                        var labelValue = (maxWeight * (5 - i) / 5).toFixed(1) + "g"
                                        var textWidth_1 = ctx.measureText(labelValue).width
                                        ctx.fillText(labelValue, width - textWidth_1 -2, y - 2)
                                    }
                                    for (var j = 0; j <= 4; j++) {
                                        var x = (width / 4) * j
                                        var timeLabel = (maxTime * j / 4).toFixed(0)
                                        ctx.fillText(timeLabel + "s", x + 2, height - 5)
                                    }
                                    
                                    // Draw current weight value
                                    ctx.fillStyle = "white"
                                    ctx.font = "20px Arial"
                                    var weightText = window.currentWeight.toFixed(1) + " g"
                                    var textWidth = ctx.measureText(weightText).width
                                    // Position value clear of y-axis labels,
                                    // aligned vertically with the chart title
                                    ctx.fillText(weightText, width - textWidth - 60, 30)
                                    
                                    // Draw data line
                                    if (dataPoints.length > 0) {
                                        ctx.strokeStyle = "#00bcd4"  // cyan
                                        ctx.lineWidth = 2
                                        ctx.beginPath()
                                        
                                        for (var j = 0; j < dataPoints.length; j++) {
                                            var x = (dataPoints[j].time / maxTime) * width
                                            var y = height - (dataPoints[j].weight / maxWeight) * height
                                            
                                            if (j === 0) {
                                                ctx.moveTo(x, y)
                                            } else {
                                                ctx.lineTo(x, y)
                                            }
                                        }
                                        ctx.stroke()
                                        
                                        // Draw current point
                                        if (dataPoints.length > 0) {
                                            var lastPoint = dataPoints[dataPoints.length - 1]
                                            var lastX = (lastPoint.time / maxTime) * width
                                            var lastY = height - (lastPoint.weight / maxWeight) * height
                                            ctx.fillStyle = "#00bcd4"  // cyan dot
                                            ctx.beginPath()
                                            ctx.arc(lastX, lastY, 3, 0, 2 * Math.PI)
                                            ctx.fill()
                                        }
                                    }
                                }
                                
                                Timer {
                                    interval: 500
                                    running: window.currentState === "BREWING" && window.scalesTared
                                    repeat: true
                                    onTriggered: {
                                        var currentTime = Date.now()
                                        if (!coffeeChart.startTime) coffeeChart.startTime = currentTime
                                        var elapsedSeconds = (currentTime - coffeeChart.startTime) / 1000
                                        coffeeChart.dataPoints.push({time: elapsedSeconds, weight: window.currentWeight})
                                        coffeeChart.updateScale()
                                        coffeeChart.requestPaint()
                                    }
                                }
                                
                                Connections {
                                    target: window
                                    function onCurrentWeightChanged() {
                                        coffeeChart.requestPaint()
                                    }
                                }
                            }
                        }
                    }
                    
                    // Pressure chart
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: "#1a1a1a"
                        radius: 5
                        
                        Item {
                            anchors.fill: parent
                            anchors.margins: 5
                            
                            Text {
                                text: "Pressure (bar)"
                                color: "white"
                                font.pixelSize: 12
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.leftMargin: 4
                                anchors.topMargin: 4
                            }
                            
                            Canvas {
                                id: pressureChart
                                width: parent.width
                                height: parent.height - 1.9

                                property var dataPoints: []
                                property real maxPressure: 16
                                property real maxTime: 30   // Start at 30 s; grows, never shrinks mid-brew
                                property var startTime: null

                                function updateScale() {
                                    if (dataPoints.length > 0) {
                                        var maxP = 16
                                        var maxT = maxTime  // Never shrink below current axis
                                        for (var i = 0; i < dataPoints.length; i++) {
                                            if (dataPoints[i].pressure > maxP) maxP = dataPoints[i].pressure
                                            if (dataPoints[i].time     > maxT) maxT = dataPoints[i].time
                                        }
                                        maxPressure = Math.max(maxP * 1.1, 1)
                                        maxTime     = Math.max(maxT * 1.1, 30)
                                    }
                                }
                                
                                onPaint: {
                                    var ctx = getContext("2d")
                                    ctx.clearRect(0, 0, width, height)
                                    
                                    // Draw grid and labels
                                    ctx.strokeStyle = "#7f8c8d"
                                    ctx.lineWidth = 0.5
                                    ctx.fillStyle = "#bdc3c7"
                                    ctx.font = "10px Arial"
                                    for (var i = 0; i <= 5; i++) {
                                        var y = (height / 5) * i
                                        ctx.beginPath()
                                        ctx.moveTo(0, y)
                                        ctx.lineTo(width, y)
                                        ctx.stroke()
                                        var labelValue = (maxPressure * (5 - i) / 5).toFixed(1)+  "bar"
                                        var textWidth_2 = ctx.measureText(labelValue).width
                                        ctx.fillText(labelValue, width - textWidth_2 - 2, y - 2)
                                    }
                                    for (var j = 0; j <= 4; j++) {
                                        var x = (width / 4) * j
                                        var timeLabel = (maxTime * j / 4).toFixed(0)
                                        ctx.fillText(timeLabel + "s", x + 2, height - 5)
                                    }
                                    
                                    // Draw current pressure value
                                    ctx.fillStyle = "white"
                                    ctx.font = "20px Arial"
                                    var pressureText = window.currentPressure.toFixed(1) + " bar"
                                    var textWidth_ = ctx.measureText(pressureText).width
                                    // Position value clear of y-axis labels,
                                    // aligned vertically with the chart title
                                    ctx.fillText(pressureText, width - textWidth_ - 60, 30)
                                    
                                    // Draw data line
                                    if (dataPoints.length > 0) {
                                        ctx.strokeStyle = "#9b59b6"  // purple
                                        ctx.lineWidth = 2
                                        ctx.beginPath()
                                        
                                        for (var j = 0; j < dataPoints.length; j++) {
                                            var x = (dataPoints[j].time / maxTime) * width
                                            var y = height - (dataPoints[j].pressure / maxPressure) * height
                                            
                                            if (j === 0) {
                                                ctx.moveTo(x, y)
                                            } else {
                                                ctx.lineTo(x, y)
                                            }
                                        }
                                        ctx.stroke()
                                        
                                        // Draw current point
                                        if (dataPoints.length > 0) {
                                            var lastPoint = dataPoints[dataPoints.length - 1]
                                            var lastX = (lastPoint.time / maxTime) * width
                                            var lastY = height - (lastPoint.pressure / maxPressure) * height
                                            ctx.fillStyle = "#9b59b6"  // purple dot
                                            ctx.beginPath()
                                            ctx.arc(lastX, lastY, 3, 0, 2 * Math.PI)
                                            ctx.fill()
                                        }
                                    }
                                }
                                
                                Timer {
                                    interval: 500
                                    running: window.currentState === "BREWING" && window.scalesTared
                                    repeat: true
                                    onTriggered: {
                                        var currentTime = Date.now()
                                        if (!pressureChart.startTime) pressureChart.startTime = currentTime
                                        var elapsedSeconds = (currentTime - pressureChart.startTime) / 1000
                                        pressureChart.dataPoints.push({time: elapsedSeconds, pressure: window.currentPressure})
                                        pressureChart.updateScale()
                                        pressureChart.requestPaint()
                                    }
                                }
                                
                                Connections {
                                    target: window
                                    function onCurrentPressureChanged() {
                                        pressureChart.requestPaint()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    // Steam Screen
    Component {
        id: steamScreen
        
        Rectangle {
            color: "#2c3e50"
            
            ColumnLayout {
                anchors.centerIn: parent
                spacing: 20
                
                Text {
                    text: "Steam Mode"
                    color: "white"
                    font.pixelSize: 24
                    Layout.alignment: Qt.AlignHCenter
                }
                
                Text {
                    text: window.steamTempActual.toFixed(1) + "°C"
                    color: "white"
                    font.pixelSize: 20
                    Layout.alignment: Qt.AlignHCenter
                }
                
                Text {
                    text: window.currentState
                    color: "white"
                    font.pixelSize: 16
                    Layout.alignment: Qt.AlignHCenter
                }
                
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 20
                    
                    Text {
                        text: "Heating to " + window.steamTargetTemp.toFixed(0) + "°C..."
                        color: "#f39c12"
                        font.pixelSize: 14
                        Layout.alignment: Qt.AlignHCenter
                        visible: window.currentState === "HEATING_STEAM"
                    }
                    
                    Text {
                        text: "Ready for steaming! Target reached."
                        color: "#27ae60"
                        font.pixelSize: 14
                        Layout.alignment: Qt.AlignHCenter
                        visible: window.currentState === "STEAMING"
                    }
                    
                    Button {
                        text: "BEGIN STEAM"
                        Material.background: "#27ae60"
                        enabled: window.currentState === "HEATING_STEAM" && window.steamTempActual >= window.steamTargetTemp - 2.0
                        visible: window.currentState === "HEATING_STEAM" && window.steamTempActual >= window.steamTargetTemp - 2.0
                        onClicked: controller.beginSteam()
                    }
                    
                    Button {
                        text: "STOP"
                        Material.background: "#e74c3c"
                        onClicked: {
                            window.steamActive = false
                            controller.stopSteam()
                            stackView.pop()
                        }
                    }
                    
                    Button {
                        text: "BACK"
                        Material.background: "#95a5a6"
                        onClicked: stackView.pop()
                    }
                }
            }
        }
    }
    
    // Flush Screen
    Component {
        id: flushScreen
        
        Rectangle {
            color: "#2c3e50"
            
            ColumnLayout {
                anchors.centerIn: parent
                spacing: 20
                
                Text {
                    text: "Flush Mode"
                    color: "white"
                    font.pixelSize: 24
                    Layout.alignment: Qt.AlignHCenter
                }
                
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 20
                    
                    Text {
                        text: "Flushing in progress..."
                        color: "#f39c12"
                        font.pixelSize: 16
                        Layout.alignment: Qt.AlignHCenter
                    }
                    
                    Button {
                        text: "STOP"
                        Material.background: "#e74c3c"
                        onClicked: {
                            window.flushActive = false
                            controller.stopFlush()
                            stackView.pop()
                        }
                    }
                    
                    Button {
                        text: "BACK"
                        Material.background: "#95a5a6"
                        onClicked: stackView.pop()
                    }
                }
            }
        }
    }
    /*
    // Settings Screen
    Component {
        id: settingsScreen
        
        Rectangle {
            color: "#2c3e50"
            
            ColumnLayout {
                anchors.centerIn: parent
                spacing: 20
                
                Text {
                    text: "Temperature Settings"
                    color: "white"
                    font.pixelSize: 20
                    Layout.alignment: Qt.AlignHCenter
                }
                
                RowLayout {
                    Text {
                        text: "Brew Temp:"
                        color: "white"
                    }
                    SpinBox {
                        id: brewTempSpin
                        from: 60
                        to: 110
                        value: 93
                    }
                    Text {
                        text: "°C"
                        color: "white"
                    }
                }
                
                RowLayout {
                    Text {
                        text: "Steam Temp:"
                        color: "white"
                    }
                    SpinBox {
                        id: steamTempSpin
                        from: 110
                        to: 150
                        value: 130
                    }
                    Text {
                        text: "°C"
                        color: "white"
                    }
                }
                
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 20
                    
                    Button {
                        text: "SAVE"
                        Material.background: "#27ae60"
                        onClicked: {
                            controller.setTemperatures(brewTempSpin.value, steamTempSpin.value)
                            stackView.pop()
                        }
                    }
                    
                    Button {
                        text: "BACK"
                        Material.background: "#95a5a6"
                        onClicked: stackView.pop()
                    }
                }
            }
        }
    }
    */

    // Settings Screen ---------------------------------------------------------
    Component {
        id: settingsScreen

        Rectangle {
            color: "#000000"

            // ── Back arrow — top-left, no outline, large tap area ─────
            Item {
                id: backArrow
                anchors.top: parent.top
                anchors.left: parent.left
                width: 72
                height: 72
                z: 50

                Text {
                    anchors.centerIn: parent
                    text: "←"
                    color: "#ffffff"
                    font.pixelSize: 34
                    font.bold: true
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: stackView.pop()
                }
            }

            // Settings card — auto-saves on each +/- tap. No local state,
            // buttons operate directly on window.brewTargetTemp / steamTargetTemp
            // and push the new value to the controller immediately.
            Item {
                id: card
                anchors.top: parent.top
                anchors.topMargin: 90
                anchors.horizontalCenter: parent.horizontalCenter
                width:  Math.min(parent.width - 80, 440)
                height: settingsCol.implicitHeight

                function saveTemps() {
                    controller.setTemperatures(window.brewTargetTemp, window.steamTargetTemp)
                }

                ColumnLayout {
                    id: settingsCol
                    anchors.centerIn: parent
                    width: parent.width - 32
                    spacing: 20

                    // ── Header ──────────────────────────────────────────────
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "TEMPERATURE SETTINGS"
                        color: "#ffffff"
                        font { pixelSize: 18; bold: true }
                    }

                    // ── Brew temperature ─────────────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            text: "Brew Temp  (60 – 110°C)"
                            color: "#888888"
                            font.pixelSize: 12
                            Layout.alignment: Qt.AlignHCenter
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            // Decrement button — white outline
                            Rectangle {
                                width: 60; height: 60
                                radius: 2
                                color: brewMinusArea.pressed ? Qt.rgba(1,1,1,0.15) : "transparent"
                                border.color: "#ffffff"
                                border.width: 1
                                Text {
                                    anchors.centerIn: parent
                                    text: "−"
                                    font { pixelSize: 30; bold: true }
                                    color: "#ffffff"
                                }
                                MouseArea {
                                    id: brewMinusArea
                                    anchors.fill: parent
                                    onClicked: {
                                        window.brewTargetTemp = Math.max(60.0, Math.round(window.brewTargetTemp - 1))
                                        card.saveTemps()
                                    }
                                }
                            }

                            // Value display
                            Text {
                                Layout.fillWidth: true
                                text: window.brewTargetTemp.toFixed(1) + "°C"
                                color: "#ffffff"
                                font { pixelSize: 32; bold: true }
                                horizontalAlignment: Text.AlignHCenter
                            }

                            // Increment button
                            Rectangle {
                                width: 60; height: 60
                                radius: 2
                                color: brewPlusArea.pressed ? Qt.rgba(1,1,1,0.15) : "transparent"
                                border.color: "#ffffff"
                                border.width: 1
                                Text {
                                    anchors.centerIn: parent
                                    text: "+"
                                    font { pixelSize: 30; bold: true }
                                    color: "#ffffff"
                                }
                                MouseArea {
                                    id: brewPlusArea
                                    anchors.fill: parent
                                    onClicked: {
                                        window.brewTargetTemp = Math.min(110.0, Math.round(window.brewTargetTemp + 1))
                                        card.saveTemps()
                                    }
                                }
                            }
                        }
                    }

                    // ── Steam temperature ────────────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            text: "Steam Temp  (110 – 150°C)"
                            color: "#888888"
                            font.pixelSize: 12
                            Layout.alignment: Qt.AlignHCenter
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            Rectangle {
                                width: 60; height: 60
                                radius: 2
                                color: steamMinusArea.pressed ? Qt.rgba(1,1,1,0.15) : "transparent"
                                border.color: "#ffffff"
                                border.width: 1
                                Text {
                                    anchors.centerIn: parent
                                    text: "−"
                                    font { pixelSize: 30; bold: true }
                                    color: "#ffffff"
                                }
                                MouseArea {
                                    id: steamMinusArea
                                    anchors.fill: parent
                                    onClicked: {
                                        window.steamTargetTemp = Math.max(110.0, Math.round(window.steamTargetTemp - 1))
                                        card.saveTemps()
                                    }
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: window.steamTargetTemp.toFixed(1) + "°C"
                                color: "#ffffff"
                                font { pixelSize: 32; bold: true }
                                horizontalAlignment: Text.AlignHCenter
                            }

                            Rectangle {
                                width: 60; height: 60
                                radius: 2
                                color: steamPlusArea.pressed ? Qt.rgba(1,1,1,0.15) : "transparent"
                                border.color: "#ffffff"
                                border.width: 1
                                Text {
                                    anchors.centerIn: parent
                                    text: "+"
                                    font { pixelSize: 30; bold: true }
                                    color: "#ffffff"
                                }
                                MouseArea {
                                    id: steamPlusArea
                                    anchors.fill: parent
                                    onClicked: {
                                        window.steamTargetTemp = Math.min(150.0, Math.round(window.steamTargetTemp + 1))
                                        card.saveTemps()
                                    }
                                }
                            }
                        }
                    }

                    // ── SCALE section header ─────────────────────────────────
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 12
                        text: "SCALE"
                        color: "#ffffff"
                        font { pixelSize: 18; bold: true }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Rectangle {
                            Layout.fillWidth: true
                            height: 48
                            color: tareArea.pressed ? Qt.rgba(1,1,1,0.15) : "transparent"
                            border.color: "#ffffff"
                            border.width: 1
                            radius: 2
                            Text {
                                anchors.centerIn: parent
                                text: "TARE"
                                color: "#ffffff"
                                font.pixelSize: 14
                                font.bold: true
                            }
                            MouseArea {
                                id: tareArea
                                anchors.fill: parent
                                onClicked: controller.tareScales()
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 48
                            color: calArea.pressed ? Qt.rgba(1,1,1,0.15) : "transparent"
                            border.color: "#ffffff"
                            border.width: 1
                            radius: 2
                            Text {
                                anchors.centerIn: parent
                                text: "CAL"
                                color: "#ffffff"
                                font.pixelSize: 14
                                font.bold: true
                            }
                            MouseArea {
                                id: calArea
                                anchors.fill: parent
                                onClicked: calDialog.open()
                            }
                        }
                    }
                }
            }

        }
    }
    
    /*
    // Calibration Dialog
    Dialog {
        id: calDialog
        anchors.centerIn: parent
        width: 300
        height: 200
        modal: true
        
        Rectangle {
            anchors.fill: parent
            color: "#2c3e50"
            radius: 10
            
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 15
                
                Text {
                    text: "Scale Calibration"
                    color: "white"
                    font.pixelSize: 16
                    font.bold: true
                    Layout.alignment: Qt.AlignHCenter
                }
                
                Text {
                    text: "Place known weight on scale (grams):"
                    color: "white"
                    font.pixelSize: 12
                    Layout.alignment: Qt.AlignHCenter
                }
                
                SpinBox {
                    id: calWeightSpin
                    from: 1
                    to: 1000
                    value: 250
                    Layout.alignment: Qt.AlignHCenter
                }
                
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 10
                    
                    Button {
                        text: "CALIBRATE"
                        Material.background: "#27ae60"
                        onClicked: {
                            controller.calibrateScales(calWeightSpin.value)
                            calDialog.close()
                        }
                    }
                    
                    Button {
                        text: "CANCEL"
                        Material.background: "#7f8c8d"
                        onClicked: calDialog.close()
                    }
                }
            }
        }
    }*/
        // Calibration Dialog — black bg, white outlines, auto-tares on open.
    Dialog {
        id: calDialog
        anchors.centerIn: parent
        width: 440
        height: 340
        padding: 0
        modal: true

        onOpened: controller.tareScales()

        background: Rectangle {
            color: "#000000"
            border.color: "#ffffff"
            border.width: 1
            radius: 4
        }

        contentItem: Item {
            anchors.fill: parent

            // Close X button — top right
            Rectangle {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 10
                width: 32
                height: 32
                color: dlgCloseArea.pressed ? Qt.rgba(1,1,1,0.2) : "transparent"
                border.color: "#ffffff"
                border.width: 1
                radius: 2
                z: 2

                Text {
                    anchors.centerIn: parent
                    text: "✕"
                    color: "#ffffff"
                    font.pixelSize: 16
                    font.bold: true
                }

                MouseArea {
                    id: dlgCloseArea
                    anchors.fill: parent
                    onClicked: calDialog.close()
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.topMargin: 24
                anchors.leftMargin: 24
                anchors.rightMargin: 24
                anchors.bottomMargin: 20
                spacing: 14

                Text {
                    text: "SCALE CALIBRATION"
                    color: "#ffffff"
                    font.pixelSize: 18
                    font.bold: true
                    Layout.alignment: Qt.AlignHCenter
                }

                Text {
                    text: "Place calibration weight on scale, then press CALIBRATE"
                    color: "#888888"
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignHCenter
                }

                // Live weight display
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    Layout.preferredHeight: 76
                    color: "#000000"
                    radius: 2
                    border.color: "#ffffff"
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: (isFinite(window.currentWeight)
                                ? window.currentWeight.toFixed(1)
                                : "—") + " g"
                        color: "#ffffff"
                        font.pixelSize: 40
                        font.family: "Consolas"
                        font.bold: true
                    }
                }

                // Known weight input — custom -/+ controls for black theme
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 8

                    Text {
                        text: "Known weight (g):"
                        color: "#ffffff"
                        font.pixelSize: 14
                    }

                    // Minus button
                    Rectangle {
                        width: 40
                        height: 40
                        color: calMinusArea.pressed ? Qt.rgba(1,1,1,0.15) : "transparent"
                        border.color: "#ffffff"
                        border.width: 1
                        radius: 2
                        Text {
                            anchors.centerIn: parent
                            text: "−"
                            color: "#ffffff"
                            font { pixelSize: 22; bold: true }
                        }
                        MouseArea {
                            id: calMinusArea
                            anchors.fill: parent
                            onClicked: calWeightSpin.value = Math.max(1, calWeightSpin.value - calWeightSpin.stepSize)
                        }
                    }

                    // Value display (invisible SpinBox holds the actual value)
                    Item {
                        width: 80
                        height: 40
                        Text {
                            anchors.centerIn: parent
                            text: calWeightSpin.value + " g"
                            color: "#ffffff"
                            font { pixelSize: 20; bold: true }
                        }
                        SpinBox {
                            id: calWeightSpin
                            visible: false
                            from: 1
                            to: 5000
                            value: 100
                            stepSize: 50
                        }
                    }

                    // Plus button
                    Rectangle {
                        width: 40
                        height: 40
                        color: calPlusArea.pressed ? Qt.rgba(1,1,1,0.15) : "transparent"
                        border.color: "#ffffff"
                        border.width: 1
                        radius: 2
                        Text {
                            anchors.centerIn: parent
                            text: "+"
                            color: "#ffffff"
                            font { pixelSize: 22; bold: true }
                        }
                        MouseArea {
                            id: calPlusArea
                            anchors.fill: parent
                            onClicked: calWeightSpin.value = Math.min(5000, calWeightSpin.value + calWeightSpin.stepSize)
                        }
                    }
                }

                // Calibrate button — white outline
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 220
                    Layout.preferredHeight: 48
                    color: calBtnArea.pressed ? Qt.rgba(1,1,1,0.15) : "transparent"
                    border.color: "#ffffff"
                    border.width: 2
                    radius: 2

                    Text {
                        anchors.centerIn: parent
                        text: "CALIBRATE"
                        color: "#ffffff"
                        font.pixelSize: 16
                        font.bold: true
                    }

                    MouseArea {
                        id: calBtnArea
                        anchors.fill: parent
                        onClicked: {
                            controller.calibrateScales(calWeightSpin.value)
                            calDialog.close()
                        }
                    }
                }
            }
        }
    }
}
