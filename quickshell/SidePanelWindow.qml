import Quickshell
import Quickshell.Wayland
import QtQuick

// Shared right-edge full-height column. Geometry, slide animation, header and
// row styling are copied 1:1 from the original clipboard panel, so every panel
// that derives from this one is visually identical.
//
// Children of an instance are placed into `bodyArea` (below the header).
PanelWindow {
    id: panel

    property bool open: false
    property string title: ""
    property string actionText: ""
    property string namespace: "quickshell-panel"
    signal actionClicked()

    readonly property Gruvbox pal: Gruvbox {}
    readonly property int panelWidth: pal.panelWidth

    anchors {
        right: true
        bottom: true
    }
    // full monitor height, bottom-anchored: not anchored top, so the bar's
    // exclusive zone can't push us down — the panel reaches y=0
    implicitHeight: panel.screen.height
    // closed: shove the leftover surface offscreen so it can't eat clicks
    margins.right: open ? 0 : -16
    implicitWidth: open ? panelWidth : 15
    color: "transparent"
    // the spacer window (shell.qml) reserves the right edge
    exclusiveZone: -1
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: panel.namespace
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Behavior on implicitWidth {
        NumberAnimation {
            duration: 200
            easing.type: Easing.OutCubic
        }
    }

    // clipped container: the card slides in from the right edge inside it
    Item {
        id: clipArea
        anchors.fill: parent
        clip: true

        Rectangle {
            id: card
            width: panel.panelWidth
            height: parent.height
            color: panel.pal.bg
            border.width: 1
            border.color: panel.pal.accent

            transform: Translate {
                id: slide
                x: panel.open ? 0 : panel.panelWidth + 12
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

                // header: title + optional text action
                Item {
                    width: parent.width
                    height: 24

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: panel.title
                        color: panel.pal.accent
                        font.family: panel.pal.font
                        font.pixelSize: 13
                        font.bold: true
                    }

                    Rectangle {
                        visible: panel.actionText.length > 0
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: actionLabel.implicitWidth + 14
                        height: 20
                        radius: 0
                        color: actionMouse.containsMouse ? panel.pal.hover : "transparent"
                        border.width: 1
                        border.color: panel.pal.border

                        Text {
                            id: actionLabel
                            anchors.centerIn: parent
                            text: panel.actionText
                            color: actionMouse.containsMouse ? panel.pal.fg : panel.pal.muted
                            font.family: panel.pal.font
                            font.pixelSize: 10
                        }

                        MouseArea {
                            id: actionMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: panel.actionClicked()
                        }
                    }
                }

                // content slot
                Item {
                    id: bodyArea
                    width: parent.width
                    height: parent.height - 24 - 8
                }
            }
        }
    }

    default property alias content: bodyArea.data
}
