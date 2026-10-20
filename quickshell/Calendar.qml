import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

// Omarchy-inspired calendar: centered month grid, ISO week numbers, month stepping.
PanelWindow {
    id: calendar

    property var shell
    readonly property Miasma pal: Miasma {}
    property date shownMonth: new Date()
    readonly property date today: new Date()
    readonly property int year: shownMonth.getFullYear()
    readonly property int month: shownMonth.getMonth()
    readonly property var weekdays: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
    readonly property var cells: makeCells()

    function daysInMonth(y, m) {
        return new Date(y, m + 1, 0).getDate();
    }

    function mondayIndex(y, m) {
        var day = new Date(y, m, 1).getDay();
        return (day + 6) % 7;
    }

    function isoWeek(y, m, d) {
        var date = new Date(y, m, d);
        date.setHours(0, 0, 0, 0);
        date.setDate(date.getDate() + 3 - ((date.getDay() + 6) % 7));
        var week1 = new Date(date.getFullYear(), 0, 4);
        return 1 + Math.round(((date - week1) / 86400000 - 3 + ((week1.getDay() + 6) % 7)) / 7);
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

    function resetToday() {
        calendar.shownMonth = new Date();
    }

    visible: shell.calendarOpen
    anchors {
        top: true
        left: true
        right: true
    }
    margins.top: pal.barHeight + 6
    implicitHeight: card.implicitHeight
    color: "transparent"
    exclusiveZone: 0
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-calendar"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    onVisibleChanged: if (visible) calendar.resetToday()

    Rectangle {
        id: card
        width: 330
        implicitHeight: content.implicitHeight + 24
        radius: 0
        color: calendar.pal.bg1
        border.width: 1
        border.color: calendar.pal.bg2

        Column {
            id: content
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            RowLayout {
                width: parent.width
                height: 28

                Text {
                    text: Qt.formatDate(calendar.shownMonth, "MMMM yyyy")
                    color: calendar.pal.fg
                    font.family: calendar.pal.font
                    font.pixelSize: 14
                    font.bold: true
                    Layout.fillWidth: true
                }

                Rectangle {
                    width: 26
                    height: 26
                    color: previousMouse.containsMouse ? calendar.pal.bg2 : "transparent"
                    Text { anchors.centerIn: parent; text: "‹"; color: calendar.pal.fg; font.pixelSize: 20 }
                    MouseArea {
                        id: previousMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: calendar.shiftMonth(-1)
                    }
                }

                Rectangle {
                    width: 26
                    height: 26
                    color: nextMouse.containsMouse ? calendar.pal.bg2 : "transparent"
                    Text { anchors.centerIn: parent; text: "›"; color: calendar.pal.fg; font.pixelSize: 20 }
                    MouseArea {
                        id: nextMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: calendar.shiftMonth(1)
                    }
                }
            }

            Row {
                width: parent.width
                spacing: 0
                Text {
                    width: 28
                    text: "W"
                    color: calendar.pal.gray
                    font.family: calendar.pal.font
                    font.pixelSize: 10
                    horizontalAlignment: Text.AlignHCenter
                }
                Repeater {
                    model: calendar.weekdays
                    delegate: Text {
                        required property string modelData
                        width: 40
                        text: modelData
                        color: calendar.pal.gray
                        font.family: calendar.pal.font
                        font.pixelSize: 10
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }

            Column {
                spacing: 2
                Repeater {
                    model: 6
                    delegate: Row {
                        id: dayRow
                        required property int index
                        spacing: 0
                        Text {
                            width: 28
                            height: 28
                            text: calendar.isoWeek(calendar.year, calendar.month, Math.max(1, index * 7 - calendar.mondayIndex(calendar.year, calendar.month) + 1))
                            color: calendar.pal.gray
                            font.family: calendar.pal.font
                            font.pixelSize: 10
                            verticalAlignment: Text.AlignVCenter
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Repeater {
                            model: 7
                            delegate: Rectangle {
                                required property int index
                                readonly property var cell: calendar.cells[dayRow.index * 7 + index]
                                width: 40
                                height: 28
                                color: cell.today ? calendar.pal.gold : "transparent"

                                Text {
                                    anchors.centerIn: parent
                                    text: cell.day > 0 ? cell.day : ""
                                    color: cell.today ? calendar.pal.bg0 : calendar.pal.fg
                                    font.family: calendar.pal.font
                                    font.pixelSize: 11
                                    font.bold: cell.today
                                }
                            }
                        }
                    }
                }
            }

            Text {
                width: parent.width
                text: "today: " + Qt.formatDate(calendar.today, "ddd, MMM d")
                color: calendar.pal.fg1
                font.family: calendar.pal.font
                font.pixelSize: 10
                horizontalAlignment: Text.AlignRight
            }
        }
    }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: calendar.shell.closeAllBut("")
    }
}
