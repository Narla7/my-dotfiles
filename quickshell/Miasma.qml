import QtQuick

// Miasma palette — Omarchy miasma theme (github.com/OldJobobo/omarchy-miasma-theme)
// colors.toml: bg #222222, fg #c2c2b0, accent(blue) #78824b, cursor #d7c483
QtObject {
    readonly property color bg0: "#222222"      // background
    readonly property color bg1: "#242d1d"      // lighter_bg (panel surface)
    readonly property color bg2: "#383838"      // selection
    readonly property color bg3: "#43492a"      // inactive-border olive
    readonly property color bg0a: Qt.rgba(0.133, 0.133, 0.133, 0.92) // #222222 @ 92%

    readonly property color fg: "#c2c2b0"
    readonly property color fg1: "#8a8a7e"      // muted
    readonly property color fg2: "#8a8a7e"
    readonly property color gray: "#666666"     // dark_fg
    readonly property color bright: "#d7c483"   // light_fg / cursor

    readonly property color red: "#685742"
    readonly property color green: "#5f875f"
    readonly property color yellow: "#b36d43"
    readonly property color gold: "#78824b"     // accent-blue (used where gold used to be)
    readonly property color blue: "#78824b"
    readonly property color purple: "#bb7744"
    readonly property color aqua: "#c9a554"     // miasma cyan
    readonly property color orange: "#b36d43"

    readonly property string font: "JetBrains Mono"
    readonly property int barHeight: 30
}