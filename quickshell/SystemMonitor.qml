import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// System monitor panel — serpantinum-style circular gauges: each metric is an
// icon in a ring, and how full the ring is = current usage.
// Metrics: cpu, ram, disk, temp. One probe script polls them all.
SidePanelWindow {
    id: sysmon

    property var shell
    open: !!sysmon.shell && sysmon.shell.sysmonOpen
    title: "system monitor"
    namespace: "quickshell-sysmon"

    property real cpu: 0
    property real ram: 0
    property real disk: 0
    // temperature in °C; the ring is scaled to 0–100°C
    property real temp: 0

    onOpenChanged: if (open) sysProbe.running = true

    Timer {
        interval: 500
        running: sysmon.open
        repeat: true
        onTriggered: sysProbe.running = true
    }

    // One script collects everything: cpu needs a delta, so it samples
    // /proc/stat twice a beat apart; the rest are single reads.
    Process {
        id: sysProbe
        command: ["sh", "-c",
            "cpu() { awk '/^cpu /{b=$2+$3+$4+$7+$8+$9; t=b+$5+$6; print b, t}' /proc/stat; }; " +
            "set -- $(cpu); b1=$1; t1=$2; sleep 0.3; set -- $(cpu); " +
            "echo \"cpu $(( ($1-b1) * 100 / ($2-t1) ))\"; " +
            "awk '/^MemTotal/{t=$2}/^MemAvailable/{a=$2}END{print \"ram\", int((t-a)*100/t)}' /proc/meminfo; " +
            "echo \"disk $(df / | awk 'NR==2{print $5}' | tr -d '%')\"; " +
            "t=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo 0); echo \"temp $((t/1000))\""
        ]
        stdout: SplitParser {
            onRead: line => {
                var p = line.trim().split(" ");
                if (p.length === 2)
                    sysmon[p[0]] = parseFloat(p[1]) || 0;
            }
        }
    }

    // ring gauge: usage ring around a centred label; the ring redraws on
    // value changes with an eased fill so spikes don't jump
    component Gauge: Item {
        id: gauge

        property real value: 0
        property real shown: 0
        property string icon: ""
        property string readout: ""
        readonly property Gruvbox pal: sysmon.pal
        readonly property bool hot: value >= 90

        Behavior on shown {
            NumberAnimation {
                duration: 600
                easing.type: Easing.OutCubic
            }
        }
        onValueChanged: gauge.shown = gauge.value

        width: 96
        height: 110

        Item {
            id: ringArea
            width: 84
            height: 84
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter

            Canvas {
                id: ring
                anchors.fill: parent
                antialiasing: true
                onPaint: {
                    var ctx = getContext("2d");
                    var cx = width / 2, cy = height / 2;
                    var r = Math.min(cx, cy) - 5;
                    ctx.reset();
                    ctx.lineWidth = 5;
                    // full track
                    ctx.strokeStyle = gauge.pal.border;
                    ctx.beginPath();
                    ctx.arc(cx, cy, r, 0, 2 * Math.PI);
                    ctx.stroke();
                    // usage arc, starting at 12 o'clock
                    if (gauge.shown > 0) {
                        ctx.strokeStyle = gauge.hot ? "#fb4934" : gauge.pal.accent;
                        ctx.beginPath();
                        ctx.arc(cx, cy, r, -Math.PI / 2,
                                -Math.PI / 2 + gauge.shown * 2 * Math.PI / 100);
                        ctx.stroke();
                    }
                }
                Connections {
                    target: gauge
                    function onShownChanged() { ring.requestPaint(); }
                }
            }

            Canvas {
                id: iconCanvas
                width: 28
                height: 28
                anchors.centerIn: parent

                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    ctx.strokeStyle = gauge.hot ? "#fb4934" : gauge.pal.fg;
                    ctx.fillStyle = ctx.strokeStyle;
                    ctx.lineWidth = 1.8;
                    ctx.lineCap = "round";
                    ctx.lineJoin = "round";

                    // same hand-drawn set as the bar (its ram widget is the
                    // reference), scaled up for the rings
                    if (gauge.icon === "cpu") {
                        ctx.strokeRect(9, 9, 10, 10);
                        ctx.strokeRect(12.5, 12.5, 3, 3);
                        ctx.beginPath();
                        // pins: 3 per side
                        for (var i = 0; i < 3; i++) {
                            var p = 11.5 + i * 2.5;
                            ctx.moveTo(p, 6.5); ctx.lineTo(p, 9);
                            ctx.moveTo(p, 19); ctx.lineTo(p, 21.5);
                            ctx.moveTo(6.5, p); ctx.lineTo(9, p);
                            ctx.moveTo(19, p); ctx.lineTo(21.5, p);
                        }
                        ctx.stroke();
                    } else if (gauge.icon === "ram") {
                        // memory stick, 2x the bar's icon
                        ctx.lineWidth = 2;
                        ctx.strokeRect(3, 7, 22, 13);
                        ctx.beginPath();
                        ctx.moveTo(7, 20); ctx.lineTo(7, 24.5);
                        ctx.moveTo(14, 20); ctx.lineTo(14, 24.5);
                        ctx.moveTo(21, 20); ctx.lineTo(21, 24.5);
                        // chip dividers
                        ctx.moveTo(10.3, 10.5); ctx.lineTo(10.3, 16.5);
                        ctx.moveTo(17.7, 10.5); ctx.lineTo(17.7, 16.5);
                        ctx.stroke();
                    } else if (gauge.icon === "disk") {
                        // drive: rounded body, activity LED, slot line
                        ctx.beginPath();
                        ctx.moveTo(6.5, 9);
                        ctx.lineTo(21.5, 9);
                        ctx.quadraticCurveTo(23.5, 9, 23.5, 11);
                        ctx.lineTo(23.5, 17);
                        ctx.quadraticCurveTo(23.5, 19, 21.5, 19);
                        ctx.lineTo(6.5, 19);
                        ctx.quadraticCurveTo(4.5, 19, 4.5, 17);
                        ctx.lineTo(4.5, 11);
                        ctx.quadraticCurveTo(4.5, 9, 6.5, 9);
                        ctx.stroke();
                        ctx.beginPath();
                        ctx.arc(19.5, 14, 1.6, 0, 2 * Math.PI);
                        ctx.fill();
                        ctx.beginPath();
                        ctx.moveTo(7.5, 14); ctx.lineTo(14.5, 14);
                        ctx.stroke();
                    } else if (gauge.icon === "temp") {
                        // thermometer: stem + bulb + ticks
                        ctx.beginPath();
                        ctx.arc(14, 6.8, 1.9, Math.PI, 0);
                        ctx.moveTo(12.1, 6.8); ctx.lineTo(12.1, 16.5);
                        ctx.moveTo(15.9, 6.8); ctx.lineTo(15.9, 16.5);
                        ctx.stroke();
                        ctx.beginPath();
                        ctx.arc(14, 18.4, 3.4, 0, 2 * Math.PI);
                        ctx.fill();
                        ctx.beginPath();
                        ctx.moveTo(18.2, 9.5); ctx.lineTo(20.2, 9.5);
                        ctx.moveTo(18.2, 12.8); ctx.lineTo(20.2, 12.8);
                        ctx.moveTo(18.2, 16); ctx.lineTo(20.2, 16);
                        ctx.stroke();
                    }
                }
                Connections {
                    target: gauge
                    function onHotChanged() { iconCanvas.requestPaint(); }
                }
            }
        }

        Text {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            text: gauge.readout
            color: gauge.pal.muted
            font.family: gauge.pal.font
            font.pixelSize: 10
        }
    }

    Item {
        anchors.fill: parent

        Column {
            anchors.fill: parent
            spacing: 12

        Item {
            width: parent.width
            height: 2 * 110 + 16

            Grid {
                anchors.centerIn: parent
                columns: 2
                columnSpacing: 40
                rowSpacing: 16

                Gauge {
                    icon: "cpu"
                    value: sysmon.cpu
                    readout: Math.round(sysmon.cpu) + "%"
                }
                Gauge {
                    icon: "ram"
                    value: sysmon.ram
                    readout: Math.round(sysmon.ram) + "%"
                }
                Gauge {
                    icon: "disk"
                    value: sysmon.disk
                    readout: Math.round(sysmon.disk) + "%"
                }
                Gauge {
                    icon: "temp"
                    value: Math.min(sysmon.temp, 100)
                    readout: Math.round(sysmon.temp) + "°C"
                }
            }
        }

            Text {
                width: parent.width
                height: 14
                // polling every 0.5s · esc closes the panel
                text: "esc close"
                color: sysmon.pal.muted
                font.family: sysmon.pal.font
                font.pixelSize: 9
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }

        // esc closes like every other panel
        Item {
            anchors.fill: parent
            focus: sysmon.open
            Keys.onEscapePressed: sysmon.shell.closeAllBut("")
        }
    }
}
