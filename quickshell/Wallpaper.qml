import Quickshell
import Quickshell.Wayland
import QtQuick

// Draws rockman.png on the background layer of the focused screen.
PanelWindow {
    id: wallpaper

    readonly property Miasma pal: Miasma {}
    // Prefer the user's Downloads copy; the identical bundled image is a fallback.
    readonly property url localImage: "file://" + Quickshell.env("HOME") + "/Downloads/rockman.png"
    readonly property url fallbackImage: Qt.resolvedUrl("wallpapers/rockman.png")

    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }

    color: pal.bg0
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "quickshell-wallpaper"

    Image {
        anchors.fill: parent
        source: wallpaper.localImage
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        smooth: true

        // Downloads copy missing? Use the identical image shipped with the config.
        onStatusChanged: if (status === Image.Error && source != wallpaper.fallbackImage)
            source = wallpaper.fallbackImage
    }
}
