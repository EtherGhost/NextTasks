import QtQuick 2.7
import Lomiri.Components 1.3

Item {
    id: root

    property string value: ""
    property date visibleMonth: value.length > 0 ? dateFromText(value) : new Date()
    property string selectedDate: normalizeDateText(value)
    property bool showClearButton: true
    property bool showCancelButton: true
    property string okText: qsTr("OK")
    property string todayTextLabel: qsTr("Today")
    property string clearText: qsTr("Clear")
    property string cancelText: qsTr("Cancel")
    property string viewMode: "month"

    signal accepted(string dateText)
    signal canceled()
    signal cleared()
    signal selected(string dateText)

    implicitWidth: units.gu(34)
    implicitHeight: contentColumn.height

    onValueChanged: {
        selectedDate = normalizeDateText(value)
        if (selectedDate.length > 0) {
            visibleMonth = dateFromText(selectedDate)
        }
    }

    function pad(value) {
        return value < 10 ? "0" + value : String(value)
    }

    function normalizeDateText(input) {
        var text = String(input || "").trim()
        if (text.length === 0) return ""
        if (/^\d{8}$/.test(text)) {
            return text.substring(0, 4) + "-" + text.substring(4, 6) + "-" + text.substring(6, 8)
        }
        if (/^\d{4}-\d{2}-\d{2}$/.test(text)) {
            return text
        }
        return ""
    }

    function formatDate(date) {
        return date.getFullYear() + "-" + pad(date.getMonth() + 1) + "-" + pad(date.getDate())
    }

    function todayText() {
        return formatDate(new Date())
    }

    function dateFromText(input) {
        var text = normalizeDateText(input)
        if (text.length === 0) return new Date()
        return new Date(parseInt(text.substring(0, 4), 10), parseInt(text.substring(5, 7), 10) - 1, parseInt(text.substring(8, 10), 10))
    }

    function monthTitle(date) {
        var names = [qsTr("January"), qsTr("February"), qsTr("March"), qsTr("April"), qsTr("May"), qsTr("June"), qsTr("July"), qsTr("August"), qsTr("September"), qsTr("October"), qsTr("November"), qsTr("December")]
        return names[date.getMonth()] + " " + date.getFullYear()
    }

    function shiftMonth(delta) {
        if (viewMode === "year") {
            visibleMonth = new Date(visibleMonth.getFullYear() + delta * 12, visibleMonth.getMonth(), 1)
        } else {
            visibleMonth = new Date(visibleMonth.getFullYear(), visibleMonth.getMonth() + delta, 1)
        }
    }

    function yearAt(index) {
        var start = Math.floor(visibleMonth.getFullYear() / 12) * 12
        return start + index
    }

    function yearIsSelected(year) {
        return selectedDate.length > 0 && dateFromText(selectedDate).getFullYear() === year
    }

    function yearIsCurrent(year) {
        return new Date().getFullYear() === year
    }

    function chooseYear(year) {
        visibleMonth = new Date(year, visibleMonth.getMonth(), 1)
        viewMode = "month"
    }

    function cellDate(index) {
        var first = new Date(visibleMonth.getFullYear(), visibleMonth.getMonth(), 1)
        var mondayOffset = (first.getDay() + 6) % 7
        return new Date(visibleMonth.getFullYear(), visibleMonth.getMonth(), 1 - mondayOffset + index)
    }

    function cellText(index) {
        return formatDate(cellDate(index))
    }

    function cellInMonth(index) {
        return cellDate(index).getMonth() === visibleMonth.getMonth()
    }

    function cellIsToday(index) {
        return cellText(index) === todayText()
    }

    function cellIsSelected(index) {
        return selectedDate === cellText(index)
    }

    function chooseDate(dateText) {
        selectedDate = normalizeDateText(dateText)
        selected(selectedDate)
    }

    Column {
        id: contentColumn
        width: root.width
        spacing: units.gu(1)

        Row {
            width: parent.width
            height: units.gu(4.6)
            spacing: units.gu(0.5)

            Rectangle {
                width: units.gu(4.6)
                height: parent.height
                radius: units.gu(0.4)
                color: prevMouse.pressed ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

                Label {
                    anchors.centerIn: parent
                    text: "<"
                    font.pixelSize: units.gu(2.5)
                    color: theme.palette.normal.backgroundText
                }

                MouseArea {
                    id: prevMouse
                    anchors.fill: parent
                    onClicked: root.shiftMonth(-1)
                }
            }

            Label {
                id: titleLabel
                width: parent.width - units.gu(9.2) - parent.spacing * 2
                height: parent.height
                text: root.viewMode === "year" ? String(root.yearAt(0)) + " - " + String(root.yearAt(11)) : root.monthTitle(root.visibleMonth)
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
                font.bold: true
                fontSize: "large"
                color: theme.palette.normal.backgroundText

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.viewMode = root.viewMode === "year" ? "month" : "year"
                }
            }

            Rectangle {
                width: units.gu(4.6)
                height: parent.height
                radius: units.gu(0.4)
                color: nextMouse.pressed ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

                Label {
                    anchors.centerIn: parent
                    text: ">"
                    font.pixelSize: units.gu(2.5)
                    color: theme.palette.normal.backgroundText
                }

                MouseArea {
                    id: nextMouse
                    anchors.fill: parent
                    onClicked: root.shiftMonth(1)
                }
            }
        }

        Row {
            visible: root.viewMode === "month"
            width: parent.width
            height: units.gu(2.4)
            spacing: units.gu(0.2)

            Repeater {
                model: [qsTr("Mon"), qsTr("Tue"), qsTr("Wed"), qsTr("Thu"), qsTr("Fri"), qsTr("Sat"), qsTr("Sun")]

                Label {
                    width: (parent.width - parent.spacing * 6) / 7
                    height: parent.height
                    text: modelData
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    opacity: 0.65
                    font.bold: true
                    fontSize: "x-small"
                    color: theme.palette.normal.backgroundText
                }
            }
        }

        Grid {
            id: calendarGrid
            visible: root.viewMode === "month"
            width: parent.width
            columns: 7
            spacing: units.gu(0.2)

            Repeater {
                model: 42

                Rectangle {
                    width: (calendarGrid.width - calendarGrid.spacing * 6) / 7
                    height: units.gu(4.2)
                    radius: units.gu(0.55)
                    color: root.cellIsSelected(index) ? "#2c7fb8" : (dayMouse.pressed ? Qt.rgba(1, 1, 1, 0.08) : "transparent")
                    border.width: root.cellIsToday(index) && !root.cellIsSelected(index) ? 2 : 0
                    border.color: root.cellIsToday(index) ? "#5a8f3c" : theme.palette.normal.base
                    opacity: root.cellInMonth(index) ? 1.0 : 0.32

                    Label {
                        anchors.centerIn: parent
                        text: String(root.cellDate(index).getDate())
                        color: root.cellIsSelected(index) ? "white" : theme.palette.normal.backgroundText
                        font.bold: root.cellIsToday(index) || root.cellIsSelected(index)
                    }

                    MouseArea {
                        id: dayMouse
                        anchors.fill: parent
                        onClicked: root.chooseDate(root.cellText(index))
                    }
                }
            }
        }

        Grid {
            id: yearGrid
            visible: root.viewMode === "year"
            width: parent.width
            columns: 3
            spacing: units.gu(0.4)

            Repeater {
                model: 12

                Rectangle {
                    property int year: root.yearAt(index)

                    width: (yearGrid.width - yearGrid.spacing * 2) / 3
                    height: units.gu(5.4)
                    radius: units.gu(0.55)
                    color: root.yearIsSelected(year) ? "#2c7fb8" : (yearMouse.pressed ? Qt.rgba(1, 1, 1, 0.08) : "transparent")
                    border.width: root.yearIsCurrent(year) && !root.yearIsSelected(year) ? 2 : 0
                    border.color: "#5a8f3c"

                    Label {
                        anchors.centerIn: parent
                        text: String(parent.year)
                        color: root.yearIsSelected(parent.year) ? "white" : theme.palette.normal.backgroundText
                        font.bold: root.yearIsSelected(parent.year) || root.yearIsCurrent(parent.year)
                    }

                    MouseArea {
                        id: yearMouse
                        anchors.fill: parent
                        onClicked: root.chooseYear(parent.year)
                    }
                }
            }
        }

        Row {
            width: parent.width
            height: units.gu(4.8)
            spacing: units.gu(0.8)

            Rectangle {
                visible: root.showClearButton
                width: visible ? Math.max(units.gu(7), clearLabel.implicitWidth + units.gu(2)) : 0
                height: parent.height
                radius: units.gu(0.4)
                color: clearMouse.pressed ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

                Label {
                    id: clearLabel
                    anchors.centerIn: parent
                    text: root.clearText
                    color: theme.palette.normal.backgroundText
                    opacity: 0.78
                }

                MouseArea {
                    id: clearMouse
                    anchors.fill: parent
                    onClicked: {
                        root.selectedDate = ""
                        root.cleared()
                    }
                }
            }

            Rectangle {
                width: Math.max(units.gu(7), todayLabel.implicitWidth + units.gu(2))
                height: parent.height
                radius: units.gu(0.4)
                color: todayMouse.pressed ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

                Label {
                    id: todayLabel
                    anchors.centerIn: parent
                    text: root.todayTextLabel
                    color: theme.palette.normal.backgroundText
                    opacity: 0.78
                }

                MouseArea {
                    id: todayMouse
                    anchors.fill: parent
                    onClicked: {
                        root.visibleMonth = new Date()
                        root.viewMode = "month"
                        root.chooseDate(root.todayText())
                    }
                }
            }

            Item {
                width: Math.max(0, parent.width
                    - (root.showClearButton ? Math.max(units.gu(7), clearLabel.implicitWidth + units.gu(2)) : 0)
                    - Math.max(units.gu(7), todayLabel.implicitWidth + units.gu(2))
                    - (root.showCancelButton ? Math.max(units.gu(7), cancelLabel.implicitWidth + units.gu(2)) : 0)
                    - Math.max(units.gu(7), okLabel.implicitWidth + units.gu(2))
                    - parent.spacing * (1 + (root.showClearButton ? 1 : 0) + (root.showCancelButton ? 1 : 0)))
                height: 1
            }

            Rectangle {
                visible: root.showCancelButton
                width: visible ? Math.max(units.gu(7), cancelLabel.implicitWidth + units.gu(2)) : 0
                height: parent.height
                radius: units.gu(0.4)
                color: cancelMouse.pressed ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

                Label {
                    id: cancelLabel
                    anchors.centerIn: parent
                    text: root.cancelText
                    color: theme.palette.normal.backgroundText
                    opacity: 0.78
                }

                MouseArea {
                    id: cancelMouse
                    anchors.fill: parent
                    onClicked: root.canceled()
                }
            }

            Rectangle {
                width: Math.max(units.gu(7), okLabel.implicitWidth + units.gu(2))
                height: parent.height
                radius: units.gu(0.4)
                color: okMouse.pressed ? Qt.rgba(0.17, 0.5, 0.72, 0.18) : "transparent"

                Label {
                    id: okLabel
                    anchors.centerIn: parent
                    text: root.okText
                    color: "#2c7fb8"
                    font.bold: true
                }

                MouseArea {
                    id: okMouse
                    anchors.fill: parent
                    onClicked: root.accepted(root.selectedDate)
                }
            }
        }
    }
}
