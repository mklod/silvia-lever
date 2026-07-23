// ChartCard (spec §2) — reused on Brew + Replay. Header overline + value/unit,
// plot with 4 gridlines and a glowing trace. Mass = white, Pressure = red.
import QtQuick
import "."

Rectangle {
    id: root
    property string title: ""
    property string valueText: ""
    property string unit: ""
    property var series: []           // [{t, v}, ...]
    property color traceColor: Theme.mass
    property real maxT: 40
    property real maxV: 50
    property real clipT: 1e9          // only draw points with t <= clipT (replay)

    radius: 6
    color: Theme.card
    border.width: 1
    border.color: Theme.hair

    onSeriesChanged: plot.requestPaint()
    onMaxTChanged: plot.requestPaint()
    onMaxVChanged: plot.requestPaint()
    onClipTChanged: plot.requestPaint()

    // Header
    Item {
        id: header
        anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
        anchors.leftMargin: 18; anchors.rightMargin: 18; anchors.topMargin: 12
        height: 30
        Overline { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                   text: root.title }
        Row {
            anchors.right: parent.right; anchors.baseline: parent.bottom
            spacing: 3
            Text { id: hv; text: root.valueText; color: root.traceColor
                   font.family: Theme.archivo; font.pixelSize: 28; font.weight: Theme.w700 }
            Text { text: root.unit; color: Theme.dim; anchors.baseline: hv.baseline
                   font.family: Theme.archivo; font.pixelSize: 11; font.weight: Theme.w500 }
        }
    }

    Canvas {
        id: plot
        anchors.top: header.bottom; anchors.topMargin: 6
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        anchors.leftMargin: 14; anchors.rightMargin: 14; anchors.bottomMargin: 12

        // Rasterize off the GUI thread so live-brew repaints can't jank the
        // rest of the UI (the MASS numeral etc.).
        renderStrategy: Canvas.Threaded

        // Trace the polyline path once; stroked in multiple passes below.
        function tracePath(ctx) {
            var s = root.series
            ctx.beginPath()
            var started = false
            for (var i = 0; i < s.length; i++) {
                if (s[i].t > root.clipT) break
                var x = (s[i].t / root.maxT) * width
                var y = height - (s[i].v / root.maxV) * height
                if (!started) { ctx.moveTo(x, y); started = true } else ctx.lineTo(x, y)
            }
        }

        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.clearRect(0, 0, width, height)

            // 4 horizontal gridlines
            ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.12)
            ctx.lineWidth = 1
            for (var g = 0; g < 4; g++) {
                var gy = Math.round(height * g / 3) + 0.5
                ctx.beginPath(); ctx.moveTo(0, gy); ctx.lineTo(width, gy); ctx.stroke()
            }

            var s = root.series
            if (!s || s.length < 2) return

            // Glow via layered strokes, NOT ctx.shadowBlur. shadowBlur is a
            // per-draw Gaussian blur — on the Pi it cost enough per repaint
            // (2 charts × growing polyline, every 250 ms during a brew) to
            // jank the GUI thread and drag the live readouts to ~1 Hz.
            // Three cheap passes read the same on the OLED.
            ctx.lineJoin = "round"
            ctx.lineCap = "round"
            var c = root.traceColor
            ctx.strokeStyle = Qt.rgba(c.r, c.g, c.b, 0.10)
            ctx.lineWidth = 9
            tracePath(ctx); ctx.stroke()
            ctx.strokeStyle = Qt.rgba(c.r, c.g, c.b, 0.25)
            ctx.lineWidth = 5
            tracePath(ctx); ctx.stroke()
            ctx.strokeStyle = c
            ctx.lineWidth = 2.5
            tracePath(ctx); ctx.stroke()
        }
    }
}
