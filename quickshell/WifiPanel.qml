import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Networking
import QtQuick
import QtQuick.Layouts

// Wifi panel: network list from Quickshell's Networking service, connect via
// nmcli. First attempt is passwordless; when nmcli fails (secured network) an
// inline password field appears. A failed password wipes the broken profile
// nmcli leaves behind so the next attempt asks again.
SidePanelWindow {
    id: wifiPanel

    property var shell
    open: !!wifiPanel.shell && wifiPanel.shell.wifiOpen
    title: "wifi"
    actionText: "rescan"
    namespace: "quickshell-wifi"

    property var wifiDev: null
    // ssid currently awaiting a password, and the one nmcli is working on
    property string pendingSsid: ""
    property string connectingSsid: ""

    function pickDevice() {
        var list = Networking.devices.values.filter(d => d.type == DeviceType.Wifi);
        wifiPanel.wifiDev = list.length > 0 ? list[0] : null;
    }

    function currentSsid() {
        if (!wifiPanel.wifiDev)
            return "";
        var nets = wifiPanel.wifiDev.networks.values;
        for (var i = 0; i < nets.length; i++)
            if (nets[i].connected)
                return nets[i].name;
        return "";
    }

    Component.onCompleted: wifiPanel.pickDevice()

    Connections {
        target: Networking.devices
        function onValuesChanged() { wifiPanel.pickDevice() }
    }

    // rescan so freshly enabled/hidden networks show up
    Process {
        id: rescanProc
        command: ["nmcli", "-t", "device", "wifi", "rescan"]
    }

    onActionClicked: {
        pickDevice();
        if (wifiPanel.wifiDev)
            rescanProc.running = true;
    }

    onOpenChanged: if (open) wifiPanel.actionClicked()

    function connect(ssid, password) {
        var args = ["-t", "device", "wifi", "connect", ssid];
        if (password !== null)
            args.push("password", password);
        connectProc.ssid = ssid;
        connectProc.prompted = password !== null && password !== "";
        connectProc.command = ["nmcli"].concat(args);
        connectProc.running = true;
    }

    Process {
        id: connectProc
        property string ssid: ""
        property bool prompted: false
        command: []
        stdout: StdioCollector { }
        stderr: StdioCollector { }
        onExited: (code, status) => {
            if (code === 0) {
                wifiPanel.connectingSsid = "";
                wifiPanel.pendingSsid = "";
                Quickshell.execDetached(["notify-send", "-a", "wifi", "wifi", "connected to " + connectProc.ssid]);
            } else {
                wifiPanel.connectingSsid = "";
                if (connectProc.prompted) {
                    // a bad password leaves a broken profile behind that would
                    // fail every future attempt; remove it so the next try asks
                    // again instead of reusing the bad credentials
                    deleteProc.running = true;
                    Quickshell.execDetached(["notify-send", "-a", "wifi", "wifi", "failed to connect to " + connectProc.ssid]);
                }
                // first failure without a password: ask for one
                wifiPanel.pendingSsid = connectProc.ssid;
            }
        }
    }

    Process {
        id: deleteProc
        command: ["nmcli", "-t", "connection", "delete", connectProc.ssid]
    }

    Process {
        id: discProc
        command: ["nmcli", "-t", "device", "disconnect",
                  wifiPanel.wifiDev !== null ? wifiPanel.wifiDev.name : ""]
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        // ---- current connection + disconnect ------------------------------
        RowLayout {
            width: parent.width
            visible: wifiPanel.wifiDev !== null && wifiPanel.wifiDev.connected

            Text {
                Layout.fillWidth: true
                text: "connected: " + wifiPanel.currentSsid()
                color: wifiPanel.pal.fg
                font.family: wifiPanel.pal.font
                font.pixelSize: 11
                elide: Text.ElideRight
            }

            Text {
                id: discBtn
                text: "disconnect"
                color: discMouse.containsMouse ? wifiPanel.pal.fg : wifiPanel.pal.muted
                font.family: wifiPanel.pal.font
                font.pixelSize: 10

                MouseArea {
                    id: discMouse
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: discProc.running = true
                }
            }
        }

        // ---- password entry ------------------------------------------------
        Rectangle {
            width: parent.width
            height: passInput.visible ? 30 : 0
            color: wifiPanel.pal.row
            border.width: 1
            border.color: wifiPanel.pal.border

            RowLayout {
                anchors.fill: parent
                anchors.margins: 6
                spacing: 6

                Text {
                    text: wifiPanel.pendingSsid + ":"
                    color: wifiPanel.pal.muted
                    font.family: wifiPanel.pal.font
                    font.pixelSize: 10
                    elide: Text.ElideRight
                    Layout.maximumWidth: parent.width / 2
                }

                TextInput {
                    id: passInput
                    Layout.fillWidth: true
                    visible: wifiPanel.pendingSsid !== ""
                    color: wifiPanel.pal.fg
                    font.family: wifiPanel.pal.font
                    font.pixelSize: 11
                    echoMode: TextInput.Password
                    focus: visible
                    onVisibleChanged: {
                        text = "";
                        if (visible)
                            forceActiveFocus();
                    }
                    onAccepted: {
                        wifiPanel.connect(wifiPanel.pendingSsid, text);
                        wifiPanel.connectingSsid = wifiPanel.pendingSsid;
                        wifiPanel.pendingSsid = "";
                    }
                    Keys.onEscapePressed: wifiPanel.pendingSsid = ""
                }

                Text {
                    visible: wifiPanel.connectingSsid !== "" && wifiPanel.pendingSsid === ""
                    text: "connecting…"
                    color: wifiPanel.pal.muted
                    font.family: wifiPanel.pal.font
                    font.pixelSize: 10
                }
            }
        }

        // ---- network list ---------------------------------------------------
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            model: wifiPanel.wifiDev !== null ? wifiPanel.wifiDev.networks : null

            delegate: Rectangle {
                id: row
                required property var modelData

                width: list.width
                height: modelData.name === "" ? 0 : 40
                visible: modelData.name !== ""
                color: netMouse.containsMouse ? wifiPanel.pal.hover : wifiPanel.pal.row

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 6

                    Text {
                        Layout.fillWidth: true
                        text: (modelData.connected ? "* " : "") + modelData.name
                        color: modelData.connected ? wifiPanel.pal.accent : wifiPanel.pal.fg
                        font.family: wifiPanel.pal.font
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }

                    Text {
                        text: Math.round(modelData.signalStrength * 100) + "%"
                        color: wifiPanel.pal.muted
                        font.family: wifiPanel.pal.font
                        font.pixelSize: 10
                    }

                    Text {
                        visible: !modelData.connected
                        text: "join"
                        color: netMouse.containsMouse ? wifiPanel.pal.fg : wifiPanel.pal.muted
                        font.family: wifiPanel.pal.font
                        font.pixelSize: 10
                    }
                }

                MouseArea {
                    id: netMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (modelData.connected)
                            return;
                        wifiPanel.connectingSsid = modelData.name;
                        wifiPanel.connect(modelData.name, null);
                    }
                }
            }
        }

        Text {
            visible: wifiPanel.wifiDev === null
            text: "no wifi device"
            color: wifiPanel.pal.muted
            font.family: wifiPanel.pal.font
            font.pixelSize: 11
        }
    }
}
