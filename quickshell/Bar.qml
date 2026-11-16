import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Networking
import QtQuick
import QtQuick.Layouts

PanelWindow {
    id: bar

    property var shell
    property var wifiDev: null
    property string ssid: ""
    property real signalStrength: 0

    // sound state, driven by wpctl (quickshell's pipewire node binding is broken in 0.3.1)
    property int volPercent: 0
    property bool muted: false
    // false while the audio backend (pipewire) is unreachable, so the bar shows "vol --"
    // instead of pretending the sink is at 0%
    property bool volOk: true

    // ram state, read straight from /proc/meminfo (no extra tools required)
    property real ramTotalKb: 0
    property real ramAvailKb: 0
    property int ramPercent: 0

    // flowstate focus timer, written by ~/.config/hypr/flowstate.sh
    property string flowPhase: "idle"
    property int flowSeconds: 0
    property bool flowPaused: false

    readonly property Miasma pal: Miasma {}

    anchors {
        top: true
        left: true
        right: true
    }

    // when the clipboard centre (gruvbox column, 380px) is open, pull the
    // bar's right edge out of the way with the same slide timing
    margins.right: shell.clipboardOpen ? 380 : 0
    Behavior on margins.right {
        NumberAnimation {
            duration: 200
            easing.type: Easing.OutCubic
        }
    }

    implicitHeight: pal.barHeight
    color: "transparent"
    exclusiveZone: pal.barHeight
    exclusionMode: ExclusionMode.Normal
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-bar"

    // ---------------------------------------------------------------- wifi state
    function findWifiDevice() {
        var list = Networking.devices.values.filter(d => d.type == DeviceType.Wifi);
        if (list.length > 0 && bar.wifiDev === null)
            bar.wifiDev = list[0];
    }

    readonly property bool wifiConnected: wifiDev !== null && wifiDev.connected

    function wifiLabel() {
        if (!bar.wifiDev)
            return "offline";
        if (bar.wifiConnected && bar.ssid.length > 0)
            return bar.ssid;
        return "not connected";
    }

    function refreshWifi() {
        bar.findWifiDevice();
        var d = bar.wifiDev;
        if (!d || !d.connected) {
            bar.ssid = "";
            bar.signalStrength = 0;
            return;
        }
        var hit = d.networks.values.filter(n => n.connected)[0];
        if (hit) {
            bar.ssid = hit.name || "connected";
            bar.signalStrength = hit.signalStrength;
        }
    }

    Component.onCompleted: {
        refreshWifi();
        volProbe.running = true;
        ramProbe.running = true;
    }

    function flowAction(cmd) {
        Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/hypr/flowstate.sh", cmd]);
    }

    // flowstate: reads "phase seconds [paused]" from flowstate.sh's state file
    Process {
        id: flowProbe
        command: ["cat", Quickshell.env("HOME") + "/.local/state/flowstate/bar"]
        stdout: SplitParser {
            onRead: line => {
                var p = line.trim().split(" ");
                bar.flowPhase = p[0] || "idle";
                bar.flowSeconds = parseInt(p[1]) || 0;
                bar.flowPaused = p[2] === "paused";
            }
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: {
            bar.refreshWifi();
            if (bar.wifiDev === null)
                bar.findWifiDevice();
        }
    }

    // ---------------------------------------------------------------- sound via wpctl
    Process {
        id: volProbe
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
        stdout: SplitParser {
            onRead: line => {
                var m = line.match(/Volume:\s*([\d.]+)/);
                if (m) {
                    bar.volOk = true;
                    bar.volPercent = Math.round(parseFloat(m[1]) * 100);
                    bar.muted = line.indexOf("MUTED") >= 0;
                }
            }
        }
        onExited: code => { if (code !== 0) bar.volOk = false; }
    }

    Process {
        id: volSet
        command: ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "10%+"]
    }

    Process {
        id: muteOffProc
        command: ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "0"]
    }

    Process {
        id: muteToggleProc
        command: ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: volProbe.running = true
    }

    Timer {
        id: afterVol
        interval: 200
        repeat: false
        onTriggered: volProbe.running = true
    }

    // coalesces a burst of wheel events into one wpctl call (wpctl starts in ~30ms,
    // wheel events can arrive faster than that, so an immediate start would race)
    Timer {
        id: volBumpTimer
        interval: 40
        repeat: false
        onTriggered: {
            volSet.running = false;
            volSet.running = true;
            afterVol.restart();
        }
    }

    // bump ±10% on the sink itself so repeated quick scrolls accumulate correctly;
    // reading bar.volPercent as the base would reuse a possibly 2s-stale value
    function bumpVolume(up) {
        volSet.command = ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", up ? "10%+" : "10%-"];
        if (up && bar.muted)
            muteOffProc.running = true;
        volBumpTimer.restart();
    }

    // ---------------------------------------------------------------- ram via /proc/meminfo
    Process {
        id: ramProbe
        command: ["cat", "/proc/meminfo"]
        stdout: SplitParser {
            onRead: line => {
                var m = line.match(/^(\w+):\s+(\d+)/);
                if (!m)
                    return;
                if (m[1] === "MemTotal")
                    bar.ramTotalKb = parseInt(m[2]);
                else if (m[1] === "MemAvailable")
                    bar.ramAvailKb = parseInt(m[2]);
            }
        }
        onRunningChanged: {
            if (running) {
                bar.ramTotalKb = 0;
                bar.ramAvailKb = 0;
                return;
            }
            if (bar.ramTotalKb > 0)
                bar.ramPercent = Math.round((bar.ramTotalKb - bar.ramAvailKb) / bar.ramTotalKb * 100);
        }
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: ramProbe.running = true
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: flowProbe.running = true
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // ================================================================ content
    Item {
        id: barContent
        anchors.fill: parent

        // -------------------------------------------------- LEFT: logo + workspaces
        Row {
            id: leftGroup
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            // Arch Linux mark -> Fuzzel app launcher
            Rectangle {
                id: logoBox
                width: 20
                height: 20
                radius: 4
                color: logoMouse.containsMouse ? bar.pal.bg2 : "transparent"

                // Real Arch Linux mark, loaded from arch.svg next to this file.
                Image {
                    anchors.centerIn: parent
                    width: 17
                    height: 17
                    source: Qt.resolvedUrl("arch.svg")
                    sourceSize: Qt.size(width * 2, height * 2)
                    fillMode: Image.PreserveAspectFit
                    mipmap: true
                    smooth: true
                }

                MouseArea {
                    id: logoMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: bar.shell.openAppLauncher()
                }
            }

            // workspaces 1-4
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                // Scratchpad-aware focused workspace. When a special workspace
                // (id < 0) is toggled on top, keep the underlying workspace's
                // pill lit so the bar looks unchanged.
                property int focusedRegularWs: {
                    const id = Hyprland.focusedWorkspace?.id;
                    return id > 0 ? id : focusedRegularWs;
                }

                Repeater {
                    model: [1, 2, 3, 4, 5]

                    delegate: Item {
                        id: wsPill
                        required property int modelData
                        readonly property bool focused: leftGroup.focusedRegularWs === wsPill.modelData

                        width: 14
                        height: 19

                        Text {
                            anchors.centerIn: parent
                            text: wsPill.modelData
                            color: bar.pal.fg1
                            font.family: bar.pal.font
                            font.pixelSize: 11
                            font.bold: wsPill.focused
                        }

                        MouseArea {
                            id: wsHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Hyprland.dispatch("hl.dsp.focus({workspace = \"" + wsPill.modelData + "\"})")
                        }
                    }
                }
            }
        }

        // -------------------------------------------------- CENTER: clock + calendar
        Row {
            id: centerGroup
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter

            Text {
                id: clockText
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDateTime(clock.date, "h:mm AP")
                color: bar.pal.fg1
                font.family: bar.pal.font
                font.pixelSize: 12
                font.bold: true
            }

            Text {
                id: dateText
                anchors.verticalCenter: parent.verticalCenter
                text: "· " + Qt.formatDate(clock.date, "ddd, MMM d")
                color: bar.pal.fg1
                font.family: bar.pal.font
                font.pixelSize: 11

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: bar.shell.closeAllBut(bar.shell.calendarOpen ? "" : "calendar")
                }
            }
        }

        // -------------------------------------------------- RIGHT: flowstate + ram + wifi + sound
        Row {
            id: rightGroup
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12

            // ---- flowstate: click open/close, middle pause/resume, right stop ----
            Rectangle {
                id: flowWidget
                anchors.verticalCenter: parent.verticalCenter
                width: flowRow.implicitWidth + 8
                height: 22
                radius: 0
                color: flowMouse.containsMouse ? bar.pal.bg2 : "transparent"

                Row {
                    id: flowRow
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "⌖"
                        color: bar.flowPhase === "idle" ? bar.pal.fg1
                            : bar.flowPhase === "focus" ? bar.pal.fg1
                            : "#f7768e"
                        font.family: bar.pal.font
                        font.pixelSize: 12
                        font.bold: bar.flowPhase !== "idle"
                    }

                    Text {
                        visible: bar.flowPhase !== "idle"
                        anchors.verticalCenter: parent.verticalCenter
                        text: Math.floor(Math.max(0, bar.flowSeconds) / 60) + ":"
                              + ("0" + (Math.max(0, bar.flowSeconds) % 60)).slice(-2)
                        color: bar.flowPaused ? bar.pal.gray
                            : bar.flowPhase === "focus" ? bar.pal.fg1
                            : "#f7768e"
                        font.family: bar.pal.font
                        font.pixelSize: 11
                    }
                }

                MouseArea {
                    id: flowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                    onClicked: mouse => {
                        if (mouse.button === Qt.MiddleButton) {
                            bar.flowAction("pause");
                        } else if (mouse.button === Qt.RightButton) {
                            bar.flowAction("stop");
                        } else {
                            bar.flowAction("toggle");
                        }
                    }
                }
            }

            // ---- clipboard: opens the clipboard history panel ----
            Rectangle {
                id: clipWidget
                anchors.verticalCenter: parent.verticalCenter
                width: 26
                height: 22
                radius: 0
                color: clipMouse.containsMouse ? bar.pal.bg2 : "transparent"

                Canvas {
                    id: clipIcon
                    width: 14
                    height: 14
                    anchors.centerIn: parent

                    property color tint: bar.shell.clipboardOpen ? "#78824b" : bar.pal.fg1

                    onTintChanged: requestPaint()

                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.reset();
                        ctx.strokeStyle = tint;
                        ctx.lineWidth = 1.2;
                        // board
                        ctx.strokeRect(2.5, 2.5, 9, 10);
                        // clip on top
                        ctx.strokeRect(5.5, 0.8, 3, 3);
                    }
                }

                MouseArea {
                    id: clipMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: bar.shell.openClipboard()
                }
            }

            // ---- ram: reads /proc/meminfo ----
            Rectangle {
                id: ramWidget
                anchors.verticalCenter: parent.verticalCenter
                width: ramRow.implicitWidth + 8
                height: 22
                radius: 0
                color: "transparent"

                Row {
                    id: ramRow
                    anchors.centerIn: parent
                    spacing: 5

                    // tiny memory stick icon
                    Canvas {
                        id: ramIcon
                        width: 14
                        height: 14
                        anchors.verticalCenter: parent.verticalCenter

                        property color tint: bar.pal.fg1

                        onTintChanged: requestPaint()

                        onPaint: {
                            var ctx = getContext("2d");
                            ctx.reset();
                            ctx.strokeStyle = tint;
                            ctx.lineWidth = 1.2;
                            ctx.strokeRect(1.5, 3.5, 11, 6.5);
                            ctx.beginPath();
                            ctx.moveTo(3.5, 10);
                            ctx.lineTo(3.5, 12.5);
                            ctx.moveTo(7, 10);
                            ctx.lineTo(7, 12.5);
                            ctx.moveTo(10.5, 10);
                            ctx.lineTo(10.5, 12.5);
                            ctx.stroke();
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: bar.ramPercent + "%"
                        color: bar.pal.fg1
                        font.family: bar.pal.font
                        font.pixelSize: 11
                    }
                }
            }

            // ---- wifi ----
            Rectangle {
                id: wifiWidget
                anchors.verticalCenter: parent.verticalCenter
                width: wifiRow.implicitWidth + 8
                height: 22
                radius: 0
                color: "transparent"

                Row {
                    id: wifiRow
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: bar.wifiConnected
                            ? "wifi " + Math.round(bar.signalStrength * 100) + "%"
                            : "wifi off"
                        color: bar.wifiConnected ? bar.pal.fg1 : bar.pal.gray
                        font.family: bar.pal.font
                        font.pixelSize: 11
                    }

                }

                MouseArea {
                    id: wifiMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: bar.shell.openWifiMenu()
                }
            }

            // ---- sound: scroll to change volume, click for devices ----
            Rectangle {
                id: audioWidget
                anchors.verticalCenter: parent.verticalCenter
                width: soundRow.implicitWidth + 8
                height: 22
                radius: 0
                color: "transparent"

                Row {
                    id: soundRow
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: bar.volOk ? "vol " + bar.volPercent + "%" : "vol --"
                        color: (bar.muted || !bar.volOk) ? bar.pal.gray : bar.pal.fg1
                        font.family: bar.pal.font
                        font.pixelSize: 11
                    }

                }

                MouseArea {
                    id: audioMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                    onClicked: mouse => {
                        if (mouse.button === Qt.MiddleButton) {
                            muteToggleProc.running = true;
                            afterVol.restart();
                        } else {
                            bar.shell.openAudioMenu();
                        }
                    }
                    onWheel: wheel => {
                        bar.bumpVolume(wheel.angleDelta.y > 0);
                        wheel.accepted = true;
                    }
                }
            }
        }
    }
}
