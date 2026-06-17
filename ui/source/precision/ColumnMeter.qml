// Engraved vertical meter (spec §3 Home). width 64, height 250. 4px track,
// ink fill from bottom with glow, 20 tick divisions (major every 5th), red
// triangular setpoint caret. Mirror via parent transform for the right column.
import QtQuick
import "."

Canvas {
    id: meter
    property real minValue: 0
    property real maxValue: 100
    property real value: 0
    property real setpoint: 0

    implicitWidth: 64
    implicitHeight: 250

    onValueChanged: requestPaint()
    onSetpointChanged: requestPaint()
    onMinValueChanged: requestPaint()
    onMaxValueChanged: requestPaint()

    function frac(v) {
        if (maxValue <= minValue) return 0
        return Math.max(0, Math.min(1, (v - minValue) / (maxValue - minValue)))
    }

    onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        ctx.clearRect(0, 0, width, height)

        var trackX = 6, trackW = 4, H = height
        var tickX = 18

        // Track
        ctx.fillStyle = Qt.rgba(1, 1, 1, 0.10)
        ctx.beginPath(); ctx.roundedRect(trackX, 0, trackW, H, 2, 2); ctx.fill()

        // Fill (bottom → value) with glow bloom
        var vy = H * (1 - frac(value))
        ctx.save()
        ctx.shadowColor = Qt.rgba(1, 1, 1, 0.5)
        ctx.shadowBlur = 7
        ctx.fillStyle = "#f5f5f6"
        ctx.beginPath(); ctx.roundedRect(trackX, vy, trackW, H - vy, 2, 2); ctx.fill()
        ctx.restore()

        // Ticks: 21 ticks (20 divisions); major every 5th
        for (var i = 0; i <= 20; i++) {
            var ty = Math.round(H * (1 - i / 20)) + 0.5
            var major = (i % 5 === 0)
            ctx.strokeStyle = major ? Qt.rgba(1, 1, 1, 0.5) : Qt.rgba(1, 1, 1, 0.12)
            ctx.lineWidth = 1
            ctx.beginPath()
            ctx.moveTo(tickX, ty)
            ctx.lineTo(tickX + (major ? 22 : 12), ty)
            ctx.stroke()
        }

        // Setpoint caret — small red triangle just left of the track
        var sy = H * (1 - frac(setpoint))
        ctx.fillStyle = "#ff453a"
        ctx.beginPath()
        ctx.moveTo(0, sy - 6)
        ctx.lineTo(trackX + 1, sy)
        ctx.lineTo(0, sy + 6)
        ctx.closePath()
        ctx.fill()
    }
}
