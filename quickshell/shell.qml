import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// Root of Narla's shell: wallpaper + bar + right-edge panels.
ShellRoot {
    id: root

    property bool calendarOpen: false
    property bool clipboardOpen: false
    property bool emojiOpen: false
    property bool launcherOpen: false
    property bool systemMenuOpen: false
    property bool notificationCenterOpen: false
    property bool mprisOpen: false
    property bool wifiOpen: false
    property bool audioOpen: false
    property bool flowstateOpen: false

    // incremented by Notifications.qml on each notification, cleared by the bell
    property int unreadNotifications: 0

    readonly property bool sidePanelOpen: calendarOpen || clipboardOpen || emojiOpen || launcherOpen || systemMenuOpen || notificationCenterOpen || mprisOpen || wifiOpen || audioOpen || flowstateOpen

    function closeAllBut(which) {
        calendarOpen = which === "calendar";
        clipboardOpen = which === "clipboard";
        emojiOpen = which === "emoji";
        launcherOpen = which === "launcher";
        systemMenuOpen = which === "system";
        notificationCenterOpen = which === "notifications";
        mprisOpen = which === "mpris";
        wifiOpen = which === "wifi";
        audioOpen = which === "audio";
        flowstateOpen = which === "flowstate";
    }

    function openClipboard() {
        closeAllBut(clipboardOpen ? "" : "clipboard");
    }

    function openCalendar() {
        closeAllBut(calendarOpen ? "" : "calendar");
    }

    function openAppLauncher() {
        closeAllBut(launcherOpen ? "" : "launcher");
    }

    function openSystemMenu() {
        closeAllBut(systemMenuOpen ? "" : "system");
    }

    function openNotificationCenter() {
        closeAllBut(notificationCenterOpen ? "" : "notifications");
        unreadNotifications = 0;
    }

    function openMpris() {
        closeAllBut(mprisOpen ? "" : "mpris");
    }

    function clearNotificationHistory() {
        notifications.clearHistory();
    }

    function openWifiMenu() {
        closeAllBut(wifiOpen ? "" : "wifi");
    }

    function openEmojiPicker() {
        closeAllBut(emojiOpen ? "" : "emoji");
    }

    function openAudioMenu() {
        closeAllBut(audioOpen ? "" : "audio");
    }

    function openFlowstate() {
        closeAllBut(flowstateOpen ? "" : "flowstate");
    }

    Wallpaper {}

    Bar {
        shell: root
    }

    Calendar {
        shell: root
    }

    EmojiPicker {
        shell: root
    }

    Notifications {
        id: notifications
        shell: root
    }

    NotificationCenter {
        shell: root
        historyModel: notifications.historyModel
    }

    MprisPanel {
        shell: root
    }

    WifiPanel {
        shell: root
    }

    AudioPanel {
        shell: root
    }

    FlowstatePanel {
        shell: root
    }

    Clipboard {
        shell: root
    }

    Launcher {
        shell: root
    }

    SystemMenu {
        shell: root
    }

    // Invisible spacer that reserves the right edge while any right-side panel
    // is open, so tiled windows slide out of its way. Hyprland ignores
    // exclusive zones on corner-anchored surfaces, so the panels can't do it
    // themselves — this one spans top->bottom on the right edge instead.
    PanelWindow {
        anchors {
            top: true
            right: true
            bottom: true
        }
        margins.right: root.sidePanelOpen ? 0 : -2
        exclusiveZone: root.sidePanelOpen ? 380 : 0
        exclusionMode: ExclusionMode.Normal
        implicitWidth: 1
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "quickshell-panel-spacer"
    }

    IpcHandler {
        target: "bar"

        function wifi() {
            root.openWifiMenu();
        }

        function audio() {
            root.openAudioMenu();
        }

        function clipboard() {
            root.openClipboard();
        }

        function emoji() {
            root.openEmojiPicker();
        }

        function calendar() {
            root.openCalendar();
        }

        function launcher() {
            root.openAppLauncher();
        }

        function system() {
            root.openSystemMenu();
        }

        function notifications() {
            root.openNotificationCenter();
        }

        function mpris() {
            root.openMpris();
        }

        function flowstate() {
            root.openFlowstate();
        }

        function close() {
            root.closeAllBut("");
        }
    }

    IpcHandler {
        target: "notifications"

        function dismiss() {
            notifications.dismissAll();
        }

        function dismissAll() {
            notifications.dismissAll();
        }
    }
}
