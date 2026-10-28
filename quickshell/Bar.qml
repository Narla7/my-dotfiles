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
                    bar.volPercent = Math.round(parseFloat(m[1]) * 100);
                    bar.muted = line.indexOf("MUTED") >= 0;
                }
            }
        }
    }

    Process {
        id: volSet
        command: ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "50%"]
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

    function bumpVolume(delta) {
        var pct = Math.max(0, Math.min(100, bar.volPercent + (delta > 0 ? 10 : -10)));
        volSet.command = ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", pct + "%"];
        volSet.running = false;
        volSet.running = true;
        afterVol.restart();
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

                Repeater {
                    model: [1, 2, 3, 4, 5]

                    delegate: Item {
                        id: wsPill
                        required property int modelData
                        readonly property bool focused: Hyprland.focusedWorkspace !== null
                            && Hyprland.focusedWorkspace !== undefined
                            && Hyprland.focusedWorkspace.id === wsPill.modelData

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
                        text: "vol " + bar.volPercent + "%"
                        color: bar.muted ? bar.pal.gray : bar.pal.fg1
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
                        bar.bumpVolume(wheel.angleDelta.y > 0 ? 0.05 : -0.05);
                        wheel.accepted = true;
                    }
                }
            }
        }
    }
}
