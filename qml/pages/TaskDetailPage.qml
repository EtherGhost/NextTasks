import QtQuick 2.7
import QtQuick.Layouts 1.3
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3
import "../NextCommon" as NextCommon
import UTControls 1.0

Page {
    id: page
    function debugLog() {}

    property var appController
    property var tasksController
    property var task: ({})
    property string activeTab: "details"
    property string titleText: ""
    property string statusValue: "NEEDS-ACTION"
    property string startText: ""
    property string dueText: ""
    property string priorityText: ""
    property string percentText: "0"
    property string locationText: ""
    property string urlText: ""
    property string tagsText: ""
    property string notesText: ""
    property string dateDialogTarget: ""
    property string newTagText: ""
    property bool initializingFields: false
    property bool deletingTask: false
    property bool inputEditing: false
    readonly property string actionBlue: "#2c7fb8"
    readonly property string deleteRed: "#c7162b"
    readonly property real pullRefreshThreshold: units.gu(7)
    readonly property real oskOverlap: Qt.inputMethod.visible && Qt.inputMethod.keyboardRectangle.height > 0
        ? Math.max(0, page.height - Qt.inputMethod.keyboardRectangle.y)
        : 0
    property bool dirty: normalizeText(titleText) !== normalizeText(task.title || "")
        || statusValue !== normalizeStatusValue(task.status || (task.completed ? "COMPLETED" : "NEEDS-ACTION"))
        || normalizeDateText(startText) !== normalizeDateText(task.startText || "")
        || normalizeDateText(dueText) !== normalizeDateText(task.dueText || "")
        || normalizePriorityText(priorityText) !== normalizePriorityText(task.priority || "")
        || normalizePercentText(percentText) !== normalizePercentText(task.percentComplete || "0")
        || locationText !== String(task.location || "")
        || urlText !== String(task.url || "")
        || tagsText !== String(task.tags || "")
        || notesText !== String(task.description || "")

    function taskReadOnly() {
        return task && task.readOnly === true
    }

    Component.onCompleted: resetFields()
    onTaskChanged: resetFields()

    Connections {
        target: tasksController
        onEntriesChanged: page.refreshTaskFromController()
        onAllTasksChanged: page.refreshTaskFromController()
    }

    Timer {
        id: autoSaveTimer
        interval: 1200
        repeat: false
        onTriggered: page.commitAndSave()
    }

    Timer {
        id: deferredSaveTimer
        interval: 80
        repeat: false
        onTriggered: page.performAutoSave()
    }

    Timer {
        id: localDraftTimer
        interval: 250
        repeat: false
        onTriggered: page.saveLocalDraftNow()
    }

    header: PageHeader {
        id: header
        title: ""

        contents: RowLayout {
            anchors {
                fill: parent
                leftMargin: units.gu(1)
                rightMargin: units.gu(1)
            }
            spacing: units.gu(0.75)

            Label {
                Layout.fillWidth: true
                text: page.titleText.length > 0 ? page.titleText : i18n.tr("New task")
                font.bold: true
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Rectangle {
                Layout.preferredWidth: units.gu(5)
                Layout.preferredHeight: units.gu(5)
                radius: units.gu(2.5)
                color: "transparent"
                border.width: 2
                border.color: page.statusAccentColor()

                Item {
                    id: statusIcon
                    anchors.centerIn: parent
                    width: units.gu(2.8)
                    height: units.gu(2.8)

                    RotationAnimation on rotation {
                        from: 0
                        to: 360
                        duration: 900
                        loops: Animation.Infinite
                        running: tasksController && (tasksController.loading || tasksController.dirtySyncRunning)
                    }

                    Connections {
                        target: tasksController
                        onLoadingChanged: {
                            if (!tasksController.loading && !tasksController.dirtySyncRunning) {
                                statusIcon.rotation = 0
                            }
                        }
                    }

                    Canvas {
                        id: statusCanvas
                        anchors.fill: parent
                        property string paintColor: page.statusAccentColor()
                        visible: page.statusIconKind() !== "dirty" && page.statusIconKind() !== "conflict"
                        onVisibleChanged: requestPaint()
                        onPaintColorChanged: requestPaint()
                        onPaint: {
                            var ctx = getContext("2d")
                            var w = width
                            var h = height
                            var s = Math.min(w, h)
                            ctx.clearRect(0, 0, w, h)
                            ctx.strokeStyle = paintColor
                            ctx.fillStyle = paintColor
                            ctx.lineWidth = Math.max(2.4, s * 0.13)
                            ctx.lineCap = "round"
                            ctx.lineJoin = "round"

                            if (tasksController && (tasksController.loading || tasksController.dirtySyncRunning)) {
                                ctx.beginPath()
                                ctx.arc(w / 2, h / 2, s * 0.35, Math.PI * 0.15, Math.PI * 1.55, false)
                                ctx.stroke()
                                ctx.beginPath()
                                ctx.moveTo(w * 0.77, h * 0.30)
                                ctx.lineTo(w * 0.82, h * 0.52)
                                ctx.lineTo(w * 0.62, h * 0.45)
                                ctx.stroke()
                            } else {
                                ctx.beginPath()
                                ctx.moveTo(w * 0.22, h * 0.54)
                                ctx.lineTo(w * 0.42, h * 0.72)
                                ctx.lineTo(w * 0.78, h * 0.28)
                                ctx.stroke()
                            }
                        }

                        Connections {
                            target: tasksController
                            onLoadingChanged: statusCanvas.requestPaint()
                            onDirtySyncRunningChanged: statusCanvas.requestPaint()
                            onSyncStateTextChanged: statusCanvas.requestPaint()
                            onSyncStateColorChanged: statusCanvas.requestPaint()
                        }
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: units.gu(1.7)
                        height: width
                        radius: width / 2
                        visible: page.statusIconKind() === "dirty"
                        color: page.statusAccentColor()
                    }

                    Item {
                        anchors.fill: parent
                        visible: page.statusIconKind() === "conflict"

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: parent.height * 0.12
                            width: Math.max(3, parent.width * 0.16)
                            height: parent.height * 0.52
                            radius: width / 2
                            color: page.statusAccentColor()
                        }

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: parent.height * 0.76
                            width: Math.max(4, parent.width * 0.20)
                            height: width
                            radius: width / 2
                            color: page.statusAccentColor()
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: page.openStatusFromIcon()
                }
            }

            Rectangle {
                Layout.preferredWidth: units.gu(5)
                Layout.preferredHeight: units.gu(5)
                radius: units.gu(2.5)
                color: "transparent"

                Icon {
                    anchors.centerIn: parent
                    width: units.gu(2.9)
                    height: units.gu(2.9)
                    name: "share"
                    color: theme.palette.normal.backgroundText
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: page.taskShareText().length > 0
                    onClicked: page.shareCurrentTask()
                }
            }
        }
    }

    Component {
        id: syncStatusDialog

        Dialog {
            id: dialog
            title: i18n.tr("Sync status")
            text: ""

            Flickable {
                width: parent ? parent.width : units.gu(34)
                height: Math.min(syncStatusText.implicitHeight, units.gu(22))
                contentWidth: width
                contentHeight: syncStatusText.implicitHeight
                clip: true

                Label {
                    id: syncStatusText
                    width: parent.width
                    text: page.syncStatusDetailsText()
                    wrapMode: Text.WordWrap
                }
            }

            NextCommon.AppButton {
                width: parent ? parent.width : units.gu(34)
                height: units.gu(4.8)
                text: i18n.tr("Resolve conflict")
                visible: page.task.conflict === true
                enabled: tasksController && !tasksController.loading
                onClicked: {
                    PopupUtils.close(dialog)
                    page.openConflictResolution()
                }
            }

            NextCommon.AppButton {
                width: parent ? parent.width : units.gu(34)
                height: units.gu(4.8)
                text: i18n.tr("Refresh")
                visible: tasksController && tasksController.syncStateText === i18n.tr("Sync failed")
                enabled: tasksController && !tasksController.loading
                onClicked: {
                    PopupUtils.close(dialog)
                    tasksController.refresh()
                }
            }

            NextCommon.AppButton {
                width: parent ? parent.width : units.gu(34)
                height: units.gu(4.8)
                text: i18n.tr("Close")
                onClicked: PopupUtils.close(dialog)
            }
        }
    }

    Component {
        id: datePickerDialog

        Dialog {
            id: dateDialog
            width: Math.min(page.width - units.gu(4), units.gu(40))
            title: page.dateDialogTarget === "start" ? i18n.tr("Start date") : i18n.tr("Due date")
            text: ""

            CalendarDatePicker {
                id: taskDatePicker
                width: Math.min(dateDialog.width - units.gu(2), units.gu(34))
                value: page.dateDialogTarget === "start" ? page.startText : page.dueText
                okText: i18n.tr("OK")
                todayTextLabel: i18n.tr("Today")
                clearText: i18n.tr("Clear date")
                cancelText: i18n.tr("Cancel")
                onAccepted: {
                    page.applyDateDialogValue(dateText)
                    PopupUtils.close(dateDialog)
                }
                onCleared: {
                    page.applyDateDialogValue("")
                    PopupUtils.close(dateDialog)
                }
                onCanceled: {
                    PopupUtils.close(dateDialog)
                }
            }
        }
    }

    Component {
        id: statusDialog

        Dialog {
            id: statusPopup
            title: i18n.tr("Status")
            text: ""

            Label {
                width: parent ? parent.width : units.gu(34)
                text: i18n.tr("Choose task status.")
                wrapMode: Text.WordWrap
            }

            Repeater {
                model: [
                    {"label": i18n.tr("Needs action"), "value": "NEEDS-ACTION"},
                    {"label": i18n.tr("In progress"), "value": "IN-PROCESS"},
                    {"label": i18n.tr("Canceled"), "value": "CANCELLED"}
                ]

                NextCommon.AppButton {
                    width: parent ? parent.width : units.gu(34)
                    height: units.gu(4.8)
                    text: modelData.label + (page.statusValue === modelData.value ? "  \u2713" : "")
                    selected: page.statusValue === modelData.value
                    onClicked: {
                        page.statusValue = modelData.value
                        if (modelData.value === "NEEDS-ACTION") page.percentText = "0"
                        if (modelData.value === "IN-PROCESS" && (parseInt(page.percentText || "0", 10) === 0 || parseInt(page.percentText || "0", 10) >= 100)) page.percentText = "10"
                        if (modelData.value === "CANCELLED" && parseInt(page.percentText || "0", 10) >= 100) page.percentText = "0"
                        page.scheduleAutoSave()
                        PopupUtils.close(statusPopup)
                    }
                }
            }

            NextCommon.AppButton {
                width: parent ? parent.width : units.gu(34)
                height: units.gu(4.8)
                text: i18n.tr("Cancel")
                onClicked: PopupUtils.close(statusPopup)
            }
        }
    }

    Component {
        id: tagsDialog

        Dialog {
            id: tagsPopup
            title: i18n.tr("Select tags")
            text: ""

            Flickable {
                width: parent ? parent.width : units.gu(34)
                height: Math.min(tagsStatusText.implicitHeight, units.gu(12))
                contentWidth: width
                contentHeight: tagsStatusText.implicitHeight
                clip: true

                Label {
                    id: tagsStatusText
                    width: parent.width
                    text: page.tagsText.length > 0 ? i18n.tr("Selected: %1").arg(page.tagsText) : i18n.tr("No tags yet. Type above to create one.")
                    wrapMode: Text.WordWrap
                }
            }

            TextField {
                id: newTagField
                width: parent ? parent.width : units.gu(34)
                text: page.newTagText
                placeholderText: i18n.tr("New tag")
                inputMethodHints: Qt.ImhNoPredictiveText
                onTextChanged: page.newTagText = text
            }

            Repeater {
                model: page.availableTags()

                NextCommon.AppButton {
                    width: parent ? parent.width : units.gu(34)
                    height: units.gu(4.8)
                    text: (page.tagSelected(modelData) ? "\u2713  " : "") + modelData
                    selected: page.tagSelected(modelData)
                    onClicked: page.toggleTag(modelData)
                }
            }

            NextCommon.AppButton {
                width: parent ? parent.width : units.gu(34)
                height: units.gu(4.8)
                text: i18n.tr("Add tag")
                onClicked: {
                    page.addTag(newTagField.text)
                    PopupUtils.close(tagsPopup)
                }
            }

            NextCommon.AppButton {
                width: parent ? parent.width : units.gu(34)
                height: units.gu(4.8)
                text: i18n.tr("Clear tags")
                visible: page.tagsText.length > 0
                onClicked: {
                    page.tagsText = ""
                    page.scheduleAutoSave()
                    PopupUtils.close(tagsPopup)
                }
            }

            NextCommon.AppButton {
                width: parent ? parent.width : units.gu(34)
                height: units.gu(4.8)
                text: i18n.tr("Done")
                onClicked: PopupUtils.close(tagsPopup)
            }
        }
    }

    Component {
        id: deleteTaskDialog

        Dialog {
            id: dialog
            title: i18n.tr("Delete task?")
            text: ""

            Label {
                width: parent ? parent.width : units.gu(34)
                text: task.dirty || task.isNew
                    ? i18n.tr("This task has local changes. Deleting it will discard those local changes.")
                    : i18n.tr("The task will be deleted from this device and synced to the server.")
                wrapMode: Text.WordWrap
            }

            NextCommon.AppButton {
                width: parent ? parent.width : units.gu(34)
                height: units.gu(4.8)
                text: i18n.tr("Delete")
                variant: "destructive"
                destructiveColor: page.deleteRed
                onClicked: {
                    PopupUtils.close(dialog)
                    page.deleteCurrentTask()
                }
            }

            NextCommon.AppButton {
                width: parent ? parent.width : units.gu(34)
                height: units.gu(4.8)
                text: i18n.tr("Cancel")
                onClicked: PopupUtils.close(dialog)
            }
        }
    }

    Component {
        id: moveTaskDialog

        Dialog {
            id: dialog
            title: i18n.tr("Move task")
            text: ""

            Label {
                width: parent ? parent.width : units.gu(34)
                text: task.dirty || task.isNew || task.conflict
                    ? i18n.tr("Sync this task before moving it to another list.")
                    : i18n.tr("Choose the target list.")
                wrapMode: Text.WordWrap
            }

            Repeater {
                model: tasksController ? tasksController.availableMoveCalendars(task) : []

                NextCommon.AppButton {
                    width: parent ? parent.width : units.gu(34)
                    height: units.gu(4.8)
                    text: modelData.title || i18n.tr("Tasks")
                    visible: !(task.dirty || task.isNew || task.conflict)
                    enabled: tasksController && !tasksController.loading
                    onClicked: {
                        PopupUtils.close(dialog)
                        page.moveCurrentTaskToCalendar(modelData)
                    }
                }
            }

            NextCommon.AppButton {
                width: parent ? parent.width : units.gu(34)
                height: units.gu(4.8)
                text: i18n.tr("Close")
                onClicked: PopupUtils.close(dialog)
            }
        }
    }

    Flickable {
        id: detailFlickable
        anchors {
            fill: parent
            topMargin: page.header.height
            bottomMargin: page.oskOverlap
        }
        contentWidth: width
        contentHeight: contentColumn.height + units.gu(3) + page.oskOverlap
        clip: true
        boundsBehavior: Flickable.DragOverBounds
        property bool pullRefreshArmed: false
        property bool pullRefreshRunning: false

        onContentYChanged: {
            if (contentY < -page.pullRefreshThreshold && tasksController && !tasksController.loading) {
                pullRefreshArmed = true
            }
        }

        onMovementEnded: {
            if (pullRefreshArmed && tasksController && !tasksController.loading) {
                pullRefreshRunning = true
                page.refreshFromServer()
            }
            pullRefreshArmed = false
        }

        Connections {
            target: tasksController
            onLoadingChanged: {
                if (!tasksController.loading) {
                    detailFlickable.pullRefreshRunning = false
                }
            }
        }

        Rectangle {
            anchors {
                top: parent.top
                horizontalCenter: parent.horizontalCenter
                topMargin: units.gu(0.6)
            }
            width: refreshPullLabel.implicitWidth + units.gu(2)
            height: units.gu(3.2)
            radius: units.gu(1.6)
            color: "#2c7fb8"
            opacity: detailFlickable.contentY < -units.gu(2) || detailFlickable.pullRefreshRunning ? 0.92 : 0
            visible: opacity > 0
            z: 4

            Label {
                id: refreshPullLabel
                anchors.centerIn: parent
                text: detailFlickable.pullRefreshRunning
                    ? i18n.tr("Refreshing...")
                    : detailFlickable.contentY < -page.pullRefreshThreshold
                    ? i18n.tr("Release to refresh")
                    : i18n.tr("Pull to refresh")
                color: "white"
            }
        }

        ColumnLayout {
            id: contentColumn
            width: parent.width
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: units.gu(2)
            }
            spacing: units.gu(1.2)

            TextField {
                id: titleField
                Layout.fillWidth: true
                text: page.titleText
                readOnly: page.taskReadOnly()
                font.pixelSize: units.gu(2.8)
                font.bold: true
                placeholderText: i18n.tr("Task title")
                inputMethodHints: Qt.ImhNoPredictiveText
                onTextChanged: {
                    page.titleText = text
                    page.scheduleAutoSave()
                }
                onActiveFocusChanged: {
                    page.updateInputEditingState()
                    if (!activeFocus) {
                        page.saveLocalDraftNow()
                        Qt.callLater(page.refreshTaskFromController)
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: units.gu(0)

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: units.gu(5.5)
                    color: "transparent"
                    border.width: 0

                    Column {
                        anchors.fill: parent
                        spacing: 0

                        Label {
                            width: parent.width
                            height: units.gu(4.9)
                            text: i18n.tr("Details")
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            font.bold: true
                            color: page.activeTab === "details" ? "#b9c8ff" : theme.palette.normal.backgroundText
                        }

                        Rectangle {
                            width: parent.width
                            height: units.dp(3)
                            color: page.activeTab === "details" ? "#b9c8ff" : theme.palette.normal.base
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: page.activeTab = "details"
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: units.gu(5.5)
                    color: "transparent"
                    border.width: 0

                    Column {
                        anchors.fill: parent
                        spacing: 0

                        Label {
                            width: parent.width
                            height: units.gu(4.9)
                            text: i18n.tr("Notes")
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            font.bold: true
                            color: page.activeTab === "notes" ? "#b9c8ff" : theme.palette.normal.backgroundText
                        }

                        Rectangle {
                            width: parent.width
                            height: units.dp(3)
                            color: page.activeTab === "notes" ? "#b9c8ff" : theme.palette.normal.base
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: page.activeTab = "notes"
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                visible: page.activeTab === "details"
                spacing: units.gu(0)

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: units.gu(7.5)
                    color: "transparent"
                    border.width: 0

                    RowLayout {
                        anchors.fill: parent
                        spacing: units.gu(1.2)

                        Label {
                            Layout.preferredWidth: units.gu(5)
                            text: "\u2611"
                            fontSize: "large"
                            horizontalAlignment: Text.AlignHCenter
                            color: statusColor()
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: units.gu(0.2)

                            Label {
                                Layout.fillWidth: true
                                text: i18n.tr("Status")
                                opacity: 0.62
                                font.bold: true
                            }

                            Label {
                                Layout.fillWidth: true
                                text: statusLabel()
                                font.bold: true
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: tasksController && !tasksController.loading
                        onClicked: PopupUtils.open(statusDialog)
                    }
                }

                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: theme.palette.normal.base }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: units.gu(1)

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: units.gu(6.5)
                        color: "transparent"

                        RowLayout {
                            anchors.fill: parent
                            spacing: units.gu(1.2)

                            Label {
                                Layout.preferredWidth: units.gu(5)
                                text: "\u25f7"
                                font.pixelSize: units.gu(2.1)
                                horizontalAlignment: Text.AlignHCenter
                                color: theme.palette.normal.backgroundText
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: units.gu(0.2)

                                Label {
                                    Layout.fillWidth: true
                                    text: i18n.tr("Start date")
                                    opacity: 0.62
                                    font.bold: true
                                }

                                Label {
                                    Layout.fillWidth: true
                                    text: page.startText.length > 0 ? page.startText : i18n.tr("No start date")
                                    opacity: page.startText.length > 0 ? 1.0 : 0.55
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: page.openDateDialog("start")
                        }
                    }

                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: theme.palette.normal.base }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: units.gu(6.5)
                        color: "transparent"

                        RowLayout {
                            anchors.fill: parent
                            spacing: units.gu(1.2)

                            Label {
                                Layout.preferredWidth: units.gu(5)
                                text: "\u25cc"
                                font.pixelSize: units.gu(2.1)
                                horizontalAlignment: Text.AlignHCenter
                                color: theme.palette.normal.backgroundText
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: units.gu(0.2)

                                Label {
                                    Layout.fillWidth: true
                                    text: i18n.tr("Due date")
                                    opacity: 0.62
                                    font.bold: true
                                }

                                Label {
                                    Layout.fillWidth: true
                                    text: page.dueText.length > 0 ? page.dueText : i18n.tr("No due date")
                                    opacity: page.dueText.length > 0 ? 1.0 : 0.55
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: page.openDateDialog("due")
                        }
                    }

                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: theme.palette.normal.base }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: units.gu(0.7)

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: units.gu(1.2)

                            Label {
                                Layout.preferredWidth: units.gu(5)
                                text: "\u25b2"
                                font.pixelSize: units.gu(1.8)
                                horizontalAlignment: Text.AlignHCenter
                                color: priorityColor()
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: units.gu(0.2)

                                Label {
                                    Layout.fillWidth: true
                                    text: i18n.tr("Priority")
                                    opacity: 0.62
                                    font.bold: true
                                }

                                Label {
                                    Layout.fillWidth: true
                                    text: priorityLabel()
                                    opacity: page.priorityText.length > 0 ? 1.0 : 0.55
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        Rectangle {
                            id: prioritySlider
                            Layout.fillWidth: true
                            Layout.preferredHeight: units.gu(3.8)
                            color: "transparent"

                            Rectangle {
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    verticalCenter: parent.verticalCenter
                                    leftMargin: units.gu(5)
                                }
                                height: units.dp(4)
                                radius: height / 2
                                color: theme.palette.normal.base
                            }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                x: units.gu(5) + prioritySliderPosition() * (parent.width - units.gu(5) - width)
                                width: units.gu(2.8)
                                height: units.gu(2.8)
                                radius: width / 2
                                color: "#2c7fb8"
                            }

                            MouseArea {
                                anchors.fill: parent
                                onPressed: page.setPriorityFromX(mouse.x, prioritySlider.width)
                                onPositionChanged: if (pressed) page.setPriorityFromX(mouse.x, prioritySlider.width)
                                onReleased: page.scheduleAutoSave()
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: theme.palette.normal.base }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: units.gu(0.7)

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: units.gu(1.2)

                            Label {
                                Layout.preferredWidth: units.gu(5)
                                text: "%"
                                font.pixelSize: units.gu(2)
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                                color: "#2c7fb8"
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: units.gu(0.2)

                                Label {
                                    Layout.fillWidth: true
                                    text: i18n.tr("%1% completed").arg(page.percentText)
                                    opacity: 0.62
                                    font.bold: true
                                }

                                Label {
                                    Layout.fillWidth: true
                                    text: i18n.tr("Progress")
                                    opacity: 0.55
                                }
                            }
                        }

                        Rectangle {
                            id: percentSlider
                            Layout.fillWidth: true
                            Layout.preferredHeight: units.gu(3.8)
                            color: "transparent"

                            Rectangle {
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    verticalCenter: parent.verticalCenter
                                    leftMargin: units.gu(5)
                                }
                                height: units.dp(4)
                                radius: height / 2
                                color: theme.palette.normal.base
                            }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                x: units.gu(5) + percentSliderPosition() * (parent.width - units.gu(5) - width)
                                width: units.gu(2.8)
                                height: units.gu(2.8)
                                radius: width / 2
                                color: "#2c7fb8"
                            }

                            MouseArea {
                                anchors.fill: parent
                                onPressed: page.setPercentFromX(mouse.x, percentSlider.width)
                                onPositionChanged: if (pressed) page.setPercentFromX(mouse.x, percentSlider.width)
                                onReleased: page.scheduleAutoSave()
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: theme.palette.normal.base }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: units.gu(0.4)

                        Label {
                            Layout.fillWidth: true
                            text: i18n.tr("Set location")
                            opacity: 0.62
                            font.bold: true
                        }

                        TextField {
                            Layout.fillWidth: true
                            text: page.locationText
                            readOnly: page.taskReadOnly()
                            placeholderText: i18n.tr("Set location")
                            inputMethodHints: Qt.ImhNoPredictiveText
                            onTextChanged: {
                                page.locationText = text
                                page.scheduleAutoSave()
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: theme.palette.normal.base }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: units.gu(0.4)

                        Label {
                            Layout.fillWidth: true
                            text: i18n.tr("Set a URL")
                            opacity: 0.62
                            font.bold: true
                        }

                        TextField {
                            Layout.fillWidth: true
                            text: page.urlText
                            readOnly: page.taskReadOnly()
                            placeholderText: i18n.tr("Set a URL")
                            inputMethodHints: Qt.ImhUrlCharactersOnly
                            onTextChanged: {
                                page.urlText = text
                                page.scheduleAutoSave()
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: theme.palette.normal.base }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: units.gu(6.5)
                        color: "transparent"

                        RowLayout {
                            anchors.fill: parent
                            spacing: units.gu(1.2)

                            Label {
                                Layout.preferredWidth: units.gu(5)
                                text: "\u25a3"
                                font.pixelSize: units.gu(1.8)
                                horizontalAlignment: Text.AlignHCenter
                                color: theme.palette.normal.backgroundText
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: units.gu(0.2)

                                Label {
                                    Layout.fillWidth: true
                                    text: i18n.tr("Select tags")
                                    opacity: 0.62
                                    font.bold: true
                                }

                                Label {
                                    Layout.fillWidth: true
                                    text: page.tagsText.length > 0 ? page.tagsText : i18n.tr("No tags")
                                    opacity: page.tagsText.length > 0 ? 1.0 : 0.55
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                page.newTagText = ""
                                PopupUtils.open(tagsDialog)
                            }
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        text: String(task.calendarTitle || "").length > 0 ? i18n.tr("List: %1").arg(task.calendarTitle) : i18n.tr("No list")
                        wrapMode: Text.WordWrap
                        opacity: 0.75
                    }

                    NextCommon.AppButton {
                        Layout.fillWidth: true
                        Layout.preferredHeight: units.gu(5.4)
                        text: i18n.tr("Move to another list")
                        enabled: tasksController && !tasksController.loading
                        onClicked: PopupUtils.open(moveTaskDialog)
                    }

                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: theme.palette.normal.base }

                    Label {
                        Layout.fillWidth: true
                        visible: String(task.lastModifiedText || "").length > 0 || String(task.createdText || "").length > 0
                        text: String(task.lastModifiedText || "").length > 0
                            ? i18n.tr("Modified: %1").arg(task.lastModifiedText)
                            : i18n.tr("Created: %1").arg(task.createdText)
                        wrapMode: Text.WordWrap
                        opacity: 0.75
                    }

                    NextCommon.AppButton {
                        Layout.fillWidth: true
                        Layout.preferredHeight: units.gu(5.4)
                        visible: task.conflict === true
                        text: i18n.tr("Resolve conflict")
                        variant: "primary"
                        enabled: tasksController && !tasksController.loading
                        onClicked: page.openConflictResolution()
                    }

                    NextCommon.AppButton {
                        Layout.fillWidth: true
                        Layout.preferredHeight: units.gu(5.4)
                        text: i18n.tr("Delete task")
                        variant: "destructive"
                        destructiveColor: page.deleteRed
                        enabled: tasksController && !tasksController.loading && !page.taskReadOnly()
                        onClicked: PopupUtils.open(deleteTaskDialog)
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.max(
                    units.gu(28),
                    detailFlickable.height - titleField.height - units.gu(11)
                )
                visible: page.activeTab === "notes"
                radius: units.gu(0.6)
                color: theme.palette.normal.background
                border.width: 1
                border.color: theme.palette.normal.base

                ColumnLayout {
                    id: notesColumn
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        bottom: parent.bottom
                        margins: units.gu(1)
                    }
                    spacing: units.gu(0.8)

                    TextArea {
                        id: notesField
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        text: page.notesText
                        readOnly: page.taskReadOnly()
                        wrapMode: TextEdit.WordWrap
                        placeholderText: i18n.tr("No notes.")
                        onTextChanged: {
                            page.notesText = text
                            page.scheduleAutoSave()
                        }
                        onActiveFocusChanged: {
                            page.updateInputEditingState()
                            if (!activeFocus) {
                                page.saveLocalDraftNow()
                                Qt.callLater(page.refreshTaskFromController)
                            }
                        }
                    }
                }
            }
        }
    }

    Component.onDestruction: {
        if (dirty && !deletingTask) {
            performAutoSave()
        }
    }

    function resetFields() {
        initializingFields = true
        titleText = editorTitle(task)
        statusValue = normalizeStatusValue(task.status || (task.completed ? "COMPLETED" : "NEEDS-ACTION"))
        startText = String(task.startText || "")
        dueText = String(task.dueText || "")
        priorityText = String(task.priority || "")
        percentText = normalizePercentText(task.percentComplete || (task.completed ? "100" : "0"))
        locationText = String(task.location || "")
        urlText = String(task.url || "")
        tagsText = String(task.tags || "")
        notesText = String(task.description || "")
        initializingFields = false
    }

    function editorTitle(source) {
        var value = String(source && source.title ? source.title : "")
        if (source && source.isNew === true) {
            var normalized = normalizeText(value)
            if (normalized === normalizeText(i18n.tr("Untitled task")) || normalized === normalizeText(i18n.tr("New task"))) {
                return ""
            }
        }
        return value
    }

    function refreshTaskFromController() {
        if (!tasksController || initializingFields) {
            return
        }
        if (page.inputEditing || dirty || autoSaveTimer.running || deferredSaveTimer.running) {
            return
        }
        var updatedTask = tasksController.taskByKey(task)
        if (updatedTask && updatedTask.type === "task") {
            if (!dirty || currentFieldsMatchTask(updatedTask)) {
                task = updatedTask
            }
        }
    }

    function scheduleAutoSave() {
        if (initializingFields || !tasksController || !dirty || page.taskReadOnly()) {
            return
        }
        localDraftTimer.restart()
        autoSaveTimer.restart()
    }

    function saveLocalDraftNow() {
        localDraftTimer.stop()
        if (initializingFields || !tasksController || !dirty || page.taskReadOnly()) {
            return
        }
        tasksController.updateTaskLocalDraft(task, currentChanges())
    }

    function commitAndSave() {
        try {
            Qt.inputMethod.commit()
        } catch (e) {
        }
        deferredSaveTimer.restart()
    }

    function performAutoSave() {
        saveLocalDraftNow()
        autoSaveTimer.stop()
        if (!tasksController || !dirty || page.taskReadOnly()) {
            return
        }
        var changes = currentChanges()
        tasksController.saveTask(task, changes)
        task = mergeLocalTask(task, changes)
    }

    function refreshFromServer() {
        if (!tasksController || tasksController.loading) {
            return
        }
        try {
            Qt.inputMethod.commit()
        } catch (e) {
        }
        if (dirty) {
            performAutoSave()
        }
        tasksController.refresh()
    }

    function deleteCurrentTask() {
        deletingTask = true
        autoSaveTimer.stop()
        deferredSaveTimer.stop()
        if (tasksController) {
            tasksController.deleteTask(task)
        }
        pageStack.pop()
    }

    function moveCurrentTaskToCalendar(targetCalendar) {
        if (!tasksController) {
            return
        }
        var started = tasksController.moveTaskToCalendar(task, targetCalendar)
        if (started) {
            pageStack.pop()
        }
    }

    function openConflictResolution() {
        pageStack.push(Qt.resolvedUrl("TaskConflictResolutionPage.qml"), {"tasksController": tasksController, "task": task})
    }

    function openStatusFromIcon() {
        if (task.conflict === true) {
            openConflictResolution()
            return
        }
        PopupUtils.open(syncStatusDialog)
    }

    function taskShareTitle() {
        var title = String(titleText || "").trim()
        return title.length > 0 ? title : tasksController.sharedDateTaskTitle()
    }

    function taskShareText() {
        if (notesField && notesField.selectedText && notesField.selectedText.length > 0) {
            return notesField.selectedText
        }
        var parts = []
        var title = String(titleText || "").trim()
        if (title.length > 0) {
            parts.push(title)
        }
        var description = String(notesText || "").trim()
        if (description.length > 0) {
            if (parts.length > 0) {
                parts.push("")
            }
            parts.push(description)
        }
        return parts.join("\n")
    }

    function shareCurrentTask() {
        var text = page.taskShareText()
        if (text.length === 0) {
            return
        }
        if (dirty) {
            performAutoSave()
        }

        var sharePage = pageStack.push(Qt.resolvedUrl("../backend/TaskShareExportPage.qml"), {
            "shareTitle": page.taskShareTitle(),
            "shareText": text
        })
        if (!sharePage) {
            debugLog("NextTasks ContentHub Lomiri.Content share page unavailable; trying Ubuntu.Content fallback")
            sharePage = pageStack.push(Qt.resolvedUrl("../backend/TaskShareExportPageUbuntu.qml"), {
                "shareTitle": page.taskShareTitle(),
                "shareText": text
            })
        }
        if (!sharePage) {
            tasksController.statusText = i18n.tr("Sharing is not available.")
            return
        }
        sharePage.shareFinished.connect(function() {
            pageStack.pop()
        })
        sharePage.shareFailed.connect(function(message) {
            tasksController.statusText = message
            pageStack.pop()
        })
    }

    function statusIconKind() {
        if (tasksController && (tasksController.loading || tasksController.dirtySyncRunning)) {
            return "syncing"
        }
        if (task.conflict === true) {
            return "conflict"
        }
        if (dirty || task.dirty === true || task.isNew === true) {
            return "dirty"
        }
        return "synced"
    }

    function statusAccentColor() {
        if (tasksController && (tasksController.loading || tasksController.dirtySyncRunning)) {
            return "#2c7fb8"
        }
        if (task.conflict === true) {
            return "#d85a7f"
        }
        if (dirty || task.dirty === true || task.isNew === true) {
            return "#b37a2a"
        }
        return "#5a8f3c"
    }

    function syncStatusDetailsText() {
        var parts = []
        if (task.conflict === true) {
            parts.push(i18n.tr("This task has a conflict."))
        } else if (dirty || task.dirty === true || task.isNew === true) {
            parts.push(i18n.tr("This task has local changes waiting to sync."))
        } else {
            parts.push(i18n.tr("This task is up to date."))
        }
        if (tasksController && tasksController.statusText.length > 0) {
            parts.push(tasksController.statusText)
        }
        if (tasksController && tasksController.syncStateText.length > 0) {
            parts.push(i18n.tr("Sync: %1").arg(tasksController.syncStateText))
        }
        return parts.join("\n")
    }

    function currentChanges() {
        return {
            "title": titleText,
            "status": statusValue,
            "completed": statusValue === "COMPLETED",
            "start": startText,
            "due": dueText,
            "priority": priorityText,
            "percentComplete": percentText,
            "location": locationText,
            "url": urlText,
            "tags": tagsText,
            "description": notesText,
            "sortOrder": Number(task.sortOrder || 0)
        }
    }

    function currentFieldsMatchTask(candidate) {
        if (!candidate) return false
        return normalizeText(titleText) === normalizeText(candidate.title || "")
            && statusValue === normalizeStatusValue(candidate.status || (candidate.completed ? "COMPLETED" : "NEEDS-ACTION"))
            && normalizeDateText(startText) === normalizeDateText(candidate.startText || "")
            && normalizeDateText(dueText) === normalizeDateText(candidate.dueText || "")
            && normalizePriorityText(priorityText) === normalizePriorityText(candidate.priority || "")
            && normalizePercentText(percentText) === normalizePercentText(candidate.percentComplete || "0")
            && locationText === String(candidate.location || "")
            && urlText === String(candidate.url || "")
            && tagsText === String(candidate.tags || "")
            && notesText === String(candidate.description || "")
    }

    function mergeLocalTask(source, changes) {
        var result = {}
        for (var key in source) {
            result[key] = source[key]
        }
        result.title = changes.title
        result.status = changes.status
        result.completed = changes.status === "COMPLETED"
        result.cancelled = changes.status === "CANCELLED"
        result.startText = normalizeDateText(changes.start)
        result.dueText = normalizeDateText(changes.due)
        result.priority = normalizePriorityText(changes.priority)
        result.percentComplete = normalizePercentText(changes.percentComplete)
        result.location = changes.location
        result.url = changes.url
        result.tags = changes.tags
        result.description = changes.description
        result.sortOrder = Number(changes.sortOrder || source.sortOrder || 0)
        result.subtitle = statusLabelFor(changes.status)
        result.dirty = true
        result.localStatus = result.isNew === true ? "LOCAL_CREATED" : "LOCAL_EDITED"
        result.localModified = Date.now()
        return result
    }

    function updateInputEditingState() {
        inputEditing = titleField.activeFocus || notesField.activeFocus
    }

    function normalizeText(value) {
        return String(value || "").trim()
    }

    function normalizeDateText(value) {
        var text = String(value || "").trim()
        if (text.length === 0) return ""
        if (/^\d{8}$/.test(text)) return text.substring(0, 4) + "-" + text.substring(4, 6) + "-" + text.substring(6, 8)
        return text
    }

    function normalizePriorityText(value) {
        var text = String(value || "").trim()
        if (text.length === 0 || text === "0") return ""
        var parsed = parseInt(text, 10)
        if (!parsed || parsed < 0) return ""
        if (parsed > 9) return "9"
        return String(parsed)
    }

    function normalizePercentText(value) {
        var parsed = parseInt(String(value || "0"), 10)
        if (!parsed || parsed < 0) return "0"
        if (parsed > 100) return "100"
        return String(parsed)
    }

    function normalizeStatusValue(value) {
        var text = String(value || "").toUpperCase()
        if (text === "COMPLETED") return "COMPLETED"
        if (text === "IN-PROCESS") return "IN-PROCESS"
        if (text === "CANCELLED") return "CANCELLED"
        return "NEEDS-ACTION"
    }

    function openDateDialog(target) {
        dateDialogTarget = target
        PopupUtils.open(datePickerDialog)
    }

    function applyDateDialogValue(value) {
        var normalized = normalizeDateText(value)
        if (dateDialogTarget === "start") {
            startText = normalized
        } else if (dateDialogTarget === "due") {
            dueText = normalized
        }
        scheduleAutoSave()
    }

    function statusLabel() {
        return statusLabelFor(statusValue)
    }

    function statusLabelFor(status) {
        var text = normalizeStatusValue(status)
        if (text === "COMPLETED") return i18n.tr("Completed")
        if (text === "IN-PROCESS") return i18n.tr("In progress")
        if (text === "CANCELLED") return i18n.tr("Canceled")
        return i18n.tr("Needs action")
    }

    function statusColor() {
        if (statusValue === "COMPLETED") return "#5a8f3c"
        if (statusValue === "IN-PROCESS") return "#2c7fb8"
        if (statusValue === "CANCELLED") return "#d85a7f"
        return theme.palette.normal.backgroundText
    }

    function prioritySliderPosition() {
        var value = parseInt(priorityText || "0", 10)
        if (!value || value < 0) value = 0
        if (value > 9) value = 9
        return value / 9
    }

    function percentSliderPosition() {
        var value = parseInt(percentText || "0", 10)
        if (!value || value < 0) value = 0
        if (value > 100) value = 100
        return value / 100
    }

    function setPriorityFromX(x, width) {
        var usable = Math.max(1, width - units.gu(5))
        var value = Math.round(Math.max(0, Math.min(1, (x - units.gu(5)) / usable)) * 9)
        priorityText = value === 0 ? "" : String(value)
        scheduleAutoSave()
    }

    function setPercentFromX(x, width) {
        var usable = Math.max(1, width - units.gu(5))
        var value = Math.round(Math.max(0, Math.min(1, (x - units.gu(5)) / usable)) * 10) * 10
        percentText = String(value)
        if (value >= 100) statusValue = "COMPLETED"
        else if (value > 0 && statusValue === "NEEDS-ACTION") statusValue = "IN-PROCESS"
        scheduleAutoSave()
    }

    function addTag(value) {
        var tag = String(value || "").trim()
        if (tag.length === 0) return
        var current = splitTags(tagsText)
        for (var i = 0; i < current.length; ++i) {
            if (current[i].toLowerCase() === tag.toLowerCase()) {
                newTagText = ""
                return
            }
        }
        current.push(tag)
        tagsText = current.join(",")
        newTagText = ""
        scheduleAutoSave()
    }

    function splitTags(value) {
        var raw = String(value || "").split(",")
        var result = []
        for (var i = 0; i < raw.length; ++i) {
            var tag = raw[i].trim()
            if (tag.length > 0) {
                result.push(tag)
            }
        }
        return result
    }

    function tagSelected(tag) {
        var selected = splitTags(tagsText)
        var lower = String(tag || "").toLowerCase()
        for (var i = 0; i < selected.length; ++i) {
            if (selected[i].toLowerCase() === lower) return true
        }
        return false
    }

    function toggleTag(tag) {
        var selected = splitTags(tagsText)
        var lower = String(tag || "").toLowerCase()
        var next = []
        var found = false
        for (var i = 0; i < selected.length; ++i) {
            if (selected[i].toLowerCase() === lower) {
                found = true
            } else {
                next.push(selected[i])
            }
        }
        if (!found && String(tag || "").trim().length > 0) {
            next.push(String(tag).trim())
        }
        tagsText = next.join(",")
        scheduleAutoSave()
    }

    function availableTags() {
        var map = {}
        var result = []
        function addMany(value) {
            var tags = splitTags(value)
            for (var i = 0; i < tags.length; ++i) {
                var key = tags[i].toLowerCase()
                if (!map[key]) {
                    map[key] = true
                    result.push(tags[i])
                }
            }
        }
        addMany(tagsText)
        if (tasksController && tasksController.allTasks) {
            for (var i = 0; i < tasksController.allTasks.length; ++i) {
                addMany(tasksController.allTasks[i].tags || "")
            }
        }
        result.sort(function(a, b) { return a.toLowerCase().localeCompare(b.toLowerCase()) })
        return result
    }

    function priorityLabel() {
        var priority = parseInt(priorityText || "0", 10)
        if (!priority) return i18n.tr("No priority assigned (0)")
        if (priority <= 4) return i18n.tr("High (%1)").arg(priority)
        if (priority === 5) return i18n.tr("Medium (5)")
        return i18n.tr("Low (%1)").arg(priority)
    }

    function priorityColor() {
        var priority = parseInt(priorityText || "0", 10)
        if (!priority) return theme.palette.normal.backgroundText
        if (priority <= 4) return "#d85a7f"
        if (priority === 5) return "#b37a2a"
        return "#5a8f3c"
    }
}
