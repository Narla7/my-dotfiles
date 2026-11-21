import QtQuick

// Gruvbox slider shared by the audio panel. Click, drag or scroll to set a
// 0..1 value; the owner applies it (wpctl) so the widget stays dumb.
Item {
    id: slider

    property real value: 0
    property bool muted: false
    property var pal

    signal moved(real value)

    implicitHeight: 14

    Rectangle {
        id: track
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: 8
        color: slider.pal.row
        border.width: 1
        border.color: slider.pal.border

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: 1
            width: Math.max(0, (parent.width - 2) * Math.max(0, Math.min(1, slider.value)))
            color: slider.muted ? slider.pal.muted : slider.pal.accent
        }
    }

    MouseArea {
        anchors.fill: parent
        anchors.topMargin: -3
        anchors.bottomMargin: -3
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => slider.moved(mouse.x / width)
        onPositionChanged: mouse => {
            if (mouse.buttons & Qt.LeftButton)
                slider.moved(mouse.x / width);
        }
        onWheel: wheel => {
            if (wheel.angleDelta.y === 0)
                return;
            wheel.accepted = true;
            slider.moved(slider.value + (wheel.angleDelta.y > 0 ? 0.05 : -0.05));
        }
    }
}
