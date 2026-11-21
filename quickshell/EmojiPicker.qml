import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// Emoji picker — replaces the old rofi script. Right-edge column like the
// launcher: search box on top, emoji grid below. Fully keyboard driven:
// arrows move in the grid (left/right = one emoji, up/down = one row),
// enter copies, ctrl+f toggles favourite, ctrl+shift+up/down reorders
// favourites. Mouse: click copies, wheel scrolls the whole grid.
// Favourites are one emoji per line in ~/.config/hypr/emoji-favorites.txt —
// the same file the old rofi picker used, so they carry over.
SidePanelWindow {
    id: picker

    property var shell
    open: !!picker.shell && picker.shell.emojiOpen
    title: "emoji"
    namespace: "quickshell-emoji"

    readonly property string stateHome: (Quickshell.env("XDG_STATE_HOME") || "").length > 0
        ? Quickshell.env("XDG_STATE_HOME")
        : Quickshell.env("HOME") + "/.local/state"
    readonly property string favFile: Quickshell.env("HOME") + "/.config/hypr/emoji-favorites.txt"
    readonly property string src: "/usr/share/noctalia/assets/emoji.json"

    readonly property int cols: 9
    property var all: []
    property var filtered: []
    property var favourites: []
    property int selected: 0

    Component.onCompleted: {
        jsonLoad.running = true;
        favLoad.running = true;
    }

    onOpenChanged: if (open) picker.reset()

    function isFavourite(emoji) {
        return picker.favourites.indexOf(emoji) >= 0;
    }

    function matches(entry, q) {
        return q.length === 0
            || entry.name.toLowerCase().indexOf(q) >= 0
            || entry.keywords.some(function(k) { return k.toLowerCase().indexOf(q) >= 0; });
    }

    function rebuild() {
        var q = input.text.trim().toLowerCase();

        // no sort: keep the raw emoji.json order (grouped by category,
        // smileys first) like the old rofi picker did
        var rest = [];
        for (var i = 0; i < picker.all.length; i++) {
            var e = picker.all[i];
            if (picker.isFavourite(e.emoji) || !picker.matches(e, q))
                continue;
            rest.push(e);
        }

        // favourites first, in favourites-file order
        var favs = [];
        for (var f = 0; f < picker.favourites.length; f++) {
            var emoji = picker.favourites[f];
            for (var j = 0; j < picker.all.length; j++) {
                if (picker.all[j].emoji === emoji && picker.matches(picker.all[j], q)) {
                    favs.push(picker.all[j]);
                    break;
                }
            }
        }

        picker.filtered = favs.concat(rest);
        if (picker.selected >= picker.filtered.length)
            picker.selected = 0;
        grid.positionViewAtIndex(Math.min(picker.selected, picker.filtered.length - 1), GridView.Contain);
    }

    function reset() {
        input.text = "";
        favLoad.running = true;
        rebuild();
        input.forceActiveFocus();
    }

    function move(delta) {
        if (picker.filtered.length === 0)
            return;
        var next = picker.selected + delta;
        if (next < 0)
            next = 0;
        if (next >= picker.filtered.length)
            next = picker.filtered.length - 1;
        picker.selected = next;
        grid.positionViewAtIndex(next, GridView.Contain);
    }

    function selectedEntry() {
        return (picker.selected >= 0 && picker.selected < picker.filtered.length)
            ? picker.filtered[picker.selected] : null;
    }

    function copy(emoji) {
        picker.shell.closeAllBut("");
        copier.command = ["sh", "-c", "printf '%s' \"$1\" | wl-copy", "copy", emoji];
        copier.running = true;
    }

    function toggleFavourite() {
        var entry = picker.selectedEntry();
        if (!entry)
            return;
        var emoji = entry.emoji;
        var next = picker.favourites.slice();
        var at = next.indexOf(emoji);
        if (at >= 0)
            next.splice(at, 1);
        else
            next.unshift(emoji);
        picker.favourites = next;
        picker.saveFavourites();
        picker.rebuild();
        picker.keepSelected(emoji);
    }

    // ctrl+shift+up/down: move the selected favourite within the favourites
    // order. No-op on non-favourites.
    function moveFavourite(delta) {
        var entry = picker.selectedEntry();
        if (!entry)
            return;
        var emoji = entry.emoji;
        var order = picker.favourites.slice();
        var at = order.indexOf(emoji);
        if (at < 0)
            return;
        var to = at + delta;
        if (to < 0 || to >= order.length)
            return;
        order.splice(at, 1);
        order.splice(to, 0, emoji);
        picker.favourites = order;
        picker.saveFavourites();
        picker.rebuild();
        picker.keepSelected(emoji);
    }

    function keepSelected(emoji) {
        for (var i = 0; i < picker.filtered.length; i++) {
            if (picker.filtered[i].emoji === emoji) {
                picker.selected = i;
                grid.positionViewAtIndex(i, GridView.Contain);
                break;
            }
        }
    }

    function saveFavourites() {
        favSave.payload = picker.favourites.join("\n");
        favSave.running = true;
    }

    // ---- data loading -------------------------------------------------
    Process {
        id: jsonLoad
        command: ["cat", picker.src]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    picker.all = JSON.parse(text);
                } catch (err) {
                    picker.all = [];
                }
                picker.rebuild();
            }
        }
    }

    Process {
        id: favLoad
        command: ["cat", picker.favFile]
        stdout: SplitParser {
            onRead: line => {
                var emoji = line.trim();
                if (emoji.length > 0)
                    picker.favourites = picker.favourites.concat([emoji]);
            }
        }
        onRunningChanged: if (running) picker.favourites = []
        onExited: picker.rebuild()
    }

    Process {
        id: favSave
        property string payload
        command: ["bash", "-c",
            "printf '%s\\n' \"$1\" > \"$2\"",
            "favsave", favSave.payload, picker.favFile]
    }

    Process {
        id: copier
    }

    Item {
        anchors.fill: parent

        Column {
            anchors.fill: parent
            spacing: 8

            // prompt line: "> " + query
            Item {
                id: promptRow
                width: parent.width
                height: 26

                Text {
                    id: prompt
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: ">"
                    color: picker.pal.accent
                    font.family: picker.pal.font
                    font.pixelSize: 12
                    font.bold: true
                }

                TextInput {
                    id: input
                    anchors.left: prompt.right
                    anchors.leftMargin: 8
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: parent.height
                    // the real text is invisible — TypingFeedback renders it
                    color: "transparent"
                    selectionColor: "transparent"
                    selectedTextColor: "transparent"
                    font.family: picker.pal.font
                    font.pixelSize: 12
                    clip: true
                    selectByMouse: true
                    onTextChanged: picker.rebuild()

                    Keys.onEscapePressed: picker.shell.closeAllBut("")

                    // everything in one handler: specific Keys handlers would
                    // swallow arrow keys before this ever sees them
                    Keys.onPressed: event => {
                        var mods = event.modifiers & (Qt.ControlModifier | Qt.ShiftModifier);
                        if (event.key === Qt.Key_Up && mods === (Qt.ControlModifier | Qt.ShiftModifier)) {
                            picker.moveFavourite(-1);
                        } else if (event.key === Qt.Key_Down && mods === (Qt.ControlModifier | Qt.ShiftModifier)) {
                            picker.moveFavourite(1);
                        } else if (event.key === Qt.Key_F && (event.modifiers & Qt.ControlModifier)) {
                            picker.toggleFavourite();
                        } else if (event.key === Qt.Key_Left) {
                            picker.move(-1);
                        } else if (event.key === Qt.Key_Right) {
                            picker.move(1);
                        } else if (event.key === Qt.Key_Up) {
                            picker.move(-picker.cols);
                        } else if (event.key === Qt.Key_Down) {
                            picker.move(picker.cols);
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            var e = picker.selectedEntry();
                            if (e)
                                picker.copy(e.emoji);
                        } else {
                            return;
                        }
                        event.accepted = true;
                    }
                }

                TypingFeedback {
                    id: typing
                    input: input
                    pal: picker.pal
                    anchors.left: input.left
                    anchors.right: input.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: promptRow.height
                }

                Text {
                    anchors.left: input.left
                    anchors.verticalCenter: parent.verticalCenter
                    visible: typing.empty
                    text: "search emoji"
                    color: picker.pal.muted
                    font.family: picker.pal.font
                    font.pixelSize: 12
                }
            }

            // emoji grid: favourites pinned first (star in the corner)
            GridView {
                id: grid
                width: parent.width
                height: parent.height - promptRow.height - statusRow.height - 16
                clip: true
                cellWidth: picker.width > 0 ? Math.floor((width - 10) / picker.cols) : 38
                cellHeight: 36
                model: picker.filtered

                delegate: Item {
                    id: cell
                    required property var modelData
                    required property int index

                    readonly property bool isFav: picker.isFavourite(modelData.emoji)

                    width: grid.cellWidth
                    height: grid.cellHeight

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 2
                        radius: 0
                        color: (cell.index === picker.selected || cellMouse.containsMouse)
                            ? picker.pal.hover : "transparent"
                        border.width: cell.isFav ? 1 : 0
                        border.color: picker.pal.accent
                    }

                    Text {
                        anchors.centerIn: parent
                        text: cell.modelData.emoji
                        font.pixelSize: 18
                    }

                    MouseArea {
                        id: cellMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onPositionChanged: picker.selected = cell.index
                        onClicked: picker.copy(cell.modelData.emoji)
                    }
                }
            }

            // status line: selected emoji name + key hints
            Text {
                id: statusRow
                width: parent.width
                height: 26

                Text {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                        var e = picker.selectedEntry();
                        var fav = e && picker.isFavourite(e.emoji) ? "★ " : "";
                        return e ? fav + e.emoji + " " + e.name : "no match";
                    }
                    elide: Text.ElideRight
                    color: picker.pal.fg
                    font.family: picker.pal.font
                    font.pixelSize: 10
                }
            }

            Text {
                width: parent.width
                height: 14
                text: "enter copy · ctrl+f fav · ctrl+shift+↑↓ order · esc close"
                color: picker.pal.muted
                font.family: picker.pal.font
                font.pixelSize: 9
                horizontalAlignment: Text.AlignRight
                verticalAlignment: Text.AlignVCenter
            }
        }
    }
}
