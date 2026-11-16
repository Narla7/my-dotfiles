import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// Clipboard history panel, top-right below the bar. Backed by cliphist
// (wl-paste --watch cliphist store, started in hyprland.lua) so images work.
// Slides in fast from the right edge; never full-screen.
PanelWindow {
    id: clipWindow

    property var shell
    readonly property Miasma pal: Miasma {}
    readonly property int panelWidth: 380
    readonly property int panelHeight: 540
    readonly property int maxItems: 25
    // decode cache dir for image thumbnails
    readonly property string cacheDir: "/tmp/qs-clip"

    anchors {
        top: true
        right: true
    }
    margins.top: pal.barHeight + 6
    implicitWidth: panelWidth
    implicitHeight: shell.clipboardOpen ? panelHeight : 1
    color: "transparent"
    exclusiveZone: 0
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-clipboard"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

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

    onVisibleChanged: if (visible) clipWindow.refresh()

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

    function clearAll() {
        clearProc.running = true;
        clipModel.clear();
    }

    // cliphist calls this "wipe" ("clear" is not a real subcommand)
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
            height: clipWindow.panelHeight
            color: clipWindow.pal.bg1
            border.width: 1
            border.color: clipWindow.pal.bg3

            transform: Translate {
                id: slide
                x: clipWindow.shell.clipboardOpen ? 0 : clipWindow.panelWidth + 12
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
                        color: clipWindow.pal.fg
                        font.family: clipWindow.pal.font
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
                        color: clearMouse.containsMouse ? clipWindow.pal.bg2 : "transparent"
                        border.width: 1
                        border.color: clipWindow.pal.bg3

                        Text {
                            id: clearText
                            anchors.centerIn: parent
                            text: "clear all"
                            color: clipWindow.pal.fg1
                            font.family: clipWindow.pal.font
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
                        color: rowMouse.containsMouse ? clipWindow.pal.bg2 : clipWindow.pal.bg0

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
                            color: clipWindow.pal.fg
                            font.family: clipWindow.pal.font
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
                            color: clipWindow.pal.fg1
                            font.family: clipWindow.pal.font
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
                            color: xMouse.containsMouse ? clipWindow.pal.red : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: "✕"
                                color: xMouse.containsMouse ? clipWindow.pal.bg0 : clipWindow.pal.gray
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
