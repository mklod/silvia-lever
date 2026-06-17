// Persistent status line (spec §2). Height 46, hairline top, mono 13.
// Left: HEAT (red, tappable kill) · BREW (AUTO/MANUAL toggle) · PROF (cycle).
// Right: PRESS (bar) · PUMP (%).
import QtQuick
import "."

Rectangle {
    id: root
    property bool heatersOn: false
    property bool brewAuto: true
    property string profName: "—"
    property real pressure: 0.0
    property int pump: 0
    property bool connected: true

    signal heatTapped()
    signal brewTapped()
    signal profTapped()

    height: 46
    color: Theme.statusFill

    Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Theme.hair }

    component Key: Text {
        font.family: Theme.mono; font.pixelSize: 13; font.weight: Theme.w600
        font.letterSpacing: 1.5; color: Theme.dim
    }
    component Val: Text {
        font.family: Theme.mono; font.pixelSize: 13; font.weight: Theme.w600
        font.letterSpacing: 0.5; color: Theme.ink
    }

    // Left group
    Row {
        anchors.left: parent.left; anchors.leftMargin: 40
        anchors.verticalCenter: parent.verticalCenter
        spacing: 30

        MouseArea {  // HEAT — tappable kill switch
            implicitWidth: heatRow.width; implicitHeight: 30
            onClicked: root.heatTapped()
            Row { id: heatRow; spacing: 8; anchors.verticalCenter: parent.verticalCenter
                Rectangle { width: 7; height: 7; radius: 3.5; color: Theme.red
                            anchors.verticalCenter: parent.verticalCenter; visible: root.heatersOn }
                Key { text: "HEAT" }
                Val { text: root.heatersOn ? "ON" : "OFF"; color: root.heatersOn ? Theme.red : Theme.dim }
            }
        }
        MouseArea {  // BREW mode
            implicitWidth: brewRow.width; implicitHeight: 30
            onClicked: root.brewTapped()
            Row { id: brewRow; spacing: 8; anchors.verticalCenter: parent.verticalCenter
                Key { text: "BREW" }
                Val { text: root.brewAuto ? "AUTO" : "MANUAL" }
            }
        }
        MouseArea {  // PROF
            implicitWidth: profRow.width; implicitHeight: 30
            onClicked: root.profTapped()
            Row { id: profRow; spacing: 8; anchors.verticalCenter: parent.verticalCenter
                Key { text: "PROF" }
                Val { text: root.profName }
            }
        }
    }

    // Right group
    Row {
        anchors.right: parent.right; anchors.rightMargin: 40
        anchors.verticalCenter: parent.verticalCenter
        spacing: 30
        Row { spacing: 8; anchors.verticalCenter: undefined; Key { text: "PRESS" } Val { text: root.pressure.toFixed(2) + " bar" } }
        Row { spacing: 8; Key { text: "PUMP" }  Val { text: root.pump + "%" } }
    }
}
