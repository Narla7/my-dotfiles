import QtMultimedia
import QtQuick

// serpantinum-style typing feedback for an existing TextInput.
// The target input keeps all real behaviour (keys, focus, selection, caret
// position) but must render its own text transparently (color: "transparent",
// selectionColor: "transparent"). This component overlays the input's text
// area with a per-character pop row — scale 0.3->1 OutBack overshoot 3.2,
// rising from +10 — an animated caret, and the serpantinum keystroke sound
// on every text edit. Backspace pops chars out upward and displaces the
// survivors with an OutBack spring.
//
// Usage: anchor it over the input's text area (same anchors as the input)
// and set `input` and `pal`. For password fields set `masked: true` and the
// row renders dots. Bind placeholders to `empty` so they hide the moment a
// char pops in (the model can lag the text by a frame).

Item {
    id: fb

    property var input
    property var pal
    property int fontPixelSize: 12
    property bool masked: false
    property real soundVolume: 0.7

    readonly property bool empty: !input
        || (input.text.length === 0 && charModel.count === 0)

    implicitWidth: input ? input.width : 0
    implicitHeight: input ? input.height : 26

    SoundEffect {
        id: keySound
        source: "assets/type.wav"
        volume: fb.soundVolume
    }

    TextMetrics {
        id: charMetrics
        font.family: fb.pal.font
        font.pixelSize: fb.fontPixelSize
        text: "0"
    }
    // monospace slot advance: char width + serpantinum's charSpacing of 1
    readonly property real slotStep: charMetrics.width + 1

    property real scrollShift: 0
    Behavior on scrollShift { NumberAnimation { duration: 250; easing.type: Easing.OutQuad } }

    ListModel { id: charModel }

    // diff-sync the model against the text, exactly like serpantinum's
    // syncModel(): only the changed middle range is inserted/removed so the
    // add/remove transitions fire on real edits, not on untouched chars.
    function syncChars() {
        var str = fb.input.text;
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
        fb.updateScroll();
    }

    // keep the caret visible once the query overflows the field
    function updateScroll() {
        var total = charRow.contentWidth;
        var visible = fb.width;
        if (visible <= 0)
            return;
        if (total <= visible) {
            fb.scrollShift = 0;
            return;
        }
        var curX = fb.input.cursorPosition * fb.slotStep;
        var minOffset = visible - total;
        var margin = 4;
        var curScreenX = curX + fb.scrollShift;
        if (curScreenX < margin)
            fb.scrollShift = Math.min(0, Math.max(minOffset, margin - curX));
        else if (curScreenX > visible - margin - 2)
            fb.scrollShift = Math.min(0, Math.max(minOffset, visible - margin - 2 - curX));
    }

    // auto-wired: no per-panel code beyond instantiating the component
    Connections {
        target: fb.input
        function onTextChanged() {
            fb.syncChars();
            keySound.play();
        }
        function onCursorPositionChanged() {
            fb.updateScroll();
        }
    }

    Item {
        id: charArea
        anchors.fill: parent
        clip: true

        ListView {
            id: charRow
            x: fb.scrollShift
            width: contentWidth
            height: parent.height
            anchors.verticalCenter: parent.verticalCenter
            orientation: ListView.Horizontal
            interactive: false
            spacing: 1
            model: charModel

            // serpantinum's add transition: scale 0.3->1 OutBack overshoot
            // 3.2, rise from +10, fade in 150ms
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
                text: fb.masked ? "•" : model.char
                color: fb.pal.fg
                font.family: fb.pal.font
                font.pixelSize: fb.fontPixelSize
            }
        }

        // animated caret at the cursor's slot
        Rectangle {
            id: caret
            width: 2
            height: fb.fontPixelSize * 1.2
            color: fb.pal.accent
            visible: fb.input ? fb.input.activeFocus : false
            anchors.verticalCenter: parent.verticalCenter
            x: (fb.input ? fb.input.cursorPosition : 0) * fb.slotStep + fb.scrollShift

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
}
