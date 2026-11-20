import QtQuick

// Shared gruvbox-dark palette for the whole shell. The clipboard column is the
// reference look; every panel and the bar read their colors from here so they
// can't drift apart.
QtObject {
    readonly property color bg: "#282828"      // bg0, card background
    readonly property color row: "#1d2021"     // bg0_h, list rows
    readonly property color hover: "#3c3836"   // bg1, hover / selection
    readonly property color border: "#504945"  // bg2, weak borders
    readonly property color fg: "#ebdbb2"      // fg
    readonly property color muted: "#a89984"   // fg4
    readonly property color accent: "#78824b"  // olive accent

    readonly property string font: "JetBrains Mono"
    readonly property int barHeight: 30
    readonly property int panelWidth: 380
}
