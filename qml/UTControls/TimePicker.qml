import QtQuick 2.7
import Lomiri.Components 1.3

Item {
    id: root

    property string value: ""
    property int hour: value.length > 0 ? parseTime(value).hour : 12
    property int minute: value.length > 0 ? parseTime(value).minute : 0
    property int minuteStep: 5
    property bool showClearButton: true
    property bool showCancelButton: true
    property string okText: qsTr("OK")
    property string nowText: qsTr("Now")
    property string clearText: qsTr("Clear")
    property string cancelText: qsTr("Cancel")

    signal selected(string timeText)
    signal accepted(string timeText)
    signal cleared()
    signal canceled()

    implicitWidth: units.gu(34)
    implicitHeight: contentColumn.height

    onValueChanged: {
        if (value.length > 0) {
            var parsed = parseTime(value)
            hour = parsed.hour
            minute = parsed.minute
        }
    }

    function pad(input) {
        return input < 10 ? "0" + input : String(input)
    }

    function clamp(input, min, max) {
        return Math.max(min, Math.min(max, input))
    }

    function parseTime(input) {
        var text = String(input || "").trim()
        var match = text.match(/^(\d{1,2})(?::?(\d{2}))?$/)
        if (!match) {
            return {"hour": 12, "minute": 0}
        }
        var h = parseInt(match[1], 10)
        var m = match[2] !== undefined ? parseInt(match[2], 10) : 0
        if (isNaN(h)) h = 12
        if (isNaN(m)) m = 0
        return {"hour": clamp(h, 0, 23), "minute": clamp(m, 0, 59)}
    }

    function timeText() {
        return pad(hour) + ":" + pad(minute)
    }

    function updateSelected() {
        selected(timeText())
    }

    function setTime(h, m) {
        hour = clamp(h, 0, 23)
        minute = clamp(m, 0, 59)
        hourField.text = pad(hour)
        minuteField.text = pad(minute)
        updateSelected()
    }

    function applyFields() {
        var parsedHour = parseInt(hourField.text, 10)
        var parsedMinute = parseInt(minuteField.text, 10)
        if (isNaN(parsedHour)) parsedHour = 0
        if (isNaN(parsedMinute)) parsedMinute = 0
        setTime(parsedHour, parsedMinute)
    }

    function shiftHour(delta) {
        setTime((hour + delta + 24) % 24, minute)
    }

    function shiftMinute(delta) {
        var total = hour * 60 + minute + delta
        while (total < 0) total += 24 * 60
        total = total % (24 * 60)
        setTime(Math.floor(total / 60), total % 60)
    }

    function chooseNow() {
        var now = new Date()
        setTime(now.getHours(), now.getMinutes())
    }

    Column {
        id: contentColumn
        width: root.width
        spacing: units.gu(1.2)

        Row {
            width: parent.width
            height: units.gu(5)
            spacing: units.gu(1)

            Label {
                width: parent.width
                height: parent.height
                text: root.timeText()
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.pixelSize: units.gu(3.2)
                font.bold: true
                color: theme.palette.normal.backgroundText
            }
        }

        Row {
            width: parent.width
            height: units.gu(13)
            spacing: units.gu(1)

            Column {
                width: (parent.width - colonLabel.width - parent.spacing * 2) / 2
                height: parent.height
                spacing: units.gu(0.5)

                FlatStepButton {
                    width: parent.width
                    height: units.gu(3.6)
                    text: "+"
                    onClicked: root.shiftHour(1)
                }

                TextField {
                    id: hourField
                    width: parent.width
                    height: units.gu(4.8)
                    text: root.pad(root.hour)
                    placeholderText: qsTr("Hour")
                    horizontalAlignment: Text.AlignHCenter
                    inputMethodHints: Qt.ImhDigitsOnly
                    onAccepted: root.applyFields()
                    onFocusChanged: if (!focus) root.applyFields()
                }

                FlatStepButton {
                    width: parent.width
                    height: units.gu(3.6)
                    text: "-"
                    onClicked: root.shiftHour(-1)
                }
            }

            Label {
                id: colonLabel
                width: units.gu(2)
                height: parent.height
                text: ":"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.pixelSize: units.gu(3)
                font.bold: true
                color: theme.palette.normal.backgroundText
            }

            Column {
                width: (parent.width - colonLabel.width - parent.spacing * 2) / 2
                height: parent.height
                spacing: units.gu(0.5)

                FlatStepButton {
                    width: parent.width
                    height: units.gu(3.6)
                    text: "+"
                    onClicked: root.shiftMinute(root.minuteStep)
                }

                TextField {
                    id: minuteField
                    width: parent.width
                    height: units.gu(4.8)
                    text: root.pad(root.minute)
                    placeholderText: qsTr("Min")
                    horizontalAlignment: Text.AlignHCenter
                    inputMethodHints: Qt.ImhDigitsOnly
                    onAccepted: root.applyFields()
                    onFocusChanged: if (!focus) root.applyFields()
                }

                FlatStepButton {
                    width: parent.width
                    height: units.gu(3.6)
                    text: "-"
                    onClicked: root.shiftMinute(-root.minuteStep)
                }
            }
        }

        Row {
            width: parent.width
            height: units.gu(4.8)
            spacing: units.gu(0.8)

            FlatActionButton {
                visible: root.showClearButton
                width: visible ? Math.max(units.gu(7), buttonImplicitWidth) : 0
                height: parent.height
                text: root.clearText
                onClicked: {
                    root.cleared()
                }
            }

            FlatActionButton {
                width: Math.max(units.gu(7), buttonImplicitWidth)
                height: parent.height
                text: root.nowText
                onClicked: root.chooseNow()
            }

            Item {
                width: Math.max(0, parent.width
                    - (root.showClearButton ? Math.max(units.gu(7), clearProxy.implicitWidth) : 0)
                    - Math.max(units.gu(7), nowProxy.implicitWidth)
                    - (root.showCancelButton ? Math.max(units.gu(7), cancelProxy.implicitWidth) : 0)
                    - Math.max(units.gu(7), okProxy.implicitWidth)
                    - parent.spacing * (1 + (root.showClearButton ? 1 : 0) + (root.showCancelButton ? 1 : 0)))
                height: 1
            }

            FlatActionButton {
                visible: root.showCancelButton
                width: visible ? Math.max(units.gu(7), buttonImplicitWidth) : 0
                height: parent.height
                text: root.cancelText
                onClicked: root.canceled()
            }

            FlatActionButton {
                width: Math.max(units.gu(7), buttonImplicitWidth)
                height: parent.height
                text: root.okText
                accent: true
                onClicked: {
                    root.applyFields()
                    root.accepted(root.timeText())
                }
            }
        }

        Label { id: clearProxy; visible: false; text: root.clearText }
        Label { id: nowProxy; visible: false; text: root.nowText }
        Label { id: cancelProxy; visible: false; text: root.cancelText }
        Label { id: okProxy; visible: false; text: root.okText }
    }

}
