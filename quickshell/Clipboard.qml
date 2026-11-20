import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// Clipboard history "centre": full-height column on the right edge, gruvbox.
// Reserves screen space via the spacer in shell.qml, so Hyprland slides
// tiled windows out of the way when it opens (windowsMove animation).
// Backed by cliphist (wl-paste --watch cliphist store, started in hyprland.lua).
SidePanelWindow {
    id: clipWindow

    property var shell
    open: !!clipWindow.shell && clipWindow.shell.clipboardOpen
    title: "clipboard"
    actionText: "clear all"
    namespace: "quickshell-clipboard"

    readonly property int maxItems: 25
    // decode cache dir for image thumbnails
    readonly property string cacheDir: "/tmp/qs-clip"

    onActionClicked: clipWindow.clearAll()

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

    // ---- history list ---------------------------------------------------
    ListView {
        id: list
        anchors.fill: parent
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
            color: rowMouse.containsMouse ? clipWindow.pal.hover : clipWindow.pal.row

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
                color: clipWindow.pal.muted
                font.family: clipWindow.pal.font
                font.pixelSize: 11
            }

            // per-item remove, centered on the right edge (text, no glyph icon)
            Text {
                id: xBtn
                z: 1
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: "del"
                color: xMouse.containsMouse ? clipWindow.pal.fg : clipWindow.pal.muted
                font.family: clipWindow.pal.font
                font.pixelSize: 10

                MouseArea {
                    id: xMouse
                    anchors.fill: parent
                    anchors.margins: -4
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

    // Esc closes
    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: clipWindow.shell.closeAllBut("")
    }
}
