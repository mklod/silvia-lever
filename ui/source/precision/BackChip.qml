// Square back chip (radius 4, hairline) with a ‹ glyph.
import QtQuick
import "."

Item {
    id: root
    property int size: 56
    signal clicked()
    implicitWidth: size; implicitHeight: size
    Rectangle {
        anchors.fill: parent
        radius: 4; color: "transparent"
        border.width: 1; border.color: Theme.hair
        Text { anchors.centerIn: parent; text: "‹"; color: Theme.ink
               font.family: Theme.archivo; font.pixelSize: 30; font.weight: Theme.w500 }
    }
    MouseArea { anchors.fill: parent; onClicked: root.clicked() }
}
