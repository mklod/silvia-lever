// Last modified: 2026-06-16--1722
// Precision Instrument design tokens (singleton). Values from
// "Silvia Lever — Design Spec.md". Logical px = device px / 2.
pragma Singleton
import QtQuick

QtObject {
    id: theme

    // ── Fonts (bundled, loaded via FontLoader; variable weights) ──────────────
    property FontLoader _archivo: FontLoader { source: Qt.resolvedUrl("../fonts/Archivo.ttf") }
    property FontLoader _mono:    FontLoader { source: Qt.resolvedUrl("../fonts/JetBrainsMono.ttf") }
    readonly property string archivo: _archivo.status === FontLoader.Ready ? _archivo.name : "sans-serif"
    readonly property string mono:    _mono.status === FontLoader.Ready ? _mono.name : "monospace"

    // ── Colors ────────────────────────────────────────────────────────────────
    readonly property color bg:        "#000000"
    readonly property color ink:       "#f5f5f6"
    readonly property color mass:      "#ffffff"
    readonly property color red:       "#ff453a"
    readonly property color dim:       Qt.rgba(1, 1, 1, 0.42)
    readonly property color hair:      Qt.rgba(1, 1, 1, 0.12)
    readonly property color card:      Qt.rgba(1, 1, 1, 0.02)
    readonly property color btn:       Qt.rgba(1, 1, 1, 0.04)
    readonly property color track:     Qt.rgba(1, 1, 1, 0.10)
    readonly property color tickMajor: Qt.rgba(1, 1, 1, 0.50)
    readonly property color popup:     "#0a0a0b"
    readonly property color redFill:   Qt.rgba(1, 0.27, 0.227, 0.08)  // #ff453a14-ish fill
    readonly property color statusFill: Qt.rgba(1, 1, 1, 0.015)

    // ── Weights ────────────────────────────────────────────────────────────────
    readonly property int w400: Font.Normal
    readonly property int w500: Font.Medium
    readonly property int w600: Font.DemiBold
    readonly property int w700: Font.Bold
    readonly property int w800: Font.ExtraBold
}
