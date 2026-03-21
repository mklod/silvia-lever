import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import CoffeeController 1.0

import "controls"

ApplicationWindow {
    id: window
    //width: 1920
    //height: 1080

    // Add these properties after the window title to center the window
    Component.onCompleted: {
        x = Screen.width / 2 - width / 2
        y = Screen.height / 2 - height / 2
    }

    visible: true
    color: "#2c3e50"
    title: "Silvia Coffee Controller"
    
    property string currentScreen: "home"
    
    property real currentTemp: 25.0
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
        
        onTemperatureChanged: function(temp) { window.currentTemp = temp }
        onPressureChanged: function(press) { window.currentPressure = press }
        onWeightChanged: function(wt) { window.currentWeight = wt }
        onPumpPowerChanged: function(power) { window.currentPumpPower = power }
        onStateChanged: function(st) { window.currentState = st }
        onBrewTimeChanged: function(time) { window.brewTime = time }
        
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
    

    Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.margins: 2
        width: 140
        height: 48
        radius: 20
        color: "transparent"
        border.color: "transparent"
        border.width: 2
                
        MouseArea {
            anchors.fill: parent
            anchors.topMargin: -60
            anchors.rightMargin: -40
            onClicked: Qt.quit()
        }
    }

    // Connection Status Indicator
    Rectangle {
        id: connectionStatus
        property bool connected: false
        
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.margins: 10
        width: 140
        height: 48
        radius: 15
        color: "transparent"
        border.color: "transparent"
        
        Text {
            anchors.centerIn: parent
            text: connectionStatus.connected ? "CONNECTED" : "DISCONNECTED"
            color: parent.connected ? "#27ae60" : "#e74c3c"
            font.pixelSize: 13
            font.bold: true
        }
    }
    
    // Emergency Stop Button
    Rectangle {
        id: emergency_Stop
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.margins: 2
        width: 140
        height: 48
        radius: 20
        color: "transparent"
        border.color: "transparent"
        border.width: 2
        z: 999
               
        MouseArea {
            anchors.fill: parent
            anchors.topMargin: -60
            anchors.leftMargin: -40
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
            id: rectangle
            //color: "#2c3e50"
            color: "#101318"
            //anchors.fill: parent

                Image {
                    id: runcilio_logo
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 120
                    source: "svgs/logo.svg"
                    //fillMode: Image.PreserveAspectFit
                    smooth: true
                }


                RowLayout{

                    spacing: 100
                    anchors.top: runcilio_logo.bottom
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 0
                    anchors.topMargin: 80
                    anchors.bottomMargin: 80
                    // width: Math.min(800, parent.width*0.9)
                    width: parent.width
                    anchors.left: parent.left

                    ColumnLayout {
                        Layout.fillHeight: true

                        Layout.leftMargin: 260
                        Layout.alignment: Qt.AlignLeft

                        spacing: 10

                        Button {
                            text: qsTr("BREW")
                            Layout.preferredWidth: 440
                            Layout.preferredHeight: 120

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
                                Layout.preferredHeight: 120
                                Layout.preferredWidth: 440

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
                                    sourceSize: Qt.size(48, 48)
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
                                bottomInset: 0
                                spacing: 0
                                topInset: 0
                                rightPadding: 14
                                leftPadding: 14
                                Layout.preferredHeight: 120
                                Layout.preferredWidth: 120
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
                                Layout.preferredHeight: 120
                                Layout.preferredWidth: 440
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
                                    sourceSize: Qt.size(48, 48)
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
                                Layout.preferredHeight: 120
                                Layout.preferredWidth: 120
                                bottomInset: 0
                                topInset: 0
                                spacing: 0
                                rightPadding: 14
                                leftPadding: 14
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
                        Layout.rightMargin: 260
                        width: 120
                        height: 120

                        minValue: 0
                        maxValue: Math.max(window.currentTemp, window.steamActive ? window.steamTargetTemp : window.brewTargetTemp)
                        value: window.currentTemp
                        Layout.preferredWidth: 480
                        Layout.preferredHeight: 480
                        Layout.fillWidth: false
                        Layout.fillHeight: false
                        interactive: false
                        progressColor: "#2290e7"
                        trackWidth: 36
                        trackColor: "#34495e"
                        progressWidth: 36

                        startAngle: 30.0
                        endAngle: 330
                        rotation: 180

                        Text {
                            anchors.centerIn: parent
                            text: window.currentTemp.toFixed(1) + "°C"
                            color: window.currentTemp > (window.steamActive ? window.steamTargetTemp : window.brewTargetTemp) ? "#ff0000" : "white"
                            //color: "white"
                            font.pixelSize: 64
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
    }


    // Brew Screen
    Component {
        id: brewScreen

        Rectangle {
            //color: "#2c3e50"
            color : "#101318"
            //anchors.fill: parent

            ColumnLayout {
                anchors.fill: parent
                anchors.leftMargin: 36
                anchors.rightMargin: 36
                anchors.topMargin: 36
                anchors.bottomMargin: 65
                spacing: 20

                // Top-info card -----------------------------------------------------------
                Rectangle {
                    id: infoCard
                    Layout.fillWidth: true
                    color: "#34495e"
                    radius: 8
                    Layout.preferredHeight: 150
                    //border.color: Qt.darker("#e0e0e0", 1.5)
                    //border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        //anchors.margins: 8
                        anchors.leftMargin: 32
                        anchors.rightMargin: 32
                        anchors.topMargin: 1
                        anchors.bottomMargin: 1

                        Button {
                            Layout.fillWidth: false
                            Layout.fillHeight: false
                            Layout.alignment: Qt.AlignLeft
                            contentItem: Image {
                                source: "svgs/chevron-left.svg"
                                sourceSize: Qt.size(48, 48)
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
                                color: "transparent"//"#95a5a6"
                                border.color: "white"
                                border.width: 1
                                radius: 16
                            }
                            Layout.preferredHeight: 100
                            Layout.preferredWidth: 100
                            onClicked: {
                                stackView.pop()
                                controller.stopBrew()
                            }
                        }

                        

                        // Temperature
                        ColumnLayout {
                            Layout.fillHeight: true
                            Layout.alignment: Qt.AlignHCenter
                            Layout.fillWidth: true
                            spacing: 20
                            Text {
                                text: "Boiler Temp"
                                color: "#ffffff"
                                font { pixelSize: 32}
                                Layout.alignment: Qt.AlignHCenter
                            }
                            Text {
                                text: window.currentTemp.toFixed(1) + "°C"
                                color: "#ffffff"
                                font { pixelSize: 40; bold: true }
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }
                        ColumnLayout {
                            Layout.fillHeight: true
                            Layout.alignment: Qt.AlignHCenter
                            Layout.fillWidth: true
                            //Layout.alignment: Qt.AlignVCenter
                            spacing: 20
                            Text {
                                text: "Pump power"
                                color: "#ffffff"
                                font { pixelSize: 32}
                                Layout.alignment: Qt.AlignHCenter
                            }
                            Text {
                                text: window.currentPumpPower.toFixed(0) + "%"
                                color: "#ffffff"
                                font { pixelSize: 40; bold: true }
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }
                        // Brew time
                        ColumnLayout {
                            Layout.fillHeight: true
                            Layout.alignment: Qt.AlignHCenter
                            Layout.fillWidth: true
                            spacing: 20
                            Text {
                                text: "Extraction time"
                                color: "#ffffff"
                                font { pixelSize: 32}
                                Layout.alignment: Qt.AlignHCenter
                            }
                            Text {
                                id: brew_time_text
                                text: window.brewTime
                                color: "#ffffff"
                                font { pixelSize: 40; bold: true }
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }

                            Button {
                                id: brew_now
                                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                                contentItem: Image {
                                    source: "svgs/play.svg"
                                    sourceSize: Qt.size(48, 48)
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
                                    color: "transparent"
                                    border.width: 1
                                    border.color: "white"
                                    //color: (window.currentState === "HEATING_BREW" && window.currentTemp >= window.brewTargetTemp - 3.0 && window.scalesSettled) ? "#27ae60" : "#7f8c8d"
                                    radius: 16
                                }
                                Layout.preferredHeight: 100
                                Layout.preferredWidth: 100
                                enabled: connectionStatus.connected && window.currentState === "HEATING_BREW" && window.scalesSettled
                                visible: window.currentState === "HEATING_BREW"
                                onClicked: {
                                    // Clear charts when starting new brew
                                    coffeeChart.dataPoints = []
                                    pressureChart.dataPoints = []
                                    coffeeChart.startTime = null
                                    pressureChart.startTime = null
                                    coffeeChart.requestPaint()
                                    pressureChart.requestPaint()
                                    controller.beginBrew()
                                }
                            }
                            Button {
                                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                                contentItem: Image {
                                    source: "svgs/pause-white.svg"
                                    sourceSize: Qt.size(48, 48)
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
                                    color: "transparent"//"#b12a2a"
                                    border.width: 1
                                    border.color: "white"
                                    radius: 16
                                }
                                Layout.preferredHeight: 100
                                Layout.preferredWidth: 100
                                enabled: window.currentState != "IDLE"
                                visible: window.currentState === "BREWING" | window.currentState === "IDLE"
                                onClicked: controller.stopBrew()
                            }
                    }
                }

                // Charts row
                ColumnLayout {
                    //Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 20

                    // Coffee extraction chart
                    Rectangle {
                        Layout.fillWidth: true
                        //Layout.fillHeight: true
                        Layout.preferredHeight: Screen.width / 9
                        color: "#34495e"
                        //border.color: "#7f8c8d"
                        //border.width: 1
                        radius: 5

                        Item {
                            anchors.fill: parent
                            anchors.margins: 5

                            Text {
                                text: "Output (g)"
                                color: "white"
                                font.pixelSize: 24
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.margins: 5
                                anchors.leftMargin: 5
                                anchors.topMargin: 5
                            }
                            Text {
                                text: window.currentWeight.toFixed(1) + " g"
                                color: "white"
                                font.pixelSize: 40
                                font.family: "Segoe UI"
                                font.bold: true
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 0
                                anchors.rightMargin: 95
                                anchors.topMargin: -5
                            }

                            Canvas {
                                id: coffeeChart
                                width: parent.width
                                height: parent.height - 1.9

                                property var dataPoints: []
                                property real maxWeight: 75
                                property real maxTime: 50
                                property var startTime: null

                                function updateScale() {
                                    if (dataPoints.length > 0) {
                                        var maxW = 75/1.1
                                        var maxT = 50
                                        for (var i = 0; i < dataPoints.length; i++) {
                                            if (dataPoints[i].weight > maxW) maxW = dataPoints[i].weight
                                            //if (dataPoints[i].time > maxT) maxT = dataPoints[i].time
                                        }
                                        maxWeight = Math.max(maxW * 1.1, 1)
                                        //maxTime = Math.max(maxT * 1.1, 10)
                                    }
                                }

                                onPaint: {
                                    var ctx = getContext("2d")
                                    ctx.clearRect(0, 0, width, height)

                                    // Draw grid and labels
                                    ctx.strokeStyle = "#7f8c8d"
                                    ctx.lineWidth = 0.5
                                    ctx.fillStyle = "#bdc3c7"
                                    ctx.font = "22px Arial"
                                    for (var i = 0; i <= 5; i++) {
                                        var y = (height / 5) * i
                                        ctx.beginPath()
                                        ctx.moveTo(0, y)
                                        ctx.lineTo(width, y)
                                        ctx.stroke()
                                        var labelValue = (maxWeight * (5 - i) / 5).toFixed(1)// + "g"
                                        var textWidth_1 = ctx.measureText(labelValue).width
                                        ctx.fillText(labelValue, width - textWidth_1 -2, y - 2)
                                    }
                                    for (var j = 0; j <= 10; j++) {
                                        var x = (width / 10) * j
                                        var timeLabel = (maxTime * j / 10).toFixed(0)
                                        ctx.fillText(timeLabel, x + 2, height - 5)
                                    }

                                    // Draw current weight value
                                    //ctx.fillStyle = "white"
                                    //ctx.font = 'bold 40px "Segoe UI"'
                                    //var weightText = window.currentWeight.toFixed(1) + " g"
                                    //var textWidth = ctx.measureText(weightText).width
                                    //ctx.fillText(weightText, width - textWidth - 70, 40)

                                    // Draw data line
                                    if (dataPoints.length > 0) {
                                        ctx.strokeStyle = "#ffffff"
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
                                            ctx.fillStyle = "#ffffff"
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
                                font.pixelSize: 24
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.margins: 5
                                anchors.leftMargin: 5
                                anchors.topMargin: 5
                            }

                            Text {
                                text: window.currentPressure.toFixed(1) + " bar"
                                color: "white"
                                font.pixelSize: 40
                                font.family: "Segoe UI"
                                font.bold: true
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 0
                                anchors.rightMargin: 90
                                anchors.topMargin: -5
                            }

                            Canvas {
                                id: pressureChart
                                width: parent.width
                                height: parent.height - 1.9

                                property var dataPoints: []
                                property real maxPressure: 12.5
                                property real maxTime: 50
                                property var startTime: null

                                function updateScale() {
                                    if (dataPoints.length > 0) {
                                        var maxP = 12.5/1.1
                                        var maxT = 50//10/1.1
                                        for (var i = 0; i < dataPoints.length; i++) {
                                            if (dataPoints[i].pressure > maxP) maxP = dataPoints[i].pressure
                                            //if (dataPoints[i].time > maxT) maxT = dataPoints[i].time
                                        }
                                        maxPressure = Math.max(maxP * 1.1, 1)
                                        //maxTime = Math.max(maxT * 1.1, 10)
                                    }
                                }

                                onPaint: {
                                    var ctx = getContext("2d")
                                    ctx.clearRect(0, 0, width, height)

                                    // Draw grid and labels
                                    ctx.strokeStyle = "#7f8c8d"
                                    ctx.lineWidth = 0.5
                                    ctx.fillStyle = "#bdc3c7"
                                    ctx.font = "22px Arial"
                                    for (var i = 0; i <= 5; i++) {
                                        var y = (height / 5) * i
                                        ctx.beginPath()
                                        ctx.moveTo(0, y)
                                        ctx.lineTo(width, y)
                                        ctx.stroke()
                                        var labelValue = (maxPressure * (5 - i) / 5).toFixed(1)//+  "bar"
                                        var textWidth_2 = ctx.measureText(labelValue).width
                                        ctx.fillText(labelValue, width - textWidth_2 - 2, y - 2)
                                    }
                                    for (var j = 0; j <= 10; j++) {
                                        var x = (width / 10) * j
                                        var timeLabel = (maxTime * j / 10).toFixed(0)
                                        //ctx.fillText(timeLabel + "s", x + 2, height - 5)
                                        ctx.fillText(timeLabel, x + 2, height - 5)
                                    }

                                    // Draw current pressure value
                                    //ctx.fillStyle = "white"
                                    //ctx.font = 'bold 40px "Segoe UI"'
                                    //var pressureText = window.currentPressure.toFixed(1) + " bar"
                                    //var textWidth_ = ctx.measureText(pressureText).width
                                    //ctx.fillText(pressureText, width - textWidth_ - 75, 40)

                                    // Draw data line
                                    if (dataPoints.length > 0) {
                                        ctx.strokeStyle = "#ffffff"
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
                                            ctx.fillStyle = "#ffffff"
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
                    text: window.currentTemp.toFixed(1) + "°C"
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
                        enabled: window.currentState === "HEATING_STEAM" && window.currentTemp >= window.steamTargetTemp - 2.0
                        visible: window.currentState === "HEATING_STEAM" && window.currentTemp >= window.steamTargetTemp - 2.0
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
                width: parent.width*2/5
                color:  Qt.rgba(1, 1, 1, 0.10)
                radius: 32
                border.color: Qt.rgba(1, 1, 1, 0.15)
                border.width: 2
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.topMargin: 120
                anchors.bottomMargin: 120
                anchors.horizontalCenter: parent.horizontalCenter


                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: parent.width/12//24
                    spacing: 24


                    /* header row */
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 20
                        Image {
                            Layout.alignment: Qt.AlignVCenter
                            source: "svgs/sliders-horizontal.svg"
                            sourceSize: Qt.size(56, 56)
                            smooth: true
                            fillMode: Image.PreserveAspectFit
                        }
                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            text: "Settings"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            font.bold: true
                            font.pointSize: 42
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            color: "white"
                        }
                    }

                    /* Brew temperature */
                    RowLayout {
                        Layout.fillHeight: true
                        Layout.fillWidth: true
                        spacing: 12
                        Text {
                            width: 310
                            Layout.fillWidth: true

                            text: "Brew Temp:"
                            font.pixelSize: 36
                            horizontalAlignment: Text.AlignLeft
                            verticalAlignment: Text.AlignVCenter
                            font.bold: false
                            Layout.fillHeight: true
                            color: "white"
                        }
                        SpinBox {
                            id: brewTempSpin

                            from: 60; to: 110; value: window.brewTargetTemp
                            font.pixelSize: 48
                            font.bold: true
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            Material.foreground: "white"
                            Material.accent: "#e74c3c"
                        }
                        Text {
                            Layout.alignment: Qt.AlignRight
                            text: "°C"
                            font.pixelSize: 36
                            verticalAlignment: Text.AlignVCenter
                            color: "white"
                        }
                    }

                    /* Steam temperature */
                    RowLayout {
                        Layout.preferredHeight: -1
                        Layout.fillHeight: true
                        layer.sourceRect.height: 0
                        Layout.fillWidth: true
                        spacing: 12
                        Text {
                            Layout.fillWidth: true

                            text: "Steam Temp:"
                            font.pixelSize: 36
                            horizontalAlignment: Text.AlignLeft
                            verticalAlignment: Text.AlignVCenter
                            font.bold: false
                            Layout.fillHeight: true
                            color: "white"
                        }
                        SpinBox {
                            id: steamTempSpin
                            //Layout.fillWidth: true
                            from: 110; to: 150; value: window.steamTargetTemp
                            font.pixelSize: 48
                            font.bold: true
                            Layout.fillHeight: false
                            Layout.fillWidth: true
                            Material.foreground: "white"
                            Material.accent: "#e74c3c"
                        }
                        Text {
                            Layout.alignment: Qt.AlignRight
                            text: "°C"
                            font.pixelSize: 36
                            horizontalAlignment: Text.AlignLeft
                            color: "white"
                            verticalAlignment: Text.AlignVCenter
                        }
                    }


                    /* Scale controls */
                    RowLayout {
                        width: parent.width
                        Layout.preferredHeight: 110
                        layer.sourceRect.height: 0
                        layer.sourceRect.width: 0
                        layoutDirection: Qt.LeftToRight
                        Layout.fillHeight: false
                        Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                        Layout.fillWidth: true
                        spacing: 12
                        Text {
                            text: "Scale:         "
                            color: "white"
                            font.pixelSize: 36
                            verticalAlignment: Text.AlignVCenter
                            Layout.fillHeight: true
                            Layout.fillWidth: false
                        }

                        Button {
                            Layout.preferredWidth: 220
                            text: qsTr("TARE")
                            // Layout.preferredHeight: 120
                            // Layout.preferredWidth: 440
                            Layout.fillWidth: true
                            Layout.fillHeight: true

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
                                // implicitWidth: 190
                                // implicitHeight: 58
                                opacity: enabled ? 1 : 0.3
                                color: "transparent"
                                border.color: parent.down || !enabled ? "#f39c12" : "#ffffff"
                                border.width: 1
                                radius: 20
                            }
                            onClicked: controller.tareScales()
                        }
                        Button {
                            Layout.preferredWidth: 220
                            text: qsTr("CAL")
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            contentItem: Text {
                                font.pixelSize: 28
                                opacity: enabled ? 1.0 : 0.3
                                color: parent.down || !enabled ?  "#f39c12" : "#ffffff"
                                text: parent.text
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                            }

                            background: Rectangle {
                                opacity: enabled ? 1 : 0.3
                                color: "transparent"
                                border.color: parent.down || !enabled ? "#f39c12" : "#ffffff"
                                border.width: 1
                                radius: 20
                            }
                            onClicked: calDialog.open()
                        }
                    }

                    /* action buttons */
                    RowLayout {
                        Layout.preferredHeight: 99
                        Layout.topMargin: 24
                        Layout.bottomMargin: -37
                        Layout.margins: -1
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 19

                        Button {
                            Layout.preferredWidth: 220
                            text: qsTr("SAVE")
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            contentItem: Text {
                                font.pixelSize: 28
                                opacity: enabled ? 1.0 : 0.3
                                color: parent.down || !enabled ?  "#f39c12" : "#ffffff"
                                text: parent.text
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                            }

                            background: Rectangle {
                                opacity: enabled ? 1 : 0.3
                                color: "transparent"
                                border.color: parent.down || !enabled ? "#f39c12" : "#ffffff"
                                border.width: 1
                                radius: 20
                            }
                            onClicked: {
                                window.brewTargetTemp = brewTempSpin.value
                                window.steamTargetTemp = steamTempSpin.value
                                controller.setTemperatures(brewTempSpin.value,
                                                           steamTempSpin.value)
                                stackView.pop()
                            }
                        }

                        Button {
                            Layout.preferredWidth: 220
                            text: qsTr("BACK")
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            contentItem: Text {
                                font.pixelSize: 28
                                opacity: enabled ? 1.0 : 0.3
                                color: parent.down || !enabled ?  "#f39c12" : "#ffffff"
                                text: parent.text
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                            }

                            background: Rectangle {
                                opacity: enabled ? 1 : 0.3
                                color: "transparent"
                                border.color: parent.down || !enabled ? "#f39c12" : "#ffffff"
                                border.width: 1
                                radius: 20
                            }
                            onClicked: stackView.pop()
                        }
                    } 

                }
            }
        }
    }
    
    // Calibration Dialog
    Dialog {
        id: calDialog
        anchors.centerIn: parent
        width: 600
        height: 400
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
                    font.pixelSize: 36
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    Layout.topMargin: -1
                    Layout.fillWidth: false
                    Layout.fillHeight: false
                    font.bold: true
                    Layout.alignment: Qt.AlignHCenter
                }

                Text {
                    text: "Place known weight on scale (grams):"
                    color: "white"
                    font.pixelSize: 26
                    verticalAlignment: Text.AlignVCenter
                    Layout.topMargin: -31
                    Layout.fillHeight: false
                    Layout.alignment: Qt.AlignHCenter
                }

                SpinBox {
                    id: calWeightSpin
                    from: 1
                    to: 1000
                    value: 200
                    stepSize: 100
		    font.bold: true
                    font.pixelSize: 48
                    Layout.preferredHeight: 86
                    Layout.bottomMargin: -26
                    Layout.topMargin: 0
                    Layout.leftMargin: 80
                    Layout.rightMargin: 80
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    Layout.alignment: Qt.AlignHCenter
                    Material.foreground: "white"
                    Material.accent: "#e74c3c"
                }

                RowLayout {
                    Layout.bottomMargin: -15
                    Layout.fillWidth: false
                    Layout.preferredHeight: 76
                    Layout.fillHeight: false
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 10

                    /*Button {
                        text: "CALIBRATE"
                        font.pixelSize: 24
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Material.background: "#27ae60"
                        onClicked: {
                            controller.calibrateScales(calWeightSpin.value)
                            calDialog.close()
                        }
                    }*/

                    Button {
                        Layout.preferredWidth: 220
                        text: qsTr("CALIBRATE")
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        contentItem: Text {
                            font.pixelSize: 28
                            opacity: enabled ? 1.0 : 0.3
                            color: parent.down || !enabled ?  "#f39c12" : "#ffffff"
                            text: parent.text
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }

                        background: Rectangle {
                            opacity: enabled ? 1 : 0.3
                            color: "transparent"
                            border.color: parent.down || !enabled ? "#f39c12" : "#ffffff"
                            border.width: 1
                            radius: 20
                        }
                        onClicked: {
                            controller.calibrateScales(calWeightSpin.value)
                            calDialog.close()
                        }
                    }

                    /*Button {
                        text: "CANCEL"
                        font.pixelSize: 24
                        Layout.fillHeight: true
                        Layout.fillWidth: true
                        Material.background: "#7f8c8d"
                        onClicked: calDialog.close()
                    }*/
                    Button {
                            Layout.preferredWidth: 220
                            text: qsTr("CANCEL")
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            contentItem: Text {
                                font.pixelSize: 28
                                opacity: enabled ? 1.0 : 0.3
                                color: parent.down || !enabled ?  "#f39c12" : "#ffffff"
                                text: parent.text
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                            }

                            background: Rectangle {
                                opacity: enabled ? 1 : 0.3
                                color: "transparent"
                                border.color: parent.down || !enabled ? "#f39c12" : "#ffffff"
                                border.width: 1
                                radius: 20
                            }
                            onClicked: calDialog.close()
                        }
                }
            }
        }
    }

}
