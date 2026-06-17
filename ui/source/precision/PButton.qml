// Precision button — height 72, radius 4, label 22/600/tracking 1.
// variant: "plain"   — hairline outline, white text
//          "primary" — ghost fill, white text
//          "outline" — red outline only (no fill/glow), white text  [armed/primed]
//          "alert"   — red fill + red stroke + glow + red text       [attention]
// active: ON state — label turns red (FLUSH/STEAM toggles)
import QtQuick
import QtQuick.Effects
import "."

Item {
    id: root
    property string text: ""
    property string variant: "primary"
    property bool enabledLook: true
    property bool active: false
    signal clicked()

    implicitWidth: 150
    implicitHeight: 72

    readonly property bool alert: variant === "alert"
    readonly property bool outline: variant === "outline"

    // Red glow bloom — only for the attention ("alert") state.
    Rectangle {
        visible: root.alert
        anchors.fill: bg
        radius: bg.radius
        color: "transparent"
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Theme.red
            shadowBlur: 1.0
            autoPaddingEnabled: true
        }
        Rectangle { anchors.fill: parent; radius: parent.radius; color: Qt.rgba(1,0.27,0.227,0.2) }
    }

    Rectangle {
        id: bg
        anchors.fill: parent
        radius: 4
        color: root.alert ? Theme.redFill
                          : (root.variant === "primary" ? Theme.btn : "transparent")
        border.width: 1
        border.color: (root.alert || root.outline) ? Theme.red : Theme.hair
        opacity: root.enabledLook ? 1.0 : 0.35

        Text {
            anchors.centerIn: parent
            text: root.text
            color: (root.alert || root.active) ? Theme.red : Theme.ink
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
