import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// Clipboard history "centre": full-height column on the right edge, gruvbox.
// Reserves screen space via layer-shell exclusive zone, so Hyprland slides
// tiled windows out of the way when it opens (windowsMove animation).
// Backed by cliphist (wl-paste --watch cliphist store, started in hyprland.lua).
PanelWindow {
    id: clipWindow

    property var shell
    readonly property bool open: shell.clipboardOpen

    // gruvbox dark
    readonly property color gBg: "#282828"      // bg0
    readonly property color gBg1: "#3c3836"     // bg1 (hover)
    readonly property color gBgRow: "#1d2021"   // bg0_h (rows)
    readonly property color gBorder: "#504945"  // gray
    readonly property color gFg: "#ebdbb2"      // fg
    readonly property color gMuted: "#a89984"   // fg4
    readonly property color gRed: "#cc241d"
    readonly property color gAccent: "#78824b"  // olive accent, matches focus border / fuzzel

    readonly property int panelWidth: 380
    readonly property int maxItems: 25
    // decode cache dir for image thumbnails
    readonly property string cacheDir: "/tmp/qs-clip"

    anchors {
        right: true
        bottom: true
    }
    // full monitor height, bottom-anchored: not anchored top, so the bar's
    // exclusive zone can't push us down — the panel reaches y=0
    implicitHeight: clipWindow.screen.height
    // closed: shove the leftover surface offscreen so it can't eat clicks
    margins.right: open ? 0 : -16
    implicitWidth: open ? panelWidth : 15
    color: "transparent"
    // the spacer window (shell.qml) reserves the right edge; this one only draws
    exclusiveZone: -1
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-clipboard"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    Behavior on implicitWidth {
        NumberAnimation {
            duration: 200
            easing.type: Easing.OutCubic
        }
    }

    // ---- history model, filled by `cliphist list` --------------------
    ListModel { id: clipModel }

    function isImage(preview) {
        return preview.indexOf("binary data") >= 0;
    }

    function imageLabel(preview) {
        var m = preview.match(/extension (\w+)/);
        var s = preview.match(/size ([\d.]+ \w+)/);
        return "[ image" + (m ? " · " + m[1] : "") + (s ? " · " + s[1] : "") + " ]";
    }

    function refresh() {
        clipList.running = true;
    }

    // the window is always visible (open/close resizes it), so hook the
    // open state instead — re-list every time the centre opens
    onOpenChanged: if (open) clipWindow.refresh()

    Component.onCompleted: clipWindow.refresh()

    Process {
        id: clipList
        command: ["cliphist", "list"]
        stdout: SplitParser {
            onRead: line => {
                if (clipModel.count >= clipWindow.maxItems)
                    return;
                var tab = line.indexOf("\t");
                if (tab < 0)
                    return;
                clipModel.append({
                    id: line.slice(0, tab),
                    preview: line.slice(tab + 1),
                    line: line,
                    isImage: clipWindow.isImage(line),
                    label: clipWindow.imageLabel(line)
                });
            }
        }
        onRunningChanged: if (running) clipModel.clear()
    }

    // ---- actions ------------------------------------------------------
    // copy an entry back to the clipboard, then close the panel
    function copyItem(id, line) {
        Quickshell.execDetached(["bash", "-c",
            "printf '%s' \"$1\" | cliphist decode | wl-copy", "clipcopy", line]);
        clipWindow.shell.closeAllBut("");
    }

    function deleteItem(index, id, line) {
        Quickshell.execDetached(["bash", "-c",
            "printf '%s' \"$1\" | cliphist delete", "clipdel", line]);
        // cliphist renumbers remaining items after a delete, so re-list
        // instead of just dropping the row (keeps later copies/deletes valid)
        clipWindow.refresh();
    }

    // cliphist calls this "wipe" ("clear" is not a real subcommand)
    function clearAll() {
        clearProc.running = true;
    }

    Process {
        id: clearProc
        command: ["cliphist", "wipe"]
        onExited: clipWindow.refresh()
    }

    // ---- visual ---------------------------------------------------------
    // clipped container: the card slides in from the right edge inside it
    Item {
        id: clipArea
        anchors.fill: parent
        clip: true

        Rectangle {
            id: card
            width: clipWindow.panelWidth
            height: parent.height
            color: clipWindow.gBg
            border.width: 1
            border.color: clipWindow.gAccent

            transform: Translate {
                id: slide
                x: clipWindow.open ? 0 : clipWindow.panelWidth + 12
                Behavior on x {
                    NumberAnimation {
                        duration: 200
                        easing.type: Easing.OutCubic
                    }
                }
            }

            Column {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 8

                // header: title + clear all
                Item {
                    width: parent.width
                    height: 24

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "clipboard"
                        color: clipWindow.gAccent
                        font.family: "JetBrains Mono"
                        font.pixelSize: 13
                        font.bold: true
                    }

                    Rectangle {
                        id: clearBtn
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: clearText.implicitWidth + 14
                        height: 20
                        radius: 0
                        color: clearMouse.containsMouse ? clipWindow.gBg1 : "transparent"
                        border.width: 1
                        border.color: clipWindow.gBorder

                        Text {
                            id: clearText
                            anchors.centerIn: parent
                            text: "clear all"
                            color: clearMouse.containsMouse ? clipWindow.gFg : clipWindow.gMuted
                            font.family: "JetBrains Mono"
                            font.pixelSize: 10
                        }

                        MouseArea {
                            id: clearMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: clipWindow.clearAll()
                        }
                    }
                }

                // history list
                ListView {
                    id: list
                    width: parent.width
                    height: parent.height - 24 - 8
                    clip: true
                    spacing: 4
                    model: clipModel

                    delegate: Rectangle {
                        id: row
                        required property int index
                        required property var model

                        width: list.width
                        height: 52
                        radius: 0
                        color: rowMouse.containsMouse ? clipWindow.gBg1 : clipWindow.gBgRow

                        // decode image entries to the cache dir, then show them
                        Process {
                            id: decodeProc
                            command: ["bash", "-c",
                                "mkdir -p \"$2\"; [ -s \"$2/$3\" ] || printf '%s' \"$1\" | cliphist decode > \"$2/$3\"",
                                "clipdecode", row.model.line, clipWindow.cacheDir, row.model.id]
                            onExited: thumb.source = "file://" + clipWindow.cacheDir + "/" + row.model.id
                        }

                        Component.onCompleted: {
                            if (row.model.isImage)
                                decodeProc.running = true;
                        }

                        // text preview (single line) or image thumbnail
                        Text {
                            visible: !row.model.isImage
                            anchors.left: parent.left
                            anchors.right: xBtn.left
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.model.preview
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            color: clipWindow.gFg
                            font.family: "JetBrains Mono"
                            font.pixelSize: 11
                        }

                        Image {
                            id: thumb
                            visible: row.model.isImage
                            anchors.left: parent.left
                            anchors.leftMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            width: 64
                            height: 44
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                        }

                        Text {
                            visible: row.model.isImage
                            anchors.left: thumb.right
                            anchors.leftMargin: 10
                            anchors.right: xBtn.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.model.label
                            elide: Text.ElideRight
                            color: clipWindow.gMuted
                            font.family: "JetBrains Mono"
                            font.pixelSize: 11
                        }

                        // per-item remove button, centered on the right edge
                        Rectangle {
                            id: xBtn
                            z: 1
                            anchors.right: parent.right
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            width: 18
                            height: 18
                            radius: 9
                            color: xMouse.containsMouse ? clipWindow.gRed : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: "✕"
                                color: xMouse.containsMouse ? clipWindow.gBgRow : clipWindow.gMuted
                                font.pixelSize: 10
                            }

                            MouseArea {
                                id: xMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: clipWindow.deleteItem(row.index, row.model.id, row.model.line)
                            }
                        }

                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: clipWindow.copyItem(row.model.id, row.model.line)
                        }
                    }
                }
            }
        }
    }

    // Esc closes
    Item {
        focus: true
        Keys.onEscapePressed: clipWindow.shell.closeAllBut("")
    }
}
