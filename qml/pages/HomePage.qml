import QtQuick 2.7
import QtQuick.Layouts 1.3
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3
import QtGraphicalEffects 1.0
import Qt.labs.settings 1.0
import UTControls 1.0
import "../backend"
import "../NextCommon" as NextCommon

Page {
    id: page
    function debugLog() {}

    property var appController
    property bool drawerOpen: false
    property string searchQuery: ""
    property var filteredEntries: []
    property var displayEntries: []
    property var completedDisplayEntries: []
    property var reorderableTaskEntries: []
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
    property var createTaskCalendars: []
    property var shareImportCalendars: []
    property string pendingSharedTitle: ""
    property string pendingSharedContent: ""
    property var pendingSharedImportQueue: []
    property bool shareImportDialogOpen: false
    property int selectionRevision: 0
    property int bulkDeleteDirtyCount: 0
    property int bulkDeleteNewCount: 0
    property string sortDialogCalendarHref: ""
    property string sortDialogCalendarTitle: ""
    property bool clearingTreeSelection: false
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

    Settings {
        id: appSettings
        category: "app"
        property bool syncOnStartup: true
        property bool multiSelectEnabled: true
        property bool swipeActionsEnabled: true
        property bool swipeActionsReversed: false
        property bool pullToRefreshEnabled: true
        property bool dragForMoveEnabled: true
        property bool levelZeroDragDropEnabled: true
        property bool childDragDropEnabled: true
        property bool defaultExpanded: true
        property bool treeLinesEnabled: true
        property bool showReadOnlyLists: true
    }

    Component.onCompleted: {
        if (appController) {
            appController.syncWhileActive = true
            appController.syncOnStartup = appSettings.syncOnStartup
            appController.multiSelectEnabled = appSettings.multiSelectEnabled
            appController.swipeActionsEnabled = appSettings.swipeActionsEnabled
            appController.swipeActionsReversed = appSettings.swipeActionsReversed
            appController.pullToRefreshEnabled = appSettings.pullToRefreshEnabled
            appController.dragForMoveEnabled = appSettings.dragForMoveEnabled
            appController.levelZeroDragDropEnabled = appSettings.levelZeroDragDropEnabled
            appController.childDragDropEnabled = appSettings.childDragDropEnabled
            appController.defaultExpanded = appSettings.defaultExpanded
            appController.treeLinesEnabled = appSettings.treeLinesEnabled
            appController.showReadOnlyLists = appSettings.showReadOnlyLists
        }
    }

    Connections {
        target: appController

        onShowReadOnlyListsChanged: {
            if (dataController) {
                dataController.showReadOnlyLists = appController.showReadOnlyLists
            }
        }
    }

    Loader {
        id: shareImportLoader
        active: !desktopLarge
        source: Qt.resolvedUrl("../backend/TaskShareImportHandler.qml")

        onLoaded: {
            item.sharedTextReceived.connect(page.handleSharedTextReceived)
            item.importFailed.connect(page.handleSharedTextImportFailed)
        }

        onStatusChanged: {
            if (status === Loader.Error && source.toString().indexOf("TaskShareImportHandler.qml") !== -1) {
                debugLog("NextTasks ContentHub Lomiri.Content handler unavailable; trying Ubuntu.Content fallback")
                source = Qt.resolvedUrl("../backend/TaskShareImportHandlerUbuntu.qml")
            }
        }
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

    function multiSelectAllowed() {
        return page.settingEnabled("multiSelectEnabled", true)
    }

    function settingEnabled(name, fallbackValue) {
        if (appController && appController[name] !== undefined) {
            return appController[name] === true
        }
        if (appSettings[name] !== undefined) {
            return appSettings[name] === true
        }
        return fallbackValue === true
    }

    function useReorderableTaskList() {
        return dataController.viewMode === "calendarTasks"
            || dataController.viewMode === "myTasks"
    }

    function reorderTaskByTreeRequest(fromSectionId, fromIndex, toSectionId, toIndex, item, fromParentId, toParentId) {
        if (String(fromSectionId || "") !== String(toSectionId || "")) {
            return
        }
        if (!page.taskManualSortEnabled(item)) {
            return
        }
        if (String(fromParentId || "") !== String(toParentId || "")) {
            return
        }
        var target = toIndex
        if (String(fromSectionId || "") === String(toSectionId || "") && fromIndex < toIndex) {
            target = toIndex - 1
        }
        if (dataController.viewMode === "calendarTasks" && String(fromParentId || "").length === 0 && fromIndex >= 0 && fromIndex < reorderableTaskEntries.length) {
            var nextEntries = reorderableTaskEntries.slice(0)
            var moved = nextEntries.splice(fromIndex, 1)[0]
            var boundedTarget = Math.max(0, Math.min(target, nextEntries.length))
            nextEntries.splice(boundedTarget, 0, moved)
            reorderableTaskEntries = nextEntries
            target = boundedTarget
            dataController.reorderManualTask(item, target, false)
            return
        }
        dataController.reorderManualTask(item, target, true)
    }

    function makeSubTaskByTreeRequest(fromSectionId, fromIndex, parentSectionId, parentIndex, item, parentItem, fromParentId) {
        if (String(fromSectionId || "") !== String(parentSectionId || "")) {
            return
        }
        if (!item || !parentItem || item.type !== "task" || parentItem.type !== "task") {
            return
        }
        dataController.updateTaskParent(item, parentItem.uid || parentItem.id || "")
    }

    function outdentTaskByTreeRequest(fromSectionId, fromIndex, toParentId, toIndex, item, fromParentId) {
        if (!item || item.type !== "task") {
            return
        }
        dataController.updateTaskParent(item, toParentId || "")
    }

    function reorderableTaskSectionsModel() {
        if (!page.useReorderableTaskList() || reorderableTaskEntries.length === 0) {
            return []
        }
        if (dataController.viewMode === "myTasks") {
            return page.reorderableTaskSectionsForMyTasks(reorderableTaskEntries)
        }
        var items = page.reorderableTaskTreeItems(reorderableTaskEntries)
        return [{
            "id": dataController.selectedCalendarHref || "current",
            "title": dataController.selectedCalendarTitle || dataController.titleText || i18n.tr("Tasks"),
            "items": items
        }]
    }

    function reorderableTaskItems(sourceEntries) {
        var items = []
        var entries = sourceEntries || []
        for (var i = 0; i < entries.length; ++i) {
            var source = entries[i]
            if (!source || source.type !== "task") {
                continue
            }
            source.id = page.taskKey(source)
            if (String(source.id || "").length > 0) {
                items.push(source)
            }
        }
        return items
    }

    function cloneTaskForTree(source) {
        var copy = {}
        for (var key in source) {
            if (key !== "children") {
                copy[key] = source[key]
            }
        }
        copy.id = String(copy.uid || page.taskKey(copy))
        copy.children = []
        return copy
    }

    function taskTreeUid(task) {
        return String(task && task.uid ? task.uid : "")
    }

    function taskTreeDepthSafe(node, seen) {
        if (!node || !node.children) {
            return
        }
        var uid = page.taskTreeUid(node)
        if (uid.length > 0) {
            if (seen[uid] === true) {
                node.children = []
                return
            }
            seen[uid] = true
        }
        for (var i = 0; i < node.children.length; ++i) {
            var childSeen = {}
            for (var key in seen) {
                childSeen[key] = seen[key]
            }
            page.taskTreeDepthSafe(node.children[i], childSeen)
        }
    }

    function reorderableTaskTreeItems(sourceEntries) {
        var entries = sourceEntries || []
        var byUid = {}
        var clones = []
        for (var i = 0; i < entries.length; ++i) {
            var source = entries[i]
            if (!source || source.type !== "task") {
                continue
            }
            var clone = page.cloneTaskForTree(source)
            clones.push(clone)
            var uid = page.taskTreeUid(clone)
            if (uid.length > 0) {
                byUid[uid] = clone
            }
        }

        var roots = []
        for (var j = 0; j < clones.length; ++j) {
            var task = clones[j]
            var parentUid = String(task.parentUid || "")
            var parent = parentUid.length > 0 ? byUid[parentUid] : null
            if (parent && parent !== task) {
                parent.children.push(task)
            } else {
                roots.push(task)
            }
        }

        for (var k = 0; k < roots.length; ++k) {
            page.taskTreeDepthSafe(roots[k], {})
        }
        return roots
    }

    function reorderableTaskSectionsForMyTasks(sourceEntries) {
        var seen = {}
        var order = []
        var entries = sourceEntries || []
        for (var i = 0; i < entries.length; ++i) {
            var source = entries[i]
            if (!source || source.type !== "task") {
                continue
            }
            var key = String(source.calendarHref || source.calendarTitle || i18n.tr("Tasks"))
            if (!seen[key]) {
                seen[key] = []
                order.push(key)
            }
            seen[key].push(source)
        }
        var sections = []
        var emitted = {}
        function appendSection(sectionKey) {
            if (emitted[sectionKey] === true || !seen[sectionKey]) {
                return
            }
            emitted[sectionKey] = true
            var group = seen[sectionKey]
            var firstTask = group.length > 0 ? group[0] : null
            var href = firstTask && firstTask.calendarHref ? firstTask.calendarHref : ""
            group = dataController.sortedTasksForCalendar(group, href)
            sections.push({
                "id": href || sectionKey,
                "title": firstTask && firstTask.calendarTitle ? firstTask.calendarTitle : i18n.tr("Tasks"),
                "items": page.reorderableTaskTreeItems(group)
            })
        }
        var calendars = dataController.calendars || []
        for (var j = 0; j < calendars.length; ++j) {
            var calendar = calendars[j]
            var calendarKey = String(calendar && (calendar.href || calendar.title) ? (calendar.href || calendar.title) : "")
            if (calendarKey.length > 0) {
                appendSection(calendarKey)
            }
        }
        for (var k = 0; k < order.length; ++k) {
            appendSection(order[k])
        }
        return sections
    }

    function anyReorderableSectionUsesManualSort() {
        if (dataController.viewMode === "calendarTasks") {
            return dataController.sortMode === "manual"
        }
        var entries = reorderableTaskEntries || []
        for (var i = 0; i < entries.length; ++i) {
            var entry = entries[i]
            if (entry && entry.type === "task" && dataController.sortModeForCalendar(entry.calendarHref || "") === "manual") {
                return true
            }
        }
        return false
    }

    function activeSortMode() {
        return sortDialogCalendarHref.length > 0
            ? dataController.sortModeForCalendar(sortDialogCalendarHref)
            : dataController.sortMode
    }

    function syncManualReorderSetting() {
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

    function swipeDeletes(offset) {
        if (!page.settingEnabled("swipeActionsEnabled", true)) {
            return false
        }
        var reversed = page.settingEnabled("swipeActionsReversed", false)
        return reversed ? offset < 0 : offset > 0
    }

    function swipeCompletes(offset) {
        return page.settingEnabled("swipeActionsEnabled", true) && offset !== 0 && !page.swipeDeletes(offset)
    }

    function positiveSwipeText(entry) {
        return page.swipeDeletes(1) ? i18n.tr("Delete") : (entry.completed === true ? i18n.tr("Reopen") : i18n.tr("Complete"))
    }

    function negativeSwipeText(entry) {
        return page.swipeDeletes(-1) ? i18n.tr("Delete") : (entry.completed === true ? i18n.tr("Reopen") : i18n.tr("Complete"))
    }

    function swipeActionColor(offset) {
        return page.swipeDeletes(offset) ? page.deleteRed : "#5a8f3c"
    }

    function createTask() {
        if (page.searchQuery.length > 0) {
            page.searchQuery = ""
        }
        if (dataController.viewMode !== "calendarTasks") {
            var calendars = dataController.availableCreateCalendars()
            if (calendars.length > 1) {
                page.createTaskCalendars = calendars
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

    Timer {
        id: shareImportRetryTimer
        interval: 250
        repeat: false
        onTriggered: page.tryOpenSharedImportDialog()
    }

    function createTaskInCalendar(calendar) {
        var task = dataController.createTaskInCalendar(calendar)
        if (task) {
            page.openTask(task)
        }
    }

    function handleSharedTextReceived(title, content) {
        var cleanContent = String(content || "")
        if (cleanContent.trim().length === 0) {
            dataController.statusText = i18n.tr("The shared content did not contain readable text.")
            return
        }
        if (page.shareImportDialogOpen || page.pendingSharedContent.length > 0) {
            page.pendingSharedImportQueue.push({"title": title || "", "content": cleanContent})
            debugLog("NextTasks ContentHub queued shared import queueLength=" + page.pendingSharedImportQueue.length)
            return
        }
        page.pendingSharedTitle = title || ""
        page.pendingSharedContent = cleanContent
        page.tryOpenSharedImportDialog()
    }

    function tryOpenSharedImportDialog() {
        if (page.pendingSharedContent.length === 0 || page.shareImportDialogOpen) {
            return
        }
        page.shareImportCalendars = dataController.availableCreateCalendars()
        if (page.shareImportCalendars.length === 0) {
            if (dataController.loading) {
                shareImportRetryTimer.restart()
                return
            }
            dataController.statusText = i18n.tr("No task list is available for imported text.")
            return
        }
        drawerOpen = false
        page.shareImportDialogOpen = true
        PopupUtils.open(shareImportListDialog)
    }

    function processNextSharedImport() {
        if (page.pendingSharedImportQueue.length === 0) {
            return
        }
        var next = page.pendingSharedImportQueue.shift()
        page.pendingSharedTitle = next.title || ""
        page.pendingSharedContent = next.content || ""
        Qt.callLater(page.tryOpenSharedImportDialog)
    }

    function handleSharedTextImportFailed(message) {
        dataController.statusText = message
    }

    function createSharedTaskInCalendar(calendar) {
        var task = dataController.createTaskFromSharedText(calendar, page.pendingSharedTitle, page.pendingSharedContent)
        page.pendingSharedTitle = ""
        page.pendingSharedContent = ""
        page.shareImportDialogOpen = false
        if (task) {
            page.openTask(task)
        }
        processNextSharedImport()
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

    function activeSelectedCount() {
        if (page.useReorderableTaskList() && reorderableTasks) {
            return reorderableTasks.selectedCount
        }
        return page.selectedTaskCount()
    }

    function clearSelection() {
        selectionMode = false
        selectedTaskKeys = ({})
        selectionRevision += 1
        if (!clearingTreeSelection && reorderableTasks && reorderableTasks.clearSelection) {
            clearingTreeSelection = true
            reorderableTasks.clearSelection()
            clearingTreeSelection = false
        }
    }

    function setSelectionFromTasks(tasks) {
        var updated = {}
        var incoming = tasks || []
        for (var i = 0; i < incoming.length; ++i) {
            var task = incoming[i] && incoming[i].item ? incoming[i].item : incoming[i]
            var key = taskKey(task)
            if (key.length > 0) {
                updated[key] = true
            }
        }
        selectedTaskKeys = updated
        selectionMode = selectedTaskCount() > 0
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
        var source = dataController.viewMode === "trash"
            ? dataController.trashItems || []
            : dataController.viewMode === "calendarTasks" || dataController.viewMode === "myTasks"
            ? dataController.visibleTasks(dataController.tasksForCurrentScope(), false)
            : dataController.entries || []
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
            reorderableTaskEntries = []
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
        reorderableTaskEntries = page.useReorderableTaskList()
            ? (dataController.showCompletedTasks ? openEntries.concat(completedEntries) : openEntries)
            : []
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
            group = dataController.viewMode === "myTasks" ? dataController.sortedTasksForCalendar(group, href) : group
            result.push({"type": "section", "title": title, "calendarHref": href})
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
        return theme.palette.normal.base
    }

    function taskCardColor(entry) {
        if (!entry || entry.type !== "task") return theme.palette.normal.background
        if (entry.conflict === true) return Qt.rgba(0.85, 0.20, 0.36, 0.14)
        return theme.palette.normal.background
    }

    function taskStatusBadgeText(entry) {
        if (!entry || entry.type !== "task") return ""
        if (dataController.taskReadOnly(entry)) return i18n.tr("Read-only")
        if (entry.conflict === true) return i18n.tr("Conflict")
        if (entry.deleted === true) return i18n.tr("Delete pending")
        if (entry.isNew === true) return i18n.tr("New")
        if (entry.dirty === true) return i18n.tr("Unsynced")
        return ""
    }

    function taskStatusBadgeColor(entry) {
        if (!entry || entry.type !== "task") return "#7a7a7a"
        if (dataController.taskReadOnly(entry)) return "#7a7a7a"
        if (entry.conflict === true) return "#c7162b"
        if (entry.isNew === true) return "#237b4b"
        if (entry.dirty === true || entry.deleted === true) return "#c65d00"
        return "#7a7a7a"
    }

    function taskFrameWidth(entry) {
        return entry && entry.type === "task" && entry.conflict === true
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

        contents: Item {
            anchors.fill: parent

            NextCommon.MainTopBar {
                visible: !page.selectionMode
                searchText: page.searchQuery
                searchPlaceholder: i18n.tr("Search")
                filterIconKind: "sort"
                filterActive: false
                statusKind: page.statusIconKind()
                statusColor: page.statusAccentColor()
                avatarUrl: dataController.accountAvatarUrl
                accountInitial: page.accountInitial
                onMenuClicked: page.drawerOpen = true
                onSearchChanged: page.searchQuery = text
                onClearSearchClicked: page.searchQuery = ""
                onFilterClicked: page.openSortPicker()
                onStatusClicked: PopupUtils.open(statusDetailsDialog)
                onAccountClicked: page.openPage("AccountSelectionPage.qml")
            }

            RowLayout {
                anchors {
                    fill: parent
                    leftMargin: units.gu(0.5)
                    rightMargin: units.gu(0.5)
                }
                visible: page.selectionMode
                spacing: units.gu(0.75)

                Item {
                    Layout.preferredWidth: units.gu(3.4)
                    Layout.preferredHeight: units.gu(5)

                    Label {
                        anchors.centerIn: parent
                        text: "\u2715"
                        color: theme.palette.normal.backgroundText
                        font.pixelSize: units.gu(2.6)
                        font.bold: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: page.clearSelection()
                    }
                }

                Label {
                    Layout.fillWidth: true
                    text: i18n.tr("%1 selected").arg(page.activeSelectedCount())
                    font.bold: true
                    elide: Text.ElideRight
                }

                NextCommon.AppButton {
                    Layout.preferredWidth: units.gu(9.5)
                    Layout.preferredHeight: units.gu(5)
                    enabled: page.activeSelectedCount() > 0
                    text: i18n.tr("Move")
                    onClicked: page.requestBulkMove()
                }

                NextCommon.AppButton {
                    Layout.preferredWidth: units.gu(9.5)
                    Layout.preferredHeight: units.gu(5)
                    enabled: page.activeSelectedCount() > 0
                    text: i18n.tr("Delete")
                    variant: "destructive"
                    destructiveColor: page.deleteRed
                    onClicked: page.requestBulkDelete()
                }
            }
        }
    }

    Component {
        id: createTaskListDialog

        Dialog {
            id: dialog
            title: i18n.tr("Choose task list")
            text: ""

            Label {
                width: parent ? parent.width : units.gu(34)
                text: i18n.tr("Select where the new task should be created.")
                wrapMode: Text.WordWrap
            }

            Repeater {
                model: page.createTaskCalendars

                NextCommon.AppButton {
                    width: parent ? parent.width : units.gu(34)
                    height: units.gu(4.8)
                    text: modelData.title || i18n.tr("Tasks")
                    onClicked: {
                        PopupUtils.close(dialog)
                        page.createTaskInCalendar(modelData)
                    }
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
        id: shareImportListDialog

        Dialog {
            id: dialog
            title: i18n.tr("Choose task list")
            text: ""

            Label {
                width: parent ? parent.width : units.gu(34)
                text: i18n.tr("Select where the shared text task should be created.")
                wrapMode: Text.WordWrap
            }

            Repeater {
                model: page.shareImportCalendars

                NextCommon.AppButton {
                    width: parent ? parent.width : units.gu(34)
                    height: units.gu(4.8)
                    text: modelData.title || i18n.tr("Tasks")
                    onClicked: {
                        PopupUtils.close(dialog)
                        page.createSharedTaskInCalendar(modelData)
                    }
                }
            }

            NextCommon.AppButton {
                width: parent ? parent.width : units.gu(34)
                height: units.gu(4.8)
                text: i18n.tr("Cancel")
                onClicked: {
                    page.pendingSharedTitle = ""
                    page.pendingSharedContent = ""
                    page.shareImportDialogOpen = false
                    PopupUtils.close(dialog)
                    page.processNextSharedImport()
                }
            }
        }
    }

    Component {
        id: createListDialog

        Dialog {
            id: dialog
            title: i18n.tr("Create new list")
            text: ""

            Label {
                width: parent ? parent.width : units.gu(34)
                text: i18n.tr("Enter a name for the new task list.")
                wrapMode: Text.WordWrap
            }

            TextField {
                id: listNameField
                width: parent ? parent.width : units.gu(34)
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

            NextCommon.AppButton {
                width: parent ? parent.width : units.gu(34)
                height: units.gu(4.8)
                text: i18n.tr("Create")
                enabled: listNameField.text.trim().length > 0 && !dataController.loading
                onClicked: {
                    dataController.createCalendar(listNameField.text)
                    page.newListName = ""
                    PopupUtils.close(dialog)
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
        id: listOptionsDialog

        Dialog {
            id: dialog
            title: page.selectedMenuCalendar.title || i18n.tr("Task list")
            text: ""

            Label {
                width: parent ? parent.width : units.gu(34)
                text: i18n.tr("Rename the list, change its color, or delete it.")
                wrapMode: Text.WordWrap
            }

            TextField {
                id: editListNameField
                width: parent ? parent.width : units.gu(34)
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

            NextCommon.AppButton {
                width: parent ? parent.width : units.gu(34)
                height: units.gu(4.8)
                text: i18n.tr("Save")
                enabled: page.editListName.trim().length > 0 && !dataController.loading
                onClicked: page.saveSelectedListSettings(dialog)
            }

            NextCommon.AppButton {
                width: parent ? parent.width : units.gu(34)
                height: units.gu(4.8)
                text: i18n.tr("Delete list")
                variant: "destructive"
                destructiveColor: page.deleteRed
                enabled: !dataController.loading
                onClicked: page.deleteSelectedList(dialog)
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
        id: deleteListDialog

        Dialog {
            id: dialog
            title: i18n.tr("Delete task list?")
            text: ""

            Label {
                width: parent ? parent.width : units.gu(34)
                text: i18n.tr("The list and its tasks will be removed from the server and this device.")
                wrapMode: Text.WordWrap
            }

            NextCommon.AppButton {
                width: parent ? parent.width : units.gu(34)
                height: units.gu(4.8)
                text: i18n.tr("Delete")
                variant: "destructive"
                destructiveColor: page.deleteRed
                enabled: !dataController.loading
                onClicked: {
                    dataController.deleteCalendar(page.selectedMenuCalendar)
                    PopupUtils.close(dialog)
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
        id: deleteTaskDialog

        Dialog {
            id: dialog
            title: i18n.tr("Delete task?")
            text: ""

            Label {
                width: parent ? parent.width : units.gu(34)
                text: i18n.tr("The task will be deleted from this device and synced to the server.")
                wrapMode: Text.WordWrap
            }

            NextCommon.AppButton {
                width: parent ? parent.width : units.gu(34)
                height: units.gu(4.8)
                text: i18n.tr("Delete")
                variant: "destructive"
                destructiveColor: page.deleteRed
                enabled: !dataController.loading
                onClicked: {
                    dataController.deleteTask(page.pendingSwipeDeleteTask)
                    page.pendingSwipeDeleteTask = ({})
                    PopupUtils.close(dialog)
                }
            }

            NextCommon.AppButton {
                width: parent ? parent.width : units.gu(34)
                height: units.gu(4.8)
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
            text: ""

            Flickable {
                width: parent ? parent.width : units.gu(34)
                height: Math.min(bulkDeleteText.implicitHeight, units.gu(16))
                contentWidth: width
                contentHeight: bulkDeleteText.implicitHeight
                clip: true

                Label {
                    id: bulkDeleteText
                    width: parent.width
                    text: page.bulkDeleteMessage()
                    wrapMode: Text.WordWrap
                }
            }

            NextCommon.AppButton {
                width: parent ? parent.width : units.gu(34)
                height: units.gu(4.8)
                text: i18n.tr("Delete")
                variant: "destructive"
                destructiveColor: page.deleteRed
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

            NextCommon.AppButton {
                width: parent ? parent.width : units.gu(34)
                height: units.gu(4.8)
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
            text: ""

            Flickable {
                width: parent ? parent.width : units.gu(34)
                height: Math.min(bulkMoveText.implicitHeight, units.gu(12))
                contentWidth: width
                contentHeight: bulkMoveText.implicitHeight
                clip: true

                Label {
                    id: bulkMoveText
                    width: parent.width
                    text: i18n.tr("Choose the target list. Tasks with unsynced local changes are skipped.")
                    wrapMode: Text.WordWrap
                }
            }

            Repeater {
                model: dataController.availableCreateCalendars()

                NextCommon.AppButton {
                    width: parent ? parent.width : units.gu(34)
                    height: units.gu(4.8)
                    text: modelData.title || i18n.tr("Tasks")
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

            NextCommon.AppButton {
                width: parent ? parent.width : units.gu(34)
                height: units.gu(4.8)
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

            Flickable {
                width: parent ? parent.width : units.gu(34)
                height: Math.min(statusDetailsLabel.implicitHeight, units.gu(22))
                contentWidth: width
                contentHeight: statusDetailsLabel.implicitHeight
                clip: true

                Label {
                    id: statusDetailsLabel
                    width: parent.width
                    text: page.statusDetailsText()
                    wrapMode: Text.WordWrap
                }
            }

            NextCommon.AppButton {
                width: parent ? parent.width : units.gu(34)
                height: units.gu(4.8)
                text: i18n.tr("Resolve conflict")
                variant: "primary"
                visible: dataController.conflictTasksCount > 0
                enabled: !dataController.loading
                onClicked: {
                    PopupUtils.close(dialog)
                    page.openConflictResolution(null)
                }
            }

            NextCommon.AppButton {
                width: parent ? parent.width : units.gu(34)
                height: units.gu(4.8)
                text: i18n.tr("Refresh")
                variant: "primary"
                visible: page.statusAllowsRefresh()
                enabled: !dataController.loading
                onClicked: {
                    PopupUtils.close(dialog)
                    dataController.refresh()
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
        id: reopenCompletedDialog

        Dialog {
            id: dialog
            title: i18n.tr("Reopen completed tasks?")
            text: ""

            Label {
                width: parent ? parent.width : units.gu(34)
                text: i18n.tr("This will mark all completed tasks in this list as open again.")
                wrapMode: Text.WordWrap
            }

            NextCommon.AppButton {
                width: parent ? parent.width : units.gu(34)
                height: units.gu(4.8)
                text: i18n.tr("Reopen all")
                onClicked: {
                    PopupUtils.close(dialog)
                    dataController.reopenCompletedTasksInCurrentScope()
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
        id: sortDialog

        Dialog {
            id: dialog
            title: page.sortDialogCalendarTitle.length > 0
                ? i18n.tr("Sort %1").arg(page.sortDialogCalendarTitle)
                : i18n.tr("Sort tasks")
            text: ""

            Label {
                width: parent ? parent.width : units.gu(34)
                text: page.activeSortMode() === "manual"
                    ? i18n.tr("Manual order is saved to the task list using Nextcloud-compatible task order values.")
                    : i18n.tr("Uses standard task sort concepts.")
                wrapMode: Text.WordWrap
            }

            Repeater {
                model: dataController.sortOptions()

                NextCommon.AppButton {
                    width: parent ? parent.width : units.gu(34)
                    height: units.gu(4.8)
                    text: modelData.label + (modelData.value === page.activeSortMode() ? "  \u2713" : "")
                    selected: modelData.value === page.activeSortMode()
                    onClicked: {
                        page.applySortMode(modelData.value)
                        PopupUtils.close(dialog)
                    }
                }
            }

            NextCommon.AppButton {
                width: parent ? parent.width : units.gu(34)
                height: units.gu(4.8)
                text: dataController.sortAscending ? i18n.tr("Ascending") : i18n.tr("Descending")
                visible: page.activeSortMode() !== "manual"
                onClicked: dataController.toggleSortAscending()
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
        id: sortScopeDialog

        Dialog {
            id: dialog
            title: i18n.tr("Sort list")
            text: ""

            Label {
                width: parent ? parent.width : units.gu(34)
                text: i18n.tr("Choose which task list to sort.")
                wrapMode: Text.WordWrap
            }

            Repeater {
                model: dataController.visibleSortCalendars()

                NextCommon.AppButton {
                    width: parent ? parent.width : units.gu(34)
                    height: units.gu(4.8)
                    text: (modelData.title || i18n.tr("Tasks")) + " - " + dataController.sortModeLabelForCalendar(modelData.href || "")
                    onClicked: {
                        page.sortDialogCalendarHref = modelData.href || ""
                        page.sortDialogCalendarTitle = modelData.title || i18n.tr("Tasks")
                        PopupUtils.close(dialog)
                        PopupUtils.open(sortDialog)
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

    Component {
        id: reorderTaskDelegate

        Rectangle {
            property var itemData: ({})
            property var rowData: ({})
            property int itemIndex: -1
            property string sectionId: ""
            property string parentId: ""
            property int depth: 0
            property bool expanded: false
            property bool hasChildren: false
            property bool placeholder: false
            property bool dragging: false
            property bool parentTarget: false
            property bool selected: false
            property bool selectionMode: false
            signal toggleExpanded()

            implicitHeight: units.gu(8.8)
            radius: units.gu(0.6)
            color: placeholder ? "transparent" : (selected ? Qt.rgba(0.17, 0.50, 0.72, 0.18) : page.taskCardColor(itemData))
            border.width: placeholder || selected ? 2 : page.taskFrameWidth(itemData)
            border.color: placeholder || selected ? page.actionBlue : page.taskFrameColor(itemData)
            opacity: placeholder ? 0.55 : (itemData.completed ? 0.56 : 1.0)

            Rectangle {
                id: expandButton
                anchors {
                    left: parent.left
                    verticalCenter: parent.verticalCenter
                    leftMargin: units.gu(0.2)
                }
                width: units.gu(3.2)
                height: units.gu(3.2)
                radius: width / 2
                z: 5
                color: expandMouse.pressed ? Qt.rgba(0.17, 0.5, 0.72, 0.18) : "transparent"
                border.width: hasChildren ? 1 : 0
                border.color: Qt.rgba(0.17, 0.5, 0.72, 0.35)
                opacity: hasChildren ? 1 : (depth > 0 ? 0.2 : 0)

                Label {
                    anchors.centerIn: parent
                    text: hasChildren ? (expanded ? "-" : "+") : ""
                    color: theme.palette.normal.backgroundText
                    font.bold: true
                }

                MouseArea {
                    id: expandMouse
                    anchors.fill: parent
                    enabled: hasChildren
                    preventStealing: true
                    onClicked: toggleExpanded()
                }
            }

            RowLayout {
                anchors {
                    fill: parent
                    margins: units.gu(1)
                    leftMargin: units.gu(4.8)
                }
                spacing: units.gu(1)

                Rectangle {
                    Layout.preferredWidth: units.gu(2.8)
                    Layout.preferredHeight: units.gu(2.8)
                    Layout.alignment: Qt.AlignVCenter
                    radius: units.gu(0.35)
                    color: selected ? page.actionBlue : (itemData.completed ? "#5a8f3c" : "transparent")
                    border.width: 2
                    border.color: selected ? page.actionBlue : (itemData.completed ? "#5a8f3c" : theme.palette.normal.backgroundText)

                    Label {
                        anchors.centerIn: parent
                        text: "\u2713"
                        visible: itemData.completed === true || selected
                        color: "white"
                        font.bold: true
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: units.gu(0.2)

                    Label {
                        Layout.fillWidth: true
                        text: itemData.title || i18n.tr("Untitled")
                        font.bold: !itemData.completed
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        opacity: itemData.completed ? 0.58 : 1.0
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: units.gu(0.75)

                        Label {
                            Layout.fillWidth: true
                            text: page.entrySubtitle(itemData)
                            textSize: Label.Small
                            opacity: itemData.completed ? 0.48 : 0.68
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }

                        Rectangle {
                            visible: page.taskStatusBadgeText(itemData).length > 0
                            color: page.taskStatusBadgeColor(itemData)
                            height: reorderTaskStatusBadgeLabel.implicitHeight + units.gu(0.35)
                            width: Math.min(reorderTaskStatusBadgeLabel.implicitWidth + units.gu(0.9), units.gu(12))
                            radius: units.gu(0.3)

                            Label {
                                id: reorderTaskStatusBadgeLabel
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    verticalCenter: parent.verticalCenter
                                    leftMargin: units.gu(0.45)
                                    rightMargin: units.gu(0.45)
                                }
                                text: page.taskStatusBadgeText(itemData)
                                color: "white"
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }
                        }
                    }
                }

                Label {
                    Layout.preferredWidth: units.gu(3.2)
                    Layout.alignment: Qt.AlignVCenter
                    text: "\u2630"
                    color: theme.palette.normal.backgroundText
                    opacity: dragging ? 0.35 : 0.62
                    font.pixelSize: units.gu(2.2)
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }

    Component {
        id: emptyReorderSectionDelegate

        RowLayout {
            property var sectionData: ({})
            property var sectionId: ""
            property int sectionIndex: -1
            width: parent ? parent.width : page.width
            height: dataController.viewMode === "myTasks" ? units.gu(4) : 0
            spacing: units.gu(0.8)
            visible: height > 0

            Rectangle {
                Layout.preferredWidth: units.gu(1.2)
                Layout.preferredHeight: units.gu(1.2)
                Layout.alignment: Qt.AlignVCenter
                radius: width / 2
                color: "#d85a7f"
            }

            Label {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: sectionData && sectionData.title ? sectionData.title : i18n.tr("Tasks")
                font.bold: true
                opacity: 0.78
                elide: Text.ElideRight
            }
        }
    }

    TasksController {
        id: dataController
        syncWhileActive: true
        syncOnStartup: appController ? appController.syncOnStartup : true
        showReadOnlyLists: appController ? appController.showReadOnlyLists : true
        onEntriesChanged: page.updateFilteredEntries()
        onTrashItemsChanged: page.updateFilteredEntries()
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
        onCalendarsChanged: page.tryOpenSharedImportDialog()
        onLoadingChanged: {
            page.tryOpenSharedImportDialog()
        }
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
        visible: !page.useReorderableTaskList()
        contentWidth: width
        contentHeight: contentColumn.height + units.gu(3)
        clip: true
        interactive: page.manualDragTaskKey.length === 0 && !page.manualDragPointerCaptured
        boundsBehavior: page.settingEnabled("pullToRefreshEnabled", true) ? Flickable.DragOverBounds : Flickable.StopAtBounds
        property bool pullRefreshArmed: false

        onContentYChanged: {
            if (page.settingEnabled("pullToRefreshEnabled", true) && contentY < -page.pullRefreshThreshold && !dataController.loading) {
                pullRefreshArmed = true
            }
        }

        onMovementEnded: {
            if (page.settingEnabled("pullToRefreshEnabled", true) && pullRefreshArmed && !dataController.loading) {
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
            opacity: page.settingEnabled("pullToRefreshEnabled", true) && (taskFlickable.contentY < -units.gu(2) || dataController.loading) ? 0.92 : 0
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
                    visible: dataController.viewMode === "calendarTasks" || dataController.viewMode === "calendarList" || dataController.viewMode === "trash"

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
                    text: dataController.titleText + " - " + page.listStatusText()
                    textSize: Label.Small
                    opacity: 0.68
                    elide: Text.ElideRight
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                visible: dataController.viewMode === "trash"
                spacing: units.gu(1)

                Repeater {
                    model: dataController.trashItems

                    delegate: Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: units.gu(9.6)
                        radius: units.gu(0.6)
                        color: theme.palette.normal.base
                        border.width: 1
                        border.color: Qt.rgba(theme.palette.normal.backgroundText.r,
                                              theme.palette.normal.backgroundText.g,
                                              theme.palette.normal.backgroundText.b,
                                              0.18)

                        RowLayout {
                            anchors {
                                fill: parent
                                margins: units.gu(1.2)
                            }
                            spacing: units.gu(1)

                            Rectangle {
                                Layout.preferredWidth: units.gu(4.4)
                                Layout.preferredHeight: units.gu(4.4)
                                Layout.alignment: Qt.AlignVCenter
                                radius: width / 2
                                color: modelData.type === "trashCalendar"
                                    ? (modelData.color || "#2f80ed")
                                    : Qt.rgba(theme.palette.normal.backgroundText.r,
                                              theme.palette.normal.backgroundText.g,
                                              theme.palette.normal.backgroundText.b,
                                              0.12)

                                Label {
                                    anchors.centerIn: parent
                                    text: modelData.type === "trashCalendar" ? "\u2630" : "\u2713"
                                    color: modelData.type === "trashCalendar"
                                        ? "white"
                                        : theme.palette.normal.backgroundText
                                    font.bold: true
                                    font.pixelSize: units.gu(2.1)
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: units.gu(0.45)

                                Label {
                                    Layout.fillWidth: true
                                    text: modelData.title || i18n.tr("Untitled")
                                    font.bold: true
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: units.gu(0.6)

                                    Rectangle {
                                        Layout.preferredHeight: units.gu(2.4)
                                        Layout.preferredWidth: typeLabel.implicitWidth + units.gu(1.4)
                                        radius: units.gu(1.2)
                                        color: Qt.rgba(theme.palette.normal.backgroundText.r,
                                                       theme.palette.normal.backgroundText.g,
                                                       theme.palette.normal.backgroundText.b,
                                                       0.10)

                                        Label {
                                            id: typeLabel
                                            anchors.centerIn: parent
                                            text: modelData.type === "trashCalendar" ? i18n.tr("List") : i18n.tr("Task")
                                            textSize: Label.Small
                                            font.bold: true
                                            opacity: 0.78
                                        }
                                    }

                                    Label {
                                        Layout.fillWidth: true
                                        text: String(modelData.deletedAtText || "").length > 0
                                            ? i18n.tr("Deleted %1").arg(modelData.deletedAtText)
                                            : (modelData.subtitle || "")
                                        textSize: Label.Small
                                        opacity: 0.68
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                    }
                                }
                            }

                            NextCommon.AppButton {
                                Layout.preferredWidth: units.gu(9.2)
                                Layout.preferredHeight: units.gu(4.4)
                                text: i18n.tr("Restore")
                                variant: "neutral"
                                enabled: !dataController.loading
                                onClicked: dataController.restoreTrashItem(modelData)
                            }
                        }
                    }
                }

                NextCommon.EmptyState {
                    Layout.fillWidth: true
                    visible: dataController.trashItems.length === 0 && !dataController.loading
                    title: i18n.tr("Trash bin is empty.")
                    message: dataController.trashRetentionSeconds > 0
                        ? i18n.tr("Deleted items are kept for a limited time by the server.")
                        : ""
                }
            }

            Repeater {
                model: dataController.viewMode !== "trash" ? page.displayEntries : []
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
                        if (page.swipeDeletes(offset)) {
                            page.requestDeleteTask(modelData)
                        } else if (page.swipeCompletes(offset)) {
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
                        color: page.swipeActionColor(swipeContent.x)
                        opacity: modelData.type === "task" ? Math.min(1, Math.abs(swipeContent.x) / taskRow.actionThreshold) : 0
                        visible: modelData.type === "task" && opacity > 0

                        Label {
                            anchors {
                                left: parent.left
                                verticalCenter: parent.verticalCenter
                                leftMargin: units.gu(2)
                            }
                            visible: swipeContent.x > units.gu(1)
                            text: page.positiveSwipeText(modelData)
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
                            text: page.negativeSwipeText(modelData)
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
                            if (page.multiSelectAllowed() && modelData.type === "task" && !dataController.loading && page.manualDragTaskKey.length === 0) {
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
                            if (page.swipeDeletes(offset)) {
                                page.requestDeleteTask(modelData)
                            } else if (page.swipeCompletes(offset)) {
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
                            color: page.swipeActionColor(completedSwipeContent.x)
                            opacity: modelData.type === "task" ? Math.min(1, Math.abs(completedSwipeContent.x) / completedTaskRow.actionThreshold) : 0
                            visible: modelData.type === "task" && opacity > 0

                            Label {
                                anchors {
                                    left: parent.left
                                    verticalCenter: parent.verticalCenter
                                    leftMargin: units.gu(2)
                                }
                                visible: completedSwipeContent.x > units.gu(1)
                                text: page.positiveSwipeText(modelData)
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
                                text: page.negativeSwipeText(modelData)
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
                                if (page.multiSelectAllowed() && modelData.type === "task" && !dataController.loading) {
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

                NextCommon.AppButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: units.gu(5)
                    visible: dataController.viewMode === "calendarTasks" && dataController.showCompletedTasks
                    text: i18n.tr("Reopen all")
                    enabled: !dataController.loading
                    onClicked: PopupUtils.open(reopenCompletedDialog)
                }
            }

            NextCommon.EmptyState {
                Layout.fillWidth: true
                visible: page.filteredEntries.length === 0 && (dataController.viewMode === "myTasks" || dataController.viewMode === "calendarTasks") && !dataController.loading && page.searchQuery.length === 0
                title: i18n.tr("No tasks found.")
            }

            NextCommon.EmptyState {
                Layout.fillWidth: true
                visible: page.filteredEntries.length === 0 && !dataController.loading && dataController.viewMode !== "trash" && (page.searchQuery.length > 0 || dataController.viewMode === "calendarList")
                title: page.searchQuery.length > 0 ? i18n.tr("No matching items") : ""
                message: page.searchQuery.length > 0 ? "" : appController.apiNote
            }
        }
    }

    ColumnLayout {
        id: reorderableContent
        anchors {
            fill: parent
            topMargin: page.header.height
            leftMargin: units.gu(2)
            rightMargin: units.gu(2)
            bottomMargin: units.gu(2)
        }
        visible: page.useReorderableTaskList()
        spacing: units.gu(1.2)

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: units.gu(4)
            spacing: units.gu(1)

            Item {
                Layout.preferredWidth: units.gu(5)
                Layout.preferredHeight: units.gu(4)

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
                text: dataController.titleText + " - " + page.listStatusText()
                textSize: Label.Small
                opacity: 0.68
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }

        TreeReorderableListView {
            id: reorderableTasks
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: page.reorderableTaskEntries.length > 0
            model: page.reorderableTaskSectionsModel()
            delegate: reorderTaskDelegate
            sectionDelegate: emptyReorderSectionDelegate
            reorderEnabled: page.anyReorderableSectionUsesManualSort() && page.searchQuery.length === 0 && page.settingEnabled("dragForMoveEnabled", true) && !dataController.loading && !page.selectionMode
            refreshing: dataController.loading
            levelZeroDragDropEnabled: page.settingEnabled("levelZeroDragDropEnabled", true)
            childDragDropEnabled: page.settingEnabled("levelZeroDragDropEnabled", true) && page.settingEnabled("childDragDropEnabled", true)
            subItemDropEnabled: page.settingEnabled("levelZeroDragDropEnabled", true) && page.settingEnabled("childDragDropEnabled", true)
            crossListDragEnabled: false
            defaultExpanded: page.settingEnabled("defaultExpanded", true)
            treeLinesEnabled: page.settingEnabled("treeLinesEnabled", true)
            swipeActionsEnabled: page.settingEnabled("swipeActionsEnabled", true)
            swipeRightEnabled: page.settingEnabled("swipeActionsEnabled", true)
            swipeLeftEnabled: page.settingEnabled("swipeActionsEnabled", true)
            swipeActionsReversed: page.settingEnabled("swipeActionsReversed", false)
            swipeRightText: i18n.tr("Delete")
            swipeLeftText: i18n.tr("Toggle complete")
            swipeRightColor: page.deleteRed
            swipeLeftColor: "#5a8f3c"
            selectionEnabled: page.multiSelectAllowed()
            sectionHeight: dataController.viewMode === "myTasks" ? units.gu(4) : 0
            cardHeight: units.gu(8.8)
            taskSpacing: units.gu(1.2)
            dropPreviewHeight: units.gu(8.8)
            dragAreaLeftMargin: units.gu(4.6)
            pullRefreshThreshold: page.pullRefreshThreshold
            pullToRefreshEnabled: page.settingEnabled("pullToRefreshEnabled", true)
            refreshIndicatorColor: page.actionBlue
            pullToRefreshText: i18n.tr("Pull to refresh")
            releaseToRefreshText: i18n.tr("Release to refresh")
            refreshingText: i18n.tr("Refreshing...")

            onItemClicked: function(sectionId, index, item, parentId) {
                if (!item || item.type !== "task") {
                    return
                }
                if (item.conflict === true) {
                    page.openConflictResolution(item)
                } else {
                    page.openTask(item)
                }
            }

            onMoveRequested: function(fromSectionId, fromIndex, toSectionId, toIndex, item, fromParentId, toParentId) {
                page.reorderTaskByTreeRequest(fromSectionId, fromIndex, toSectionId, toIndex, item, fromParentId, toParentId)
            }

            onSubItemRequested: function(fromSectionId, fromIndex, parentSectionId, parentIndex, item, parentItem, fromParentId) {
                page.makeSubTaskByTreeRequest(fromSectionId, fromIndex, parentSectionId, parentIndex, item, parentItem, fromParentId)
            }

            onOutdentRequested: function(fromSectionId, fromIndex, toParentId, toIndex, item, fromParentId) {
                page.outdentTaskByTreeRequest(fromSectionId, fromIndex, toParentId, toIndex, item, fromParentId)
            }

            onDragStarted: function(sectionId, index, item, parentId) {
                dataController.pauseUserSync()
            }
            onDragEnded: function(sectionId, fromIndex, toSectionId, toIndex, item, fromParentId, toParentId) {
                dataController.resumeUserSync()
            }
            onSwipeRightRequested: function(sectionId, index, item, parentId) {
                if (!item || item.type !== "task") {
                    return
                }
                page.requestDeleteTask(item)
            }
            onSwipeLeftRequested: function(sectionId, index, item, parentId) {
                if (!item || item.type !== "task") {
                    return
                }
                dataController.toggleTaskCompleted(item)
            }
            onSelectionChanged: function(selectedItems) {
                if (!page.clearingTreeSelection) {
                    page.setSelectionFromTasks(selectedItems)
                }
            }
            onSelectionCleared: {
                if (!page.clearingTreeSelection) {
                    page.clearSelection()
                }
            }
            onRefreshRequested: dataController.refresh()
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: units.gu(4.8)
            visible: page.completedTaskCount > 0
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

            NextCommon.AppButton {
                Layout.preferredWidth: units.gu(10)
                Layout.preferredHeight: units.gu(4.6)
                visible: dataController.viewMode === "calendarTasks" && dataController.showCompletedTasks
                text: i18n.tr("Reopen all")
                enabled: !dataController.loading
                onClicked: PopupUtils.open(reopenCompletedDialog)
            }
        }

        NextCommon.EmptyState {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: page.reorderableTaskEntries.length === 0 && !dataController.loading
            title: page.searchQuery.length > 0 ? i18n.tr("No matching items") : i18n.tr("No tasks found.")
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

        NextCommon.DrawerShell {
            id: drawer
            anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
            appName: appController.appName
            bottomItems: [
                {"label": i18n.tr("Language"), "page": "LanguageSelectionPage.qml"},
                {"label": i18n.tr("Account"), "page": "AccountSelectionPage.qml"},
                {"label": i18n.tr("Settings"), "page": "SettingsPage.qml"},
                {"label": i18n.tr("About"), "page": "AboutPage.qml"}
            ]
            onCloseClicked: page.drawerOpen = false
            onBottomItemClicked: page.openPage(pageUrl)

            ListView {
                id: tasksMenuList
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: drawer.availableContentHeight
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

                    NextCommon.AppButton {
                        visible: createListItem
                        anchors.centerIn: parent
                        width: Math.min(parent.width - units.gu(4), units.gu(26))
                        height: units.gu(4.2)
                        text: modelData.label
                        opacity: dataController.loading ? 0.45 : 1.0
                        enabled: !dataController.loading
                        onClicked: {
                            page.drawerOpen = false
                            page.newListName = ""
                            PopupUtils.open(createListDialog)
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
        }
    }
}
