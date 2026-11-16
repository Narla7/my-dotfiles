import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// Root of Narla's Miasma shell: wallpaper + bar + panels. Fuzzel is the app launcher.
ShellRoot {
    id: root

    property bool calendarOpen: false
    property bool clipboardOpen: false

    function closeAllBut(which) {
        calendarOpen = which === "calendar";
        clipboardOpen = which === "clipboard";
    }

    function openClipboard() {
        closeAllBut(clipboardOpen ? "" : "clipboard");
    }

    function openAppLauncher() {
        closeAllBut("");
        Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/hypr/toggle-launcher.sh"]);
    }

    function openWifiMenu() {
        Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/hypr/wifi-menu.sh"]);
    }

    function openAudioMenu() {
        Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/hypr/audio-menu.sh"]);
    }

    Wallpaper {}

    Bar {
        shell: root
    }

    Calendar {
        shell: root
    }

    Notifications {
        id: notifications
        shell: root
    }

    Clipboard {
        shell: root
    }

    // Invisible spacer that reserves the right edge while the clipboard centre
    // is open, so tiled windows slide out of its way. Hyprland ignores
    // exclusive zones on corner-anchored surfaces, so the panel can't do it
    // itself — this one spans top->bottom on the right edge instead.
    PanelWindow {
        anchors {
            top: true
            right: true
            bottom: true
        }
        margins.right: root.clipboardOpen ? 0 : -2
        exclusiveZone: root.clipboardOpen ? 380 : 0
        exclusionMode: ExclusionMode.Normal
        implicitWidth: 1
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "quickshell-clipboard-spacer"
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
