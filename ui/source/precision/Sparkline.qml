// Tiny profile sparkline for list rows. pts = [[t,bar],...].
import QtQuick
import "."

Canvas {
    property var pts: []
    property color color: Theme.dim
    property real maxBar: 10
    onPtsChanged: requestPaint()
    onColorChanged: requestPaint()
    onPaint: {
        var ctx = getContext("2d"); ctx.reset(); ctx.clearRect(0, 0, width, height)
        if (!pts || pts.length < 2) return
        var mt = 0
        for (var i = 0; i < pts.length; i++) if (pts[i][0] > mt) mt = pts[i][0]
        ctx.save()
        ctx.shadowColor = color; ctx.shadowBlur = 4
        ctx.strokeStyle = color; ctx.lineWidth = 2; ctx.lineJoin = "round"; ctx.lineCap = "round"
        ctx.beginPath()
        for (var j = 0; j < pts.length; j++) {
            var x = (pts[j][0] / mt) * width
            var y = height - (pts[j][1] / maxBar) * (height - 2) - 1
            if (j === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
        }
        ctx.stroke(); ctx.restore()
    }
}
