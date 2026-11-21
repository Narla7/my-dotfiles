import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

// Wifi panel (caelestia-style): radio toggle, auto-rescanning network list with
// signal/security/saved state, inline password prompt, connected-IP card and an
// ethernet section. Driven entirely by nmcli — Quickshell's Networking model
// doesn't expose security/saved profiles, which is what made the old panel
// feel unpredictable.
SidePanelWindow {
    id: wifiPanel

    property var shell
    open: !!wifiPanel.shell && wifiPanel.shell.wifiOpen
    title: "wifi"
    actionText: "rescan"
    namespace: "quickshell-wifi"

    property bool wifiEnabled: true
    property bool scanning: false
    property bool loaded: false
    property string connectingSsid: ""
    property string pendingSsid: ""
    property string pendingSecurity: ""
    property string errorText: ""
    property string activeSsid: ""
    property string activeIface: ""
    property string activeIp: ""

    property var networks: []
    // ssid -> NetworkManager UUID of the saved wireless profile
    property var saved: ({})
    property var ethernet: []

    onActionClicked: wifiPanel.rescan()
    onOpenChanged: {
        if (open) {
            wifiPanel.refresh();
            wifiPanel.rescan();
        } else {
            wifiPanel.pendingSsid = "";
            wifiPanel.errorText = "";
        }
    }

    // ---------------------------------------------------------------- refresh
    function refresh() {
        if (!refreshProc.running)
            refreshProc.running = true;
    }

    function splitTerse(line) {
        var out = [];
        var cur = "";
        var escaped = false;
        for (var i = 0; i < line.length; i++) {
            var ch = line[i];
            if (escaped) {
                cur += ch;
                escaped = false;
            } else if (ch === "\\") {
                escaped = true;
            } else if (ch === ":") {
                out.push(cur);
                cur = "";
            } else {
                cur += ch;
            }
        }
        out.push(cur);
        return out;
    }

    function parseRefresh(text) {
        var lines = text.split("\n");
        var section = "";
        var map = {};
        var savedMap = {};
        var eth = [];
        var radio = "enabled";
        var iface = "";
        var active = "";

        for (var i = 0; i < lines.length; i++) {
            var line = lines[i];
            var t = line.trim();
            if (t === "@@radio") { section = "radio"; continue; }
            if (t === "@@wifi") { section = "wifi"; continue; }
            if (t === "@@saved") { section = "saved"; continue; }
            if (t === "@@devices") { section = "devices"; continue; }
            if (t === "")
                continue;

            if (section === "radio") {
                radio = t;
            } else if (section === "wifi") {
                var f = splitTerse(line);
                if (f.length < 4)
                    continue;
                var ssid = f[1];
                if (ssid === "")
                    continue;
                var sig = parseInt(f[2]) || 0;
                var sec = f[3] === "" || f[3] === "--" ? "" : f[3];
                var isActive = f[0].indexOf("*") >= 0;
                var old = map[ssid];
                // one row per SSID (mesh/extenders share a name); prefer the
                // active BSSID, otherwise the strongest one
                if (!old || (isActive && !old.active) || (!old.active && sig > old.signal)) {
                    map[ssid] = {
                        ssid: ssid,
                        signal: sig,
                        security: sec,
                        active: isActive
                    };
                }
                if (isActive)
                    active = ssid;
            } else if (section === "saved") {
                var tab = line.indexOf("\t");
                if (tab < 0)
                    continue;
                var savedSsid = line.slice(0, tab);
                if (savedSsid !== "") {
                    if (!savedMap[savedSsid])
                        savedMap[savedSsid] = [];
                    savedMap[savedSsid].push(line.slice(tab + 1));
                }
            } else if (section === "devices") {
                var d = splitTerse(line);
                if (d.length < 4)
                    continue;
                if (d[1] === "wifi" && d[2].indexOf("connected") === 0)
                    iface = d[0];
                if (d[1] === "ethernet")
                    eth.push({ dev: d[0], state: d[2], connection: d[3] });
            }
        }

        // merge saved state, then sort like caelestia: active, connecting,
        // saved, then strongest first
        var list = Object.keys(map).map(function (key) {
            var n = map[key];
            n.saved = !!savedMap[n.ssid];
            return n;
        });
        function rank(n) {
            if (n.active)
                return 0;
            if (n.ssid === wifiPanel.connectingSsid)
                return 1;
            if (n.saved)
                return 2;
            return 3;
        }
        list.sort(function (a, b) { return rank(a) - rank(b) || b.signal - a.signal; });

        wifiPanel.wifiEnabled = radio === "enabled";
        wifiPanel.loaded = true;
        wifiPanel.activeSsid = active;
        wifiPanel.saved = savedMap;
        wifiPanel.networks = list;
        wifiPanel.ethernet = eth;

        if (iface !== wifiPanel.activeIface) {
            wifiPanel.activeIface = iface;
            wifiPanel.activeIp = "";
        }
        if (iface !== "")
            ipProc.running = true;
    }

    Process {
        id: refreshProc
        command: ["bash", "-c",
            'echo "@@radio"\n'
            + 'nmcli radio wifi\n'
            + 'echo "@@wifi"\n'
            + 'nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY device wifi list\n'
            + 'echo "@@saved"\n'
            + 'nmcli -t -f UUID,TYPE connection show | while IFS=: read -r uuid type; do if [ "$type" = "802-11-wireless" ]; then ssid=$(nmcli -g 802-11-wireless.ssid connection show "$uuid"); printf "%s\\t%s\\n" "$ssid" "$uuid"; fi; done\n'
            + 'echo "@@devices"\n'
            + 'nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device status']
        stdout: StdioCollector {
            onStreamFinished: wifiPanel.parseRefresh(text)
        }
    }

    Process {
        id: ipProc
        command: ["nmcli", "-g", "IP4.ADDRESS", "device", "show", wifiPanel.activeIface]
        stdout: StdioCollector {
            onStreamFinished: {
                var addr = text.trim().split("\n")[0] || "";
                wifiPanel.activeIp = addr.split("/")[0];
            }
        }
    }

    // ---------------------------------------------------------------- scanning
    function rescan() {
        if (!wifiPanel.wifiEnabled || rescanProc.running)
            return;
        wifiPanel.scanning = true;
        rescanProc.running = true;
        scanDone.restart();
        refreshSoon.restart();
    }

    Process {
        id: rescanProc
        command: ["nmcli", "-t", "device", "wifi", "rescan"]
    }

    Timer {
        id: scanDone
        interval: 2500
        onTriggered: {
            wifiPanel.scanning = false;
            wifiPanel.refresh();
        }
    }

    Timer {
        id: refreshSoon
        interval: 900
        onTriggered: wifiPanel.refresh()
    }

    // soft poll while open; a rescan every 20s keeps the list fresh
    Timer {
        interval: 2500
        repeat: true
        running: wifiPanel.open
        triggeredOnStart: true
        onTriggered: wifiPanel.refresh()
    }

    Timer {
        interval: 20000
        repeat: true
        running: wifiPanel.open && wifiPanel.wifiEnabled
        onTriggered: wifiPanel.rescan()
    }

    // ---------------------------------------------------------------- actions
    function setWifiEnabled(on) {
        wifiPanel.wifiEnabled = on;
        wifiPanel.errorText = "";
        radioProc.command = ["nmcli", "radio", "wifi", on ? "on" : "off"];
        radioProc.running = false;
        radioProc.running = true;
    }

    Process {
        id: radioProc
        command: []
        onExited: {
            wifiPanel.refresh();
            if (wifiPanel.wifiEnabled)
                wifiPanel.rescan();
        }
    }

    function connectTo(net) {
        if (net.active)
            return;
        wifiPanel.errorText = "";
        wifiPanel.pendingSsid = "";

        var isSaved = !!wifiPanel.saved[net.ssid];
        if (net.security !== "" && !isSaved) {
            // don't burn 10s on a doomed passwordless attempt: ask right away
            wifiPanel.pendingSsid = net.ssid;
            wifiPanel.pendingSecurity = net.security;
            return;
        }

        wifiPanel.connectingSsid = net.ssid;
        connectProc.ssid = net.ssid;
        connectProc.hadSaved = isSaved;
        connectProc.auth = false;
        connectProc.command = ["nmcli", "--wait", "20", "device", "wifi", "connect", net.ssid];
        connectProc.running = false;
        connectProc.running = true;
    }

    function submitPassword(password) {
        if (wifiPanel.pendingSsid === "" || password === "")
            return;
        var ssid = wifiPanel.pendingSsid;
        wifiPanel.connectingSsid = ssid;
        wifiPanel.pendingSsid = "";
        wifiPanel.errorText = "";
        connectProc.ssid = ssid;
        connectProc.hadSaved = !!wifiPanel.saved[ssid];
        connectProc.auth = true;
        connectProc.command = ["nmcli", "--wait", "25", "device", "wifi", "connect", ssid, "password", password];
        connectProc.running = false;
        connectProc.running = true;
    }

    Process {
        id: connectProc
        property string ssid: ""
        property bool hadSaved: false
        property bool auth: false
        command: []
        stderr: StdioCollector { id: connectErr }
        onExited: (code, status) => {
            var ssid = connectProc.ssid;
            wifiPanel.connectingSsid = "";

            if (code === 0) {
                wifiPanel.pendingSsid = "";
                wifiPanel.errorText = "";
                Quickshell.execDetached(["notify-send", "-a", "wifi", "wifi", "connected to " + ssid]);
                refreshSoon.restart();
                return;
            }

            var err = connectErr.text || "";
            var passwordIssue = /secret|password|802-11-wireless-security|authoriz|auth/i.test(err);

            // a failed password attempt can leave a half-made profile behind;
            // drop it so the next try asks again instead of replaying bad creds
            if (connectProc.auth && !connectProc.hadSaved) {
                deleteProc.command = ["nmcli", "connection", "delete", "id", ssid];
                deleteProc.running = false;
                deleteProc.running = true;
            }

            if (passwordIssue || connectProc.auth) {
                wifiPanel.pendingSsid = ssid;
                wifiPanel.pendingSecurity = "";
                wifiPanel.errorText = connectProc.auth ? "wrong password?" : "password required";
            } else {
                wifiPanel.pendingSsid = "";
                wifiPanel.errorText = "couldn't connect to " + ssid;
            }
            refreshSoon.restart();
        }
    }

    Process { id: deleteProc; command: [] }

    function disconnect() {
        if (wifiPanel.activeIface === "")
            return;
        disconnectProc.command = ["nmcli", "device", "disconnect", wifiPanel.activeIface];
        disconnectProc.running = false;
        disconnectProc.running = true;
    }

    Process {
        id: disconnectProc
        command: []
        onExited: refreshSoon.restart()
    }

    function forget(ssid) {
        var uuids = wifiPanel.saved[ssid];
        if (!uuids || uuids.length === 0)
            return;
        forgetProc.command = ["bash", "-c",
            'for u in "$@"; do nmcli connection delete uuid "$u"; done',
            "wifi-forget"].concat(uuids);
        forgetProc.running = false;
        forgetProc.running = true;
        refreshSoon.restart();
    }

    Process { id: forgetProc; command: [] }

    function ethernetAction(dev) {
        ethProc.command = dev.state.indexOf("connected") === 0
            ? ["nmcli", "device", "disconnect", dev.dev]
            : ["nmcli", "device", "connect", dev.dev];
        ethProc.running = false;
        ethProc.running = true;
    }

    Process {
        id: ethProc
        command: []
        onExited: refreshSoon.restart()
    }

    // ------------------------------------------------------------------ layout
    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        // ---- radio row ----------------------------------------------------
        RowLayout {
            Layout.fillWidth: true

            Text {
                text: "wi-fi"
                color: wifiPanel.wifiEnabled ? wifiPanel.pal.accent : wifiPanel.pal.muted
                font.family: wifiPanel.pal.font
                font.pixelSize: 12
                font.bold: true
            }

            Item { Layout.fillWidth: true; height: 1 }

            Rectangle {
                width: radioLabel.implicitWidth + 14
                height: 20
                color: radioMouse.containsMouse ? wifiPanel.pal.hover : "transparent"
                border.width: 1
                border.color: wifiPanel.pal.border

                Text {
                    id: radioLabel
                    anchors.centerIn: parent
                    text: wifiPanel.wifiEnabled ? "enabled" : "disabled"
                    color: radioMouse.containsMouse ? wifiPanel.pal.fg : wifiPanel.pal.muted
                    font.family: wifiPanel.pal.font
                    font.pixelSize: 9
                }

                MouseArea {
                    id: radioMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: wifiPanel.setWifiEnabled(!wifiPanel.wifiEnabled)
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true

            Text {
                text: !wifiPanel.loaded ? "loading…"
                    : !wifiPanel.wifiEnabled ? "radio is off"
                    : wifiPanel.scanning ? "scanning…"
                    : wifiPanel.networks.length + " networks"
                color: wifiPanel.pal.muted
                font.family: wifiPanel.pal.font
                font.pixelSize: 9
            }

            Item { Layout.fillWidth: true; height: 1 }

            Text {
                visible: wifiPanel.wifiEnabled
                text: "rescan"
                color: rescanMouse.containsMouse ? wifiPanel.pal.fg : wifiPanel.pal.muted
                font.family: wifiPanel.pal.font
                font.pixelSize: 9

                MouseArea {
                    id: rescanMouse
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: wifiPanel.rescan()
                }
            }
        }

        // ---- password prompt ----------------------------------------------
        Rectangle {
            Layout.fillWidth: true
            visible: wifiPanel.pendingSsid !== ""
            height: visible ? passColumn.implicitHeight + 12 : 0
            color: wifiPanel.pal.row
            border.width: 1
            border.color: wifiPanel.errorText !== "" ? "#f7768e" : wifiPanel.pal.border

            ColumnLayout {
                id: passColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: 6
                spacing: 3

                Text {
                    Layout.fillWidth: true
                    text: "password for " + wifiPanel.pendingSsid
                        + (wifiPanel.pendingSecurity !== "" ? " · " + wifiPanel.pendingSecurity : "")
                    color: wifiPanel.pal.muted
                    font.family: wifiPanel.pal.font
                    font.pixelSize: 9
                    elide: Text.ElideRight
                }

                Rectangle {
                    Layout.fillWidth: true
                    visible: wifiPanel.pendingSsid !== ""
                    height: 24
                    color: wifiPanel.pal.bg
                    border.width: 1
                    border.color: passInput.activeFocus ? wifiPanel.pal.accent : wifiPanel.pal.border

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        visible: passInput.text === "" && passTyping.empty
                        text: "password"
                        color: wifiPanel.pal.muted
                        font.family: wifiPanel.pal.font
                        font.pixelSize: 10
                    }

                    TextInput {
                        id: passInput
                        anchors.fill: parent
                        anchors.margins: 5
                        // the real text is invisible — TypingFeedback renders it
                        color: "transparent"
                        font.family: wifiPanel.pal.font
                        font.pixelSize: 10
                        verticalAlignment: TextInput.AlignVCenter
                        echoMode: TextInput.Password
                        focus: visible
                        onVisibleChanged: {
                            text = "";
                            if (visible)
                                forceActiveFocus();
                        }
                        onAccepted: wifiPanel.submitPassword(text)
                        Keys.onEscapePressed: {
                            wifiPanel.pendingSsid = "";
                            wifiPanel.errorText = "";
                        }
                    }

                    TypingFeedback {
                        id: passTyping
                        input: passInput
                        pal: wifiPanel.pal
                        fontPixelSize: 10
                        masked: true
                        anchors.fill: parent
                        anchors.margins: 5
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: wifiPanel.errorText === ""
                    text: "enter to connect · esc to cancel"
                    color: wifiPanel.pal.muted
                    font.family: wifiPanel.pal.font
                    font.pixelSize: 8
                }

                Text {
                    Layout.fillWidth: true
                    visible: wifiPanel.errorText !== ""
                    text: wifiPanel.errorText
                    color: "#f7768e"
                    font.family: wifiPanel.pal.font
                    font.pixelSize: 9
                    elide: Text.ElideRight
                }
            }
        }

        // ---- connected card ----------------------------------------------
        Rectangle {
            Layout.fillWidth: true
            visible: wifiPanel.activeSsid !== ""
            height: visible ? connectedColumn.implicitHeight + 12 : 0
            color: wifiPanel.pal.row
            border.width: 1
            border.color: wifiPanel.pal.border

            ColumnLayout {
                id: connectedColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: 6
                spacing: 3

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        Layout.fillWidth: true
                        text: "connected: " + wifiPanel.activeSsid
                        color: wifiPanel.pal.accent
                        font.family: wifiPanel.pal.font
                        font.pixelSize: 10
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    Text {
                        text: "disconnect"
                        color: discMouse.containsMouse ? wifiPanel.pal.fg : wifiPanel.pal.muted
                        font.family: wifiPanel.pal.font
                        font.pixelSize: 9

                        MouseArea {
                            id: discMouse
                            anchors.fill: parent
                            anchors.margins: -4
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: wifiPanel.disconnect()
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        Layout.fillWidth: true
                        text: {
                            var net = null;
                            for (var i = 0; i < wifiPanel.networks.length; i++)
                                if (wifiPanel.networks[i].active)
                                    net = wifiPanel.networks[i];
                            var parts = [];
                            if (wifiPanel.activeIp !== "")
                                parts.push(wifiPanel.activeIp);
                            if (net)
                                parts.push(net.signal + "%");
                            return parts.length > 0 ? parts.join(" · ") : "waiting for address…";
                        }
                        color: wifiPanel.pal.muted
                        font.family: wifiPanel.pal.font
                        font.pixelSize: 9
                        elide: Text.ElideRight
                    }

                    Text {
                        visible: !!wifiPanel.saved[wifiPanel.activeSsid]
                        text: "forget"
                        color: forgetMouse.containsMouse ? "#f7768e" : wifiPanel.pal.muted
                        font.family: wifiPanel.pal.font
                        font.pixelSize: 9

                        MouseArea {
                            id: forgetMouse
                            anchors.fill: parent
                            anchors.margins: -4
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: wifiPanel.forget(wifiPanel.activeSsid)
                        }
                    }
                }
            }
        }

        // ---- network list -------------------------------------------------
        Text {
            text: "NETWORKS"
            color: wifiPanel.pal.muted
            font.family: wifiPanel.pal.font
            font.pixelSize: 9
            font.bold: true
        }

        ListView {
            id: netList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            model: wifiPanel.networks

            delegate: Rectangle {
                id: netRow
                required property var modelData

                width: netList.width
                height: 44
                color: netMouse.containsMouse && !netRow.modelData.active
                    ? wifiPanel.pal.hover : wifiPanel.pal.row

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 6

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        Text {
                            Layout.fillWidth: true
                            text: netRow.modelData.ssid
                            color: netRow.modelData.active ? wifiPanel.pal.accent : wifiPanel.pal.fg
                            font.family: wifiPanel.pal.font
                            font.pixelSize: 10
                            font.bold: netRow.modelData.active
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            text: {
                                var parts = [];
                                parts.push(netRow.modelData.security !== "" ? netRow.modelData.security : "open");
                                if (netRow.modelData.active)
                                    parts.push("connected");
                                else if (netRow.modelData.ssid === wifiPanel.connectingSsid)
                                    parts.push("connecting…");
                                else if (netRow.modelData.saved)
                                    parts.push("saved");
                                return parts.join(" · ");
                            }
                            color: netRow.modelData.ssid === wifiPanel.connectingSsid
                                ? wifiPanel.pal.accent : wifiPanel.pal.muted
                            font.family: wifiPanel.pal.font
                            font.pixelSize: 9
                            elide: Text.ElideRight
                        }
                    }

                    Text {
                        text: netRow.modelData.signal + "%"
                        color: wifiPanel.pal.muted
                        font.family: wifiPanel.pal.font
                        font.pixelSize: 9
                    }

                    Text {
                        visible: !netRow.modelData.active
                        text: "join"
                        color: netMouse.containsMouse ? wifiPanel.pal.fg : wifiPanel.pal.muted
                        font.family: wifiPanel.pal.font
                        font.pixelSize: 9
                    }
                }

                MouseArea {
                    id: netMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: wifiPanel.connectTo(netRow.modelData)
                }
            }
        }

        Text {
            visible: wifiPanel.loaded && wifiPanel.wifiEnabled && wifiPanel.networks.length === 0
            text: wifiPanel.scanning ? "scanning…" : "no networks found"
            color: wifiPanel.pal.muted
            font.family: wifiPanel.pal.font
            font.pixelSize: 10
        }

        // ---- ethernet -----------------------------------------------------
        Text {
            visible: wifiPanel.ethernet.length > 0
            text: "ETHERNET"
            color: wifiPanel.pal.muted
            font.family: wifiPanel.pal.font
            font.pixelSize: 9
            font.bold: true
        }

        Column {
            Layout.fillWidth: true
            spacing: 2

            Repeater {
                model: wifiPanel.ethernet

                delegate: Rectangle {
                    id: ethRow
                    required property var modelData

                    width: parent.width
                    height: 30
                    color: ethMouse.containsMouse ? wifiPanel.pal.hover : wifiPanel.pal.row

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 6

                        Text {
                            Layout.fillWidth: true
                            text: ethRow.modelData.dev
                                + " · " + (ethRow.modelData.state === "unavailable"
                                    ? "unplugged" : ethRow.modelData.state)
                            color: ethRow.modelData.state.indexOf("connected") === 0
                                ? wifiPanel.pal.accent : wifiPanel.pal.fg
                            font.family: wifiPanel.pal.font
                            font.pixelSize: 9
                            elide: Text.ElideRight
                        }

                        Text {
                            text: ethRow.modelData.state === "unavailable" ? "no cable"
                                : ethRow.modelData.state.indexOf("connected") === 0 ? "disconnect" : "connect"
                            color: ethMouse.containsMouse && ethMouse.enabled
                                ? wifiPanel.pal.fg : wifiPanel.pal.muted
                            font.family: wifiPanel.pal.font
                            font.pixelSize: 9
                        }
                    }

                    MouseArea {
                        id: ethMouse
                        anchors.fill: parent
                        enabled: ethRow.modelData.state !== "unavailable"
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: wifiPanel.ethernetAction(ethRow.modelData)
                    }
                }
            }
        }
    }

    // Esc closes (or cancels a pending password first)
    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: {
            if (wifiPanel.pendingSsid !== "") {
                wifiPanel.pendingSsid = "";
                wifiPanel.errorText = "";
            } else {
                wifiPanel.shell.closeAllBut("");
            }
        }
    }
}
