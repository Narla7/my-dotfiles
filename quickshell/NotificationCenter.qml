import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

// Notification history "centre": full-height column on the right edge, gruvbox.
// Chronological record (oldest first) of every notification the popup server in
// Notifications.qml has seen, backed by its shared history model.
SidePanelWindow {
    id: notifCentre

    property var shell
    property var historyModel: null

    open: !!notifCentre.shell && notifCentre.shell.notificationCenterOpen
    title: "notifications"
    actionText: "clear all"
    namespace: "quickshell-notif-centre"

    onActionClicked: {
        if (notifCentre.shell)
            notifCentre.shell.clearNotificationHistory();
    }

    // quickshell can hand the image over as a plain path; normalize to a URL
    function imageSource(p) {
        if (!p || p === "")
            return "";
        return p.indexOf("/") === 0 ? "file://" + p : p;
    }

    ListView {
        id: list
        anchors.fill: parent
        clip: true
        spacing: 4
        model: notifCentre.historyModel

        // keep the newest entry (bottom) in view when the centre opens or a
        // new notification lands
        onCountChanged: {
            if (notifCentre.open)
                Qt.callLater(list.positionViewAtEnd);
        }

        delegate: Rectangle {
            id: row
            required property int index
            required property var model

            width: list.width
            height: col.implicitHeight + 12
            color: rowMouse.containsMouse ? notifCentre.pal.hover : notifCentre.pal.row

            ColumnLayout {
                id: col
                anchors.fill: parent
                anchors.margins: 6
                spacing: 3

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        Layout.fillWidth: true
                        text: row.model.appName
                        color: notifCentre.pal.muted
                        font.family: notifCentre.pal.font
                        font.pixelSize: 10
                        elide: Text.ElideRight
                    }

                    Text {
                        text: row.model.timestamp
                        color: notifCentre.pal.muted
                        font.family: notifCentre.pal.font
                        font.pixelSize: 10
                    }

                    Text {
                        id: xBtn
                        text: "×"
                        color: notifCentre.pal.muted
                        font.family: notifCentre.pal.font
                        font.pixelSize: 12

                        MouseArea {
                            id: xMouse
                            anchors.fill: parent
                            anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            onClicked: notifCentre.historyModel.remove(row.index, 1)
                        }
                    }
                }

                Image {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 90
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    visible: row.model.image !== ""
                    source: notifCentre.imageSource(row.model.image)
                }

                Text {
                    Layout.fillWidth: true
                    visible: row.model.summary !== ""
                    text: row.model.summary
                    color: notifCentre.pal.fg
                    font.family: notifCentre.pal.font
                    font.pixelSize: 12
                    font.bold: true
                    wrapMode: Text.Wrap
                }

                Text {
                    Layout.fillWidth: true
                    visible: row.model.body !== ""
                    text: row.model.body
                    color: notifCentre.pal.fg
                    font.family: notifCentre.pal.font
                    font.pixelSize: 11
                    wrapMode: Text.Wrap
                }
            }

            // hover highlight only; clicks must fall through to the × button
            MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
            }
        }
    }

    // empty state
    Text {
        anchors.centerIn: parent
        visible: !notifCentre.historyModel || notifCentre.historyModel.count === 0
        text: "no notifications"
        color: notifCentre.pal.muted
        font.family: notifCentre.pal.font
        font.pixelSize: 11
    }

    // Esc closes
    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: notifCentre.shell.closeAllBut("")
    }
}
