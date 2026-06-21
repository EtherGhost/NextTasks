import QtQuick 2.7
import QtQuick.Layouts 1.3
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3
import QtGraphicalEffects 1.0
import Qt.labs.settings 1.0
import "../backend"

Page {
    id: page
    property var appController
    property bool drawerOpen: false
    property string searchQuery: ""
    property var filteredEntries: []
    property var displayEntries: []
    property var completedDisplayEntries: []
    property int completedTaskCount: 0
    property string newListName: ""
    property var selectedMenuCalendar: ({})
    property var pendingSwipeDeleteTask: ({})
    property string editListName: ""
    property string editListColor: ""
    property string manualDragTaskKey: ""
    property bool manualDragPointerCaptured: false
    property string manualDropBeforeTaskKey: ""
    property string manualDropAfterTaskKey: ""
    property bool selectionMode: false
    property var selectedTaskKeys: ({})
    property var bulkMoveTasks: []
    property var bulkMoveCalendars: []
    property int selectionRevision: 0
    property int bulkDeleteDirtyCount: 0
    property int bulkDeleteNewCount: 0
    property string sortDialogCalendarHref: ""
    property string sortDialogCalendarTitle: ""
    readonly property string actionBlue: "#2c7fb8"
    readonly property string deleteRed: "#c7162b"
    readonly property var listColorChoices: [
        "#2196F3", "#607D8B", "#616161", "#F44336", "#FF9800",
        "#F6BF26", "#8BC34A", "#4CAF50", "#009688", "#00BCD4",
        "#3F51B5", "#9C27B0", "#E91E63", "#795548"
    ]
    readonly property real pullRefreshThreshold: units.gu(7)
    readonly property string accountInitial: accountSettings.displayName.length > 0
        ? accountSettings.displayName.charAt(0).toUpperCase()
        : "?"

    Settings {
        id: accountSettings
        category: "account"
        property string displayName: ""
    }

    function openPage(url) {
        drawerOpen = false
        pageStack.push(Qt.resolvedUrl(url), {"appController": appController})
    }

    function openTask(task) {
        pageStack.push(Qt.resolvedUrl("TaskDetailPage.qml"), {"appController": appController, "tasksController": dataController, "task": task})
    }

    function openConflictResolution(task) {
        var target = task || dataController.firstConflictTask()
        if (target) {
            pageStack.push(Qt.resolvedUrl("TaskConflictResolutionPage.qml"), {"tasksController": dataController, "task": target})
        }
    }

    function openSortPicker() {
        if (dataController.viewMode === "myTasks") {
            sortDialogCalendarHref = ""
            sortDialogCalendarTitle = ""
            PopupUtils.open(sortScopeDialog)
            return
        }
        sortDialogCalendarHref = dataController.selectedCalendarHref
        sortDialogCalendarTitle = dataController.selectedCalendarTitle
        PopupUtils.open(sortDialog)
    }

    function activeSortMode() {
        return sortDialogCalendarHref.length > 0
            ? dataController.sortModeForCalendar(sortDialogCalendarHref)
            : dataController.sortMode
    }

    function applySortMode(mode) {
        if (sortDialogCalendarHref.length > 0) {
            dataController.setSortModeForCalendar(sortDialogCalendarHref, mode)
        } else {
            dataController.setSortMode(mode)
        }
    }

    function taskManualSortEnabled(task) {
        if (!task || task.type !== "task") {
            return false
        }
        if (dataController.viewMode === "myTasks") {
            return dataController.sortModeForCalendar(task.calendarHref || "") === "manual"
        }
        return dataController.sortMode === "manual"
    }

    function createTask() {
        if (searchField.text.length > 0) {
            searchField.text = ""
            page.searchQuery = ""
        }
        if (dataController.viewMode !== "calendarTasks") {
            var calendars = dataController.availableCreateCalendars()
            if (calendars.length > 1) {
                PopupUtils.open(createTaskListDialog)
                return
            }
            if (calendars.length === 1) {
                page.createTaskInCalendar(calendars[0])
                return
            }
        }
        var task = dataController.createTask()
        if (task) {
            page.openTask(task)
        }
    }

    function createTaskInCalendar(calendar) {
        var task = dataController.createTaskInCalendar(calendar)
        if (task) {
            page.openTask(task)
        }
    }

    function openListOptions(calendar) {
        selectedMenuCalendar = calendar || ({})
        editListName = selectedMenuCalendar.title || ""
        editListColor = selectedMenuCalendar.color || "#2196F3"
        PopupUtils.open(listOptionsDialog)
    }

    function clearManualDropTarget() {
        manualDropBeforeTaskKey = ""
        manualDropAfterTaskKey = ""
    }

    function clearManualDragState() {
        manualDragTaskKey = ""
        manualDragPointerCaptured = false
        clearManualDropTarget()
    }

    function manualDropTargetIndex(task, offsetY, rowDistance) {
        var current = dataController.manualReorderSource(task)
        var key = page.taskKey(task)
        var currentIndex = -1
        for (var i = 0; i < current.length; ++i) {
            if (page.taskKey(current[i]) === key) {
                currentIndex = i
                break
            }
        }
        if (currentIndex < 0) {
            return -1
        }
        var rowOffset = Math.round(offsetY / Math.max(1, rowDistance))
        return Math.max(0, Math.min(currentIndex + rowOffset, current.length - 1))
    }

    function updateManualDropTarget(task, offsetY, rowDistance) {
        var current = dataController.manualReorderSource(task)
        var targetIndex = manualDropTargetIndex(task, offsetY, rowDistance)
        if (targetIndex < 0) {
            clearManualDropTarget()
            return
        }
        var key = page.taskKey(task)
        var withoutMoved = []
        for (var i = 0; i < current.length; ++i) {
            if (page.taskKey(current[i]) !== key) {
                withoutMoved.push(current[i])
            }
        }
        if (targetIndex >= withoutMoved.length) {
            manualDropBeforeTaskKey = ""
            manualDropAfterTaskKey = withoutMoved.length > 0 ? page.taskKey(withoutMoved[withoutMoved.length - 1]) : ""
            return
        }
        manualDropBeforeTaskKey = page.taskKey(withoutMoved[targetIndex])
        manualDropAfterTaskKey = ""
    }

    function saveSelectedListSettings(dialog) {
        if (editListName.trim().length === 0) {
            return
        }
        dataController.updateCalendar(selectedMenuCalendar, editListName, editListColor)
        PopupUtils.close(dialog)
    }

    function deleteSelectedList(dialog) {
        PopupUtils.close(dialog)
        PopupUtils.open(deleteListDialog)
    }

    function requestDeleteTask(task) {
        pendingSwipeDeleteTask = task || ({})
        PopupUtils.open(deleteTaskDialog)
    }

    function taskKey(task) {
        return String(task && (task.href || task.uid || task.title) ? (task.href || task.uid || task.title) : "")
    }

    function taskSelected(task) {
        var ignored = selectionRevision
        var key = taskKey(task)
        return key.length > 0 && selectedTaskKeys[key] === true
    }

    function selectedTaskCount() {
        var ignored = selectionRevision
        var count = 0
        for (var key in selectedTaskKeys) {
            if (selectedTaskKeys[key] === true) {
                count += 1
            }
        }
        return count
    }

    function clearSelection() {
        selectionMode = false
        selectedTaskKeys = ({})
        selectionRevision += 1
    }

    function toggleTaskSelection(task) {
        var key = taskKey(task)
        if (key.length === 0) return
        var updated = {}
        for (var existingKey in selectedTaskKeys) {
            updated[existingKey] = selectedTaskKeys[existingKey]
        }
        if (updated[key] === true) {
            delete updated[key]
        } else {
            updated[key] = true
        }
        selectedTaskKeys = updated
        selectionMode = selectedTaskCount() > 0
        selectionRevision += 1
    }

    function taskForKey(key) {
        var source = dataController.allTasks || []
        for (var i = 0; i < source.length; ++i) {
            if (page.taskKey(source[i]) === key) {
                return source[i]
            }
        }
        return null
    }

    function selectedTasks() {
        var result = []
        for (var key in selectedTaskKeys) {
            if (selectedTaskKeys[key] !== true) {
                continue
            }
            var task = taskForKey(key)
            if (task) {
                result.push(task)
            }
        }
        return result
    }

    function requestBulkDelete() {
        bulkDeleteDirtyCount = 0
        bulkDeleteNewCount = 0
        for (var key in selectedTaskKeys) {
            if (selectedTaskKeys[key] !== true) {
                continue
            }
            var task = taskForKey(key)
            if (!task) {
                continue
            }
            if (task.dirty === true || task.deleted === true) {
                bulkDeleteDirtyCount += 1
            }
            if (task.isNew === true || task.localStatus === "LOCAL_CREATED") {
                bulkDeleteNewCount += 1
            }
        }
        PopupUtils.open(bulkDeleteConfirmDialog)
    }

    function requestBulkMove() {
        bulkMoveTasks = selectedTasks()
        bulkMoveCalendars = dataController.availableMoveCalendarsForTasks(bulkMoveTasks)
        PopupUtils.open(bulkMoveDialog)
    }

    function bulkDeleteMessage() {
        var count = selectedTaskCount()
        var message = i18n.tr("This will delete %1 selected tasks.").arg(count)
        if (bulkDeleteNewCount > 0) {
            message += "\n" + i18n.tr("%1 local-only drafts will be removed from this device.").arg(bulkDeleteNewCount)
        }
        if (bulkDeleteDirtyCount > 0) {
            message += "\n" + i18n.tr("%1 tasks have unsynced local changes that will be discarded.").arg(bulkDeleteDirtyCount)
        }
        return message
    }

    function updateFilteredEntries() {
        var query = String(searchQuery || "").toLowerCase()
        var source = dataController.entries || []
        if (query.length === 0) {
            filteredEntries = source
            updateDisplayGroups(source)
            return
        }

        var result = []
        for (var i = 0; i < source.length; ++i) {
            var entry = source[i]
            var text = String(entry.title || "") + " " + String(entry.subtitle || "") + " " + String(entry.detail || "")
            if (text.toLowerCase().indexOf(query) >= 0) {
                result.push(entry)
            }
        }
        filteredEntries = result
        updateDisplayGroups(result)
    }

    function updateDisplayGroups(source) {
        var scopedCompleted = dataController.completedTasksForCurrentScope()
        completedTaskCount = scopedCompleted.length
        if (completedTaskCount === 0 && dataController.showCompletedTasks) {
            dataController.showCompletedTasks = false
        }

        if (dataController.viewMode === "calendarList") {
            displayEntries = source || []
            completedDisplayEntries = []
            return
        }

        var openEntries = []
        var completedEntries = []
        var entries = source || []
        for (var i = 0; i < entries.length; ++i) {
            var entry = entries[i]
            if (entry && entry.type === "task" && entry.completed === true) {
                completedEntries.push(entry)
            } else {
                openEntries.push(entry)
            }
        }
        displayEntries = sectionedEntries(openEntries)
        completedDisplayEntries = sectionedEntries(completedEntries)
    }

    function sectionedEntries(source) {
        var entries = source || []
        if (dataController.viewMode === "calendarList") {
            return entries
        }

        var result = []
        var seen = {}
        var order = []
        for (var i = 0; i < entries.length; ++i) {
            var entry = entries[i]
            if (!entry || entry.type !== "task") {
                result.push(entry)
                continue
            }
            var key = String(entry.calendarHref || entry.calendarTitle || i18n.tr("Tasks"))
            if (!seen[key]) {
                seen[key] = []
                order.push(key)
            }
            seen[key].push(entry)
        }
        if (order.length === 0) {
            return result
        }
        for (var j = 0; j < order.length; ++j) {
            var group = seen[order[j]]
            var firstTask = group.length > 0 ? group[0] : null
            var title = firstTask && firstTask.calendarTitle ? firstTask.calendarTitle : i18n.tr("Tasks")
            var href = firstTask && firstTask.calendarHref ? firstTask.calendarHref : ""
            result.push({"type": "section", "title": title, "calendarHref": href})
            group = dataController.viewMode === "myTasks" ? dataController.sortedTasksForCalendar(group, href) : group
            for (var k = 0; k < group.length; ++k) {
                result.push(group[k])
            }
        }
        return result
    }

    onSearchQueryChanged: updateFilteredEntries()

    function statusIconKind() {
        if (dataController.loading || dataController.dirtySyncRunning) {
            return "syncing"
        }
        if (dataController.conflictTasksCount > 0) {
            return "conflict"
        }
        if (dataController.dirtyTasksCount > 0) {
            return "warning"
        }
        if (dataController.syncStateText === i18n.tr("Up to date")) {
            return "synced"
        }
        return "warning"
    }

    function statusAccentColor() {
        if (dataController.loading || dataController.dirtySyncRunning) {
            return "#2c7fb8"
        }
        if (dataController.conflictTasksCount > 0) {
            return "#d85a7f"
        }
        if (dataController.dirtyTasksCount > 0) {
            return "#b37a2a"
        }
        return dataController.syncStateColor
    }

    function statusDetailsText() {
        var parts = []
            if (dataController.statusText.length > 0) {
                parts.push(dataController.statusText)
            }
            if (dataController.conflictTasksCount > 0) {
                parts.push(i18n.tr("%1 tasks have conflicts.").arg(dataController.conflictTasksCount))
            }
            if (dataController.dirtyTasksCount > 0) {
                parts.push(i18n.tr("%1 tasks have unsynced local changes.").arg(dataController.dirtyTasksCount))
            }
            if (dataController.syncStateText.length > 0) {
                parts.push(i18n.tr("Sync: %1").arg(dataController.syncStateText))
            }
        return parts.length > 0 ? parts.join("\n") : i18n.tr("No status message.")
    }

    function entrySubtitle(entry) {
        var parts = []
        if (String(entry.calendarTitle || "").length > 0 && dataController.viewMode === "myTasks") {
            parts.push(entry.calendarTitle)
        }
        if (String(entry.subtitle || "").length > 0 && entry.subtitle !== i18n.tr("Open task")) {
            parts.push(entry.subtitle)
        }
        if (String(entry.dueText || "").length > 0) {
            parts.push(i18n.tr("Due %1").arg(entry.dueText))
        }
        if (String(entry.priorityText || "").length > 0) {
            parts.push(entry.priorityText)
        }
        return parts.length > 0 ? parts.join("  |  ") : i18n.tr("Open task")
    }

    function listStatusText() {
        var base = dataController.viewMode === "calendarList"
            ? i18n.tr("Choose a list")
            : dataController.showCompletedTasks
                ? i18n.tr("Completed tasks are shown")
                : i18n.tr("Open tasks")
        return base + " - " + i18n.tr("Sort: %1").arg(dataController.sortModeLabel())
    }

    function taskFrameColor(entry) {
        if (!entry || entry.type !== "task") return theme.palette.normal.base
        if (entry.conflict === true) return "#d85a7f"
        if (entry.isNew === true) return "#2c7fb8"
        if (entry.dirty === true || entry.deleted === true) return "#b37a2a"
        return theme.palette.normal.base
    }

    function taskCardColor(entry) {
        if (!entry || entry.type !== "task") return theme.palette.normal.background
        if (entry.conflict === true) return Qt.rgba(0.85, 0.20, 0.36, 0.14)
        if (entry.isNew === true) return Qt.rgba(0.17, 0.50, 0.72, 0.14)
        if (entry.dirty === true || entry.deleted === true) return Qt.rgba(0.70, 0.48, 0.16, 0.14)
        return theme.palette.normal.background
    }

    function taskStatusBadgeText(entry) {
        if (!entry || entry.type !== "task") return ""
        if (entry.conflict === true) return i18n.tr("Conflict")
        if (entry.deleted === true) return i18n.tr("Delete pending")
        if (entry.isNew === true) return i18n.tr("New")
        if (entry.dirty === true) return i18n.tr("Unsynced")
        return ""
    }

    function taskStatusBadgeColor(entry) {
        if (!entry || entry.type !== "task") return "#7a7a7a"
        if (entry.conflict === true) return "#c7162b"
        if (entry.isNew === true) return "#237b4b"
        if (entry.dirty === true || entry.deleted === true) return "#c65d00"
        return "#7a7a7a"
    }

    function taskFrameWidth(entry) {
        return entry && entry.type === "task" && (entry.conflict === true || entry.dirty === true || entry.isNew === true || entry.deleted === true)
            ? 2
            : 1
    }

    function statusAllowsRefresh() {
        return dataController.syncStateText === i18n.tr("Sync failed")
            || dataController.statusText.indexOf(i18n.tr("Server version changed. Refresh tasks and try again.")) >= 0
    }

    header: PageHeader {
        id: header
        title: ""

        contents: RowLayout {
            anchors {
                fill: parent
                leftMargin: units.gu(0.5)
                rightMargin: units.gu(0.5)
            }
            spacing: units.gu(0.75)

            Item {
                Layout.preferredWidth: units.gu(3.4)
                Layout.preferredHeight: units.gu(5)

                Label {
                    anchors.centerIn: parent
                    text: page.selectionMode ? "\u2715" : "\u2630"
                    color: theme.palette.normal.backgroundText
                    font.pixelSize: units.gu(2.6)
                    font.bold: true
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (page.selectionMode) {
                            page.clearSelection()
                        } else {
                            page.drawerOpen = true
                        }
                    }
                }
            }

            Label {
                Layout.fillWidth: true
                visible: page.selectionMode
                text: i18n.tr("%1 selected").arg(page.selectedTaskCount())
                font.bold: true
                elide: Text.ElideRight
            }

            TextField {
                id: searchField
                Layout.fillWidth: true
                visible: !page.selectionMode
                placeholderText: i18n.tr("Search")
                text: page.searchQuery
                onTextChanged: page.searchQuery = text
            }

            Item {
                Layout.preferredWidth: units.gu(5)
                Layout.preferredHeight: units.gu(5)
                visible: !page.selectionMode && searchField.text.length > 0

                Label {
                    anchors.centerIn: parent
                    text: "\u2715"
                    color: theme.palette.normal.backgroundText
                    font.pixelSize: units.gu(2.2)
                    font.bold: true
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        searchField.text = ""
                        page.searchQuery = ""
                    }
                }
            }

            Item {
                Layout.preferredWidth: units.gu(5)
                Layout.preferredHeight: units.gu(5)
                visible: !page.selectionMode

                Label {
                    anchors.centerIn: parent
                    text: "\u21c5"
                    color: theme.palette.normal.backgroundText
                    font.pixelSize: units.gu(2.6)
                    font.bold: true
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: page.openSortPicker()
                }
            }

            Button {
                Layout.preferredWidth: units.gu(8)
                Layout.preferredHeight: units.gu(5)
                visible: page.selectionMode
                enabled: page.selectedTaskCount() > 0
                text: i18n.tr("Move")
                color: page.actionBlue
                onClicked: page.requestBulkMove()
            }

            Button {
                Layout.preferredWidth: units.gu(8)
                Layout.preferredHeight: units.gu(5)
                visible: page.selectionMode
                enabled: page.selectedTaskCount() > 0
                text: i18n.tr("Delete")
                color: page.deleteRed
                onClicked: page.requestBulkDelete()
            }

            Rectangle {
                Layout.preferredWidth: units.gu(5)
                Layout.preferredHeight: units.gu(5)
                visible: !page.selectionMode
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
                        running: dataController.loading || dataController.dirtySyncRunning
                    }

                    Connections {
                        target: dataController
                        onLoadingChanged: {
                            if (!dataController.loading && !dataController.dirtySyncRunning) {
                                statusIcon.rotation = 0
                            }
                        }
                    }

                    Canvas {
                        id: statusCanvas
                        anchors.fill: parent
                        property string paintColor: page.statusAccentColor()
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

                            if (page.statusIconKind() === "syncing") {
                                ctx.beginPath()
                                ctx.arc(w / 2, h / 2, s * 0.35, Math.PI * 0.15, Math.PI * 1.55, false)
                                ctx.stroke()
                                ctx.beginPath()
                                ctx.moveTo(w * 0.77, h * 0.30)
                                ctx.lineTo(w * 0.82, h * 0.52)
                                ctx.lineTo(w * 0.62, h * 0.45)
                                ctx.stroke()
                            } else if (page.statusIconKind() === "synced") {
                                ctx.beginPath()
                                ctx.moveTo(w * 0.22, h * 0.54)
                                ctx.lineTo(w * 0.42, h * 0.72)
                                ctx.lineTo(w * 0.78, h * 0.28)
                                ctx.stroke()
                            } else {
                                ctx.beginPath()
                                ctx.arc(w / 2, h / 2, s * 0.36, 0, Math.PI * 2, false)
                                ctx.stroke()
                                ctx.beginPath()
                                ctx.moveTo(w / 2, h * 0.26)
                                ctx.lineTo(w / 2, h * 0.58)
                                ctx.stroke()
                                ctx.beginPath()
                                ctx.arc(w / 2, h * 0.75, s * 0.035, 0, Math.PI * 2, false)
                                ctx.fill()
                            }
                        }

                        Connections {
                            target: dataController
                            onLoadingChanged: statusCanvas.requestPaint()
                            onDirtySyncRunningChanged: statusCanvas.requestPaint()
                            onSyncStateTextChanged: statusCanvas.requestPaint()
                            onSyncStateColorChanged: statusCanvas.requestPaint()
                            onConflictTasksCountChanged: statusCanvas.requestPaint()
                            onDirtyTasksCountChanged: statusCanvas.requestPaint()
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: PopupUtils.open(statusDetailsDialog)
                }
            }

            Rectangle {
                Layout.preferredWidth: units.gu(5)
                Layout.preferredHeight: units.gu(5)
                radius: units.gu(2.5)
                color: "#2c7fb8"
                border.width: 1
                border.color: "#7a7a7a"

                Image {
                    id: accountAvatarSource
                    anchors.fill: parent
                    source: dataController.accountAvatarUrl
                    fillMode: Image.PreserveAspectCrop
                    visible: false
                }

                Rectangle {
                    id: accountAvatarMask
                    anchors.fill: parent
                    radius: width / 2
                    visible: false
                }

                OpacityMask {
                    anchors.fill: parent
                    source: accountAvatarSource
                    maskSource: accountAvatarMask
                    visible: accountAvatarSource.status === Image.Ready
                }

                Label {
                    anchors.centerIn: parent
                    text: page.accountInitial
                    color: "white"
                    font.bold: true
                    visible: accountAvatarSource.status !== Image.Ready
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: page.openPage("AccountSelectionPage.qml")
                }
            }
        }
    }

    Component {
        id: createTaskListDialog

        Dialog {
            id: dialog
            title: i18n.tr("Choose task list")
            text: i18n.tr("Select where the new task should be created.")

            Repeater {
                model: page.bulkMoveCalendars

                Button {
                    text: modelData.title || i18n.tr("Tasks")
                    onClicked: {
                        PopupUtils.close(dialog)
                        page.createTaskInCalendar(modelData)
                    }
                }
            }

            Button {
                text: i18n.tr("Cancel")
                onClicked: PopupUtils.close(dialog)
            }
        }
    }

    Component {
        id: createListDialog

        Dialog {
            id: dialog
            title: i18n.tr("Create new list")
            text: i18n.tr("Enter a name for the new task list.")

            TextField {
                id: listNameField
                text: page.newListName
                placeholderText: i18n.tr("List name")
                inputMethodHints: Qt.ImhNoPredictiveText
                onTextChanged: page.newListName = text
                onAccepted: {
                    if (text.trim().length > 0) {
                        dataController.createCalendar(text)
                        page.newListName = ""
                        PopupUtils.close(dialog)
                    }
                }
            }

            Button {
                text: i18n.tr("Create")
                color: "#2c7fb8"
                enabled: listNameField.text.trim().length > 0 && !dataController.loading
                onClicked: {
                    dataController.createCalendar(listNameField.text)
                    page.newListName = ""
                    PopupUtils.close(dialog)
                }
            }

            Button {
                text: i18n.tr("Cancel")
                onClicked: PopupUtils.close(dialog)
            }
        }
    }

    Component {
        id: listOptionsDialog

        Dialog {
            id: dialog
            title: page.selectedMenuCalendar.title || i18n.tr("Task list")
            text: i18n.tr("Rename the list, change its color, or delete it.")

            TextField {
                id: editListNameField
                text: page.editListName
                placeholderText: i18n.tr("List name")
                inputMethodHints: Qt.ImhNoPredictiveText
                onTextChanged: page.editListName = text
                onAccepted: {
                    if (text.trim().length > 0) {
                        page.saveSelectedListSettings(dialog)
                    }
                }
            }

            Label {
                text: i18n.tr("Color")
                font.bold: true
            }

            GridLayout {
                columns: 7
                rowSpacing: units.gu(0.8)
                columnSpacing: units.gu(0.8)

                Repeater {
                    model: page.listColorChoices

                    Rectangle {
                        width: units.gu(3.8)
                        height: units.gu(3.8)
                        radius: width / 2
                        color: modelData
                        border.width: page.editListColor === modelData ? 3 : 1
                        border.color: page.editListColor === modelData ? theme.palette.normal.backgroundText : "#7a7a7a"

                        MouseArea {
                            anchors.fill: parent
                            onClicked: page.editListColor = modelData
                        }
                    }
                }
            }

            Button {
                text: i18n.tr("Save")
                color: page.actionBlue
                enabled: page.editListName.trim().length > 0 && !dataController.loading
                onClicked: page.saveSelectedListSettings(dialog)
            }

            Button {
                text: i18n.tr("Delete list")
                color: page.deleteRed
                enabled: !dataController.loading
                onClicked: page.deleteSelectedList(dialog)
            }

            Button {
                text: i18n.tr("Cancel")
                onClicked: PopupUtils.close(dialog)
            }
        }
    }

    Component {
        id: deleteListDialog

        Dialog {
            id: dialog
            title: i18n.tr("Delete task list?")
            text: i18n.tr("The list and its tasks will be removed from the server and this device.")

            Button {
                text: i18n.tr("Delete")
                color: page.deleteRed
                enabled: !dataController.loading
                onClicked: {
                    dataController.deleteCalendar(page.selectedMenuCalendar)
                    PopupUtils.close(dialog)
                }
            }

            Button {
                text: i18n.tr("Cancel")
                onClicked: PopupUtils.close(dialog)
            }
        }
    }

    Component {
        id: deleteTaskDialog

        Dialog {
            id: dialog
            title: i18n.tr("Delete task?")
            text: i18n.tr("The task will be deleted from this device and synced to the server.")

            Button {
                text: i18n.tr("Delete")
                color: page.deleteRed
                enabled: !dataController.loading
                onClicked: {
                    dataController.deleteTask(page.pendingSwipeDeleteTask)
                    page.pendingSwipeDeleteTask = ({})
                    PopupUtils.close(dialog)
                }
            }

            Button {
                text: i18n.tr("Cancel")
                onClicked: {
                    page.pendingSwipeDeleteTask = ({})
                    PopupUtils.close(dialog)
                }
            }
        }
    }

    Component {
        id: bulkDeleteConfirmDialog

        Dialog {
            id: dialog
            title: i18n.tr("Delete selected tasks?")
            text: page.bulkDeleteMessage()

            Button {
                text: i18n.tr("Delete")
                color: page.deleteRed
                enabled: !dataController.loading
                onClicked: {
                    PopupUtils.close(dialog)
                    var count = dataController.deleteTasksByKeys(page.selectedTaskKeys)
                    page.clearSelection()
                    if (count === 0) {
                        dataController.statusText = i18n.tr("No selected tasks could be deleted.")
                    }
                }
            }

            Button {
                text: i18n.tr("Cancel")
                onClicked: PopupUtils.close(dialog)
            }
        }
    }

    Component {
        id: bulkMoveDialog

        Dialog {
            id: dialog
            title: i18n.tr("Move selected tasks")
            text: i18n.tr("Choose the target list. Tasks with unsynced local changes are skipped.")

            Repeater {
                model: dataController.availableCreateCalendars()

                Button {
                    text: modelData.title || i18n.tr("Tasks")
                    color: page.actionBlue
                    visible: dataController.canMoveTasksToCalendar(page.bulkMoveTasks, modelData)
                    enabled: visible && !dataController.loading
                    onClicked: {
                        PopupUtils.close(dialog)
                        var count = dataController.moveTasksByKeysToCalendar(page.selectedTaskKeys, modelData)
                        page.clearSelection()
                        if (count === 0) {
                            dataController.statusText = i18n.tr("No selected tasks could be moved.")
                        }
                    }
                }
            }

            Button {
                text: i18n.tr("Cancel")
                onClicked: PopupUtils.close(dialog)
            }
        }
    }

    Component {
        id: statusDetailsDialog

        Dialog {
            id: dialog
            title: i18n.tr("Sync status")
            text: page.statusDetailsText()

            Button {
                text: i18n.tr("Resolve conflict")
                color: page.actionBlue
                visible: dataController.conflictTasksCount > 0
                enabled: !dataController.loading
                onClicked: {
                    PopupUtils.close(dialog)
                    page.openConflictResolution(null)
                }
            }

            Button {
                text: i18n.tr("Refresh")
                color: page.actionBlue
                visible: page.statusAllowsRefresh()
                enabled: !dataController.loading
                onClicked: {
                    PopupUtils.close(dialog)
                    dataController.refresh()
                }
            }

            Button {
                text: i18n.tr("Close")
                onClicked: PopupUtils.close(dialog)
            }
        }
    }

    Component {
        id: reopenCompletedDialog

        Dialog {
            id: dialog
            title: i18n.tr("Reopen completed tasks?")
            text: i18n.tr("This will mark all completed tasks in this list as open again.")

            Button {
                text: i18n.tr("Reopen all")
                color: page.actionBlue
                onClicked: {
                    PopupUtils.close(dialog)
                    dataController.reopenCompletedTasksInCurrentScope()
                }
            }

            Button {
                text: i18n.tr("Cancel")
                onClicked: PopupUtils.close(dialog)
            }
        }
    }

    Component {
        id: sortDialog

        Dialog {
            id: dialog
            title: page.sortDialogCalendarTitle.length > 0
                ? i18n.tr("Sort %1").arg(page.sortDialogCalendarTitle)
                : i18n.tr("Sort tasks")
            text: page.activeSortMode() === "manual"
                ? i18n.tr("Manual order is saved to the task list using Nextcloud-compatible task order values.")
                : i18n.tr("Uses standard task sort concepts.")

            Repeater {
                model: dataController.sortOptions()

                Button {
                    text: modelData.label + (modelData.value === page.activeSortMode() ? "  \u2713" : "")
                    color: modelData.value === page.activeSortMode() ? "#2c7fb8" : theme.palette.normal.background
                    onClicked: {
                        page.applySortMode(modelData.value)
                        PopupUtils.close(dialog)
                    }
                }
            }

            Button {
                text: dataController.sortAscending ? i18n.tr("Ascending") : i18n.tr("Descending")
                visible: page.activeSortMode() !== "manual"
                onClicked: dataController.toggleSortAscending()
            }

            Button {
                text: i18n.tr("Close")
                onClicked: PopupUtils.close(dialog)
            }
        }
    }

    Component {
        id: sortScopeDialog

        Dialog {
            id: dialog
            title: i18n.tr("Sort list")
            text: i18n.tr("Choose which task list to sort.")

            Repeater {
                model: dataController.visibleSortCalendars()

                Button {
                    text: (modelData.title || i18n.tr("Tasks")) + " - " + dataController.sortModeLabelForCalendar(modelData.href || "")
                    onClicked: {
                        page.sortDialogCalendarHref = modelData.href || ""
                        page.sortDialogCalendarTitle = modelData.title || i18n.tr("Tasks")
                        PopupUtils.close(dialog)
                        PopupUtils.open(sortDialog)
                    }
                }
            }

            Button {
                text: i18n.tr("Close")
                onClicked: PopupUtils.close(dialog)
            }
        }
    }

    TasksController {
        id: dataController
        onEntriesChanged: page.updateFilteredEntries()
        onAccountDataRevisionChanged: {
            page.filteredEntries = []
            page.displayEntries = []
            page.completedDisplayEntries = []
            page.completedTaskCount = 0
            page.selectionMode = false
            page.selectedTaskKeys = ({})
            page.selectionRevision += 1
            page.clearManualDragState()
        }
        onViewModeChanged: page.updateFilteredEntries()
        onShowCompletedTasksChanged: page.updateFilteredEntries()
    }

    Connections {
        target: appController
        function onAccountChanged(accountId, displayName, providerId, serviceId, serverUrl, avatarUrl) {
            dataController.applyAccountSelection(accountId, displayName, providerId, serviceId, serverUrl, avatarUrl)
        }
    }

    Flickable {
        id: taskFlickable
        anchors { fill: parent; topMargin: page.header.height }
        contentWidth: width
        contentHeight: contentColumn.height + units.gu(3)
        clip: true
        interactive: page.manualDragTaskKey.length === 0 && !page.manualDragPointerCaptured
        boundsBehavior: Flickable.DragOverBounds
        property bool pullRefreshArmed: false

        onContentYChanged: {
            if (contentY < -page.pullRefreshThreshold && !dataController.loading) {
                pullRefreshArmed = true
            }
        }

        onMovementEnded: {
            if (pullRefreshArmed && !dataController.loading) {
                dataController.refresh()
            }
            pullRefreshArmed = false
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
            opacity: taskFlickable.contentY < -units.gu(2) || dataController.loading ? 0.92 : 0
            visible: opacity > 0
            z: 4

            Label {
                id: refreshPullLabel
                anchors.centerIn: parent
                text: dataController.loading
                    ? i18n.tr("Refreshing...")
                    : taskFlickable.contentY < -page.pullRefreshThreshold
                    ? i18n.tr("Release to refresh")
                    : i18n.tr("Pull to refresh")
                color: "white"
            }
        }

        ColumnLayout {
            id: contentColumn
            width: Math.max(0, taskFlickable.width - units.gu(4))
            x: units.gu(2)
            y: 0
            spacing: units.gu(1.2)

            RowLayout {
                Layout.fillWidth: true
                spacing: units.gu(1)
                Item {
                    Layout.preferredWidth: units.gu(5)
                    Layout.preferredHeight: units.gu(4)
                    visible: dataController.viewMode === "calendarTasks" || dataController.viewMode === "calendarList"

                    Label {
                        anchors.centerIn: parent
                        text: "\u2039"
                        color: theme.palette.normal.backgroundText
                        font.pixelSize: units.gu(3)
                        font.bold: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: dataController.goBackToMyTasks()
                    }
                }
                Label {
                    Layout.fillWidth: true
                    text: dataController.titleText + "  \u2022  " + page.listStatusText()
                    textSize: Label.Small
                    opacity: 0.68
                    elide: Text.ElideRight
                }
            }

            Repeater {
                model: page.displayEntries
                delegate: Item {
                    id: taskRow
                    Layout.fillWidth: true
                    Layout.preferredHeight: baseHeight + dropBeforeHeight + dropAfterHeight
                    readonly property real baseHeight: modelData.type === "section" ? units.gu(4) : (modelData.type === "task" ? units.gu(8.8) : units.gu(6.2))
                    readonly property real dropBeforeHeight: modelData.type === "task" && page.manualDropBeforeTaskKey === page.taskKey(modelData) ? units.gu(5.8) : 0
                    readonly property real dropAfterHeight: modelData.type === "task" && page.manualDropAfterTaskKey === page.taskKey(modelData) ? units.gu(5.8) : 0
                    readonly property real actionThreshold: units.gu(8)
                    property bool manualDragActive: false
                    property bool manualDragMoved: false
                    property bool manualDragCapture: false
                    property real manualDragStartY: 0
                    property real manualDragOffsetY: 0

                    function resetSwipe() {
                        swipeContent.x = 0
                        manualDragActive = false
                        manualDragMoved = false
                        manualDragCapture = false
                        page.manualDragPointerCaptured = false
                        manualDragOffsetY = 0
                    }

                    function triggerSwipeAction(offset) {
                        if (modelData.type !== "task") return
                        if (offset > 0) {
                            page.requestDeleteTask(modelData)
                        } else if (offset < 0) {
                            dataController.toggleTaskCompleted(modelData)
                        }
                    }

                    function beginManualDrag(localY) {
                        if (modelData.type !== "task" || !page.taskManualSortEnabled(modelData) || dataController.loading) {
                            return
                        }
                        dataController.pauseUserSync()
                        manualDragCapture = true
                        manualDragActive = true
                        manualDragStartY = localY
                        manualDragMoved = false
                        manualDragOffsetY = 0
                        page.manualDragPointerCaptured = true
                        page.manualDragTaskKey = page.taskKey(modelData)
                        page.clearManualDropTarget()
                        swipeContent.x = 0
                    }

                    function updateManualDrag(localY) {
                        if (!manualDragActive || page.manualDragTaskKey !== page.taskKey(modelData)) {
                            return
                        }
                        manualDragOffsetY = localY - manualDragStartY
                        if (Math.abs(manualDragOffsetY) > units.gu(1.2)) {
                            manualDragMoved = true
                        }
                        if (manualDragMoved) {
                            page.updateManualDropTarget(modelData, manualDragOffsetY, height + units.gu(1.2))
                        }
                    }

                    function finishManualDrag() {
                        if (page.manualDragTaskKey !== page.taskKey(modelData)) {
                            return
                        }
                        var shouldMove = manualDragMoved
                        var targetIndex = -1
                        if (manualDragMoved) {
                            var rowOffset = Math.round(manualDragOffsetY / Math.max(1, height + units.gu(1.2)))
                            var current = dataController.manualReorderSource(modelData)
                            var currentIndex = -1
                            for (var ri = 0; ri < current.length; ++ri) {
                                if (page.taskKey(current[ri]) === page.taskKey(modelData)) {
                                    currentIndex = ri
                                    break
                                }
                            }
                            if (currentIndex >= 0) {
                                targetIndex = currentIndex + rowOffset
                            }
                        }
                        page.clearManualDragState()
                        resetSwipe()
                        dataController.resumeUserSync()
                        if (shouldMove && targetIndex >= 0) {
                            dataController.reorderManualTask(modelData, targetIndex)
                        } else if (!shouldMove) {
                            page.toggleTaskSelection(modelData)
                        }
                    }

                    RowLayout {
                        anchors {
                            fill: parent
                            leftMargin: units.gu(0.5)
                            rightMargin: units.gu(0.5)
                        }
                        visible: modelData.type === "section"
                        spacing: units.gu(0.8)

                        Rectangle {
                            Layout.preferredWidth: units.gu(1.2)
                            Layout.preferredHeight: units.gu(1.2)
                            radius: width / 2
                            color: "#d85a7f"
                        }

                        Label {
                            Layout.fillWidth: true
                            text: modelData.title || i18n.tr("Tasks")
                            font.bold: true
                            opacity: 0.78
                            elide: Text.ElideRight
                        }
                    }

                    Rectangle {
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            bottom: parent.bottom
                            topMargin: taskRow.dropBeforeHeight + units.gu(0.45)
                            bottomMargin: taskRow.dropAfterHeight + units.gu(0.45)
                            leftMargin: units.gu(0.45)
                            rightMargin: units.gu(0.45)
                        }
                        radius: units.gu(0.6)
                        color: swipeContent.x > 0 ? "#c7162b" : "#5a8f3c"
                        opacity: modelData.type === "task" ? Math.min(1, Math.abs(swipeContent.x) / taskRow.actionThreshold) : 0
                        visible: modelData.type === "task" && opacity > 0

                        Label {
                            anchors {
                                left: parent.left
                                verticalCenter: parent.verticalCenter
                                leftMargin: units.gu(2)
                            }
                            visible: swipeContent.x > units.gu(1)
                            text: i18n.tr("Delete")
                            color: "white"
                            font.bold: true
                        }

                        Label {
                            anchors {
                                right: parent.right
                                verticalCenter: parent.verticalCenter
                                rightMargin: units.gu(2)
                            }
                            visible: swipeContent.x < -units.gu(1)
                            text: modelData.completed === true ? i18n.tr("Reopen") : i18n.tr("Complete")
                            color: "white"
                            font.bold: true
                        }
                    }

                    Item {
                        id: swipeContent
                        anchors {
                            top: parent.top
                            bottom: parent.bottom
                            topMargin: taskRow.dropBeforeHeight
                            bottomMargin: taskRow.dropAfterHeight
                        }
                        width: parent.width
                        x: 0
                        z: taskRow.manualDragActive ? 5 : 0
                        opacity: taskRow.manualDragActive ? 0.92 : 1.0
                        scale: taskRow.manualDragActive ? 1.02 : 1.0
                        transform: Translate {
                            y: taskRow.manualDragActive ? taskRow.manualDragOffsetY : 0
                        }

                        Rectangle {
                            anchors { fill: parent; margins: units.gu(0.45) }
                            radius: units.gu(0.6)
                            color: page.taskCardColor(modelData)
                            border.width: page.manualDragTaskKey === page.taskKey(modelData) || page.taskSelected(modelData) ? 2 : page.taskFrameWidth(modelData)
                            border.color: page.manualDragTaskKey === page.taskKey(modelData) || page.taskSelected(modelData) ? page.actionBlue : page.taskFrameColor(modelData)
                            opacity: modelData.completed ? 0.56 : 1.0
                            visible: modelData.type !== "section"
                        }

                        Rectangle {
                            anchors {
                                top: parent.top
                                horizontalCenter: parent.horizontalCenter
                                topMargin: -taskRow.dropBeforeHeight / 2
                            }
                            visible: taskRow.dropBeforeHeight > 0
                            width: parent.width - units.gu(3)
                            height: units.gu(0.35)
                            radius: height / 2
                            color: page.actionBlue
                            opacity: 0.75
                        }

                        Rectangle {
                            anchors {
                                bottom: parent.bottom
                                horizontalCenter: parent.horizontalCenter
                                bottomMargin: -taskRow.dropAfterHeight / 2
                            }
                            visible: taskRow.dropAfterHeight > 0
                            width: parent.width - units.gu(3)
                            height: units.gu(0.35)
                            radius: height / 2
                            color: page.actionBlue
                            opacity: 0.75
                        }

                        RowLayout {
                            anchors {
                                left: parent.left
                                right: parent.right
                                top: parent.top
                                bottom: parent.bottom
                                margins: units.gu(1)
                            }
                            spacing: units.gu(1)
                            visible: modelData.type !== "section"

                        Item {
                            Layout.preferredWidth: units.gu(4.2)
                            Layout.fillHeight: true

                            Rectangle {
                                anchors.centerIn: parent
                                width: units.gu(2.8)
                                height: units.gu(2.8)
                                radius: units.gu(0.35)
                                visible: modelData.type === "task"
                                color: modelData.completed ? "#5a8f3c" : "transparent"
                                border.width: 2
                                border.color: modelData.completed ? "#5a8f3c" : theme.palette.normal.backgroundText

                                Label {
                                    anchors.centerIn: parent
                                    text: "\u2713"
                                    visible: modelData.completed === true
                                    color: "white"
                                    font.bold: true
                                }
                            }

                            Label {
                                anchors.centerIn: parent
                                visible: modelData.type !== "task"
                                text: "\u25b8"
                                font.bold: true
                                color: theme.palette.normal.backgroundText
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: modelData.type === "task" && !dataController.loading
                                onClicked: {
                                    if (page.selectionMode) {
                                        page.toggleTaskSelection(modelData)
                                    } else {
                                        dataController.toggleTaskCompleted(modelData)
                                    }
                                }
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: units.gu(0.2)
                            Label {
                                Layout.fillWidth: true
                                text: modelData.title || i18n.tr("Untitled")
                                font.bold: !modelData.completed
                                wrapMode: Text.WordWrap
                                maximumLineCount: modelData.type === "task" ? 2 : 1
                                elide: Text.ElideRight
                                opacity: modelData.completed ? 0.58 : 1.0
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                visible: modelData.type === "task"
                                spacing: units.gu(0.75)

                                Label {
                                    Layout.fillWidth: true
                                    text: page.entrySubtitle(modelData)
                                    textSize: Label.Small
                                    opacity: modelData.completed ? 0.48 : 0.68
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }

                                Row {
                                    Layout.alignment: Qt.AlignVCenter
                                    visible: modelData.type === "task" && page.taskStatusBadgeText(modelData).length > 0
                                    spacing: units.gu(0.4)

                                    Rectangle {
                                        color: page.taskStatusBadgeColor(modelData)
                                        height: taskStatusBadgeLabel.implicitHeight + units.gu(0.35)
                                        width: Math.min(taskStatusBadgeLabel.implicitWidth + units.gu(0.9), units.gu(12))
                                        radius: units.gu(0.3)

                                        Label {
                                            id: taskStatusBadgeLabel
                                            anchors {
                                                left: parent.left
                                                right: parent.right
                                                verticalCenter: parent.verticalCenter
                                                leftMargin: units.gu(0.45)
                                                rightMargin: units.gu(0.45)
                                            }
                                            text: page.taskStatusBadgeText(modelData)
                                            color: "white"
                                            elide: Text.ElideRight
                                            maximumLineCount: 1
                                        }
                                    }
                                }
                            }
                        }

                        Item {
                            Layout.preferredWidth: page.taskManualSortEnabled(modelData) && !page.selectionMode ? units.gu(4.2) : 0
                            Layout.fillHeight: true
                            visible: page.taskManualSortEnabled(modelData) && !page.selectionMode

                            Label {
                                anchors.centerIn: parent
                                text: "\u2630"
                                font.pixelSize: units.gu(2.4)
                                font.bold: true
                                color: theme.palette.normal.backgroundText
                                opacity: 0.62
                            }

                            MouseArea {
                                id: dragHandleArea
                                anchors.fill: parent
                                enabled: page.taskManualSortEnabled(modelData) && !page.selectionMode && !dataController.loading
                                preventStealing: true
                                onPressed: taskRow.beginManualDrag(dragHandleArea.mapToItem(page, mouse.x, mouse.y).y)
                                onPositionChanged: taskRow.updateManualDrag(dragHandleArea.mapToItem(page, mouse.x, mouse.y).y)
                                onReleased: taskRow.finishManualDrag()
                                onCanceled: {
                                    page.clearManualDragState()
                                    taskRow.resetSwipe()
                                    dataController.resumeUserSync()
                                }
                            }
                        }

                    }
                    }

                    MouseArea {
                        id: taskPointerArea
                        anchors {
                            top: parent.top
                            bottom: parent.bottom
                            left: parent.left
                            right: parent.right
                            leftMargin: modelData.type === "task" ? units.gu(5) : 0
                            rightMargin: page.taskManualSortEnabled(modelData) && !page.selectionMode ? units.gu(5) : 0
                        }
                        enabled: modelData.type !== "section"
                        drag.target: page.selectionMode ? null : (modelData.type === "task" && !taskRow.manualDragActive ? swipeContent : null)
                        drag.axis: Drag.XAxis
                        drag.minimumX: -taskRow.actionThreshold * 1.25
                        drag.maximumX: taskRow.actionThreshold * 1.25
                        preventStealing: taskRow.manualDragCapture || taskRow.manualDragActive || (modelData.type === "task" && Math.abs(swipeContent.x) > units.gu(1))
                        onPressed: {
                            taskRow.manualDragStartY = mouse.y
                            taskRow.manualDragMoved = false
                            taskRow.manualDragCapture = false
                            page.manualDragPointerCaptured = false
                            taskRow.manualDragOffsetY = 0
                        }
                        onPressAndHold: {
                            if (modelData.type === "task" && !dataController.loading && page.manualDragTaskKey.length === 0) {
                                page.toggleTaskSelection(modelData)
                            }
                        }
                        onPositionChanged: {
                            if (taskRow.manualDragActive) {
                                taskRow.updateManualDrag(mouse.y)
                            }
                        }
                        onClicked: {
                            if (taskRow.manualDragActive || page.manualDragTaskKey === page.taskKey(modelData)) {
                                return
                            }
                            if (modelData.type === "task" && Math.abs(swipeContent.x) >= units.gu(1)) {
                                return
                            }
                            if (page.selectionMode && modelData.type === "task") {
                                page.toggleTaskSelection(modelData)
                                return
                            }
                            if (modelData.type === "calendar") {
                                dataController.openCalendar(modelData.href, modelData.title)
                            } else if (modelData.type === "task") {
                                if (modelData.conflict === true) {
                                    page.openConflictResolution(modelData)
                                } else {
                                    page.openTask(modelData)
                                }
                            }
                        }
                        onReleased: {
                            if (modelData.type !== "task") return
                            if (page.manualDragTaskKey === page.taskKey(modelData)) {
                                taskRow.finishManualDrag()
                                return
                            }
                            if (swipeContent.x > taskRow.actionThreshold) {
                                var positiveOffset = swipeContent.x
                                taskRow.resetSwipe()
                                taskRow.triggerSwipeAction(positiveOffset)
                            } else if (swipeContent.x < -taskRow.actionThreshold) {
                                var negativeOffset = swipeContent.x
                                taskRow.resetSwipe()
                                taskRow.triggerSwipeAction(negativeOffset)
                            } else {
                                taskRow.resetSwipe()
                            }
                        }
                        onCanceled: {
                            if (page.manualDragTaskKey === page.taskKey(modelData)) {
                                page.clearManualDragState()
                                taskRow.resetSwipe()
                                dataController.resumeUserSync()
                            } else if (taskRow.manualDragCapture) {
                                page.clearManualDragState()
                                taskRow.resetSwipe()
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                visible: page.completedTaskCount > 0 && dataController.viewMode !== "calendarList"
                spacing: units.gu(1)

                RowLayout {
                    id: completedColumn
                    Layout.fillWidth: true
                    Layout.preferredHeight: units.gu(4.8)
                    spacing: units.gu(1)

                    Label {
                        Layout.fillWidth: true
                        text: dataController.showCompletedTasks
                            ? i18n.tr("Hide completed tasks (%1)").arg(page.completedTaskCount)
                            : i18n.tr("Show completed tasks (%1)").arg(page.completedTaskCount)
                        opacity: 0.72
                        horizontalAlignment: Text.AlignHCenter
                        font.bold: true

                        MouseArea {
                            anchors.fill: parent
                            enabled: !dataController.loading
                            onClicked: dataController.toggleShowCompletedTasks()
                        }
                    }

                }

                Repeater {
                    model: dataController.showCompletedTasks ? page.completedDisplayEntries : []
                    delegate: Item {
                        id: completedTaskRow
                        Layout.fillWidth: true
                        Layout.preferredHeight: modelData.type === "section" ? units.gu(4) : units.gu(8.8)
                        readonly property real actionThreshold: units.gu(8)

                        function resetSwipe() {
                            completedSwipeContent.x = 0
                        }

                        function triggerSwipeAction(offset) {
                            if (modelData.type !== "task") return
                            if (offset > 0) {
                                page.requestDeleteTask(modelData)
                            } else if (offset < 0) {
                                dataController.toggleTaskCompleted(modelData)
                            }
                        }

                        RowLayout {
                            anchors {
                                fill: parent
                                leftMargin: units.gu(0.5)
                                rightMargin: units.gu(0.5)
                            }
                            visible: modelData.type === "section"
                            spacing: units.gu(0.8)

                            Rectangle {
                                Layout.preferredWidth: units.gu(1.2)
                                Layout.preferredHeight: units.gu(1.2)
                                radius: width / 2
                                color: "#d85a7f"
                            }

                            Label {
                                Layout.fillWidth: true
                                text: modelData.title || i18n.tr("Tasks")
                                font.bold: true
                                opacity: 0.78
                                elide: Text.ElideRight
                            }
                        }

                        Rectangle {
                            anchors { fill: parent; margins: units.gu(0.45) }
                            radius: units.gu(0.6)
                            color: completedSwipeContent.x > 0 ? "#c7162b" : "#5a8f3c"
                            opacity: modelData.type === "task" ? Math.min(1, Math.abs(completedSwipeContent.x) / completedTaskRow.actionThreshold) : 0
                            visible: modelData.type === "task" && opacity > 0

                            Label {
                                anchors {
                                    left: parent.left
                                    verticalCenter: parent.verticalCenter
                                    leftMargin: units.gu(2)
                                }
                                visible: completedSwipeContent.x > units.gu(1)
                                text: i18n.tr("Delete")
                                color: "white"
                                font.bold: true
                            }

                            Label {
                                anchors {
                                    right: parent.right
                                    verticalCenter: parent.verticalCenter
                                    rightMargin: units.gu(2)
                                }
                                visible: completedSwipeContent.x < -units.gu(1)
                                text: i18n.tr("Reopen")
                                color: "white"
                                font.bold: true
                            }
                        }

                        Item {
                            id: completedSwipeContent
                            anchors {
                                top: parent.top
                                bottom: parent.bottom
                            }
                            width: parent.width
                            x: 0

                            Rectangle {
                                anchors { fill: parent; margins: units.gu(0.45) }
                                radius: units.gu(0.6)
                                color: page.taskCardColor(modelData)
                                border.width: page.taskSelected(modelData) ? 2 : page.taskFrameWidth(modelData)
                                border.color: page.taskSelected(modelData) ? page.actionBlue : page.taskFrameColor(modelData)
                                opacity: 0.56
                                visible: modelData.type !== "section"
                            }

                            RowLayout {
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    top: parent.top
                                    bottom: parent.bottom
                                    margins: units.gu(1)
                                }
                                spacing: units.gu(1)
                                visible: modelData.type !== "section"

                                Item {
                                    Layout.preferredWidth: units.gu(4.2)
                                    Layout.fillHeight: true

                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: units.gu(2.8)
                                        height: units.gu(2.8)
                                        radius: units.gu(0.35)
                                        color: "#5a8f3c"
                                        border.width: 2
                                        border.color: "#5a8f3c"

                                        Label {
                                            anchors.centerIn: parent
                                            text: "\u2713"
                                            color: "white"
                                            font.bold: true
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        enabled: !dataController.loading
                                        onClicked: {
                                            if (page.selectionMode) {
                                                page.toggleTaskSelection(modelData)
                                            } else {
                                                dataController.toggleTaskCompleted(modelData)
                                            }
                                        }
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: units.gu(0.2)

                                    Label {
                                        Layout.fillWidth: true
                                        text: modelData.title || i18n.tr("Untitled")
                                        font.bold: false
                                        wrapMode: Text.WordWrap
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                        opacity: 0.58
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: units.gu(0.75)

                                        Label {
                                            Layout.fillWidth: true
                                            text: page.entrySubtitle(modelData)
                                            textSize: Label.Small
                                            opacity: 0.48
                                            elide: Text.ElideRight
                                            maximumLineCount: 1
                                        }

                                        Row {
                                            Layout.alignment: Qt.AlignVCenter
                                            visible: modelData.type === "task" && page.taskStatusBadgeText(modelData).length > 0
                                            spacing: units.gu(0.4)

                                            Rectangle {
                                                color: page.taskStatusBadgeColor(modelData)
                                                height: completedTaskStatusBadgeLabel.implicitHeight + units.gu(0.35)
                                                width: Math.min(completedTaskStatusBadgeLabel.implicitWidth + units.gu(0.9), units.gu(12))
                                                radius: units.gu(0.3)

                                                Label {
                                                    id: completedTaskStatusBadgeLabel
                                                    anchors {
                                                        left: parent.left
                                                        right: parent.right
                                                        verticalCenter: parent.verticalCenter
                                                        leftMargin: units.gu(0.45)
                                                        rightMargin: units.gu(0.45)
                                                    }
                                                    text: page.taskStatusBadgeText(modelData)
                                                    color: "white"
                                                    elide: Text.ElideRight
                                                    maximumLineCount: 1
                                                }
                                            }
                                        }
                                    }
                                }

                            }
                        }

                        MouseArea {
                            anchors {
                                top: parent.top
                                bottom: parent.bottom
                                left: parent.left
                                right: parent.right
                                leftMargin: modelData.type === "task" ? units.gu(5) : 0
                            }
                            enabled: modelData.type !== "section"
                            drag.target: page.selectionMode ? null : (modelData.type === "task" ? completedSwipeContent : null)
                            drag.axis: Drag.XAxis
                            drag.minimumX: -completedTaskRow.actionThreshold * 1.25
                            drag.maximumX: completedTaskRow.actionThreshold * 1.25
                            preventStealing: modelData.type === "task" && Math.abs(completedSwipeContent.x) > units.gu(1)
                            onClicked: {
                                if (modelData.type === "task" && Math.abs(completedSwipeContent.x) >= units.gu(1)) {
                                    return
                                }
                                if (page.selectionMode && modelData.type === "task") {
                                    page.toggleTaskSelection(modelData)
                                    return
                                }
                                if (modelData.conflict === true) {
                                    page.openConflictResolution(modelData)
                                } else {
                                    page.openTask(modelData)
                                }
                            }
                            onPressAndHold: {
                                if (modelData.type === "task" && !dataController.loading) {
                                    page.toggleTaskSelection(modelData)
                                }
                            }
                            onReleased: {
                                if (modelData.type !== "task") return
                                if (completedSwipeContent.x > completedTaskRow.actionThreshold) {
                                    var positiveOffset = completedSwipeContent.x
                                    completedTaskRow.resetSwipe()
                                    completedTaskRow.triggerSwipeAction(positiveOffset)
                                } else if (completedSwipeContent.x < -completedTaskRow.actionThreshold) {
                                    var negativeOffset = completedSwipeContent.x
                                    completedTaskRow.resetSwipe()
                                    completedTaskRow.triggerSwipeAction(negativeOffset)
                                } else {
                                    completedTaskRow.resetSwipe()
                                }
                            }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: units.gu(5)
                    visible: dataController.viewMode === "calendarTasks" && dataController.showCompletedTasks

                    Label {
                        anchors.centerIn: parent
                        text: i18n.tr("Reopen all")
                        color: theme.palette.normal.backgroundText
                        font.bold: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: !dataController.loading
                        onClicked: PopupUtils.open(reopenCompletedDialog)
                    }
                }
            }

            Label {
                Layout.fillWidth: true
                visible: page.filteredEntries.length === 0 && (dataController.viewMode === "myTasks" || dataController.viewMode === "calendarTasks") && !dataController.loading && page.searchQuery.length === 0
                text: i18n.tr("No tasks found.")
                wrapMode: Text.WordWrap
                opacity: 0.72
            }

            Label {
                Layout.fillWidth: true
                visible: page.filteredEntries.length === 0 && !dataController.loading && (page.searchQuery.length > 0 || dataController.viewMode === "calendarList")
                text: page.searchQuery.length > 0 ? i18n.tr("No matching items") : appController.apiNote
                wrapMode: Text.WordWrap
                opacity: 0.72
            }
        }
    }

    Rectangle {
        id: newTaskButton
        width: units.gu(6.5)
        height: units.gu(6.5)
        radius: width / 2
        color: "#2c7fb8"
        border.width: 1
        border.color: "#7a7a7a"
        visible: !page.drawerOpen && !page.selectionMode && dataController.viewMode !== "calendarList"
        enabled: visible && !dataController.loading
        opacity: enabled ? 1.0 : 0.45
        z: 10
        anchors {
            right: parent.right
            bottom: parent.bottom
            rightMargin: units.gu(2.2)
            bottomMargin: units.gu(2.2)
        }

        Label {
            anchors.centerIn: parent
            text: "+"
            color: "white"
            font.pixelSize: units.gu(3.2)
            font.bold: true
        }

        MouseArea {
            anchors.fill: parent
            enabled: parent.enabled
            onClicked: page.createTask()
        }
    }

    Item {
        anchors.fill: parent
        visible: page.drawerOpen
        z: 20

        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: 0.32
        }

        MouseArea {
            anchors.fill: parent
            onClicked: page.drawerOpen = false
        }

        Rectangle {
            id: drawer
            anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
            width: Math.min(parent.width * 0.82, units.gu(38))
            color: theme.palette.normal.background
            border.width: 1
            border.color: "#7a7a7a"

            ColumnLayout {
                anchors { fill: parent; margins: units.gu(1.5) }
                spacing: units.gu(1)

                RowLayout {
                    Layout.fillWidth: true

                    Label {
                        Layout.fillWidth: true
                        text: i18n.tr("Task Lists")
                        font.bold: true
                        fontSize: "large"
                        elide: Text.ElideRight
                    }

                    Item {
                        Layout.preferredWidth: units.gu(5)
                        Layout.preferredHeight: units.gu(5)

                        Label {
                            anchors.centerIn: parent
                            text: "\u2715"
                            color: theme.palette.normal.backgroundText
                            font.pixelSize: units.gu(2.2)
                            font.bold: true
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: page.drawerOpen = false
                        }
                    }
                }

                ListView {
                    id: tasksMenuList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: units.gu(0.5)
                    model: {
                        dataController.menuRevision
                        return dataController.menuItems()
                    }

                    delegate: Rectangle {
                        id: menuItem
                        readonly property bool headerItem: modelData.type === "header"
                        readonly property bool createListItem: modelData.type === "createList"
                        readonly property bool selected: dataController.menuItemSelected(modelData)

                        width: tasksMenuList.width
                        height: headerItem ? units.gu(4.5) : (createListItem ? units.gu(5.8) : units.gu(5.2))
                        radius: headerItem || createListItem ? 0 : units.gu(0.5)
                        color: headerItem || createListItem ? theme.palette.normal.background : (selected ? "#2c7fb8" : "transparent")
                        border.width: headerItem || selected || createListItem ? 0 : 1
                        border.color: "#7a7a7a"

                        Rectangle {
                            visible: createListItem
                            anchors.centerIn: parent
                            width: Math.min(parent.width - units.gu(4), units.gu(26))
                            height: units.gu(4.2)
                            radius: units.gu(0.8)
                            color: "transparent"
                            border.width: 0
                            border.color: theme.palette.normal.backgroundText
                            opacity: dataController.loading ? 0.45 : 1.0

                            Label {
                                anchors.centerIn: parent
                                text: modelData.label
                                color: theme.palette.normal.backgroundText
                                font.bold: true
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }
                        }

                        RowLayout {
                            visible: !menuItem.createListItem
                            anchors {
                                fill: parent
                                leftMargin: units.gu(1)
                                rightMargin: units.gu(1)
                            }
                        spacing: units.gu(1)

                            Rectangle {
                                Layout.preferredWidth: units.gu(1.2)
                                Layout.preferredHeight: units.gu(1.2)
                                radius: width / 2
                                visible: modelData.type === "calendar"
                                color: modelData.color || "#d85a7f"
                            }

                            Label {
                                Layout.fillWidth: true
                                text: modelData.label
                                color: selected ? "white" : theme.palette.normal.backgroundText
                                font.bold: headerItem || selected
                                opacity: headerItem ? 0.58 : 1.0
                                elide: Text.ElideRight
                            }

                            Label {
                                visible: modelData.count !== undefined && modelData.count >= 0
                                text: modelData.count !== undefined ? modelData.count : ""
                                color: selected ? "white" : theme.palette.normal.backgroundText
                                opacity: selected ? 1.0 : 0.62
                                font.bold: selected
                            }

                            Item {
                                Layout.preferredWidth: units.gu(4)
                                Layout.fillHeight: true
                                visible: modelData.type === "calendar"

                                Label {
                                    anchors.centerIn: parent
                                    text: "\u22EE"
                                    color: selected ? "white" : theme.palette.normal.backgroundText
                                    font.pixelSize: units.gu(2.4)
                                    font.bold: true
                                }
                            }
                        }

                        MouseArea {
                            anchors {
                                left: parent.left
                                top: parent.top
                                bottom: parent.bottom
                                right: parent.right
                                rightMargin: modelData.type === "calendar" ? units.gu(4.8) : 0
                            }
                            enabled: !menuItem.headerItem
                            onClicked: {
                                page.drawerOpen = false
                                if (menuItem.createListItem) {
                                    page.newListName = ""
                                    PopupUtils.open(createListDialog)
                                } else {
                                    dataController.activateMenuItem(modelData)
                                }
                            }
                        }

                        MouseArea {
                            anchors {
                                top: parent.top
                                bottom: parent.bottom
                                right: parent.right
                            }
                            width: units.gu(5)
                            visible: modelData.type === "calendar"
                            enabled: visible && !dataController.loading
                            z: 10
                            onClicked: page.openListOptions(modelData)
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: units.gu(5)
                    Label { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; anchors.leftMargin: units.gu(1); text: i18n.tr("Language"); color: theme.palette.normal.backgroundText; font.bold: true }
                    MouseArea { anchors.fill: parent; onClicked: page.openPage("LanguageSelectionPage.qml") }
                }
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: units.gu(5)
                    Label { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; anchors.leftMargin: units.gu(1); text: i18n.tr("Account"); color: theme.palette.normal.backgroundText; font.bold: true }
                    MouseArea { anchors.fill: parent; onClicked: page.openPage("AccountSelectionPage.qml") }
                }
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: units.gu(5)
                    Label { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; anchors.leftMargin: units.gu(1); text: i18n.tr("About"); color: theme.palette.normal.backgroundText; font.bold: true }
                    MouseArea { anchors.fill: parent; onClicked: page.openPage("AboutPage.qml") }
                }
            }
        }
    }
}
