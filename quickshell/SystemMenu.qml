import Quickshell
import Quickshell.Wayland
import QtQuick

// System / power menu — text only. Same right-edge column as the clipboard.
// Fully keyboard driven: up/down move the selection (wrapping), enter runs it,
// esc closes. Mouse clicks still work.
SidePanelWindow {
    id: systemMenu

    property var shell
    open: !!systemMenu.shell && systemMenu.shell.systemMenuOpen
    title: "system"
    namespace: "quickshell-system"

    readonly property var actions: [
        { label: "logout", cmd: ["hyprctl", "eval", "hl.dispatch(hl.dsp.exit())"] },
        { label: "reboot", cmd: ["systemctl", "reboot"] },
        { label: "power off", cmd: ["systemctl", "poweroff"] },
        { label: "suspend", cmd: ["systemctl", "suspend"] }
    ]

    property int selected: 0

    onOpenChanged: if (open) systemMenu.selected = 0

    function run(action) {
        systemMenu.shell.closeAllBut("");
        Quickshell.execDetached(action.cmd);
    }

    function move(delta) {
        var count = systemMenu.actions.length;
        if (count === 0)
            return;
        var next = systemMenu.selected + delta;
        if (next < 0)
            next = count - 1;
        if (next >= count)
            next = 0;
        systemMenu.selected = next;
    }

    Item {
        anchors.fill: parent

        Column {
            anchors.fill: parent
            spacing: 4

            Repeater {
                model: systemMenu.actions

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index

                    width: parent.width
                    height: 52
                    radius: 0
                    color: (index === systemMenu.selected || rowMouse.containsMouse)
                        ? systemMenu.pal.hover : systemMenu.pal.row

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.label
                        color: systemMenu.pal.fg
                        font.family: systemMenu.pal.font
                        font.pixelSize: 11
                        font.bold: index === systemMenu.selected
                    }

                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onPositionChanged: systemMenu.selected = row.index
                        onClicked: systemMenu.run(row.modelData)
                    }
                }
            }

            Text {
                width: parent.width
                height: 14
                text: "up/down select · enter run · esc close"
                color: systemMenu.pal.muted
                font.family: systemMenu.pal.font
                font.pixelSize: 9
                horizontalAlignment: Text.AlignRight
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: systemMenu.shell.closeAllBut("")
        Keys.onUpPressed: systemMenu.move(-1)
        Keys.onDownPressed: systemMenu.move(1)
        Keys.onReturnPressed: systemMenu.run(systemMenu.actions[systemMenu.selected])
        Keys.onEnterPressed: systemMenu.run(systemMenu.actions[systemMenu.selected])
    }
}
