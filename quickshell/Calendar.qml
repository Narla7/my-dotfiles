import Quickshell
import Quickshell.Wayland
import QtQuick

// Calendar sidebar — right-edge column like the clipboard/launcher. Shows the
// current month's days only (no week numbers), a progress bar for how much of
// the month has passed, left/right month stepping (buttons and arrow keys),
// and a 1px outline on today. mod+C toggles it.
SidePanelWindow {
    id: calendar

    property var shell
    open: !!calendar.shell && calendar.shell.calendarOpen
    title: "calendar"
    namespace: "quickshell-calendar"

    property date shownMonth: new Date()
    readonly property date today: new Date()
    readonly property int year: shownMonth.getFullYear()
    readonly property int month: shownMonth.getMonth()
    readonly property var weekdays: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
    readonly property var cells: makeCells()

    // fraction of the shown month that has already passed: 0..1
    readonly property real monthProgress: {
        var days = daysInMonth(year, month);
        var diff = (today.getFullYear() - year) * 12 + (today.getMonth() - month);
        if (diff > 0)
            return 1; // a past month: fully over
        if (diff < 0)
            return 0; // a future month: not started
        // current month: elapsed days / total days
        return today.getDate() / days;
    }

    function daysInMonth(y, m) {
        return new Date(y, m + 1, 0).getDate();
    }

    function mondayIndex(y, m) {
        var day = new Date(y, m, 1).getDay();
        return (day + 6) % 7;
    }

    function makeCells() {
        var out = [];
        var first = mondayIndex(year, month);
        var count = daysInMonth(year, month);
        for (var i = 0; i < 42; i++) {
            var n = i - first + 1;
            var valid = n >= 1 && n <= count;
            out.push({
                day: valid ? n : 0,
                today: valid && year === today.getFullYear() && month === today.getMonth() && n === today.getDate()
            });
        }
        return out;
    }

    function shiftMonth(delta) {
        calendar.shownMonth = new Date(year, month + delta, 1);
    }

    onOpenChanged: if (open) {
        calendar.shownMonth = new Date();
        focusGrab.forceActiveFocus();
    }

    Item {
        anchors.fill: parent

        Column {
            anchors.fill: parent
            spacing: 10

            // month progress: "how much of the month is over"
            Item {
                width: parent.width
                height: 26

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: Qt.formatDate(calendar.shownMonth, "MMMM yyyy")
                    color: calendar.pal.accent
                    font.family: calendar.pal.font
                    font.pixelSize: 13
                    font.bold: true
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: Math.round(calendar.monthProgress * 100) + "%"
                    color: calendar.pal.muted
                    font.family: calendar.pal.font
                    font.pixelSize: 11
                }
            }

            Rectangle {
                width: parent.width
                height: 6
                color: calendar.pal.border

                Rectangle {
                    width: parent.width * calendar.monthProgress
                    height: parent.height
                    color: calendar.pal.accent
                }
            }

            Row {
                width: parent.width
                spacing: 0
                Repeater {
                    model: calendar.weekdays
                    delegate: Text {
                        required property string modelData
                        width: parent.width / 7
                        text: modelData
                        color: calendar.pal.muted
                        font.family: calendar.pal.font
                        font.pixelSize: 10
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }

            Column {
                width: parent.width
                spacing: 2
                Repeater {
                    model: 6
                    delegate: Row {
                        id: dayRow
                        required property int index
                        width: parent.width
                        spacing: 0
                        Repeater {
                            model: 7
                            delegate: Rectangle {
                                required property int index
                                readonly property var cell: calendar.cells[dayRow.index * 7 + index]
                                width: dayRow.width / 7
                                height: 32
                                radius: 0
                                color: "transparent"
                                border.width: cell.today ? 1 : 0
                                border.color: calendar.pal.accent

                                Text {
                                    anchors.centerIn: parent
                                    text: cell.day > 0 ? cell.day : ""
                                    color: cell.today ? calendar.pal.accent : calendar.pal.fg
                                    font.family: calendar.pal.font
                                    font.pixelSize: 11
                                    font.bold: cell.today
                                }
                            }
                        }
                    }
                }
            }

            // month stepping: prev / today / next
            Row {
                width: parent.width
                spacing: 8

                Rectangle {
                    width: (parent.width - 16) / 3
                    height: 26
                    radius: 0
                    color: prevMouse.containsMouse ? calendar.pal.hover : calendar.pal.row
                    border.width: 1
                    border.color: calendar.pal.border
                    Text {
                        anchors.centerIn: parent
                        text: "◀ prev"
                        color: calendar.pal.fg
                        font.family: calendar.pal.font
                        font.pixelSize: 10
                    }
                    MouseArea {
                        id: prevMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: calendar.shiftMonth(-1)
                    }
                }

                Rectangle {
                    width: (parent.width - 16) / 3
                    height: 26
                    radius: 0
                    color: todayMouse.containsMouse ? calendar.pal.hover : calendar.pal.row
                    border.width: 1
                    border.color: calendar.pal.border
                    Text {
                        anchors.centerIn: parent
                        text: "today"
                        color: calendar.pal.fg
                        font.family: calendar.pal.font
                        font.pixelSize: 10
                    }
                    MouseArea {
                        id: todayMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: calendar.shownMonth = new Date()
                    }
                }

                Rectangle {
                    width: (parent.width - 16) / 3
                    height: 26
                    radius: 0
                    color: nextMouse.containsMouse ? calendar.pal.hover : calendar.pal.row
                    border.width: 1
                    border.color: calendar.pal.border
                    Text {
                        anchors.centerIn: parent
                        text: "next ▶"
                        color: calendar.pal.fg
                        font.family: calendar.pal.font
                        font.pixelSize: 10
                    }
                    MouseArea {
                        id: nextMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: calendar.shiftMonth(1)
                    }
                }
            }

            Text {
                width: parent.width
                text: "today: " + Qt.formatDate(calendar.today, "ddd, MMM d")
                    + " · ←/→ switch month · esc close"
                color: calendar.pal.muted
                font.family: calendar.pal.font
                font.pixelSize: 9
            }
        }
    }

    // keep arrow keys / esc while the panel is open
    FocusScope {
        id: focusGrab
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: calendar.shell.closeAllBut("")
        Keys.onLeftPressed: calendar.shiftMonth(-1)
        Keys.onRightPressed: calendar.shiftMonth(1)
    }
}
