import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Layouts

// Miasma-styled notification popups, top-right. Replaces dunst.
PanelWindow {
    id: notifWindow

    property var shell
    readonly property Miasma pal: Miasma {}

    property int uidCounter: 0

    ListModel { id: notifModel }

    anchors {
        top: true
        right: true
    }
    margins {
        top: 50
        right: 10
    }
    implicitWidth: 340
    implicitHeight: Math.max(1, notifColumn.implicitHeight)
    color: "transparent"
    exclusiveZone: 0
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-notifications"

    function removeNotification(uid) {
        for (var i = 0; i < notifModel.count; i++) {
            var it = notifModel.get(i);
            if (it && it.uid === uid) {
                var n = it.notif;
                // remove from model first so re-entrant closed handlers don't double-remove
                notifModel.remove(i, 1);
                if (n && typeof n.dismiss === "function")
                    n.dismiss();
                return;
            }
        }
    }

    function dismissAll() {
        var toDismiss = [];
        for (var i = 0; i < notifModel.count; i++) {
            var it = notifModel.get(i);
            if (it && it.notif)
                toDismiss.push(it.notif);
        }
        notifModel.clear();
        for (var j = 0; j < toDismiss.length; j++) {
            if (toDismiss[j] && typeof toDismiss[j].dismiss === "function")
                toDismiss[j].dismiss();
        }
    }

    NotificationServer {
        id: server
        bodySupported: true
        actionsSupported: true
        imageSupported: true

        onNotification: (n) => {
            n.tracked = true;

            if (n.closed) {
                n.closed.connect(() => {
                    for (var i = 0; i < notifModel.count; i++) {
                        var it = notifModel.get(i);
                        if (it && it.notif === n) {
                            notifModel.remove(i, 1);
                            break;
                        }
                    }
                });
            }

            notifWindow.uidCounter++;
            var currentUid = notifWindow.uidCounter;

            notifModel.insert(0, {
                "uid": currentUid,
                "notif": n,
                "appName": (n.appName && n.appName !== "") ? n.appName : "System",
                "summary": (n.summary && n.summary !== "") ? n.summary : "",
                "body": (n.body && n.body !== "") ? n.body : "",
                "appIcon": (n.appIcon && n.appIcon !== "") ? n.appIcon : "",
                "image": (n.image && n.image !== "") ? n.image : "",
                "urgency": n.urgency,
                "expireTimeout": n.expireTimeout
            });
        }
    }

    Column {
        id: notifColumn
        width: parent.width
        spacing: 8

        Repeater {
            model: notifModel

            delegate: Rectangle {
                id: card
                required property var model
                required property int index

                width: notifColumn.width
                implicitHeight: cardContent.implicitHeight + 16
                height: implicitHeight
                color: notifWindow.pal.bg1
                border.width: 1
                border.color: notifWindow.pal.bg2

                property int effectiveTimeout: {
                    var t = model.expireTimeout;
                    if (t === 0) return 0;
                    if (t > 0) return t;
                    // critical notifications stay until dismissed
                    if (model.urgency === 2) return 0;
                    return 5000;
                }
                property bool hovered: false

                Timer {
                    interval: card.effectiveTimeout > 0 ? card.effectiveTimeout : 5000
                    running: card.effectiveTimeout > 0 && !card.hovered
                    repeat: false
                    onTriggered: notifWindow.removeNotification(card.model.uid)
                }

                Connections {
                    target: card.model.notif ? card.model.notif : null
                    function onClosed() {
                        notifWindow.removeNotification(card.model.uid);
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                    onEntered: card.hovered = true
                    onExited: card.hovered = false
                }

                ColumnLayout {
                    id: cardContent
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            Layout.fillWidth: true
                            text: card.model.appName
                            color: notifWindow.pal.fg1
                            font.family: notifWindow.pal.font
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            width: 16
                            height: 16
                            color: closeMouse.containsMouse ? notifWindow.pal.bg2 : "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: "×"
                                color: notifWindow.pal.fg
                                font.family: notifWindow.pal.font
                                font.pixelSize: 12
                            }
                            MouseArea {
                                id: closeMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: notifWindow.removeNotification(card.model.uid)
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: card.model.summary !== ""
                        text: card.model.summary
                        color: notifWindow.pal.fg
                        font.family: notifWindow.pal.font
                        font.pixelSize: 12
                        font.bold: true
                        wrapMode: Text.Wrap
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: card.model.body !== ""
                        text: card.model.body
                        color: notifWindow.pal.fg1
                        font.family: notifWindow.pal.font
                        font.pixelSize: 11
                        wrapMode: Text.Wrap
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        visible: card.model.notif && card.model.notif.actions && card.model.notif.actions.length > 0

                        Repeater {
                            model: card.model.notif ? card.model.notif.actions : []

                            delegate: Rectangle {
                                required property var modelData
                                width: actionLabel.implicitWidth + 10
                                height: 18
                                color: actionMouse.containsMouse ? notifWindow.pal.bg2 : "transparent"
                                border.width: 1
                                border.color: notifWindow.pal.bg2

                                Text {
                                    id: actionLabel
                                    anchors.centerIn: parent
                                    text: modelData.text
                                    color: notifWindow.pal.fg
                                    font.family: notifWindow.pal.font
                                    font.pixelSize: 10
                                }

                                MouseArea {
                                    id: actionMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        modelData.invoke();
                                        notifWindow.removeNotification(card.model.uid);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
