import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// Flowstate focus timer as a side panel. The session itself still runs in
// ~/.config/hypr/flowstate.sh (started headless: it just sleeps and writes
// "phase seconds [paused]" to ~/.local/state/flowstate/bar, which both this
// panel and the bar widget read) — the panel replaces the old kitty window.
SidePanelWindow {
    id: flowPanel

    property var shell
    open: !!flowPanel.shell && flowPanel.shell.flowstateOpen
    title: "flowstate"
    namespace: "quickshell-flowstate"

    // ---- session state, mirrored from the state file ----------------------
    property string phase: "idle"       // idle | focus | break
    property int seconds: 0
    property bool paused: false

    readonly property bool running: flowPanel.phase !== "idle"

    // finished focus blocks, tracked by watching focus→break transitions in
    // the state file (the script doesn't report cycle count itself)
    property int doneBlocks: 0
    property string lastPhase: "idle"
    // timestamp of the last Enter/primary press, for the debounce below
    property real lastPrimary: 0

    function fmt(s) {
        s = Math.max(0, s);
        return Math.floor(s / 60) + ":" + ("0" + (s % 60)).slice(-2);
    }

    // 4 cycles hardcoded for the dots — matches flowstate.sh's CYCLES default
    readonly property int cycles: 4

    onOpenChanged: if (open) flowProbe.running = true

    Timer {
        interval: 500
        running: flowPanel.open
        repeat: true
        onTriggered: flowProbe.running = true
    }

    // kick the probe a beat after an action, so the state file already
    // reflects it and the panel doesn't flash back to the pre-action state
    Timer {
        id: probeKick
        interval: 300
        onTriggered: {
            flowProbe.running = false;
            flowProbe.running = true;
        }
    }

    Process {
        id: flowProbe
        command: ["cat", Quickshell.env("HOME") + "/.local/state/flowstate/bar"]
        stdout: SplitParser {
            onRead: line => {
                var p = line.trim().split(" ");
                flowPanel.phase = p[0] || "idle";
                flowPanel.seconds = parseInt(p[1]) || 0;
                flowPanel.paused = p[2] === "paused";
                if (flowPanel.phase === "break" && flowPanel.lastPhase === "focus")
                    flowPanel.doneBlocks = Math.min(flowPanel.doneBlocks + 1, flowPanel.cycles);
                if (flowPanel.phase === "idle")
                    flowPanel.doneBlocks = 0;
                flowPanel.lastPhase = flowPanel.phase;
            }
        }
    }

    function action(cmd) {
        // optimistic UI: flip immediately, the probe confirms/corrects after
        // the script has written the new state
        if (cmd === "run") {
            flowPanel.phase = "focus";
            flowPanel.paused = false;
        } else if (cmd === "stop") {
            flowPanel.phase = "idle";
            flowPanel.paused = false;
            flowPanel.doneBlocks = 0;
        } else if (cmd === "pause") {
            flowPanel.paused = !flowPanel.paused;
        }
        Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/hypr/flowstate.sh", cmd]);
        probeKick.restart();
    }

    function togglePause() {
        if (flowPanel.running)
            flowPanel.action("pause");
    }

    // enter: start the session when idle, stop it when running
    function primaryAction() {
        // cooldown so key auto-repeat / double clicks can't stop-then-start
        var now = Date.now();
        if (now - (flowPanel.lastPrimary || 0) < 600)
            return;
        flowPanel.lastPrimary = now;
        if (flowPanel.running) {
            flowPanel.action("stop");
        } else {
            flowPanel.action("run");
        }
    }

    Item {
        anchors.fill: parent
        focus: true

        Keys.onPressed: event => {
            // ignore auto-repeat: holding a key must not stop-then-restart
            // the session
            if (event.isAutoRepeat)
                return;
            if (event.key === Qt.Key_Escape) {
                flowPanel.shell.closeAllBut("");
                event.accepted = true;
            } else if (event.key === Qt.Key_Space) {
                flowPanel.togglePause();
                event.accepted = true;
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                flowPanel.primaryAction();
                event.accepted = true;
            }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            spacing: 14

            // ---- big countdown / idle prompt ---------------------------------
            Item {
                width: parent.width
                height: 120

                Text {
                    visible: flowPanel.running
                    anchors.centerIn: parent
                    text: flowPanel.fmt(flowPanel.seconds)
                    color: flowPanel.paused ? flowPanel.pal.muted
                        : flowPanel.phase === "break" ? "#f7768e" : flowPanel.pal.accent
                    font.family: flowPanel.pal.font
                    font.pixelSize: 48
                    font.bold: true
                }

                Column {
                    visible: !flowPanel.running
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "⌖"
                        color: flowPanel.pal.muted
                        font.family: flowPanel.pal.font
                        font.pixelSize: 40
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "no session running"
                        color: flowPanel.pal.muted
                        font.family: flowPanel.pal.font
                        font.pixelSize: 11
                    }
                }
            }

            // ---- phase label --------------------------------------------------
            Text {
                width: parent.width
                visible: flowPanel.running
                text: flowPanel.paused ? "‖ paused"
                    : flowPanel.phase === "break" ? "☾ break"
                    : "⌖ focus"
                color: flowPanel.paused ? flowPanel.pal.muted
                    : flowPanel.phase === "break" ? "#f7768e" : flowPanel.pal.muted
                font.family: flowPanel.pal.font
                font.pixelSize: 11
                font.bold: true
            }

            // ---- session dots (filled = finished focus blocks) -----------------
            Row {
                width: parent.width
                visible: flowPanel.running
                spacing: 6

                Repeater {
                    model: flowPanel.cycles

                    delegate: Text {
                        required property int index
                        property bool done: index < flowPanel.doneBlocks
                        text: done ? "●" : "○"
                        color: done ? flowPanel.pal.accent : flowPanel.pal.muted
                        font.family: flowPanel.pal.font
                        font.pixelSize: 12
                    }
                }
            }

            // ---- primary button: start when idle, stop when running ------------
            Rectangle {
                width: parent.width
                height: 46
                radius: 0
                color: !flowPanel.running ? flowPanel.pal.accent
                    : primaryMouse.containsMouse ? flowPanel.pal.hover : flowPanel.pal.row
                border.width: 1
                border.color: flowPanel.running ? flowPanel.pal.border : flowPanel.pal.accent

                Text {
                    anchors.centerIn: parent
                    text: flowPanel.running ? "■  stop" : "▶  start"
                    color: flowPanel.running ? flowPanel.pal.fg : flowPanel.pal.bg
                    font.family: flowPanel.pal.font
                    font.pixelSize: 13
                    font.bold: true
                }

                MouseArea {
                    id: primaryMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: flowPanel.primaryAction()
                }
            }

            // ---- pause / resume --------------------------------------------------
            Rectangle {
                width: parent.width
                height: 38
                radius: 0
                visible: flowPanel.running
                color: pauseMouse.containsMouse ? flowPanel.pal.hover : flowPanel.pal.row
                border.width: 1
                border.color: flowPanel.pal.border

                Text {
                    anchors.centerIn: parent
                    text: flowPanel.paused ? "▶  resume" : "‖  pause"
                    color: flowPanel.pal.fg
                    font.family: flowPanel.pal.font
                    font.pixelSize: 12
                    font.bold: flowPanel.paused
                }

                MouseArea {
                    id: pauseMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: flowPanel.togglePause()
                }
            }

            Text {
                width: parent.width
                text: "4 × 25/5 min · enter start/stop · space pause · esc close"
                color: flowPanel.pal.muted
                font.family: flowPanel.pal.font
                font.pixelSize: 9
                horizontalAlignment: Text.AlignRight
            }
        }
    }
}
