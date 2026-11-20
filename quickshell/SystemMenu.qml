import Quickshell
import Quickshell.Wayland
import QtQuick

// System / power menu — text only. Same right-edge column as the clipboard.
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

    function run(action) {
        systemMenu.shell.closeAllBut("");
        Quickshell.execDetached(action.cmd);
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

                    width: parent.width
                    height: 52
                    radius: 0
                    color: rowMouse.containsMouse ? systemMenu.pal.hover : systemMenu.pal.row

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
                    }

                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: systemMenu.run(row.modelData)
                    }
                }
            }
        }
    }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: systemMenu.shell.closeAllBut("")
    }
}
