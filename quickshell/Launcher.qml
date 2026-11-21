import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtMultimedia
import QtQuick

// App launcher — text only, no icons. Same right-edge column as the clipboard.
// Backed by Quickshell's DesktopEntries, so fuzzel is no longer involved.
// Ctrl+F toggles the selected app as a favourite; favourites are pinned above
// the alphabetical list and persisted under ~/.local/state.
SidePanelWindow {
    id: launcher

    property var shell
    open: !!launcher.shell && launcher.shell.launcherOpen
    title: "launcher"
    namespace: "quickshell-launcher"

    readonly property string stateHome: (Quickshell.env("XDG_STATE_HOME") || "").length > 0
        ? Quickshell.env("XDG_STATE_HOME")
        : Quickshell.env("HOME") + "/.local/state"
    readonly property string favFile: launcher.stateHome + "/narla-shell/launcher-favorites"

    // every installed desktop entry, filtered live by the query below
    property var allApps: DesktopEntries.applications.values
    property var filtered: []
    property var favourites: []
    property int selected: 0

    function normId(id) {
        return (id || "").toLowerCase().replace(/\.desktop$/, "");
    }

    function isFavourite(id) {
        return launcher.favourites.indexOf(launcher.normId(id)) >= 0;
    }

    function matches(entry, query) {
        return query.length === 0 || entry.name.toLowerCase().indexOf(query) >= 0;
    }

    function rebuild() {
        var q = input.text.trim().toLowerCase();

        // index every entry by normalized id (desktop ids vary by suffix/case)
        var byId = {};
        var apps = launcher.allApps;
        for (var i = 0; i < apps.length; i++) {
            var e = apps[i];
            if (!e || e.noDisplay)
                continue;
            byId[launcher.normId(e.id)] = e;
        }

        // favourites first, in the order they were pinned (newest first)
        var favEntries = [];
        var favKeys = {};
        for (var f = 0; f < launcher.favourites.length; f++) {
            var key = launcher.normId(launcher.favourites[f]);
            if (favKeys[key])
                continue;
            favKeys[key] = true;
            var fav = byId[key];
            if (fav && launcher.matches(fav, q))
                favEntries.push(fav);
        }

        // then everything else alphabetically
        var rest = [];
        for (var id in byId) {
            if (favKeys[id] || !launcher.matches(byId[id], q))
                continue;
            rest.push(byId[id]);
        }
        rest.sort((a, b) => a.name.localeCompare(b.name));

        launcher.filtered = favEntries.concat(rest);
        launcher.selected = 0;
        if (list)
            list.positionViewAtBeginning();
    }

    function reset() {
        input.text = "";
        // pick up favourites edited outside the shell, too
        favLoad.running = true;
        rebuild();
        input.forceActiveFocus();
    }

    function move(delta) {
        if (launcher.filtered.length === 0)
            return;
        var next = launcher.selected + delta;
        if (next < 0)
            next = launcher.filtered.length - 1;
        if (next >= launcher.filtered.length)
            next = 0;
        launcher.selected = next;
        list.positionViewAtIndex(next, ListView.Contain);
    }

    function activate() {
        if (launcher.selected < 0 || launcher.selected >= launcher.filtered.length)
            return;
        var entry = launcher.filtered[launcher.selected];
        launcher.shell.closeAllBut("");
        if (entry)
            entry.execute();
    }

    function toggleFavourite() {
        if (launcher.selected < 0 || launcher.selected >= launcher.filtered.length)
            return;
        var entry = launcher.filtered[launcher.selected];
        var id = launcher.normId(entry.id);
        var next = launcher.favourites.slice();
        var at = next.indexOf(id);
        if (at >= 0)
            next.splice(at, 1);
        else
            next.unshift(id);
        launcher.favourites = next;
        launcher.saveFavourites();
        launcher.rebuild();

        // keep the toggled app selected after the reorder
        for (var i = 0; i < launcher.filtered.length; i++) {
            if (launcher.normId(launcher.filtered[i].id) === id) {
                launcher.selected = i;
                list.positionViewAtIndex(i, ListView.Contain);
                break;
            }
        }
    }

    function saveFavourites() {
        favSave.payload = launcher.favourites.join("\n");
        favSave.running = true;
    }

    // serpantinum-style typing feedback: keystroke sound + per-character pop row.
    // The TextInput keeps all real behaviour (keys, focus, selection, caret
    // position) but its own text is transparent; what you see is the char row
    // below, whose items animate in with the launcher's OutBack overshoot.
    SoundEffect {
        id: keySound
        source: "assets/type.wav"
        volume: 0.7
    }

    TextMetrics {
        id: charMetrics
        font.family: launcher.pal.font
        font.pixelSize: 12
        text: "0"
    }
    // monospace slot advance: char width + serpantinum's charSpacing of 1
    readonly property real slotStep: charMetrics.width + 1

    ListModel { id: charModel }
    property real scrollShift: 0
    readonly property real scrollOffset: launcher.scrollShift
    Behavior on scrollShift { NumberAnimation { duration: 250; easing.type: Easing.OutQuad } }

    // diff-sync the model against the text, exactly like serpantinum's
    // syncModel(): only the changed middle range is inserted/removed so the
    // add/remove transitions fire on real edits, not on untouched chars.
    function syncChars() {
        var str = input.text;
        var old = charModel.count;
        var prefix = 0;
        while (prefix < old && prefix < str.length
               && charModel.get(prefix).char === str[prefix])
            prefix++;
        var suffix = 0;
        while (suffix < (old - prefix) && suffix < (str.length - prefix)
               && charModel.get(old - 1 - suffix).char === str[str.length - 1 - suffix])
            suffix++;
        if (old - prefix - suffix > 0)
            charModel.remove(prefix, old - prefix - suffix);
        var ins = str.slice(prefix, str.length - suffix);
        for (var i = 0; i < ins.length; i++)
            charModel.insert(prefix + i, { char: ins[i] });
        launcher.updateScroll();
    }

    // keep the caret visible once the query overflows the field
    function updateScroll() {
        var total = charRow.contentWidth;
        var visible = charArea.width;
        if (visible <= 0)
            return;
        if (total <= visible) {
            launcher.scrollShift = 0;
            return;
        }
        var curX = input.cursorPosition * launcher.slotStep;
        var minOffset = visible - total;
        var margin = 4;
        var curScreenX = curX + launcher.scrollShift;
        if (curScreenX < margin)
            launcher.scrollShift = Math.min(0, Math.max(minOffset, margin - curX));
        else if (curScreenX > visible - margin - 2)
            launcher.scrollShift = Math.min(0, Math.max(minOffset, visible - margin - 2 - curX));
    }

    // Ctrl+Shift+Up/Down: move the selected favourite up/down within the
    // favourites order (newest first = top). No-op on non-favourites.
    function moveFavourite(delta) {
        if (launcher.selected < 0 || launcher.selected >= launcher.filtered.length)
            return;
        var entry = launcher.filtered[launcher.selected];
        var id = launcher.normId(entry.id);
        var order = launcher.favourites.slice();
        var at = order.indexOf(id);
        if (at < 0)
            return;
        var to = at + delta;
        if (to < 0 || to >= order.length)
            return;
        order.splice(at, 1);
        order.splice(to, 0, id);
        launcher.favourites = order;
        launcher.saveFavourites();
        launcher.rebuild();

        // keep the moved app selected after the reorder
        for (var i = 0; i < launcher.filtered.length; i++) {
            if (launcher.normId(launcher.filtered[i].id) === id) {
                launcher.selected = i;
                list.positionViewAtIndex(i, ListView.Contain);
                break;
            }
        }
    }

    onOpenChanged: if (open) launcher.reset()
    Component.onCompleted: {
        launcher.rebuild();
        favLoad.running = true;
    }

    // persistent favourites: one desktop-entry id per line
    Process {
        id: favLoad
        command: ["cat", launcher.favFile]
        stdout: SplitParser {
            onRead: line => {
                var id = line.trim();
                if (id.length > 0) {
                    // assign a new array so the favourites binding re-evaluates
                    var next = launcher.favourites.slice();
                    next.push(id);
                    launcher.favourites = next;
                }
            }
        }
        onRunningChanged: if (running) launcher.favourites = []
        onExited: launcher.rebuild()
    }

    Process {
        id: favSave
        property string payload
        command: ["bash", "-c",
            "mkdir -p \"$(dirname \"$2\")\" && printf '%s' \"$1\" > \"$2\"",
            "favsave", favSave.payload, launcher.favFile]
    }

    Item {
        anchors.fill: parent

        Column {
            anchors.fill: parent
            spacing: 8

            // prompt line: "> " + query, text only
            Item {
                id: promptRow
                width: parent.width
                height: 26

                Text {
                    id: prompt
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: ">"
                    color: launcher.pal.accent
                    font.family: launcher.pal.font
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
                    // the real text is invisible — the char row renders it
                    color: "transparent"
                    selectionColor: "transparent"
                    selectedTextColor: "transparent"
                    font.family: launcher.pal.font
                    font.pixelSize: 12
                    clip: true
                    selectByMouse: true
                    onTextChanged: {
                        launcher.syncChars();
                        keySound.play();
                        launcher.rebuild();
                    }
                    onCursorPositionChanged: launcher.updateScroll()

                    Keys.onEscapePressed: launcher.shell.closeAllBut("")

                    // all keys in one handler — separate onUpPressed/onDownPressed
                    // handlers would eat ctrl+shift+up/down before this runs
                    Keys.onPressed: event => {
                        var mods = event.modifiers & (Qt.ControlModifier | Qt.ShiftModifier);
                        if (event.key === Qt.Key_F && (event.modifiers & Qt.ControlModifier)) {
                            launcher.toggleFavourite();
                        } else if (event.key === Qt.Key_Up && mods === (Qt.ControlModifier | Qt.ShiftModifier)) {
                            launcher.moveFavourite(-1);
                        } else if (event.key === Qt.Key_Down && mods === (Qt.ControlModifier | Qt.ShiftModifier)) {
                            launcher.moveFavourite(1);
                        } else if (event.key === Qt.Key_Up) {
                            launcher.move(-1);
                        } else if (event.key === Qt.Key_Down) {
                            launcher.move(1);
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            launcher.activate();
                        } else {
                            return;
                        }
                        event.accepted = true;
                    }
                }

                // visible text: one item per char with serpantinum's pop
                Item {
                    id: charArea
                    anchors.left: input.left
                    anchors.right: input.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: parent.height
                    clip: true

                    ListView {
                        id: charRow
                        x: launcher.scrollOffset
                        width: contentWidth
                        height: parent.height
                        anchors.verticalCenter: parent.verticalCenter
                        orientation: ListView.Horizontal
                        interactive: false
                        spacing: 1
                        model: charModel

                        // serpantinum's add transition: scale 0.3->1 OutBack
                        // overshoot 3.2, rise from +10, fade in 150ms
                        add: Transition {
                            ParallelAnimation {
                                NumberAnimation { property: "scale"; from: 0.3; to: 1.0; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 3.2 }
                                NumberAnimation { property: "y"; from: 10; to: 0; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2.6 }
                                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 150; easing.type: Easing.OutCubic }
                            }
                        }
                        // exits fall up and shrink; survivors spring back (displaced)
                        remove: Transition {
                            ParallelAnimation {
                                NumberAnimation { property: "scale"; to: 0.3; duration: 160; easing.type: Easing.InBack }
                                NumberAnimation { property: "y"; to: -8; duration: 160; easing.type: Easing.InCubic }
                                NumberAnimation { property: "opacity"; to: 0; duration: 144; easing.type: Easing.InCubic }
                            }
                        }
                        displaced: Transition {
                            NumberAnimation { properties: "x,y"; duration: 250; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
                        }

                        delegate: Text {
                            text: model.char
                            color: launcher.pal.fg
                            font.family: launcher.pal.font
                            font.pixelSize: 12
                        }
                    }

                    // animated caret at the cursor's slot
                    Rectangle {
                        id: caret
                        width: 2
                        height: 14
                        color: launcher.pal.accent
                        visible: input.activeFocus
                        anchors.verticalCenter: parent.verticalCenter
                        x: input.cursorPosition * launcher.slotStep + launcher.scrollOffset

                        Behavior on x { NumberAnimation { duration: 250; easing.type: Easing.OutQuad } }

                        SequentialAnimation on opacity {
                            running: caret.visible
                            loops: Animation.Infinite
                            NumberAnimation { to: 0; duration: 100; easing.type: Easing.InQuad }
                            PauseAnimation { duration: 400 }
                            NumberAnimation { to: 1; duration: 100; easing.type: Easing.OutQuad }
                            PauseAnimation { duration: 400 }
                        }
                    }
                }

                Text {
                    anchors.left: input.left
                    anchors.verticalCenter: parent.verticalCenter
                    // charModel can lag the text by a frame — check both so the
                    // placeholder never flashes over a popped-in char
                    visible: input.text.length === 0 && charModel.count === 0
                    text: "search applications"
                    color: launcher.pal.muted
                    font.family: launcher.pal.font
                    font.pixelSize: 12
                }
            }

            // results: favourites pinned first, then the alphabetical list
            ListView {
                id: list
                width: parent.width
                height: parent.height - promptRow.height - hintRow.height - 16
                clip: true
                spacing: 4
                model: launcher.filtered

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index

                    readonly property bool isFav: launcher.isFavourite(modelData.id)

                    width: list.width
                    height: 52
                    radius: 0
                    color: (index === launcher.selected || rowMouse.containsMouse)
                        ? launcher.pal.hover : launcher.pal.row

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.right: favLabel.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.name
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        color: row.isFav ? launcher.pal.accent : launcher.pal.fg
                        font.family: launcher.pal.font
                        font.pixelSize: 11
                        font.bold: index === launcher.selected
                    }

                    Text {
                        id: favLabel
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        visible: row.isFav
                        text: "fav"
                        color: launcher.pal.muted
                        font.family: launcher.pal.font
                        font.pixelSize: 9
                    }

                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            launcher.selected = row.index;
                            launcher.activate();
                        }
                    }
                }
            }

            Text {
                id: hintRow
                width: parent.width
                height: 14
                text: "ctrl+f fav · ctrl+shift+↑↓ reorder favs · enter open · esc close"
                color: launcher.pal.muted
                font.family: launcher.pal.font
                font.pixelSize: 9
                horizontalAlignment: Text.AlignRight
                verticalAlignment: Text.AlignVCenter
            }
        }
    }
}
