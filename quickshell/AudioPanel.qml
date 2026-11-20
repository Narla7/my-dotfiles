import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

// Audio panel: default sink volume slider + mute, and a sink picker.
// Driven by wpctl throughout — Quickshell's PipeWire node binding is broken
// in 0.3.x (same workaround as the bar's volume widget).
SidePanelWindow {
    id: audioPanel

    property var shell
    open: !!audioPanel.shell && audioPanel.shell.audioOpen
    title: "audio"
    actionText: "mute"
    namespace: "quickshell-audio"

    property int volPercent: 0
    property bool muted: false
    property bool dragging: false

    onActionClicked: {
        muteProc.running = true;
        afterChange.restart();
    }

    onOpenChanged: if (open) volProbe.running = true

    function setVolume(ratio) {
        var pct = Math.round(Math.max(0, Math.min(1, ratio)) * 100);
        audioPanel.volPercent = pct;
        if (pct > 0 && audioPanel.muted)
            unmuteProc.running = true;
        volSetProc.command = ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", (pct / 100).toFixed(2)];
        volSetProc.running = false;
        volSetProc.running = true;
        afterChange.restart();
    }

    Timer {
        id: afterChange
        interval: 250
        onTriggered: volProbe.running = true
    }

    // ---- default sink volume ---------------------------------------------
    Process {
        id: volProbe
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
        stdout: SplitParser {
            onRead: line => {
                var m = line.match(/Volume:\s*([\d.]+)/);
                if (m) {
                    audioPanel.volPercent = Math.round(parseFloat(m[1]) * 100);
                    audioPanel.muted = line.indexOf("MUTED") >= 0;
                }
            }
        }
    }

    Process { id: volSetProc; command: [] }
    Process { id: muteProc; command: ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"] }
    Process { id: unmuteProc; command: ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "0"] }

    // ---- sink list from wpctl status --------------------------------------
    ListModel { id: sinkModel }

    Process {
        id: sinkProbe
        command: ["bash", "-c", "wpctl status | sed -n '/Sinks:/,/Sources:/p'"]
        stdout: SplitParser {
            onRead: line => {
                var starred = line.indexOf("*") >= 0;
                var m = line.match(/^\s*\*?\s*(\d+)\.\s+(.*)$/);
                if (!m)
                    return;
                var name = m[2].replace(/\s*\[vol:.*$/, "");
                sinkModel.append({ id: m[1], name: name, isDefault: starred });
            }
        }
        onRunningChanged: if (running) sinkModel.clear()
    }

    function setDefaultSink(id) {
        defaultProc.command = ["wpctl", "set-default", id];
        defaultProc.running = false;
        defaultProc.running = true;
        afterChange.restart();
    }

    Process { id: defaultProc; command: [] }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        // ---- volume ----------------------------------------------------------
        RowLayout {
            width: parent.width

            Text {
                text: audioPanel.muted ? "muted" : audioPanel.volPercent + "%"
                color: audioPanel.muted ? "#f7768e" : audioPanel.pal.fg
                font.family: audioPanel.pal.font
                font.pixelSize: 14
                font.bold: true
            }

            Item { Layout.fillWidth: true; height: 1 }
        }

        // volume slider: click or drag to set
        Rectangle {
            id: volTrack
            Layout.fillWidth: true
            height: 10
            color: audioPanel.pal.row
            border.width: 1
            border.color: audioPanel.pal.border

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.margins: 1
                width: (parent.width - 2) * audioPanel.volPercent / 100
                color: audioPanel.muted ? audioPanel.pal.muted : audioPanel.pal.accent
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => audioPanel.setVolume(mouse.x / width)
                onPositionChanged: mouse => {
                    if (mouse.buttons & Qt.LeftButton)
                        audioPanel.setVolume(mouse.x / width);
                }
            }
        }

        Text {
            width: parent.width
            text: "default sink"
            color: audioPanel.pal.muted
            font.family: audioPanel.pal.font
            font.pixelSize: 10
        }

        // ---- sink list ---------------------------------------------------------
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            model: sinkModel

            delegate: Rectangle {
                id: row
                required property int index
                required property var model

                width: list.width
                height: 36
                color: rowMouse.containsMouse ? audioPanel.pal.hover : audioPanel.pal.row

                Text {
                    anchors.left: parent.left
                    anchors.right: defBtn.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: (row.model.isDefault ? "* " : "") + row.model.name
                    color: row.model.isDefault ? audioPanel.pal.accent : audioPanel.pal.fg
                    font.family: audioPanel.pal.font
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }

                Text {
                    id: defBtn
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.model.isDefault ? "default" : "set"
                    color: row.model.isDefault ? audioPanel.pal.muted
                        : (rowMouse.containsMouse ? audioPanel.pal.fg : audioPanel.pal.muted)
                    font.family: audioPanel.pal.font
                    font.pixelSize: 10

                    MouseArea {
                        id: defMouse
                        anchors.fill: parent
                        anchors.margins: -4
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (!row.model.isDefault)
                            audioPanel.setDefaultSink(row.model.id)
                    }
                }

                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (!row.model.isDefault)
                        audioPanel.setDefaultSink(row.model.id)
                }
            }
        }

        Text {
            visible: sinkModel.count === 0
            text: "no sinks"
            color: audioPanel.pal.muted
            font.family: audioPanel.pal.font
            font.pixelSize: 11
        }
    }
}
