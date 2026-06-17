// Profile detail chart (spec §3) — phase bands + red setpoint curve, 0–10 bar.
import QtQuick
import "."

Canvas {
    property var pts: []       // [[t,bar],...]
    property var phases: []    // [{name, band:[s,e]}]
    property real maxBar: 10
    onPtsChanged: requestPaint()
    onPhasesChanged: requestPaint()

    function mt() { var m = 0; for (var i = 0; i < pts.length; i++) if (pts[i][0] > m) m = pts[i][0]; return m || 1 }

    onPaint: {
        var ctx = getContext("2d"); ctx.reset(); ctx.clearRect(0, 0, width, height)
        var L = 30, R = 10, T = 16, B = 22
        var x0 = L, x1 = width - R, y0 = T, y1 = height - B
        var maxt = mt()
        function X(t) { return x0 + (t / maxt) * (x1 - x0) }
        function Y(b) { return y1 - (b / maxBar) * (y1 - y0) }

        // Phase bands + labels
        for (var p = 0; p < phases.length; p++) {
            var b = phases[p].band
            var bx0 = X(b[0]), bx1 = X(b[1])
            ctx.fillStyle = Qt.rgba(1, 1, 1, (p % 2 === 0) ? 0.055 : 0.03)
            ctx.fillRect(bx0, y0, bx1 - bx0, y1 - y0)
            // dashed divider at band end
            if (p < phases.length - 1) {
                ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.12); ctx.lineWidth = 1
                ctx.setLineDash([3, 3])
                ctx.beginPath(); ctx.moveTo(bx1, y0); ctx.lineTo(bx1, y1); ctx.stroke()
                ctx.setLineDash([])
            }
            // phase name centered on top
            ctx.fillStyle = Qt.rgba(1, 1, 1, 0.42)
            ctx.font = '700 8.5px "' + Theme.archivo + '"'
            ctx.textAlign = "center"
            ctx.fillText(phases[p].name, (bx0 + bx1) / 2, y0 + 9)
        }

        // Gridlines + axis labels every 2 bar
        ctx.textAlign = "right"
        ctx.font = '9px "' + Theme.mono + '"'
        for (var g = 0; g <= 10; g += 2) {
            var gy = Y(g)
            ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.12); ctx.lineWidth = 1
            ctx.beginPath(); ctx.moveTo(x0, gy + 0.5); ctx.lineTo(x1, gy + 0.5); ctx.stroke()
            ctx.fillStyle = Qt.rgba(1, 1, 1, 0.42)
            ctx.fillText(g.toString(), x0 - 6, gy + 3)
        }

        // Setpoint curve (red + glow)
        if (pts && pts.length >= 2) {
            ctx.save()
            ctx.shadowColor = "#ff453a"; ctx.shadowBlur = 6
            ctx.strokeStyle = "#ff453a"; ctx.lineWidth = 2.5; ctx.lineJoin = "round"; ctx.lineCap = "round"
            ctx.beginPath()
            for (var i = 0; i < pts.length; i++) {
                var x = X(pts[i][0]), y = Y(pts[i][1])
                if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
            }
            ctx.stroke()
            ctx.restore()
            ctx.fillStyle = "#ff453a"
            for (var v = 0; v < pts.length; v++) {
                ctx.beginPath(); ctx.arc(X(pts[v][0]), Y(pts[v][1]), 2.4, 0, 2 * Math.PI); ctx.fill()
            }
        }

        // maxT label bottom-right
        ctx.fillStyle = Qt.rgba(1, 1, 1, 0.42)
        ctx.font = '9px "' + Theme.mono + '"'
        ctx.textAlign = "right"
        ctx.fillText(Math.round(maxt) + "s", x1, y1 + 14)
    }
}
