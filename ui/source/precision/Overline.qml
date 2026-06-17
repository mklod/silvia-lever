// Overline label — 13/600/tracking 3/uppercase/dim (spec §2).
import QtQuick
import "."

Text {
    property real tracking: 3
    font.family: Theme.archivo
    font.pixelSize: 13
    font.weight: Theme.w600
    font.letterSpacing: tracking
    font.capitalization: Font.AllUppercase
    color: Theme.dim
    renderType: Text.NativeRendering
}
