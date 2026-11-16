import Quickshell
import Quickshell.Io
import QtQuick

// Root of Narla's Miasma shell: wallpaper + bar + panels. Fuzzel is the app launcher.
ShellRoot {
    id: root

    property bool calendarOpen: false

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
