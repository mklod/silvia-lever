// Home instrument column: ColumnMeter + readout (hero numeral + SET) + 2 buttons.
// `mirrored` puts the meter on the outer (right) edge and right-aligns text.
import QtQuick
import "."

Item {
    id: root
    property bool mirrored: false
    property string label: ""
    property string sub: ""
    property real meterMin: 0
    property real meterMax: 100
    property real valueF: 0
    property real setF: 0
    property string btn1Text: ""
    property string btn1Variant: "primary"
    property string btn2Text: ""
    property string btn2Variant: "plain"

    signal meterTapped()
    signal btn1()
    signal btn2()

    implicitWidth: 372
    implicitHeight: 360

    readonly property int ha: mirrored ? Text.AlignRight : Text.AlignLeft

    // Meter pinned to the outer edge
    ColumnMeter {
        id: meter
        anchors.top: parent.top
        anchors.left: mirrored ? undefined : parent.left
        anchors.right: mirrored ? parent.right : undefined
        minValue: root.meterMin; maxValue: root.meterMax
        value: root.valueF; setpoint: root.setF
        transform: Scale { origin.x: 32; xScale: root.mirrored ? -1 : 1 }
        MouseArea { anchors.fill: parent; onClicked: root.meterTapped() }
    }

    // Readout beside the meter
    Column {
        id: readout
        anchors.top: parent.top; anchors.topMargin: 6
        anchors.left: mirrored ? parent.left : meter.right
        anchors.right: mirrored ? meter.left : parent.right
        anchors.leftMargin: mirrored ? 0 : 22
        anchors.rightMargin: mirrored ? 22 : 0
        spacing: 2

        Overline { width: parent.width; horizontalAlignment: root.ha; text: root.label }
        Text {
            width: parent.width; horizontalAlignment: root.ha
            text: root.sub; color: Theme.dim
            font.family: Theme.archivo; font.pixelSize: 14; font.weight: Theme.w500
        }
        // Hero numeral + °F (baseline aligned)
        Item {
            width: parent.width; height: hero.height * 0.86; clip: false
            Row {
                anchors.left: mirrored ? undefined : parent.left
                anchors.right: mirrored ? parent.right : undefined
                spacing: 2
                Text {
                    id: hero
                    text: root.valueF.toFixed(0)
                    color: Theme.ink
                    font.family: Theme.archivo; font.pixelSize: 108; font.weight: Theme.w700
                    font.letterSpacing: -3
                }
                Text {
                    text: "°F"; color: Theme.dim
                    anchors.baseline: hero.baseline
                    font.family: Theme.archivo; font.pixelSize: 34; font.weight: Theme.w500
                }
            }
        }
        // red tick + SET
        Row {
            anchors.left: mirrored ? undefined : parent.left
            anchors.right: mirrored ? parent.right : undefined
            spacing: 8
            layoutDirection: mirrored ? Qt.RightToLeft : Qt.LeftToRight
            Rectangle { width: 18; height: 2; color: Theme.red; anchors.verticalCenter: parent.verticalCenter }
            Text { text: "SET " + root.setF.toFixed(0) + "°"; color: Theme.dim
                   font.family: Theme.archivo; font.pixelSize: 15; font.weight: Theme.w500 }
        }
    }

    // Button row at the bottom, on the readout side
    Row {
        anchors.bottom: parent.bottom
        anchors.left: mirrored ? parent.left : meter.right
        anchors.leftMargin: mirrored ? 0 : 22
        anchors.right: mirrored ? meter.left : undefined
        anchors.rightMargin: mirrored ? 22 : 0
        spacing: 14
        PButton { text: root.btn1Text; variant: root.btn1Variant; onClicked: root.btn1() }
        PButton { text: root.btn2Text; variant: root.btn2Variant; onClicked: root.btn2() }
    }
}
