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
        onWeightChanged:     function(wt)    { window.currentWeight   = wt    }
        onPumpPowerChanged:  function(power) { window.currentPumpPower = power }
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
    
    // Connection Status Indicator
    Rectangle {
        id: connectionStatus
        property bool connected: false
        //property bool connected: true
        
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.margins: 10
        width: 100
        height: 30
        radius: 15
        color: connected ? "#27ae60" : "#e74c3c"
        
        Text {
            anchors.centerIn: parent
            text: connectionStatus.connected ? "CONNECTED" : "DISCONNECTED"
            color: "white"
            font.pixelSize: 10
            font.bold: true
        }
    }
    
    // Emergency Stop Button
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.right: connectionStatus.left
        anchors.margins: 10
        width: 100
        height: 30
        radius: 20
        color: "#c0392b"
        border.color: "#ffffff"
        border.width: 2
        
        Text {
            anchors.centerIn: parent
            text: "EMERGENCY STOP"//"/n"
            color: "white"
            font.pixelSize: 10
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
        }
        
        MouseArea {
            anchors.fill: parent
            onClicked: controller.emergencyStop()
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
                                color: parent.down || !enabled?  "#3498db" : "#ffffff"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                            }

                            background: Rectangle {
                                implicitWidth: 190
                                implicitHeight: 58
                                opacity: enabled ? 1 : 0.3
                                color: "transparent"
                                border.color: parent.down || !enabled? "#3498db" : "#ffffff"
                                border.width: 1
                                radius: 20
                            }

                            enabled: connectionStatus.connected
                            onClicked: {
                                window.brewTime = "00:00"
                                controller.startBrew()
                                stackView.push(brewScreen)
                            }
                        }
                        
                        RowLayout {
                            spacing: 10
                            Button {
                                text: qsTr("STEAM")

                                contentItem: Text {
                                    text: parent.text
                                    font.pixelSize: 28
                                    opacity: enabled ? 1.0 : 0.3
                                    color: parent.down || !enabled?  "#e74c3c" : "#ffffff"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                }

                                background: Rectangle {
                                    implicitWidth: 190
                                    implicitHeight: 58
                                    opacity: enabled ? 1 : 0.3
                                    color: "transparent"
                                    border.color: parent.down|| !enabled ? "#e74c3c" : "#ffffff"
                                    border.width: 1
                                    radius: 20
                                }

                                enabled: connectionStatus.connected && !window.steamActive
                                onClicked: {
                                    window.steamActive = true
                                    controller.startSteam()
                                    //stackView.push(steamScreen)
                                }
                            }
                            Button {
                                contentItem: Image {
                                    source: "svgs/pause-white.svg"
                                    //sourceSize: Qt.size(60, 60)
                                    fillMode: Image.PreserveAspectFit
                                    horizontalAlignment: Image.AlignHCenter
                                    verticalAlignment: Image.AlignVCenter
                                    smooth: true
                                    opacity: enabled ? 1.0 : 0.3
                                    anchors.centerIn: parent
                                }

                                background: Rectangle {
                                    implicitWidth: 58
                                    implicitHeight: 58
                                    opacity: enabled ? 1 : 0.3
                                    color: "#b12a2a"
                                    radius: 16
                                }
                                enabled: connectionStatus.connected
                                visible: window.steamActive
                                onClicked: {
                                    window.steamActive = false
                                    controller.stopSteam()
                                }
                            }
                        }
                        
                        RowLayout {
                            spacing: 10
                            /*Button {
                                Layout.preferredWidth: 200
                                Layout.preferredHeight: 60
                                text: "FLUSH"
                                font.pixelSize: 28
                                //font.bold: true

                                //Material.background: "#f39c12"
                                Material.background: "transparent"
                                Material.foreground: "white"

                                enabled: connectionStatus.connected && !window.flushActive
                                onClicked: {
                                    window.flushActive = true
                                    controller.startFlush()
                                    //stackView.push(flushScreen)
                                }
                            }*/
                            Button {
                                text: qsTr("FLUSH")
                                //Layout.preferredWidth: 180
                                //Layout.preferredHeight: 64

                                contentItem: Text {
                                    text: parent.text
                                    font.pixelSize: 28
                                    opacity: enabled ? 1.0 : 0.3
                                    color: parent.down || !enabled ?  "#f39c12" : "#ffffff"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                }

                                background: Rectangle {
                                    implicitWidth: 190
                                    implicitHeight: 58
                                    opacity: enabled ? 1 : 0.3
                                    color: "transparent"
                                    border.color: parent.down || !enabled ? "#f39c12" : "#ffffff"
                                    border.width: 1
                                    radius: 20
                                }

                                enabled: connectionStatus.connected && !window.flushActive
                                onClicked: {
                                    window.flushActive = true
                                    controller.startFlush()
                                    //stackView.push(flushScreen)
                                }
                            }
                            /*Button {
                                text: "STOP"
                                Layout.preferredWidth: 64
                                Layout.preferredHeight: 64
                                Material.background: "#b12a2a"
                                enabled: connectionStatus.connected
                                visible: window.flushActive
                                onClicked: {
                                    window.flushActive = false
                                    controller.stopFlush()
                                }
                            }*/
                            Button {
                                contentItem: Image {
                                    source: "svgs/pause-white.svg"
                                    //sourceSize: Qt.size(60, 60)
                                    fillMode: Image.PreserveAspectFit
                                    horizontalAlignment: Image.AlignHCenter
                                    verticalAlignment: Image.AlignVCenter
                                    smooth: true
                                    opacity: enabled ? 1.0 : 0.3
                                    anchors.centerIn: parent
                                }

                                background: Rectangle {
                                    implicitWidth: 58
                                    implicitHeight: 58
                                    opacity: enabled ? 1 : 0.3
                                    color: "#b12a2a"
                                    radius: 16
                                }
                                enabled: connectionStatus.connected
                                visible: window.flushActive
                                onClicked: {
                                    window.flushActive = false
                                    controller.stopFlush()
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
            color: "#101318"

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

            ColumnLayout {
                anchors.fill: parent
                anchors.topMargin: 20
                anchors.leftMargin: 50
                anchors.rightMargin: 50
                anchors.bottomMargin: 50
                spacing: 20

                // Top-info card -----------------------------------------------------------
                Rectangle {
                    id: infoCard
                    Layout.fillWidth: true
                    height: 72
                    color: "#34495e"
                    radius: 8
                    //border.color: Qt.darker("#e0e0e0", 1.5)
                    //border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        //anchors.margins: 8
                        anchors.leftMargin: 15
                        anchors.rightMargin: 15
                        anchors.topMargin: 1
                        anchors.bottomMargin: 1
                        
                        Button {
                            Layout.alignment: Qt.AlignLeft

                            contentItem: Image {
                                source: "svgs/square-chevron-left.svg"
                                fillMode: Image.PreserveAspectFit

                                smooth: true
                                opacity: enabled ? 1.0 : 0.3
                                anchors.centerIn: parent
                            }

                            background: Rectangle {
                                implicitWidth: 58
                                implicitHeight: 58
                                opacity: enabled ? 1 : 0.3
                                color: "#95a5a6"
                                border.color: "white"
                                border.width: 1
                                radius: 16
                            }

                            onClicked: {
                                stackView.pop()
                                controller.stopBrew()
                            }
                        }

                        // XL: Current mass
                        ColumnLayout {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                text: "Mass"
                                color: "#aaaaaa"
                                font { pixelSize: 13 }
                                Layout.alignment: Qt.AlignHCenter
                            }
                            Text {
                                text: window.currentWeight.toFixed(1) + " g"
                                color: "#4caf50"
                                font { pixelSize: 48; bold: true }
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }

                        // XL: Brew timer
                        ColumnLayout {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                text: "Time"
                                color: "#aaaaaa"
                                font { pixelSize: 13 }
                                Layout.alignment: Qt.AlignHCenter
                            }
                            Text {
                                text: window.brewTime
                                color: "#ffffff"
                                font { pixelSize: 48; bold: true }
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }

                        // Secondary info: thermoblock temp + pump
                        ColumnLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 4
                            Text {
                                text: "Thermoblock"
                                color: "#aaaaaa"
                                font { pixelSize: 12 }
                                Layout.alignment: Qt.AlignHCenter
                            }
                            Text {
                                text: window.brewTempActual.toFixed(1) + "°C"
                                color: "#ff5252"
                                font { pixelSize: 20; bold: true }
                                Layout.alignment: Qt.AlignHCenter
                            }
                            Text {
                                text: window.currentPumpPower.toFixed(0) + "% pump"
                                color: "#29b6f6"
                                font { pixelSize: 14 }
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }

                            Button {
                                id: brew_now
                                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                                contentItem: Image {
                                    source: "svgs/play.svg"
                                    fillMode: Image.PreserveAspectFit

                                    smooth: true
                                    opacity: enabled ? 1.0 : 0.3
                                    anchors.centerIn: parent
                                }

                                background: Rectangle {
                                    implicitWidth: 58
                                    implicitHeight: 58
                                    opacity: enabled ? 1 : 0.3
                                    color: (window.currentState === "HEATING_BREW" && window.brewTempActual >= window.brewTargetTemp - 3.0 && window.scalesSettled) ? "#27ae60" : "#7f8c8d"
                                    radius: 16
                                }
                                enabled: connectionStatus.connected && window.currentState === "HEATING_BREW" && window.scalesSettled
                                visible: window.currentState === "HEATING_BREW"
                                onClicked: {
                                    // Clear charts when starting new brew
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
                            Button {
                                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                                contentItem: Image {
                                    source: "svgs/pause-white.svg"
                                    fillMode: Image.PreserveAspectFit

                                    smooth: true
                                    opacity: enabled ? 1.0 : 0.3
                                    anchors.centerIn: parent
                                }

                                background: Rectangle {
                                    implicitWidth: 58
                                    implicitHeight: 58
                                    opacity: enabled ? 1 : 0.3
                                    color: "#b12a2a"
                                    radius: 16
                                }
                                enabled: window.currentState != "IDLE"
                                visible: window.currentState === "BREWING" | window.currentState === "IDLE"
                                onClicked: controller.stopBrew()
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
                        color: "#34495e"
                        //border.color: "#7f8c8d"
                        //border.width: 1
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
                                anchors.margins: 5
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
                                    ctx.fillText(weightText, width - textWidth - 5, 15)
                                    
                                    // Draw data line
                                    if (dataPoints.length > 0) {
                                        ctx.strokeStyle = "#27ae60"
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
                                            ctx.fillStyle = "#27ae60"
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
                        color: "#34495e"
                        //border.color: "#7f8c8d"
                        //border.width: 1
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
                                anchors.margins: 5
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
                                    ctx.fillText(pressureText, width - textWidth_ - 5, 15)
                                    
                                    // Draw data line
                                    if (dataPoints.length > 0) {
                                        ctx.strokeStyle = "#e74c3c"
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
                                            ctx.fillStyle = "#e74c3c"
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
            color: "#2c3e50"

            /* dim background */
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.35)
            }

            /* frosted-glass card */
            Rectangle {
                id: card
                anchors.centerIn: parent
                width:  Math.min(parent.width - 40, 360)
                height: settingsCol.implicitHeight + 48
                color:  Qt.rgba(1, 1, 1, 0.10)
                radius: 16
                border.color: Qt.rgba(1, 1, 1, 0.15)
                border.width: 1

                // Working values — edited live, applied on SAVE
                property real brewVal:  window.brewTargetTemp
                property real steamVal: window.steamTargetTemp

                ColumnLayout {
                    id: settingsCol
                    anchors.centerIn: parent
                    width: parent.width - 48
                    spacing: 20

                    // ── Header ──────────────────────────────────────────────
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 14
                        Image {
                            Layout.alignment: Qt.AlignVCenter
                            source: "svgs/sliders-horizontal.svg"
                            sourceSize: Qt.size(26, 26)
                            smooth: true
                            fillMode: Image.PreserveAspectFit
                        }
                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            text: "Temperature Settings"
                            color: "white"
                            font { pixelSize: 20; bold: true }
                        }
                    }

                    // ── Brew temperature ─────────────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            text: "Brew Temp  (60 – 110°C)"
                            color: "#aaaaaa"
                            font.pixelSize: 13
                            Layout.alignment: Qt.AlignHCenter
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            // Decrement button
                            Rectangle {
                                width: 64; height: 64
                                radius: 12
                                color: brewMinusArea.pressed ? "#1a6b38" : "#27ae60"
                                Text {
                                    anchors.centerIn: parent
                                    text: "−"
                                    font { pixelSize: 32; bold: true }
                                    color: "white"
                                }
                                MouseArea {
                                    id: brewMinusArea
                                    anchors.fill: parent
                                    onClicked: card.brewVal = Math.max(60.0, Math.round((card.brewVal - 0.5) * 10) / 10)
                                }
                            }

                            // Value display
                            Text {
                                Layout.fillWidth: true
                                text: card.brewVal.toFixed(1) + "°C"
                                color: "#27ae60"
                                font { pixelSize: 34; bold: true }
                                horizontalAlignment: Text.AlignHCenter
                            }

                            // Increment button
                            Rectangle {
                                width: 64; height: 64
                                radius: 12
                                color: brewPlusArea.pressed ? "#1a6b38" : "#27ae60"
                                Text {
                                    anchors.centerIn: parent
                                    text: "+"
                                    font { pixelSize: 32; bold: true }
                                    color: "white"
                                }
                                MouseArea {
                                    id: brewPlusArea
                                    anchors.fill: parent
                                    onClicked: card.brewVal = Math.min(110.0, Math.round((card.brewVal + 0.5) * 10) / 10)
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
                            color: "#aaaaaa"
                            font.pixelSize: 13
                            Layout.alignment: Qt.AlignHCenter
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            Rectangle {
                                width: 64; height: 64
                                radius: 12
                                color: steamMinusArea.pressed ? "#922b21" : "#e74c3c"
                                Text {
                                    anchors.centerIn: parent
                                    text: "−"
                                    font { pixelSize: 32; bold: true }
                                    color: "white"
                                }
                                MouseArea {
                                    id: steamMinusArea
                                    anchors.fill: parent
                                    onClicked: card.steamVal = Math.max(110.0, Math.round((card.steamVal - 0.5) * 10) / 10)
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: card.steamVal.toFixed(1) + "°C"
                                color: "#e74c3c"
                                font { pixelSize: 34; bold: true }
                                horizontalAlignment: Text.AlignHCenter
                            }

                            Rectangle {
                                width: 64; height: 64
                                radius: 12
                                color: steamPlusArea.pressed ? "#922b21" : "#e74c3c"
                                Text {
                                    anchors.centerIn: parent
                                    text: "+"
                                    font { pixelSize: 32; bold: true }
                                    color: "white"
                                }
                                MouseArea {
                                    id: steamPlusArea
                                    anchors.fill: parent
                                    onClicked: card.steamVal = Math.min(150.0, Math.round((card.steamVal + 0.5) * 10) / 10)
                                }
                            }
                        }
                    }

                    // ── Scale controls ───────────────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        Text {
                            text: "Scale:"
                            color: "white"
                            font.pixelSize: 15
                        }
                        Button {
                            text: "TARE"
                            Material.background: "#3498db"
                            Layout.fillWidth: true
                            onClicked: controller.tareScales()
                        }
                        Button {
                            text: "CAL"
                            Material.background: "#f39c12"
                            Layout.fillWidth: true
                            onClicked: calDialog.open()
                        }
                    }

                    // ── Action buttons ───────────────────────────────────────
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 16
                        Button {
                            text: "SAVE"
                            Material.background: "#27ae60"
                            Material.elevation: 2
                            onClicked: {
                                window.brewTargetTemp  = card.brewVal
                                window.steamTargetTemp = card.steamVal
                                controller.setTemperatures(card.brewVal, card.steamVal)
                                stackView.pop()
                            }
                        }
                        Button {
                            text: "BACK"
                            Material.background: "#7f8c8d"
                            Material.elevation: 2
                            onClicked: stackView.pop()
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
        // Calibration Dialog
    Dialog {
        id: calDialog
        anchors.centerIn: parent
        width: 320
        height: 280
        // modal: true

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
                    width: 250
                    from: 1
                    to: 1000
                    value: 200
                    stepSize: 100
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                    Material.foreground: "#FFEB3B"
                    Material.accent: "#e74c3c"
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 10

                    Button {
                        text: "CALIBRATE"
                        bottomPadding: 14
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
    }
}
