// Precision button — height 72, radius 4, hairline, label 22/600/tracking 1.
// variant: "primary" (ghost fill) | "primed" (red stroke + fill + glow) |
//          "plain" (hairline only).
import QtQuick
import QtQuick.Effects
import "."

Item {
    id: root
    property string text: ""
    property string variant: "primary"
    property bool enabledLook: true
    property bool active: false        // ON state — label turns red (FLUSH/STEAM)
    signal clicked()

    implicitWidth: 150
    implicitHeight: 72

    readonly property bool primed: variant === "primed"

    // Red glow bloom behind the primed button.
    Rectangle {
        visible: root.primed
        anchors.fill: bg
        radius: bg.radius
        color: "transparent"
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Theme.red
            shadowBlur: 1.0
            shadowVerticalOffset: 0
            shadowHorizontalOffset: 0
            autoPaddingEnabled: true
        }
        Rectangle { anchors.fill: parent; radius: parent.radius; color: Qt.rgba(1,0.27,0.227,0.2) }
    }

    Rectangle {
        id: bg
        anchors.fill: parent
        radius: 4
        color: root.primed ? Theme.redFill
                            : (root.variant === "primary" ? Theme.btn : "transparent")
        border.width: 1
        border.color: root.primed ? Theme.red : Theme.hair
        opacity: root.enabledLook ? 1.0 : 0.35

        Text {
            anchors.centerIn: parent
            text: root.text
            color: (root.primed || root.active) ? Theme.red : Theme.ink
            font.family: Theme.archivo
            font.pixelSize: 22
            font.weight: Theme.w600
            font.letterSpacing: 1
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.enabledLook
        onClicked: root.clicked()
    }
}
