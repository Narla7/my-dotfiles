import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

// Audio panel (caelestia-style): output/input volume + mute, device pickers and
// per-app volumes. Everything goes through wpctl — Quickshell's PipeWire node
// binding is broken in 0.3.x (same workaround as the bar's volume widget).
SidePanelWindow {
    id: audioPanel

    property var shell
    open: !!audioPanel.shell && audioPanel.shell.audioOpen
    title: "audio"
    actionText: audioPanel.tab === "apps" ? "" : (audioPanel.activeMuted ? "unmute" : "mute")
    namespace: "quickshell-audio"

    // output / input / apps
    property string tab: "output"

    property int sinkVol: 0
    property bool sinkMuted: false
    property int srcVol: 0
    property bool srcMuted: false
    property string sinkName: ""
    property string sourceName: ""

    property var sinks: []
    property var sources: []
    property var streams: []

    // true while a slider is being dragged / just released, so the poll timer
    // can't yank the value back out from under the pointer
    property bool dragging: false

    readonly property bool activeMuted: audioPanel.tab === "input" ? audioPanel.srcMuted : audioPanel.sinkMuted
    readonly property int activeVol: audioPanel.tab === "input" ? audioPanel.srcVol : audioPanel.sinkVol

    readonly property string sinkTarget: "@DEFAULT_AUDIO_SINK@"
    readonly property string sourceTarget: "@DEFAULT_AUDIO_SOURCE@"
    readonly property string target: audioPanel.tab === "input" ? audioPanel.sourceTarget : audioPanel.sinkTarget

    onOpenChanged: if (open) audioPanel.refresh()

    onActionClicked: {
        if (audioPanel.tab === "apps")
            return;
        audioPanel.toggleMute(audioPanel.target);
    }

    // ---------------------------------------------------------------- refresh
    function refresh() {
        if (!statusProc.running)
            statusProc.running = true;
    }

    function parseStatus(text) {
        var lines = text.split("\n");
        var section = "";
        var prev = {};
        audioPanel.streams.forEach(function (s) { prev[s.id] = s; });

        var newSinks = [];
        var newSources = [];
        var newStreams = [];
        var defaultSink = "";
        var defaultSource = "";

        for (var i = 0; i < lines.length; i++) {
            var raw = lines[i];
            var t = raw.trim();

            if (t === "Video" || t === "Settings") {
                section = "";
                continue;
            }
            if (t.indexOf("Sinks:") >= 0) { section = "sinks"; continue; }
            if (t.indexOf("Sources:") >= 0) { section = "sources"; continue; }
            if (t.indexOf("Streams:") >= 0) { section = "streams"; continue; }
            if (t.indexOf("Devices:") >= 0 || t.indexOf("Filters:") >= 0
                    || t.indexOf("Clients:") >= 0 || t === "Audio") {
                section = "";
                continue;
            }

            // strip the tree drawing so the same regex works in every section
            var clean = raw.replace(/[│├└─]/g, " ").trim();
            if (clean === "")
                continue;

            var m = clean.match(/^(\*)?\s*(\d+)\.\s+(.+)$/);
            if (!m)
                continue;

            var id = m[2];
            var starred = m[1] === "*";
            var name = m[3].replace(/\s*\[vol:.*$/, "").trim();

            if (section === "sinks") {
                newSinks.push({ id: id, name: name, active: starred });
                if (starred)
                    defaultSink = name;
            } else if (section === "sources") {
                newSources.push({ id: id, name: name, active: starred });
                if (starred)
                    defaultSource = name;
            } else if (section === "streams") {
                // port lines look like "66. output_FL > sink:playback_FL"
                if (clean.indexOf(">") >= 0)
                    continue;
                newStreams.push({
                    id: id,
                    name: name,
                    volume: prev[id] ? prev[id].volume : 0,
                    muted: prev[id] ? prev[id].muted : false
                });
            }
        }

        audioPanel.sinks = newSinks;
        audioPanel.sources = newSources;
        audioPanel.streams = newStreams;
        audioPanel.sinkName = defaultSink;
        audioPanel.sourceName = defaultSource;
    }

    // one shell call for the defaults + every stream, so a poll is 2 processes
    function probeVolumes() {
        if (volProc.running)
            return;
        var script = "printf 'sink:'; wpctl get-volume @DEFAULT_AUDIO_SINK@;"
            + " printf 'source:'; wpctl get-volume @DEFAULT_AUDIO_SOURCE@;";
        for (var i = 0; i < audioPanel.streams.length; i++)
            script += " printf '" + audioPanel.streams[i].id + ":'; wpctl get-volume " + audioPanel.streams[i].id + ";";
        volProc.command = ["bash", "-c", script];
        volProc.running = true;
    }

    function applyVolumeText(text) {
        var lines = text.split("\n");
        var streamVols = {};
        for (var i = 0; i < lines.length; i++) {
            var m = lines[i].match(/^([^:]+):Volume:\s*([\d.]+)(\s+\[MUTED\])?\s*$/);
            if (!m)
                continue;
            var pct = Math.round(parseFloat(m[2]) * 100);
            var muted = !!m[3];
            if (m[1] === "sink") {
                audioPanel.sinkVol = pct;
                audioPanel.sinkMuted = muted;
            } else if (m[1] === "source") {
                audioPanel.srcVol = pct;
                audioPanel.srcMuted = muted;
            } else {
                streamVols[m[1]] = { volume: pct, muted: muted };
            }
        }

        var updated = audioPanel.streams.map(function (s) {
            var v = streamVols[s.id];
            return v ? { id: s.id, name: s.name, volume: v.volume, muted: v.muted } : s;
        });
        audioPanel.streams = updated;
    }

    Process {
        id: statusProc
        command: ["wpctl", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                audioPanel.parseStatus(text);
                audioPanel.probeVolumes();
            }
        }
    }

    Process {
        id: volProc
        command: []
        stdout: StdioCollector {
            onStreamFinished: audioPanel.applyVolumeText(text)
        }
    }

    // ---------------------------------------------------------------- actions
    function updateStreamVolume(id, pct) {
        audioPanel.streams = audioPanel.streams.map(function (s) {
            return s.id === id ? { id: s.id, name: s.name, volume: pct, muted: false } : s;
        });
    }

    function setVolume(target, ratio) {
        var clamped = Math.max(0, Math.min(1, ratio));
        var pct = Math.round(clamped * 100);

        audioPanel.dragging = true;
        settle.restart();

        // optimistic repaint, so dragging feels immediate and the poll can't
        // fight the pointer
        if (target === audioPanel.sinkTarget) {
            audioPanel.sinkVol = pct;
            audioPanel.sinkMuted = false;
        } else if (target === audioPanel.sourceTarget) {
            audioPanel.srcVol = pct;
            audioPanel.srcMuted = false;
        } else {
            audioPanel.updateStreamVolume(target, pct);
        }

        pendingTarget = target;
        pendingValue = clamped;
        commitDebounce.restart();
    }

    property string pendingTarget: ""
    property real pendingValue: 0

    Timer {
        id: commitDebounce
        interval: 60
        onTriggered: {
            volumeProc.command = ["bash", "-c",
                "wpctl set-mute \"$1\" 0; wpctl set-volume \"$1\" \"$2\"",
                "audio-volume", audioPanel.pendingTarget, audioPanel.pendingValue.toFixed(2)];
            volumeProc.running = false;
            volumeProc.running = true;
        }
    }

    Timer {
        id: settle
        interval: 450
        onTriggered: {
            audioPanel.dragging = false;
            refreshSoon.restart();
        }
    }

    Timer {
        id: refreshSoon
        interval: 120
        onTriggered: audioPanel.refresh()
    }

    Process { id: volumeProc; command: [] }

    function toggleMute(target) {
        var muted;
        if (target === audioPanel.sinkTarget) {
            audioPanel.sinkMuted = !audioPanel.sinkMuted;
            muted = audioPanel.sinkMuted;
        } else if (target === audioPanel.sourceTarget) {
            audioPanel.srcMuted = !audioPanel.srcMuted;
            muted = audioPanel.srcMuted;
        } else {
            audioPanel.streams = audioPanel.streams.map(function (s) {
                if (s.id !== target)
                    return s;
                muted = !s.muted;
                return { id: s.id, name: s.name, volume: s.volume, muted: muted };
            });
        }

        muteProc.command = ["wpctl", "set-mute", target, "toggle"];
        muteProc.running = false;
        muteProc.running = true;
        refreshSoon.restart();
    }

    Process { id: muteProc; command: [] }

    function setDefault(target, id) {
        defaultProc.command = ["wpctl", "set-default", id];
        defaultProc.running = false;
        defaultProc.running = true;
        refreshSoon.restart();
    }

    Process { id: defaultProc; command: [] }

    // ------------------------------------------------------------- poll timer
    Timer {
        id: poll
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: audioPanel.open && !audioPanel.dragging
        onTriggered: audioPanel.refresh()
    }

    // ------------------------------------------------------------------ layout
    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        // tabs
        Row {
            spacing: 16

            Repeater {
                model: [
                    { key: "output", label: "output" },
                    { key: "input", label: "input" },
                    { key: "apps", label: "apps" }
                ]

                delegate: Item {
                    id: tabItem
                    required property var modelData

                    width: tabLabel.implicitWidth
                    height: 20

                    readonly property bool selected: audioPanel.tab === tabItem.modelData.key

                    Text {
                        id: tabLabel
                        anchors.verticalCenter: parent.verticalCenter
                        text: tabItem.modelData.key === "apps" && audioPanel.streams.length > 0
                            ? "apps (" + audioPanel.streams.length + ")"
                            : tabItem.modelData.label
                        color: tabItem.selected ? audioPanel.pal.accent
                            : (tabMouse.containsMouse ? audioPanel.pal.fg : audioPanel.pal.muted)
                        font.family: audioPanel.pal.font
                        font.pixelSize: 11
                        font.bold: tabItem.selected
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 1
                        color: audioPanel.pal.accent
                        visible: tabItem.selected
                    }

                    MouseArea {
                        id: tabMouse
                        anchors.fill: parent
                        anchors.margins: -3
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: audioPanel.tab = tabItem.modelData.key
                    }
                }
            }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: audioPanel.tab === "output" ? 0 : audioPanel.tab === "input" ? 1 : 2

            // ------------------------------------------------------ output tab
            ColumnLayout {
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        text: audioPanel.sinkMuted ? "muted" : audioPanel.sinkVol + "%"
                        color: audioPanel.sinkMuted ? "#f7768e" : audioPanel.pal.fg
                        font.family: audioPanel.pal.font
                        font.pixelSize: 16
                        font.bold: true
                    }

                    Item { Layout.fillWidth: true; height: 1 }

                    Text {
                        text: audioPanel.sinkMuted ? "unmute" : "mute"
                        color: muteOutMouse.containsMouse ? audioPanel.pal.fg : audioPanel.pal.muted
                        font.family: audioPanel.pal.font
                        font.pixelSize: 10

                        MouseArea {
                            id: muteOutMouse
                            anchors.fill: parent
                            anchors.margins: -4
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: audioPanel.toggleMute(audioPanel.sinkTarget)
                        }
                    }
                }

                PanelSlider {
                    Layout.fillWidth: true
                    pal: audioPanel.pal
                    value: audioPanel.sinkVol / 100
                    muted: audioPanel.sinkMuted
                    onMoved: v => audioPanel.setVolume(audioPanel.sinkTarget, v)
                }

                Text {
                    Layout.fillWidth: true
                    text: audioPanel.sinkName !== "" ? audioPanel.sinkName : "no output device"
                    color: audioPanel.pal.muted
                    font.family: audioPanel.pal.font
                    font.pixelSize: 9
                    elide: Text.ElideRight
                }

                RowLayout {
                    Layout.topMargin: 6
                    Layout.fillWidth: true

                    Text {
                        text: "OUTPUT DEVICES"
                        color: audioPanel.pal.muted
                        font.family: audioPanel.pal.font
                        font.pixelSize: 9
                        font.bold: true
                    }

                    Item { Layout.fillWidth: true; height: 1 }

                    Text {
                        text: "click to set default"
                        color: audioPanel.pal.muted
                        font.family: audioPanel.pal.font
                        font.pixelSize: 8
                    }
                }

                ListView {
                    id: sinkList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    model: audioPanel.sinks

                    delegate: Rectangle {
                        id: sinkRow
                        required property var modelData
                        width: sinkList.width
                        height: 32
                        color: sinkMouse.containsMouse ? audioPanel.pal.hover : audioPanel.pal.row

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 6
                            anchors.right: sinkSet.left
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            text: (sinkRow.modelData.active ? "* " : "") + sinkRow.modelData.name
                            color: sinkRow.modelData.active ? audioPanel.pal.accent : audioPanel.pal.fg
                            font.family: audioPanel.pal.font
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }

                        Text {
                            id: sinkSet
                            anchors.right: parent.right
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            text: sinkRow.modelData.active ? "default" : "set"
                            color: sinkRow.modelData.active ? audioPanel.pal.muted
                                : (sinkMouse.containsMouse ? audioPanel.pal.fg : audioPanel.pal.muted)
                            font.family: audioPanel.pal.font
                            font.pixelSize: 9

                            MouseArea {
                                id: sinkSetMouse
                                anchors.fill: parent
                                anchors.margins: -5
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (!sinkRow.modelData.active)
                                    audioPanel.setDefault(audioPanel.sinkTarget, sinkRow.modelData.id)
                            }
                        }

                        MouseArea {
                            id: sinkMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (!sinkRow.modelData.active)
                                audioPanel.setDefault(audioPanel.sinkTarget, sinkRow.modelData.id)
                        }
                    }
                }

                Text {
                    visible: audioPanel.sinks.length === 0
                    text: "no sinks"
                    color: audioPanel.pal.muted
                    font.family: audioPanel.pal.font
                    font.pixelSize: 10
                }
            }

            // ------------------------------------------------------- input tab
            ColumnLayout {
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        text: audioPanel.srcMuted ? "muted" : audioPanel.srcVol + "%"
                        color: audioPanel.srcMuted ? "#f7768e" : audioPanel.pal.fg
                        font.family: audioPanel.pal.font
                        font.pixelSize: 16
                        font.bold: true
                    }

                    Item { Layout.fillWidth: true; height: 1 }

                    Text {
                        text: audioPanel.srcMuted ? "unmute" : "mute"
                        color: muteInMouse.containsMouse ? audioPanel.pal.fg : audioPanel.pal.muted
                        font.family: audioPanel.pal.font
                        font.pixelSize: 10

                        MouseArea {
                            id: muteInMouse
                            anchors.fill: parent
                            anchors.margins: -4
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: audioPanel.toggleMute(audioPanel.sourceTarget)
                        }
                    }
                }

                PanelSlider {
                    Layout.fillWidth: true
                    pal: audioPanel.pal
                    value: audioPanel.srcVol / 100
                    muted: audioPanel.srcMuted
                    onMoved: v => audioPanel.setVolume(audioPanel.sourceTarget, v)
                }

                Text {
                    Layout.fillWidth: true
                    text: audioPanel.sourceName !== "" ? audioPanel.sourceName : "no input device"
                    color: audioPanel.pal.muted
                    font.family: audioPanel.pal.font
                    font.pixelSize: 9
                    elide: Text.ElideRight
                }

                RowLayout {
                    Layout.topMargin: 6
                    Layout.fillWidth: true

                    Text {
                        text: "INPUT DEVICES"
                        color: audioPanel.pal.muted
                        font.family: audioPanel.pal.font
                        font.pixelSize: 9
                        font.bold: true
                    }

                    Item { Layout.fillWidth: true; height: 1 }

                    Text {
                        text: "click to set default"
                        color: audioPanel.pal.muted
                        font.family: audioPanel.pal.font
                        font.pixelSize: 8
                    }
                }

                ListView {
                    id: sourceList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    model: audioPanel.sources

                    delegate: Rectangle {
                        id: sourceRow
                        required property var modelData
                        width: sourceList.width
                        height: 32
                        color: sourceMouse.containsMouse ? audioPanel.pal.hover : audioPanel.pal.row

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 6
                            anchors.right: sourceSet.left
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            text: (sourceRow.modelData.active ? "* " : "") + sourceRow.modelData.name
                            color: sourceRow.modelData.active ? audioPanel.pal.accent : audioPanel.pal.fg
                            font.family: audioPanel.pal.font
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }

                        Text {
                            id: sourceSet
                            anchors.right: parent.right
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            text: sourceRow.modelData.active ? "default" : "set"
                            color: sourceRow.modelData.active ? audioPanel.pal.muted
                                : (sourceMouse.containsMouse ? audioPanel.pal.fg : audioPanel.pal.muted)
                            font.family: audioPanel.pal.font
                            font.pixelSize: 9

                            MouseArea {
                                id: sourceSetMouse
                                anchors.fill: parent
                                anchors.margins: -5
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (!sourceRow.modelData.active)
                                    audioPanel.setDefault(audioPanel.sourceTarget, sourceRow.modelData.id)
                            }
                        }

                        MouseArea {
                            id: sourceMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (!sourceRow.modelData.active)
                                audioPanel.setDefault(audioPanel.sourceTarget, sourceRow.modelData.id)
                        }
                    }
                }

                Text {
                    visible: audioPanel.sources.length === 0
                    text: "no sources"
                    color: audioPanel.pal.muted
                    font.family: audioPanel.pal.font
                    font.pixelSize: 10
                }
            }

            // -------------------------------------------------------- apps tab
            ColumnLayout {
                spacing: 6

                Text {
                    Layout.fillWidth: true
                    text: audioPanel.streams.length === 0
                        ? "nothing is playing audio"
                        : "PER-APP VOLUME"
                    color: audioPanel.pal.muted
                    font.family: audioPanel.pal.font
                    font.pixelSize: 9
                    font.bold: true
                }

                ListView {
                    id: streamList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 4
                    model: audioPanel.streams

                    delegate: Rectangle {
                        id: streamRow
                        required property var modelData
                        width: streamList.width
                        height: 54
                        color: streamMouse.containsMouse ? audioPanel.pal.hover : audioPanel.pal.row

                        // hover only; declared first so the controls stay on top
                        MouseArea {
                            id: streamMouse
                            anchors.fill: parent
                            acceptedButtons: Qt.NoButton
                            hoverEnabled: true
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 6
                            spacing: 3

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Text {
                                    Layout.fillWidth: true
                                    text: streamRow.modelData.name
                                    color: streamRow.modelData.muted ? audioPanel.pal.muted : audioPanel.pal.fg
                                    font.family: audioPanel.pal.font
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                }

                                Text {
                                    text: streamRow.modelData.muted ? "muted" : streamRow.modelData.volume + "%"
                                    color: streamRow.modelData.muted ? "#f7768e" : audioPanel.pal.muted
                                    font.family: audioPanel.pal.font
                                    font.pixelSize: 9
                                }

                                Text {
                                    text: streamRow.modelData.muted ? "unmute" : "mute"
                                    color: streamMuteMouse.containsMouse ? audioPanel.pal.fg : audioPanel.pal.muted
                                    font.family: audioPanel.pal.font
                                    font.pixelSize: 9

                                    MouseArea {
                                        id: streamMuteMouse
                                        anchors.fill: parent
                                        anchors.margins: -4
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: audioPanel.toggleMute(streamRow.modelData.id)
                                    }
                                }
                            }

                            PanelSlider {
                                Layout.fillWidth: true
                                pal: audioPanel.pal
                                value: streamRow.modelData.volume / 100
                                muted: streamRow.modelData.muted
                                onMoved: v => audioPanel.setVolume(streamRow.modelData.id, v)
                            }
                        }
                    }
                }
            }
        }
    }

    // Esc closes
    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: audioPanel.shell.closeAllBut("")
    }
}
