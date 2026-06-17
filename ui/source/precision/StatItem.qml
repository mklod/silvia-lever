// A labelled numeral readout: overline label + big tabular numeral with a
// dim baseline-aligned unit. Used in the Brew header and Replay stat row.
import QtQuick
import "."

Column {
    property string label: ""
    property string value: ""
    property string unit: ""
    property int numeralSize: 54
    property int tracking: -1
    property color valueColor: Theme.ink
    property int align: Text.AlignLeft

    spacing: 6

    Overline {
        text: label
        width: parent.width
        horizontalAlignment: align
    }

    Item {
        width: parent.width
        height: numeral.height
        Row {
            anchors.left: align === Text.AlignLeft ? parent.left : undefined
            anchors.horizontalCenter: align === Text.AlignHCenter ? parent.horizontalCenter : undefined
            anchors.right: align === Text.AlignRight ? parent.right : undefined
            spacing: 3
            Text {
                id: numeral
                text: value
                color: valueColor
                font.family: Theme.archivo
                font.pixelSize: numeralSize
                font.weight: Theme.w700
                font.letterSpacing: tracking
                font.preferShaping: false
            }
            Text {
                text: unit
                visible: unit !== ""
                color: Theme.dim
                anchors.baseline: numeral.baseline
                font.family: Theme.archivo
                font.pixelSize: Math.round(numeralSize / 3)
                font.weight: Theme.w500
            }
        }
    }
}
