import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Layouts

// Media panel (MPRIS): album art, track info, seek bar and transport buttons
// for the active player, in the shared gruvbox right-edge column.
SidePanelWindow {
    id: mediaPanel

    property var shell
    open: !!mediaPanel.shell && mediaPanel.shell.mprisOpen
    title: "media"
    namespace: "quickshell-mpris"

    // ---- player selection: first playing player, else first known --------
    property MprisPlayer player: null

    function pickPlayer() {
        var list = Mpris.players.values;
        var chosen = null;
        for (var i = 0; i < list.length; i++) {
            if (list[i].playbackState === MprisPlaybackState.Playing) {
                chosen = list[i];
                break;
            }
        }
        if (!chosen && list.length > 0)
            chosen = list[0];
        mediaPanel.player = chosen;
    }

    Component.onCompleted: mediaPanel.pickPlayer()

    Connections {
        target: Mpris.players
        function onValuesChanged() { mediaPanel.pickPlayer() }
    }

    readonly property bool playing: player !== null
        && player.playbackState === MprisPlaybackState.Playing
    readonly property real trackLength: player !== null && player.length > 0 ? player.length : 0

    // quickshell advances player.position itself while playing, so the bar
    // tracks it directly — never accumulate on top of it
    readonly property real dispPos: player ? player.position : 0

    function fmtTime(ms) {
        if (!ms || ms <= 0)
            return "0:00";
        var s = Math.floor(ms / 1000);
        return Math.floor(s / 60) + ":" + ("0" + (s % 60)).slice(-2);
    }

    // artwork arrives either as a remote/local URL or a plain path
    function artSource(p) {
        if (!p || p === "")
            return "";
        return p.indexOf("/") === 0 ? "file://" + p : p;
    }

    readonly property string art: artSource(player ? (player.trackArt || player.trackArtUrl) : "")

    function seekTo(ratio) {
        if (!player || !player.canSeek || trackLength <= 0)
            return;
        player.position = Math.max(0, Math.min(1, ratio)) * trackLength;
    }

    Column {
        anchors.fill: parent
        spacing: 12

        // ---- player name / empty state -----------------------------------
        Text {
            width: parent.width
            text: mediaPanel.player ? (mediaPanel.player.identity || "player") : "nothing is playing"
            color: mediaPanel.pal.muted
            font.family: mediaPanel.pal.font
            font.pixelSize: 10
            elide: Text.ElideRight
        }

        // ---- album art ----------------------------------------------------
        Rectangle {
            width: parent.width
            height: parent.width
            color: mediaPanel.pal.row
            border.width: 1
            border.color: mediaPanel.pal.border

            Image {
                anchors.fill: parent
                anchors.margins: 8
                source: mediaPanel.art
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                visible: mediaPanel.art !== ""
            }

            Text {
                anchors.centerIn: parent
                visible: mediaPanel.art === ""
                text: "♫"
                color: mediaPanel.pal.muted
                font.family: mediaPanel.pal.font
                font.pixelSize: 44
            }
        }

        // ---- track info ----------------------------------------------------
        Text {
            width: parent.width
            text: mediaPanel.player ? (mediaPanel.player.trackTitle || "nothing is playing") : "nothing is playing"
            color: mediaPanel.pal.fg
            font.family: mediaPanel.pal.font
            font.pixelSize: 13
            font.bold: true
            wrapMode: Text.Wrap
        }

        Text {
            width: parent.width
            visible: mediaPanel.player && mediaPanel.player.trackArtist !== ""
            text: mediaPanel.player ? mediaPanel.player.trackArtist : ""
            color: mediaPanel.pal.muted
            font.family: mediaPanel.pal.font
            font.pixelSize: 11
            wrapMode: Text.Wrap
        }

        Text {
            width: parent.width
            visible: mediaPanel.player && mediaPanel.player.trackAlbum !== ""
            text: mediaPanel.player ? mediaPanel.player.trackAlbum : ""
            color: mediaPanel.pal.muted
            font.family: mediaPanel.pal.font
            font.pixelSize: 10
            wrapMode: Text.Wrap
        }

        // ---- seek bar -------------------------------------------------------
        Item {
            width: parent.width
            height: 8
            visible: mediaPanel.player !== null

            Rectangle {
                id: seekTrack
                anchors.fill: parent
                color: mediaPanel.pal.row
                border.width: 1
                border.color: mediaPanel.pal.border

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.margins: 1
                    width: mediaPanel.trackLength > 0
                        ? (parent.width - 2) * Math.max(0, Math.min(1, mediaPanel.dispPos / mediaPanel.trackLength))
                        : 0
                    color: mediaPanel.pal.accent
                }
            }

            MouseArea {
                anchors.fill: seekTrack
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => mediaPanel.seekTo(mouse.x / width)
                onPositionChanged: mouse => {
                    if (mouse.buttons & Qt.LeftButton)
                        mediaPanel.seekTo(mouse.x / width);
                }
            }
        }

        // ---- position / length row ------------------------------------------
        RowLayout {
            width: parent.width
            visible: mediaPanel.player !== null

            Text {
                text: mediaPanel.fmtTime(mediaPanel.dispPos)
                color: mediaPanel.pal.muted
                font.family: mediaPanel.pal.font
                font.pixelSize: 10
            }

            Item { Layout.fillWidth: true; height: 1 }

            Text {
                text: mediaPanel.fmtTime(mediaPanel.trackLength)
                color: mediaPanel.pal.muted
                font.family: mediaPanel.pal.font
                font.pixelSize: 10
            }
        }

        // ---- transport controls ---------------------------------------------
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 24
            visible: mediaPanel.player !== null

            Text {
                text: "⏮"
                color: mediaPanel.player && mediaPanel.player.canGoPrevious
                    ? mediaPanel.pal.fg : mediaPanel.pal.muted
                font.family: mediaPanel.pal.font
                font.pixelSize: 18

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -8
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (mediaPanel.player && mediaPanel.player.canGoPrevious)
                        mediaPanel.player.previous()
                }
            }

            Text {
                text: mediaPanel.playing ? "⏸" : "⏵"
                color: mediaPanel.pal.fg
                font.family: mediaPanel.pal.font
                font.pixelSize: 20

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -8
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        var p = mediaPanel.player;
                        if (!p)
                            return;
                        if (mediaPanel.playing ? p.canPause : p.canPlay)
                            p.togglePlaying();
                    }
                }
            }

            Text {
                text: "⏭"
                color: mediaPanel.player && mediaPanel.player.canGoNext
                    ? mediaPanel.pal.fg : mediaPanel.pal.muted
                font.family: mediaPanel.pal.font
                font.pixelSize: 18

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -8
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (mediaPanel.player && mediaPanel.player.canGoNext)
                        mediaPanel.player.next()
                }
            }
        }
    }

    // Esc closes
    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: mediaPanel.shell.closeAllBut("")
    }
}
