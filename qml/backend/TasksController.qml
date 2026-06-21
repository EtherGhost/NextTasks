import QtQuick 2.7
import Qt.labs.settings 1.0

Item {
    id: controller
    property bool loading: false
    property string statusText: i18n.tr("Select an account to load CalDAV task calendars.")
    property string syncStateText: i18n.tr("No account")
    property string syncStateColor: "#b37a2a"
    property string accountAvatarUrl: accountSettings.avatarUrl || ""
    property var entries: []
    property var calendars: []
    property var allTasks: []
    property string viewMode: "myTasks"
    property string titleText: i18n.tr("My Tasks")
    property string selectedCalendarHref: ""
    property string selectedCalendarTitle: ""
    property var pendingCalendars: []
    property var pendingTasks: []
    property int pendingCalendarIndex: 0
    property string currentUserName: ""
    property string currentSecret: ""
    property string currentServerUrl: ""
    property string activeAccountKey: ""
    property bool applyingAccountSelection: false
    property bool completionUpdateRunning: false
    property bool taskUpdateRunning: false
    property bool taskMoveRunning: false
    property bool dirtySyncRunning: false
    property bool dirtySyncAfterRefresh: false
    property var pendingCompletionTask: ({})
    property bool pendingCompletionValue: false
    property var pendingCompletionQueue: []
    property int pendingCompletionTotal: 0
    property var pendingUpdateTask: ({})
    property var pendingUpdateChanges: ({})
    property var pendingMoveQueue: []
    property var pendingMoveTargetCalendar: ({})
    property int pendingMoveTotal: 0
    property int pendingMoveMovedCount: 0
    property int pendingMoveFailedCount: 0
    property int pendingMoveSkippedCount: 0
    property string pendingCalendarTitle: ""
    property string pendingCalendarOperation: ""
    property var pendingCalendar: ({})
    property string pendingCalendarColor: ""
    property string pendingOpenCalendarTitle: ""
    property bool forceFullRefresh: false
    property int menuRevision: 0
    property var dirtySyncQueue: []
    property int dirtySyncTotal: 0
    property int dirtySyncUploadedCount: 0
    property int dirtySyncFailedCount: 0
    property int dirtySyncConflictCount: 0
    property int conflictTasksCount: 0
    property int dirtyTasksCount: 0
    property int accountDataRevision: 0
    property bool dirtySyncQueuedAfterLoading: false
    property bool dirtySyncQueuedAfterInteraction: false
    property bool skipNextCachedLoad: false
    property bool userSyncPaused: false
    property bool showCompletedTasks: false
    property int completedTasksCount: completedTasksForCurrentScope().length
    property string sortMode: sortSettings.sortMode
    property bool sortAscending: sortSettings.sortAscending
    property var sortModeByScope: parseJsonMap(sortSettings.sortModeByScopeJson)
    property int accountRequestGeneration: 0

    Settings {
        id: accountSettings
        category: "account"
        property int accountId: 0
        property string displayName: ""
        property string providerId: ""
        property string serviceId: ""
        property string serverUrl: ""
        property string avatarUrl: ""

        onAccountIdChanged: if (!controller.applyingAccountSelection) controller.handleAccountChanged()
        onProviderIdChanged: if (!controller.applyingAccountSelection) controller.handleAccountChanged()
        onServiceIdChanged: if (!controller.applyingAccountSelection) controller.handleAccountChanged()
        onServerUrlChanged: if (!controller.applyingAccountSelection) controller.handleAccountChanged()
    }

    Timer {
        id: autoDirtySyncTimer
        interval: 500
        repeat: false
        onTriggered: controller.autoDirtySyncNow()
    }

    Settings {
        id: sortSettings
        category: "sort"
        property string sortMode: "due"
        property bool sortAscending: true
        property string sortModeByScopeJson: "{}"

        onSortModeChanged: controller.applyCurrentViewFilter()
        onSortAscendingChanged: controller.applyCurrentViewFilter()
        onSortModeByScopeJsonChanged: {
            controller.sortModeByScope = controller.parseJsonMap(sortModeByScopeJson)
            controller.applyCurrentViewFilter()
        }
    }

    AccountSessionAdapter {
        id: session
        onAuthenticated: function(userName, secret, serverUrl, accountId, serviceId) {
            if (!controller.isCurrentAccountResponse(accountId, serviceId, serverUrl)) {
                console.log("NextTasks Controller ignored stale auth response accountId=" + accountId + " serviceId=" + serviceId)
                return
            }
            controller.accountAvatarUrl = avatarUrl(serverUrl, userName)
            if (controller.accountAvatarUrl.length > 0) {
                accountSettings.avatarUrl = controller.accountAvatarUrl
            }
            controller.activeAccountKey = controller.accountKey()
            controller.currentUserName = userName
            controller.currentSecret = secret
            controller.currentServerUrl = serverUrl
            if (controller.completionUpdateRunning) {
                controller.startNextCompletionUpdate()
                return
            }
            if (controller.dirtySyncRunning) {
                controller.startNextDirtySync()
                return
            }
            if (controller.taskUpdateRunning) {
                controller.startTaskUpdate()
                return
            }
            if (controller.taskMoveRunning) {
                controller.startNextTaskMove()
                return
            }
            if (controller.pendingCalendarTitle.length > 0) {
                if (controller.pendingCalendarOperation === "update") {
                    api.updateCalendar(serverUrl, userName, secret, controller.pendingCalendar.href || "", controller.pendingCalendarTitle, controller.pendingCalendarColor)
                } else if (controller.pendingCalendarOperation === "delete") {
                    api.deleteCalendar(serverUrl, userName, secret, controller.pendingCalendar.href || "")
                } else {
                    api.createCalendar(serverUrl, userName, secret, controller.pendingCalendarTitle)
                }
                return
            }
            controller.requestRemoteRefresh()
        }
        onFailed: {
            controller.loading = false
            controller.taskMoveRunning = false
            controller.pendingMoveQueue = []
            controller.pendingMoveTargetCalendar = ({})
            controller.pendingMoveTotal = 0
            controller.pendingMoveMovedCount = 0
            controller.pendingMoveFailedCount = 0
            controller.pendingMoveSkippedCount = 0
            controller.dirtySyncRunning = false
            controller.dirtySyncQueue = []
            controller.pendingCalendarTitle = ""
            controller.pendingCalendarOperation = ""
            controller.pendingCalendar = ({})
            controller.statusText = message
            controller.syncStateText = i18n.tr("Authentication failed")
            controller.syncStateColor = "#b37a2a"
        }
    }

    TasksApiClient {
        id: api
        onCalendarsLoaded: function(entries, generation) {
            if (!controller.isCurrentApiGeneration(generation)) {
                console.log("NextTasks Controller ignored stale calendars response generation=" + generation)
                return
            }
            console.log(
                "NextTasks Controller applying calendars"
                + " generation=" + generation
                + " accountId=" + accountSettings.accountId
                + " count=" + (entries ? entries.length : 0)
                + " scopeHash=" + controller.stableHash(controller.accountKey())
            )
            tasksCache.replaceCalendars(entries)
            controller.calendars = tasksCache.loadCalendars()
            controller.menuRevision += 1
            if (controller.pendingOpenCalendarTitle.length > 0) {
                var createdCalendar = controller.findCalendarByTitle(controller.pendingOpenCalendarTitle)
                controller.pendingOpenCalendarTitle = ""
                if (createdCalendar && String(createdCalendar.href || "").length > 0) {
                    controller.selectedCalendarHref = createdCalendar.href || ""
                    controller.selectedCalendarTitle = createdCalendar.title || i18n.tr("Tasks")
                    controller.viewMode = "calendarTasks"
                    controller.titleText = controller.selectedCalendarTitle
                    controller.sortMode = controller.currentSortMode()
                    api.loadTasks(controller.currentServerUrl, controller.currentUserName, controller.currentSecret, controller.selectedCalendarHref, controller.selectedCalendarTitle)
                    return
                }
            }
            if (controller.viewMode === "calendarList") {
                controller.entries = controller.calendars
                controller.loading = false
                controller.runQueuedDirtySyncIfReady()
                if (controller.dirtySyncRunning) return
                controller.statusText = controller.calendars.length > 0 ? i18n.tr("Loaded %1 list(s).").arg(controller.calendars.length) : i18n.tr("No lists found.")
                controller.markUpToDateIfClean()
            } else {
                controller.loadMyTasksFromCalendars(controller.calendars)
            }
        }
        onTasksLoaded: function(calendarTitle, calendarHref, entries, generation) {
            if (!controller.isCurrentApiGeneration(generation)) {
                console.log("NextTasks Controller ignored stale tasks response generation=" + generation)
                return
            }
            console.log(
                "NextTasks Controller applying tasks"
                + " generation=" + generation
                + " accountId=" + accountSettings.accountId
                + " calendarOwner=" + controller.hrefOwnerFingerprint(calendarHref)
                + " count=" + (entries ? entries.length : 0)
                + " scopeHash=" + controller.stableHash(controller.accountKey())
            )
            var decorated = controller.decorateTasks(entries, calendarTitle, calendarHref)
            tasksCache.replaceCalendarTasks(calendarHref, decorated)
            if (controller.viewMode === "calendarTasks") {
                controller.replaceCalendarTasks(calendarHref, tasksCache.loadTasksForCalendar(calendarHref))
                controller.allTasks = controller.tasksForKnownCalendars(tasksCache.loadAllTasks(), controller.calendars)
                controller.entries = controller.visibleTasks(controller.tasksForCurrentScope(), true)
                controller.titleText = calendarTitle
                controller.loading = false
                controller.runQueuedDirtySyncIfReady()
                if (controller.dirtySyncRunning) return
                controller.statusText = controller.entries.length > 0 ? i18n.tr("Loaded %1 task(s).").arg(controller.entries.length) : i18n.tr("No tasks found.")
                controller.markUpToDateIfClean()
            } else {
                controller.pendingTasks = controller.pendingTasks.concat(decorated)
                controller.loadNextPendingCalendar()
            }
        }
        onFailed: function(message, generation) {
            if (!controller.isCurrentApiGeneration(generation)) {
                console.log("NextTasks Controller ignored stale API failure generation=" + generation)
                return
            }
            controller.completionUpdateRunning = false
            controller.taskUpdateRunning = false
            controller.dirtySyncRunning = false
            controller.dirtySyncAfterRefresh = false
            controller.pendingCompletionTask = ({})
            controller.pendingUpdateTask = ({})
            controller.dirtySyncQueue = []
            controller.loading = false
            controller.statusText = message
            controller.syncStateText = i18n.tr("Sync failed")
            controller.syncStateColor = "#b37a2a"
        }
        onTaskCompletionUpdated: function(completed, generation) {
            if (!controller.isCurrentApiGeneration(generation)) {
                console.log("NextTasks Controller ignored stale completion response generation=" + generation)
                return
            }
            controller.pendingCompletionQueue.shift()
            if (controller.pendingCompletionQueue.length > 0) {
                controller.startNextCompletionUpdate()
            } else {
                var total = controller.pendingCompletionTotal
                controller.completionUpdateRunning = false
                controller.pendingCompletionTask = ({})
                controller.pendingCompletionTotal = 0
                controller.statusText = total > 1
                    ? i18n.tr("Updated %1 tasks.").arg(total)
                    : completed ? i18n.tr("Task marked completed.") : i18n.tr("Task marked open.")
                controller.markUpToDateIfClean()
                controller.refresh()
            }
        }
        onTaskCompletionFailed: function(message, generation) {
            if (!controller.isCurrentApiGeneration(generation)) {
                console.log("NextTasks Controller ignored stale completion failure generation=" + generation)
                return
            }
            controller.completionUpdateRunning = false
            controller.pendingCompletionTask = ({})
            controller.pendingCompletionQueue = []
            controller.pendingCompletionTotal = 0
            controller.loading = false
            controller.statusText = message
            controller.syncStateText = i18n.tr("Sync failed")
            controller.syncStateColor = "#b37a2a"
        }
        onTaskUpdated: function(updatedTask, generation) {
            if (!controller.isCurrentApiGeneration(generation)) {
                console.log("NextTasks Controller ignored stale task update response generation=" + generation)
                return
            }
            controller.applyLocalTaskIdentity(updatedTask, controller.pendingUpdateTask)
            controller.taskUpdateRunning = false
            controller.pendingUpdateTask = ({})
            controller.pendingUpdateChanges = ({})
            tasksCache.saveUploadedTask(updatedTask)
            var cachedUpdatedTask = tasksCache.loadTask(updatedTask)
            controller.upsertTask(cachedUpdatedTask || updatedTask)
            controller.applyCurrentViewFilter()
            if (controller.dirtySyncRunning) {
                controller.dirtySyncUploadedCount += 1
                controller.dirtySyncQueue.shift()
                controller.startNextDirtySync()
            } else {
                controller.loading = false
                controller.statusText = i18n.tr("Task saved.")
                controller.markUpToDateIfClean()
            }
        }
        onTaskCreated: function(createdTask, generation) {
            if (!controller.isCurrentApiGeneration(generation)) {
                console.log("NextTasks Controller ignored stale task create response generation=" + generation)
                return
            }
            controller.applyLocalTaskIdentity(createdTask, controller.pendingUpdateTask)
            controller.taskUpdateRunning = false
            controller.pendingUpdateTask = ({})
            controller.pendingUpdateChanges = ({})
            tasksCache.saveUploadedTask(createdTask)
            var cachedCreatedTask = tasksCache.loadTask(createdTask)
            controller.upsertTask(cachedCreatedTask || createdTask)
            controller.applyCurrentViewFilter()
            if (controller.dirtySyncRunning) {
                controller.dirtySyncUploadedCount += 1
                controller.dirtySyncQueue.shift()
                controller.startNextDirtySync()
            } else {
                controller.loading = false
                controller.statusText = i18n.tr("Task created.")
                controller.markUpToDateIfClean()
            }
        }
        onTaskCreateFailed: function(message, generation) {
            controller.handleDirtyWriteFailure(message, generation)
        }
        onTaskDeleted: function(deletedTask, generation) {
            if (!controller.isCurrentApiGeneration(generation)) {
                console.log("NextTasks Controller ignored stale task delete response generation=" + generation)
                return
            }
            tasksCache.deleteTask(deletedTask)
            controller.removeTask(deletedTask)
            controller.applyCurrentViewFilter()
            controller.taskUpdateRunning = false
            controller.pendingUpdateTask = ({})
            controller.pendingUpdateChanges = ({})
            if (controller.dirtySyncRunning) {
                controller.dirtySyncUploadedCount += 1
                controller.dirtySyncQueue.shift()
                controller.startNextDirtySync()
            } else {
                controller.loading = false
                controller.statusText = i18n.tr("Task deleted.")
                controller.markUpToDateIfClean()
            }
        }
        onTaskDeleteFailed: function(message, generation) {
            controller.handleDirtyWriteFailure(message, generation)
        }
        onTaskMoved: function(sourceTask, movedTask, generation) {
            if (!controller.isCurrentApiGeneration(generation)) {
                console.log("NextTasks Controller ignored stale task move response generation=" + generation)
                return
            }
            tasksCache.deleteTask(sourceTask)
            tasksCache.saveUploadedTask(movedTask)
            controller.removeTask(sourceTask)
            var cachedMovedTask = tasksCache.loadTask(movedTask)
            controller.upsertTask(cachedMovedTask || movedTask)
            controller.pendingMoveMovedCount += 1
            controller.pendingMoveQueue.shift()
            controller.applyCurrentViewFilter()
            controller.refreshMenuCounts()
            controller.startNextTaskMove()
        }
        onTaskMoveFailed: function(message, generation) {
            if (!controller.isCurrentApiGeneration(generation)) {
                console.log("NextTasks Controller ignored stale task move failure generation=" + generation)
                return
            }
            controller.pendingMoveFailedCount += 1
            controller.pendingMoveQueue.shift()
            controller.statusText = message
            controller.startNextTaskMove()
        }
        onTaskUpdateFailed: function(message, generation) {
            controller.handleDirtyWriteFailure(message, generation)
        }
        onTaskConflict: function(localTask, serverTask, message, generation) {
            if (!controller.isCurrentApiGeneration(generation)) {
                console.log("NextTasks Controller ignored stale task conflict generation=" + generation)
                return
            }
            tasksCache.markConflict(localTask, serverTask)
            controller.dirtySyncConflictCount += 1
            var conflictedTask = tasksCache.loadTask(localTask)
            if (conflictedTask) {
                controller.upsertTask(conflictedTask)
            }
            controller.applyCurrentViewFilter()
            if (controller.dirtySyncRunning) {
                controller.taskUpdateRunning = false
                controller.pendingUpdateTask = ({})
                controller.pendingUpdateChanges = ({})
                controller.dirtySyncQueue.shift()
                controller.startNextDirtySync()
            } else {
                controller.loading = false
                controller.statusText = message
                controller.syncStateText = i18n.tr("Conflict")
                controller.syncStateColor = "#d85a7f"
            }
        }
        onCalendarCreated: function(generation) {
            if (!controller.isCurrentApiGeneration(generation)) {
                console.log("NextTasks Controller ignored stale calendar create response generation=" + generation)
                return
            }
            var createdTitle = controller.pendingCalendarTitle
            controller.loading = false
            controller.pendingCalendarTitle = ""
            controller.pendingCalendarOperation = ""
            controller.pendingCalendar = ({})
            controller.pendingCalendarColor = ""
            controller.pendingOpenCalendarTitle = createdTitle
            controller.statusText = i18n.tr("Task list created. Refreshing...")
            controller.syncStateText = i18n.tr("Refreshing")
            controller.syncStateColor = "#2c7fb8"
            controller.forceFullRefresh = true
            controller.refresh()
        }
        onCalendarCreateFailed: function(message, generation) {
            if (!controller.isCurrentApiGeneration(generation)) {
                console.log("NextTasks Controller ignored stale calendar create failure generation=" + generation)
                return
            }
            controller.loading = false
            controller.pendingCalendarTitle = ""
            controller.pendingCalendarOperation = ""
            controller.pendingCalendar = ({})
            controller.pendingCalendarColor = ""
            controller.statusText = message
            controller.syncStateText = i18n.tr("Sync failed")
            controller.syncStateColor = "#b37a2a"
        }
        onCalendarUpdated: function(generation) {
            if (!controller.isCurrentApiGeneration(generation)) {
                console.log("NextTasks Controller ignored stale calendar update response generation=" + generation)
                return
            }
            controller.loading = false
            controller.pendingCalendarTitle = ""
            controller.pendingCalendarOperation = ""
            controller.pendingCalendar = ({})
            controller.pendingCalendarColor = ""
            controller.statusText = i18n.tr("Task list updated. Refreshing...")
            controller.syncStateText = i18n.tr("Refreshing")
            controller.syncStateColor = "#2c7fb8"
            controller.forceFullRefresh = true
            controller.refresh()
        }
        onCalendarUpdateFailed: function(message, generation) {
            if (!controller.isCurrentApiGeneration(generation)) {
                console.log("NextTasks Controller ignored stale calendar update failure generation=" + generation)
                return
            }
            controller.loading = false
            controller.pendingCalendarTitle = ""
            controller.pendingCalendarOperation = ""
            controller.pendingCalendar = ({})
            controller.pendingCalendarColor = ""
            controller.statusText = message
            controller.syncStateText = i18n.tr("Sync failed")
            controller.syncStateColor = "#b37a2a"
        }
        onCalendarDeleted: function(generation) {
            if (!controller.isCurrentApiGeneration(generation)) {
                console.log("NextTasks Controller ignored stale calendar delete response generation=" + generation)
                return
            }
            var deletedHref = controller.pendingCalendar.href || ""
            if (deletedHref.length > 0) {
                tasksCache.deleteCalendar(deletedHref)
            }
            controller.loading = false
            controller.pendingCalendarTitle = ""
            controller.pendingCalendarOperation = ""
            controller.pendingCalendar = ({})
            controller.pendingCalendarColor = ""
            controller.goBackToMyTasks()
            controller.statusText = i18n.tr("Task list deleted. Refreshing...")
            controller.syncStateText = i18n.tr("Refreshing")
            controller.syncStateColor = "#2c7fb8"
            controller.forceFullRefresh = true
            controller.refresh()
        }
        onCalendarDeleteFailed: function(message, generation) {
            if (!controller.isCurrentApiGeneration(generation)) {
                console.log("NextTasks Controller ignored stale calendar delete failure generation=" + generation)
                return
            }
            controller.loading = false
            controller.pendingCalendarTitle = ""
            controller.pendingCalendarOperation = ""
            controller.pendingCalendar = ({})
            controller.pendingCalendarColor = ""
            controller.statusText = message
            controller.syncStateText = i18n.tr("Sync failed")
            controller.syncStateColor = "#b37a2a"
        }
    }

    TasksCache {
        id: tasksCache
    }

    function refresh() {
        if (loading && !forceFullRefresh) {
            console.log("NextTasks Controller refresh skipped while loading")
            return
        }
        accountRequestGeneration += 1
        session.setAccount(accountSettings.accountId, accountSettings.providerId, accountSettings.serviceId, accountSettings.serverUrl)
        api.requestGeneration = accountRequestGeneration
        var key = accountKey()
        if (key !== activeAccountKey) {
            clearAccountData()
            activeAccountKey = key
            skipNextCachedLoad = true
        }
        tasksCache.setScope(key)
        console.log(
            "NextTasks Controller refresh"
            + " generation=" + accountRequestGeneration
            + " accountId=" + accountSettings.accountId
            + " scopeHash=" + stableHash(key)
            + " viewMode=" + viewMode
            + " skipCached=" + skipNextCachedLoad
        )
        if (skipNextCachedLoad) {
            tasksCache.clearCleanServerDataForCurrentScope()
            skipNextCachedLoad = false
            entries = []
            calendars = []
            allTasks = []
            menuRevision += 1
            statusText = i18n.tr("Account changed. Refreshing...")
        } else {
            loadCachedState()
        }
        var localChanges = tasksCache.loadLocalChanges()
        if (localChanges.length > 0) {
            dirtySyncQueue = localChanges
            dirtySyncTotal = localChanges.length
            dirtySyncUploadedCount = 0
            dirtySyncFailedCount = 0
            dirtySyncConflictCount = 0
            dirtySyncRunning = true
            dirtySyncAfterRefresh = true
        }
        loading = true
        statusText = localChanges.length > 0 ? i18n.tr("Syncing local changes...") : i18n.tr("Loading...")
        syncStateText = i18n.tr("Syncing")
        syncStateColor = "#2c7fb8"
        api.requestGeneration = accountRequestGeneration
        session.authenticate()
    }

    function showMyTasks() {
        selectedCalendarHref = ""
        selectedCalendarTitle = ""
        viewMode = "myTasks"
        titleText = i18n.tr("My Tasks")
        refresh()
    }

    function showCalendarList() {
        selectedCalendarHref = ""
        selectedCalendarTitle = ""
        viewMode = "calendarList"
        titleText = i18n.tr("Lists")
        if (calendars.length > 0) {
            entries = calendars
            statusText = calendars.length > 0 ? i18n.tr("Loaded %1 list(s).").arg(calendars.length) : i18n.tr("No lists found.")
            markUpToDateIfClean()
            return
        }
        refresh()
    }

    function openCalendar(href, title) {
        selectedCalendarHref = href || ""
        selectedCalendarTitle = title || i18n.tr("Tasks")
        viewMode = "calendarTasks"
        titleText = selectedCalendarTitle
        sortMode = currentSortMode()
        loadCachedState()
        loading = true
        statusText = i18n.tr("Loading...")
        syncStateText = i18n.tr("Syncing")
        syncStateColor = "#2c7fb8"
        api.requestGeneration = accountRequestGeneration
        session.authenticate()
    }

    function goBackToMyTasks() {
        selectedCalendarHref = ""
        selectedCalendarTitle = ""
        viewMode = "myTasks"
        titleText = i18n.tr("My Tasks")
        entries = visibleTasks(allTasks, true)
        statusText = entries.length > 0 ? i18n.tr("Loaded %1 task(s).").arg(entries.length) : i18n.tr("No tasks found.")
    }

    function toggleTaskCompleted(task) {
        if (!task || task.type !== "task" || loading) {
            return
        }
        updateTaskCompletionQueue([task], !task.completed)
    }

    function saveTask(task, changes) {
        if (!task || task.type !== "task") {
            return
        }
        var localTask = mergeTaskChanges(taskByKey(task) || task, changes || {})
        tasksCache.saveLocalDraft(localTask)
        upsertTask(localTask)
        applyCurrentViewFilter()
        scheduleDirtyAutoSync()
    }

    function createTask() {
        var targetCalendar = createTargetCalendar()
        return createTaskInCalendar(targetCalendar)
    }

    function createTaskInCalendar(targetCalendar) {
        if (loading) {
            return null
        }
        if (!targetCalendar || String(targetCalendar.href || "").length === 0) {
            statusText = i18n.tr("No task list is available for new tasks.")
            return null
        }
        var task = tasksCache.createLocalTask(targetCalendar.href, targetCalendar.title)
        console.log("NextTasks Controller createTaskInCalendar queued localStatus=" + String(task.localStatus || "") + " isNew=" + (task.isNew === true ? "true" : "false"))
        statusText = i18n.tr("New task")
        syncStateText = i18n.tr("Waiting to sync")
        syncStateColor = "#b37a2a"
        refreshMenuCounts()
        return task
    }

    function createTargetCalendar() {
        if (viewMode === "calendarTasks" && selectedCalendarHref.length > 0) {
            return {"href": selectedCalendarHref, "title": selectedCalendarTitle || i18n.tr("Tasks")}
        }
        return null
    }

    function availableCreateCalendars() {
        var source = calendars.length > 0 ? calendars : tasksCache.loadCalendars()
        var result = []
        for (var i = 0; i < source.length; ++i) {
            var calendar = source[i]
            if (String(calendar.href || "").length === 0) continue
            result.push({
                "href": calendar.href || "",
                "title": calendar.title || i18n.tr("Tasks")
            })
        }
        return result
    }

    function createCalendar(title) {
        var name = String(title || "").trim()
        if (loading) {
            return
        }
        if (name.length === 0) {
            statusText = i18n.tr("Task list name is required.")
            return
        }
        loading = true
        statusText = i18n.tr("Creating task list...")
        syncStateText = i18n.tr("Syncing")
        syncStateColor = "#2c7fb8"
        pendingCalendarTitle = name
        pendingCalendarOperation = "create"
        pendingCalendar = ({})
        pendingCalendarColor = ""
        session.setAccount(accountSettings.accountId, accountSettings.providerId, accountSettings.serviceId, accountSettings.serverUrl)
        api.requestGeneration = accountRequestGeneration
        session.authenticate()
    }

    function updateCalendar(calendar, title, color) {
        var name = String(title || "").trim()
        if (!calendar || String(calendar.href || "").length === 0 || loading) {
            return
        }
        if (name.length === 0) {
            statusText = i18n.tr("Task list name is required.")
            return
        }
        loading = true
        statusText = i18n.tr("Updating task list...")
        syncStateText = i18n.tr("Syncing")
        syncStateColor = "#2c7fb8"
        pendingCalendarTitle = name
        pendingCalendarOperation = "update"
        pendingCalendar = calendar
        pendingCalendarColor = color || ""
        session.setAccount(accountSettings.accountId, accountSettings.providerId, accountSettings.serviceId, accountSettings.serverUrl)
        api.requestGeneration = accountRequestGeneration
        session.authenticate()
    }

    function deleteCalendar(calendar) {
        if (!calendar || String(calendar.href || "").length === 0 || loading) {
            return
        }
        loading = true
        statusText = i18n.tr("Deleting task list...")
        syncStateText = i18n.tr("Syncing")
        syncStateColor = "#2c7fb8"
        pendingCalendarTitle = calendar.title || i18n.tr("Tasks")
        pendingCalendarOperation = "delete"
        pendingCalendar = calendar
        pendingCalendarColor = calendar.color || ""
        session.setAccount(accountSettings.accountId, accountSettings.providerId, accountSettings.serviceId, accountSettings.serverUrl)
        api.requestGeneration = accountRequestGeneration
        session.authenticate()
    }

    function deleteTask(task) {
        if (!task || task.type !== "task" || loading) {
            return
        }
        tasksCache.markDeleted(task)
        if (task.localStatus === tasksCache.statusCreated || task.isNew) {
            removeTask(task)
            applyCurrentViewFilter()
            refreshMenuCounts()
            statusText = i18n.tr("Deleted local task draft.")
            return
        }
        var deletedTask = {}
        for (var key in task) {
            deletedTask[key] = task[key]
        }
        deletedTask.localStatus = tasksCache.statusDeleted
        deletedTask.deleted = true
        deletedTask.dirty = true
        upsertTask(deletedTask)
        applyCurrentViewFilter()
        refreshMenuCounts()
        statusText = i18n.tr("Task deleted locally. Syncing deletion...")
        syncStateText = i18n.tr("Waiting to sync")
        syncStateColor = "#b37a2a"
        startDirtySync(false)
    }

    function deleteTasksByKeys(taskKeys) {
        if (!taskKeys || loading) {
            return 0
        }
        var deletedCount = 0
        var changedServerBacked = false
        var source = allTasks.slice()
        for (var i = 0; i < source.length; ++i) {
            var task = source[i]
            if (!task || task.type !== "task" || task.deleted) {
                continue
            }
            var key = taskKey(task)
            if (key.length === 0 || taskKeys[key] !== true) {
                continue
            }
            tasksCache.markDeleted(task)
            if (task.localStatus === tasksCache.statusCreated || task.isNew) {
                removeTask(task)
            } else {
                var deletedTask = {}
                for (var prop in task) {
                    deletedTask[prop] = task[prop]
                }
                deletedTask.localStatus = tasksCache.statusDeleted
                deletedTask.deleted = true
                deletedTask.dirty = true
                upsertTask(deletedTask)
                changedServerBacked = true
            }
            deletedCount += 1
        }
        if (deletedCount === 0) {
            return 0
        }
        applyCurrentViewFilter()
        refreshMenuCounts()
        updateDirtySummary()
        if (changedServerBacked) {
            statusText = i18n.tr("%1 tasks deleted locally. Syncing deletions...").arg(deletedCount)
            syncStateText = i18n.tr("Waiting to sync")
            syncStateColor = "#b37a2a"
            startDirtySync(false)
        } else {
            statusText = i18n.tr("%1 local task drafts deleted.").arg(deletedCount)
            markUpToDateIfClean()
        }
        return deletedCount
    }

    function availableMoveCalendars(task) {
        var source = calendars.length > 0 ? calendars : tasksCache.loadCalendars()
        var currentHref = calendarHrefForTask(task)
        var currentTitle = normalizedCalendarTitle(task && task.calendarTitle ? task.calendarTitle : "")
        var result = []
        for (var i = 0; i < source.length; ++i) {
            var calendar = source[i]
            var href = String(calendar.href || "")
            var same = sameCalendarHref(href, currentHref) || sameCalendarTitle(calendar.title, currentTitle)
            if (href.length === 0 || same) continue
            result.push({
                "href": href,
                "title": calendar.title || i18n.tr("Tasks")
            })
        }
        return result
    }

    function availableMoveCalendarsForTasks(tasks) {
        var source = calendars.length > 0 ? calendars : tasksCache.loadCalendars()
        var selected = tasks || []
        var selectedCalendarHrefs = {}
        var selectedCalendarTitles = {}
        for (var i = 0; i < selected.length; ++i) {
            var href = normalizedCalendarHref(calendarHrefForTask(selected[i]))
            if (href.length > 0) {
                selectedCalendarHrefs[href] = true
            }
            var title = normalizedCalendarTitle(selected[i] && selected[i].calendarTitle ? selected[i].calendarTitle : "")
            if (title.length > 0) {
                selectedCalendarTitles[title] = true
            }
        }
        var result = []
        for (var j = 0; j < source.length; ++j) {
            var calendar = source[j]
            var calendarHref = String(calendar.href || "")
            var normalizedHref = normalizedCalendarHref(calendarHref)
            if (calendarHref.length === 0) continue
            var normalizedTitle = normalizedCalendarTitle(calendar.title || "")
            var same = selectedCalendarHrefs[normalizedHref] === true || selectedCalendarTitles[normalizedTitle] === true
            if (same) continue
            result.push({
                "href": calendarHref,
                "title": calendar.title || i18n.tr("Tasks")
            })
        }
        return result
    }

    function moveTaskToCalendar(task, targetCalendar) {
        if (!task || task.type !== "task" || loading) {
            return false
        }
        return moveTaskListToCalendar([task], targetCalendar)
    }

    function moveTasksByKeysToCalendar(taskKeys, targetCalendar) {
        if (!taskKeys || loading) {
            return 0
        }
        var selectedTasks = []
        for (var i = 0; i < allTasks.length; ++i) {
            var task = allTasks[i]
            var key = taskKey(task)
            if (key.length > 0 && taskKeys[key] === true) {
                selectedTasks.push(task)
            }
        }
        moveTaskListToCalendar(selectedTasks, targetCalendar)
        return selectedTasks.length
    }

    function canMoveTasksToCalendar(tasks, targetCalendar) {
        var targetHref = String(targetCalendar && targetCalendar.href ? targetCalendar.href : "")
        var targetTitle = String(targetCalendar && targetCalendar.title ? targetCalendar.title : "")
        if (targetHref.length === 0) {
            return false
        }
        var selected = tasks || []
        for (var i = 0; i < selected.length; ++i) {
            var task = selected[i]
            if (!task || task.type !== "task") {
                continue
            }
            if (sameCalendarHref(calendarHrefForTask(task), targetHref) || sameCalendarTitle(task.calendarTitle, targetTitle)) {
                return false
            }
        }
        return true
    }

    function moveTaskListToCalendar(tasks, targetCalendar) {
        var targetHref = String(targetCalendar && targetCalendar.href ? targetCalendar.href : "")
        if (targetHref.length === 0) {
            statusText = i18n.tr("Choose a target task list.")
            return false
        }
        var queue = []
        var skipped = 0
        var source = tasks || []
        for (var i = 0; i < source.length; ++i) {
            var task = source[i]
            if (!task || task.type !== "task") {
                skipped += 1
                continue
            }
            if (sameCalendarHref(calendarHrefForTask(task), targetHref)) {
                skipped += 1
                continue
            }
            if (task.isNew === true || task.dirty === true || task.deleted === true || task.conflict === true || String(task.href || "").length === 0) {
                skipped += 1
                continue
            }
            queue.push(task)
        }
        if (queue.length === 0) {
            pendingMoveSkippedCount = skipped
            statusText = skipped > 0
                ? i18n.tr("Selected tasks must be synced before they can be moved.")
                : i18n.tr("No tasks can be moved.")
            return false
        }
        taskMoveRunning = true
        pendingMoveQueue = queue
        pendingMoveTargetCalendar = targetCalendar
        pendingMoveTotal = queue.length
        pendingMoveMovedCount = 0
        pendingMoveFailedCount = 0
        pendingMoveSkippedCount = skipped
        loading = true
        statusText = queue.length > 1
            ? i18n.tr("Moving %1 tasks...").arg(queue.length)
            : i18n.tr("Moving task...")
        syncStateText = i18n.tr("Syncing")
        syncStateColor = "#2c7fb8"
        session.setAccount(accountSettings.accountId, accountSettings.providerId, accountSettings.serviceId, accountSettings.serverUrl)
        api.requestGeneration = accountRequestGeneration
        session.authenticate()
        return true
    }

    function startNextTaskMove() {
        if (!taskMoveRunning) {
            return
        }
        if (pendingMoveQueue.length === 0) {
            finishTaskMove()
            return
        }
        var task = pendingMoveQueue[0]
        statusText = i18n.tr("Moving task %1 of %2...").arg(pendingMoveTotal - pendingMoveQueue.length + 1).arg(pendingMoveTotal)
        api.moveTask(currentServerUrl, currentUserName, currentSecret, task, pendingMoveTargetCalendar)
    }

    function finishTaskMove() {
        var moved = pendingMoveMovedCount
        var failed = pendingMoveFailedCount
        var skipped = pendingMoveSkippedCount
        taskMoveRunning = false
        pendingMoveQueue = []
        pendingMoveTargetCalendar = ({})
        pendingMoveTotal = 0
        pendingMoveMovedCount = 0
        pendingMoveFailedCount = 0
        pendingMoveSkippedCount = 0
        loading = false
        forceFullRefresh = true
        if (failed > 0) {
            statusText = i18n.tr("Moved %1 task(s), %2 failed, %3 skipped.").arg(moved).arg(failed).arg(skipped)
            syncStateText = i18n.tr("Sync failed")
            syncStateColor = "#b37a2a"
        } else {
            statusText = skipped > 0
                ? i18n.tr("Moved %1 task(s). %2 skipped because they need sync first.").arg(moved).arg(skipped)
                : i18n.tr("Moved %1 task(s).").arg(moved)
            syncStateText = i18n.tr("Refreshing")
            syncStateColor = "#2c7fb8"
            refresh()
        }
    }

    function reopenCompletedTasksInCurrentScope() {
        var tasks = completedTasksForCurrentScope()
        if (tasks.length === 0 || loading) {
            return
        }
        updateTaskCompletionQueue(tasks, false)
    }

    function updateTaskCompletionQueue(tasks, completed) {
        if (!tasks || tasks.length === 0) {
            return
        }
        for (var i = 0; i < tasks.length; ++i) {
            var task = tasks[i]
            var changes = taskToChanges(task)
            changes.status = completed ? "COMPLETED" : "NEEDS-ACTION"
            changes.completed = completed === true
            changes.percentComplete = completed ? "100" : "0"
            var localTask = mergeTaskChanges(task, changes)
            tasksCache.saveLocalDraft(localTask)
            upsertTask(localTask)
        }
        applyCurrentViewFilter()
        statusText = tasks.length > 1
            ? i18n.tr("%1 local task changes saved.").arg(tasks.length)
            : completed ? i18n.tr("Task marked completed locally.") : i18n.tr("Task marked open locally.")
        startDirtySync(false)
    }

    function startNextCompletionUpdate() {
        if (!completionUpdateRunning || pendingCompletionQueue.length === 0) {
            return
        }
        pendingCompletionTask = pendingCompletionQueue[0]
        statusText = pendingCompletionTotal > 1
            ? i18n.tr("Updating task %1 of %2...").arg(pendingCompletionTotal - pendingCompletionQueue.length + 1).arg(pendingCompletionTotal)
            : pendingCompletionValue ? i18n.tr("Marking task completed...") : i18n.tr("Marking task open...")
        api.updateTaskCompletion(currentServerUrl, currentUserName, currentSecret, pendingCompletionTask, pendingCompletionValue)
    }

    function startTaskUpdate() {
        if (!taskUpdateRunning || !pendingUpdateTask || pendingUpdateTask.type !== "task") {
            return
        }
        statusText = i18n.tr("Saving task...")
        api.updateTask(currentServerUrl, currentUserName, currentSecret, pendingUpdateTask, pendingUpdateChanges)
    }

    function updateTaskLocalDraft(task, changes) {
        if (!task || task.type !== "task") {
            return
        }
        var localTask = mergeTaskChanges(taskByKey(task) || task, changes || {})
        tasksCache.saveLocalDraft(localTask)
        upsertTask(localTask)
        applyCurrentViewFilter()
        console.log("NextTasks Controller updateTaskLocalDraft queued localStatus=" + String(localTask.localStatus || "") + " isNew=" + (localTask.isNew === true ? "true" : "false"))
        statusText = i18n.tr("Local changes saved on this device")
        syncStateText = i18n.tr("Waiting to sync")
        syncStateColor = "#b37a2a"
        scheduleDirtyAutoSync()
    }

    function scheduleDirtyAutoSync() {
        updateDirtySummary()
        if (userSyncPaused) {
            dirtySyncQueuedAfterInteraction = true
            statusText = i18n.tr("Local changes waiting to sync.")
            syncStateText = i18n.tr("Waiting to sync")
            syncStateColor = "#b37a2a"
            return
        }
        if (dirtySyncRunning || loading) {
            dirtySyncQueuedAfterLoading = true
            statusText = i18n.tr("Local changes waiting to sync.")
            syncStateText = i18n.tr("Waiting to sync")
            syncStateColor = "#b37a2a"
            return
        }
        if (tasksCache.loadLocalChanges().length === 0) {
            return
        }
        statusText = i18n.tr("Local changes saved on this device")
        syncStateText = i18n.tr("Waiting to sync")
        syncStateColor = "#b37a2a"
        autoDirtySyncTimer.restart()
    }

    function autoDirtySyncNow() {
        if (userSyncPaused) {
            dirtySyncQueuedAfterInteraction = true
            return
        }
        if (dirtySyncRunning || loading) {
            dirtySyncQueuedAfterLoading = true
            return
        }
        if (tasksCache.loadLocalChanges().length === 0) {
            markUpToDateIfClean()
            return
        }
        startDirtySync(false)
    }

    function menuItems() {
        var items = [
            {"type": "header", "label": i18n.tr("Views")},
            {"type": "myTasks", "label": i18n.tr("My Tasks"), "count": visibleTasks(allTasks, true).length},
            {"type": "calendarList", "label": i18n.tr("All lists"), "count": calendars.length},
            {"type": "header", "label": i18n.tr("Lists")}
        ]
        for (var i = 0; i < calendars.length; ++i) {
            var calendar = calendars[i]
            items.push({
                "type": "calendar",
                "label": calendar.title || i18n.tr("Untitled"),
                "count": countTasksForCalendar(calendar.href || ""),
                "href": calendar.href || "",
                "title": calendar.title || i18n.tr("Untitled"),
                "color": calendar.color || ""
            })
        }
        items.push({
            "type": "createList",
            "label": i18n.tr("Create new list")
        })
        return items
    }

    function sortOptions() {
        return [
            {"value": "due", "label": i18n.tr("Due date")},
            {"value": "start", "label": i18n.tr("Start date")},
            {"value": "priority", "label": i18n.tr("Priority")},
            {"value": "alpha", "label": i18n.tr("Alphabetical")},
            {"value": "modified", "label": i18n.tr("Modified")},
            {"value": "created", "label": i18n.tr("Created")},
            {"value": "list", "label": i18n.tr("List")},
            {"value": "manual", "label": i18n.tr("Manual order")}
        ]
    }

    function sortModeLabel() {
        return sortModeLabelForMode(sortMode)
    }

    function sortModeLabelForMode(mode) {
        var options = sortOptions()
        for (var i = 0; i < options.length; ++i) {
            if (options[i].value === mode) {
                return options[i].label
            }
        }
        return i18n.tr("Due date")
    }

    function sortModeLabelForCalendar(calendarHref) {
        return sortModeLabelForMode(sortModeForCalendar(calendarHref))
    }

    function setSortMode(mode) {
        var value = mode || "due"
        sortSettings.sortMode = value
        sortMode = value
        var updated = sortModeByScope || {}
        var scopes = visibleSortScopes()
        for (var i = 0; i < scopes.length; ++i) {
            updated[scopes[i]] = value
        }
        sortModeByScope = updated
        sortSettings.sortModeByScopeJson = JSON.stringify(updated)
        applyCurrentViewFilter()
    }

    function setSortModeForCalendar(calendarHref, mode) {
        var href = String(calendarHref || "")
        if (href.length === 0) {
            setSortMode(mode)
            return
        }
        var value = mode || "due"
        var updated = sortModeByScope || {}
        updated[sortScopeForCalendar(href)] = value
        sortModeByScope = updated
        sortSettings.sortModeByScopeJson = JSON.stringify(updated)
        if (viewMode === "calendarTasks" && sameCalendarHref(selectedCalendarHref, href)) {
            sortMode = value
        }
        applyCurrentViewFilter()
    }

    function toggleSortAscending() {
        sortSettings.sortAscending = !sortSettings.sortAscending
        sortAscending = sortSettings.sortAscending
        applyCurrentViewFilter()
    }

    function menuItemSelected(item) {
        if (!item) return false
        if (item.type === "myTasks") return viewMode === "myTasks"
        if (item.type === "calendarList") return viewMode === "calendarList"
        if (item.type === "calendar") return viewMode === "calendarTasks" && item.href === selectedCalendarHref
        return false
    }

    function activateMenuItem(item) {
        if (!item) return
        if (item.type === "myTasks") {
            showMyTasks()
        } else if (item.type === "calendarList") {
            showCalendarList()
        } else if (item.type === "calendar") {
            openCalendar(item.href, item.title)
        }
    }

    function loadMyTasksFromCalendars(sourceCalendars) {
        pendingCalendars = sourceCalendars || []
        pendingTasks = []
        pendingCalendarIndex = 0
        allTasks = []
        entries = []
        menuRevision += 1
        console.log(
            "NextTasks Controller loadMyTasksFromCalendars"
            + " generation=" + accountRequestGeneration
            + " accountId=" + accountSettings.accountId
            + " calendars=" + pendingCalendars.length
        )
        if (pendingCalendars.length === 0) {
            entries = []
            loading = false
            statusText = i18n.tr("No lists found.")
            markUpToDateIfClean()
            return
        }
        loadNextPendingCalendar()
    }

    function loadNextPendingCalendar() {
        if (pendingCalendarIndex >= pendingCalendars.length) {
            allTasks = tasksForKnownCalendars(tasksCache.loadAllTasks(), calendars)
            menuRevision += 1
            entries = visibleTasks(allTasks, true)
            console.log(
                "NextTasks Controller finished task load"
                + " generation=" + accountRequestGeneration
                + " accountId=" + accountSettings.accountId
                + " allTasks=" + allTasks.length
                + " entries=" + entries.length
            )
            viewMode = "myTasks"
            titleText = i18n.tr("My Tasks")
            loading = false
            runQueuedDirtySyncIfReady()
            if (dirtySyncRunning) return
            statusText = entries.length > 0 ? i18n.tr("Loaded %1 task(s).").arg(entries.length) : i18n.tr("No tasks found.")
            markUpToDateIfClean()
            return
        }

        var calendar = pendingCalendars[pendingCalendarIndex]
        pendingCalendarIndex += 1
        console.log(
            "NextTasks Controller loading calendar tasks"
            + " generation=" + accountRequestGeneration
            + " accountId=" + accountSettings.accountId
            + " calendarOwner=" + hrefOwnerFingerprint(calendar.href)
            + " index=" + pendingCalendarIndex
            + "/" + pendingCalendars.length
        )
        api.loadTasks(currentServerUrl, currentUserName, currentSecret, calendar.href, calendar.title)
    }

    function requestRemoteRefresh() {
        if (!forceFullRefresh && viewMode === "calendarTasks" && selectedCalendarHref.length > 0) {
            api.loadTasks(currentServerUrl, currentUserName, currentSecret, selectedCalendarHref, selectedCalendarTitle)
        } else {
            forceFullRefresh = false
            api.loadCalendars(currentServerUrl, currentUserName, currentSecret)
        }
    }

    function loadCachedState() {
        tasksCache.setScope(accountKey())
        calendars = tasksCache.loadCalendars()
        allTasks = tasksForKnownCalendars(tasksCache.loadAllTasks(), calendars)
        console.log(
            "NextTasks Controller cached state"
            + " accountId=" + accountSettings.accountId
            + " calendars=" + calendars.length
            + " allTasks=" + allTasks.length
            + " scopeHash=" + stableHash(accountKey())
        )
        sortMode = currentSortMode()
        sortAscending = sortSettings.sortAscending
        menuRevision += 1
        if (viewMode === "calendarList") {
            entries = calendars
            titleText = i18n.tr("Lists")
        } else if (viewMode === "calendarTasks" && selectedCalendarHref.length > 0) {
            entries = visibleTasks(tasksCache.loadTasksForCalendar(selectedCalendarHref), true)
            titleText = selectedCalendarTitle || i18n.tr("Tasks")
        } else {
            entries = visibleTasks(allTasks, true)
            titleText = i18n.tr("My Tasks")
        }
        if (entries.length > 0) {
            statusText = i18n.tr("Loaded cached tasks. Refreshing...")
        }
        updateDirtySummary()
        updateConflictSummary()
    }

    function startDirtySync(refreshAfter) {
        if (dirtySyncRunning) {
            return
        }
        if (userSyncPaused) {
            dirtySyncQueuedAfterInteraction = true
            return
        }
        if (loading) {
            dirtySyncQueuedAfterLoading = true
            return
        }
        dirtySyncQueue = syncableLocalChanges(tasksCache.loadLocalChanges())
        console.log("NextTasks Controller startDirtySync queue=" + dirtySyncQueue.length)
        if (dirtySyncQueue.length === 0) {
            var pendingLocalChanges = tasksCache.loadLocalChanges()
            if (pendingLocalChanges.length > 0) {
                statusText = i18n.tr("New task waiting for a title before sync.")
                syncStateText = i18n.tr("Waiting to sync")
                syncStateColor = "#b37a2a"
            }
            return
        }
        dirtySyncTotal = dirtySyncQueue.length
        dirtySyncUploadedCount = 0
        dirtySyncFailedCount = 0
        dirtySyncConflictCount = 0
        dirtySyncRunning = true
        dirtySyncAfterRefresh = refreshAfter === true
        loading = true
        statusText = i18n.tr("Syncing local changes...")
        syncStateText = i18n.tr("Syncing")
        syncStateColor = "#2c7fb8"
        session.setAccount(accountSettings.accountId, accountSettings.providerId, accountSettings.serviceId, accountSettings.serverUrl)
        api.requestGeneration = accountRequestGeneration
        session.authenticate()
    }

    function runQueuedDirtySyncIfReady() {
        if (!dirtySyncQueuedAfterLoading || loading || dirtySyncRunning) {
            return
        }
        dirtySyncQueuedAfterLoading = false
        startDirtySync(false)
    }

    function pauseUserSync() {
        userSyncPaused = true
        autoDirtySyncTimer.stop()
    }

    function resumeUserSync() {
        if (!userSyncPaused) {
            return
        }
        userSyncPaused = false
        if (dirtySyncQueuedAfterInteraction) {
            dirtySyncQueuedAfterInteraction = false
            scheduleDirtyAutoSync()
        }
    }

    function startNextDirtySync() {
        if (!dirtySyncRunning) {
            return
        }
        if (dirtySyncQueue.length === 0) {
            finishDirtySync()
            return
        }
        pendingUpdateTask = dirtySyncQueue[0]
        pendingUpdateChanges = taskToChanges(pendingUpdateTask)
        taskUpdateRunning = true
        console.log("NextTasks Controller startNextDirtySync localStatus=" + String(pendingUpdateTask.localStatus || "") + " isNew=" + (pendingUpdateTask.isNew === true ? "true" : "false") + " deleted=" + (pendingUpdateTask.deleted === true ? "true" : "false"))
        statusText = i18n.tr("Uploading task %1 of %2...").arg(dirtySyncTotal - dirtySyncQueue.length + 1).arg(dirtySyncTotal)
        if (pendingUpdateTask.localStatus === tasksCache.statusCreated || pendingUpdateTask.isNew) {
            api.createTask(currentServerUrl, currentUserName, currentSecret, pendingUpdateTask, pendingUpdateChanges)
        } else if (pendingUpdateTask.localStatus === tasksCache.statusDeleted || pendingUpdateTask.deleted) {
            api.deleteTask(currentServerUrl, currentUserName, currentSecret, pendingUpdateTask)
        } else {
            api.updateTask(currentServerUrl, currentUserName, currentSecret, pendingUpdateTask, pendingUpdateChanges)
        }
    }

    function handleDirtyWriteFailure(message, generation) {
        if (!isCurrentApiGeneration(generation)) {
            console.log("NextTasks Controller ignored stale dirty write failure generation=" + generation)
            return
        }
        taskUpdateRunning = false
        pendingUpdateTask = ({})
        pendingUpdateChanges = ({})
        pendingCalendarTitle = ""
        pendingCalendarOperation = ""
        pendingCalendar = ({})
        pendingCalendarColor = ""
        if (dirtySyncRunning) {
            if (isConflictMessage(message)) {
                tasksCache.markConflict(dirtySyncQueue.length > 0 ? dirtySyncQueue[0] : null)
                dirtySyncConflictCount += 1
            } else {
                dirtySyncFailedCount += 1
            }
            dirtySyncQueue.shift()
            startNextDirtySync()
        } else {
            loading = false
            statusText = message
            syncStateText = i18n.tr("Sync failed")
            syncStateColor = "#b37a2a"
        }
    }

    function keepLocalTaskAfterConflict(task) {
        if (!task || !task.conflict) return
        tasksCache.keepLocalTaskAfterConflict(task)
        var cachedTask = tasksCache.loadTask(task)
        if (cachedTask) {
            upsertTask(cachedTask)
        }
        applyCurrentViewFilter()
        statusText = i18n.tr("Local version kept. It will be uploaded on the next sync.")
        syncStateText = i18n.tr("Waiting to sync")
        syncStateColor = "#b37a2a"
        startDirtySync(false)
    }

    function discardLocalTaskAndUseServer(task) {
        if (!task || !task.conflict) return
        var serverTask = serverConflictTask(task)
        if (!serverTask) {
            statusText = i18n.tr("Server version is not available. Refresh and try again.")
            return
        }
        tasksCache.discardLocalTaskAndUseServer(task, serverTask)
        var cachedTask = tasksCache.loadTask(task)
        if (cachedTask) {
            upsertTask(cachedTask)
        }
        applyCurrentViewFilter()
        statusText = i18n.tr("Using server version.")
        markUpToDateIfClean()
    }

    function isConflictMessage(message) {
        var text = String(message || "")
        return text.indexOf(i18n.tr("Server version changed")) >= 0
            || text.indexOf("already exists") >= 0
            || text.indexOf("HTTP 404") >= 0
            || text.indexOf("HTTP 409") >= 0
            || text.indexOf("HTTP 412") >= 0
    }

    function finishDirtySync() {
        var hadFailures = dirtySyncFailedCount > 0 || dirtySyncConflictCount > 0
        var shouldRefresh = dirtySyncAfterRefresh && !hadFailures
        dirtySyncRunning = false
        dirtySyncAfterRefresh = false
        taskUpdateRunning = false
        pendingUpdateTask = ({})
        pendingUpdateChanges = ({})
        pendingCalendarTitle = ""
        pendingCalendarOperation = ""
        pendingCalendar = ({})
        pendingCalendarColor = ""
        dirtySyncQueue = []
        loadCachedState()
        var remainingLocalChanges = syncableLocalChanges(tasksCache.loadLocalChanges())
        if (!hadFailures && remainingLocalChanges.length > 0) {
            loading = false
            statusText = i18n.tr("Local changes waiting to sync.")
            syncStateText = i18n.tr("Waiting to sync")
            syncStateColor = "#b37a2a"
            startDirtySync(false)
            return
        }
        if (shouldRefresh) {
            statusText = i18n.tr("Local changes uploaded. Refreshing...")
            requestRemoteRefresh()
            return
        }
        loading = false
        runQueuedDirtySyncIfReady()
        if (dirtySyncRunning) {
            return
        }
        if (hadFailures) {
            statusText = i18n.tr("Sync finished with %1 failed and %2 conflicts. Local changes were kept.").arg(dirtySyncFailedCount).arg(dirtySyncConflictCount)
            syncStateText = i18n.tr("Sync failed")
            syncStateColor = "#b37a2a"
        } else {
            statusText = dirtySyncUploadedCount > 0 ? i18n.tr("%1 local task changes uploaded.").arg(dirtySyncUploadedCount) : i18n.tr("Up to date")
            markUpToDateIfClean()
        }
    }

    function syncableLocalChanges(tasks) {
        var result = []
        var source = tasks || []
        for (var i = 0; i < source.length; ++i) {
            var task = source[i]
            var isNewTask = task && (task.localStatus === tasksCache.statusCreated || task.isNew === true)
            if (isNewTask && String(task.title || "").trim().length === 0) {
                continue
            }
            result.push(task)
        }
        return result
    }

    function decorateTasks(tasks, calendarTitle, calendarHref) {
        var result = []
        for (var i = 0; i < tasks.length; ++i) {
            var task = tasks[i]
            task.calendarTitle = calendarTitle || ""
            task.calendarHref = calendarHref || ""
            result.push(task)
        }
        return result
    }

    function tasksForKnownCalendars(tasks, sourceCalendars) {
        var source = tasks || []
        var known = {}
        var calendarSource = sourceCalendars || []
        for (var i = 0; i < calendarSource.length; ++i) {
            var calendarHref = normalizedCalendarHref(calendarSource[i] && calendarSource[i].href ? calendarSource[i].href : "")
            if (calendarHref.length > 0) {
                known[calendarHref] = true
            }
        }
        if (Object.keys(known).length === 0) {
            return source
        }
        var result = []
        for (var j = 0; j < source.length; ++j) {
            var task = source[j]
            if (!task || task.type !== "task") {
                continue
            }
            var taskCalendarHref = normalizedCalendarHref(task.calendarHref || calendarHrefForTask(task))
            if (taskCalendarHref.length > 0 && known[taskCalendarHref] === true) {
                result.push(task)
            }
        }
        return result
    }

    function applyLocalTaskIdentity(target, source) {
        if (!target || !source) return
        target.localModified = Number(source.localModified || 0)
        target.calendarHref = source.calendarHref || target.calendarHref || ""
        target.calendarTitle = source.calendarTitle || target.calendarTitle || ""
        target.uid = target.uid || source.uid || ""
        target.href = target.href || source.href || ""
    }

    function replaceCalendarTasks(calendarHref, tasks) {
        var href = normalizedCalendarHref(calendarHref)
        var result = []
        for (var i = 0; i < allTasks.length; ++i) {
            if (normalizedCalendarHref(allTasks[i].calendarHref || calendarHrefForTask(allTasks[i])) !== href) {
                result.push(allTasks[i])
            }
        }
        var incoming = tasks || []
        for (var j = 0; j < incoming.length; ++j) {
            result.push(incoming[j])
        }
        allTasks = result
        menuRevision += 1
    }

    function upsertTask(task) {
        if (!task || task.type !== "task") {
            return
        }
        var key = taskKey(task)
        var updatedAll = []
        var replaced = false
        for (var i = 0; i < allTasks.length; ++i) {
            if (taskKey(allTasks[i]) === key) {
                updatedAll.push(task)
                replaced = true
            } else {
                updatedAll.push(allTasks[i])
            }
        }
        if (!replaced) {
            updatedAll.push(task)
        }
        allTasks = updatedAll
        menuRevision += 1

        var updatedEntries = []
        var entryReplaced = false
        for (var j = 0; j < entries.length; ++j) {
            if (taskKey(entries[j]) === key) {
                updatedEntries.push(task)
                entryReplaced = true
            } else {
                updatedEntries.push(entries[j])
            }
        }
        if (!entryReplaced && viewMode !== "calendarList") {
            updatedEntries.push(task)
        }
        entries = updatedEntries
    }

    function removeTask(task) {
        var key = taskKey(task)
        var updatedAll = []
        for (var i = 0; i < allTasks.length; ++i) {
            if (taskKey(allTasks[i]) !== key) {
                updatedAll.push(allTasks[i])
            }
        }
        allTasks = updatedAll
        menuRevision += 1

        var updatedEntries = []
        for (var j = 0; j < entries.length; ++j) {
            if (taskKey(entries[j]) !== key) {
                updatedEntries.push(entries[j])
            }
        }
        entries = updatedEntries
    }

    function taskByKey(task) {
        var key = taskKey(task)
        if (key.length === 0) return null
        for (var i = 0; i < allTasks.length; ++i) {
            if (taskKey(allTasks[i]) === key) {
                return allTasks[i]
            }
        }
        return tasksCache.loadTask(task)
    }

    function mergeTaskChanges(source, changes) {
        var result = {}
        for (var key in source) {
            result[key] = source[key]
        }
        var wasNew = source.isNew === true || source.localStatus === tasksCache.statusCreated
        result.title = String(changes.title || "")
        result.status = normalizeStatusText(changes.status, changes.completed)
        result.completed = result.status === "COMPLETED"
        result.cancelled = result.status === "CANCELLED"
        result.startText = normalizeDateText(changes.start)
        result.start = normalizeDateCompact(changes.start)
        result.dueText = normalizeDateText(changes.due)
        result.due = normalizeDateCompact(changes.due)
        result.priority = normalizePriorityText(changes.priority)
        result.priorityText = formatPriorityText(result.priority)
        result.percentComplete = normalizePercentText(changes.percentComplete)
        result.location = String(changes.location || "")
        result.url = String(changes.url || "")
        result.tags = String(changes.tags || "")
        result.description = String(changes.description || "")
        result.sortOrder = Number(changes.sortOrder || source.sortOrder || 0)
        result.subtitle = statusSubtitle(result.status, result.completed)
        result.detail = result.dueText.length > 0 ? i18n.tr("Due %1").arg(result.dueText) : ""
        result.localStatus = wasNew ? tasksCache.statusCreated : tasksCache.statusEdited
        result.dirty = true
        result.isNew = wasNew
        result.deleted = false
        result.conflict = false
        result.localModified = Date.now()
        return result
    }

    function taskToChanges(task) {
        return {
            "title": task.title || "",
            "status": task.status || (task.completed ? "COMPLETED" : "NEEDS-ACTION"),
            "completed": task.completed === true,
            "start": task.startText || task.start || "",
            "due": task.dueText || task.due || "",
            "priority": task.priority || "",
            "percentComplete": task.percentComplete || (task.completed ? "100" : "0"),
            "location": task.location || "",
            "url": task.url || "",
            "tags": task.tags || "",
            "description": task.description || "",
            "sortOrder": Number(task.sortOrder || 0)
        }
    }

    function visibleTasks(tasks, topLevelOnly) {
        var result = []
        for (var i = 0; i < tasks.length; ++i) {
            var task = tasks[i]
            if (task.deleted) continue
            if (task.completed && !showCompletedTasks) continue
            if (topLevelOnly && String(task.parentUid || "").length > 0) continue
            result.push(task)
        }
        result.sort(compareTasks)
        return result
    }

    function compareTasks(a, b) {
        return compareTasksWithMode(a, b, sortMode, sortAscending)
    }

    function compareTasksWithMode(a, b, mode, ascending) {
        var value = 0
        if (mode === "manual") {
            value = compareManualOrder(a, b)
        } else if (mode === "alpha") {
            value = compareText(a.title, b.title)
        } else if (mode === "priority") {
            value = comparePriority(a.priority, b.priority)
        } else if (mode === "modified") {
            value = compareDate(b.lastModified, a.lastModified)
        } else if (mode === "created") {
            value = compareDate(b.created, a.created)
        } else if (mode === "start") {
            value = compareDateWithEmptyLast(a.start, b.start)
        } else if (mode === "list") {
            value = compareText(a.calendarTitle, b.calendarTitle)
        } else {
            value = compareDateWithEmptyLast(a.due, b.due)
        }
        if (!ascending && mode !== "modified" && mode !== "created" && mode !== "manual") {
            value = -value
        }
        if (value !== 0) return value
        return compareText(a.title, b.title)
    }

    function sortedTasksForCalendar(tasks, calendarHref) {
        var result = (tasks || []).slice()
        var mode = sortModeForCalendar(calendarHref)
        result.sort(function(a, b) {
            return compareTasksWithMode(a, b, mode, sortAscending)
        })
        return result
    }

    function compareText(a, b) {
        return String(a || "").toLowerCase().localeCompare(String(b || "").toLowerCase())
    }

    function comparePriority(a, b) {
        var priorityA = parseInt(a || "0", 10)
        var priorityB = parseInt(b || "0", 10)
        if (!priorityA) priorityA = 99
        if (!priorityB) priorityB = 99
        return priorityA - priorityB
    }

    function compareDate(a, b) {
        return String(a || "").localeCompare(String(b || ""))
    }

    function compareDateWithEmptyLast(a, b) {
        var valueA = String(a || "")
        var valueB = String(b || "")
        if (valueA.length === 0 && valueB.length > 0) return 1
        if (valueA.length > 0 && valueB.length === 0) return -1
        return valueA.localeCompare(valueB)
    }

    function taskKey(task) {
        return String(task.href || task.uid || task.title || "")
    }

    function compareManualOrder(a, b) {
        var orderA = Number(a.sortOrder || 0)
        var orderB = Number(b.sortOrder || 0)
        if (orderA > 0 && orderB > 0 && orderA !== orderB) return orderA - orderB
        if (orderA > 0 && orderB <= 0) return -1
        if (orderA <= 0 && orderB > 0) return 1
        return compareDateWithEmptyLast(a.due, b.due) || compareText(a.title, b.title)
    }

    function moveManualTask(task, direction) {
        if (!task || task.type !== "task") return
        var current = manualReorderSource(task)
        var key = taskKey(task)
        var index = -1
        for (var i = 0; i < current.length; ++i) {
            if (taskKey(current[i]) === key) {
                index = i
                break
            }
        }
        var target = index + direction
        if (index < 0 || target < 0 || target >= current.length) {
            return
        }
        reorderManualTask(task, target)
    }

    function reorderManualTask(task, targetIndex) {
        if (!task || task.type !== "task") return
        if (sortMode !== "manual") {
            setSortMode("manual")
        }
        var current = manualReorderSource(task)
        var key = taskKey(task)
        var index = -1
        for (var i = 0; i < current.length; ++i) {
            if (taskKey(current[i]) === key) {
                index = i
                break
            }
        }
        if (index < 0) return
        var target = Math.max(0, Math.min(targetIndex, current.length - 1))
        if (index === target) return
        var moved = current.splice(index, 1)[0]
        current.splice(target, 0, moved)
        applyManualOrderForList(current, moved)
    }

    function manualReorderSource(task) {
        var calendarHref = String(task && task.calendarHref ? task.calendarHref : selectedCalendarHref)
        var source = tasksForCurrentScope()
        var result = []
        for (var i = 0; i < source.length; ++i) {
            var candidate = source[i]
            if (candidate && candidate.type === "task" && !candidate.completed && !candidate.deleted && String(candidate.calendarHref || "") === calendarHref) {
                result.push(candidate)
            }
        }
        return visibleTasks(result, true)
    }

    function applyManualOrderForList(orderedTasks, movedTask) {
        var targetIndex = -1
        for (var i = 0; i < orderedTasks.length; ++i) {
            if (taskKey(orderedTasks[i]) === taskKey(movedTask)) {
                targetIndex = i
                break
            }
        }
        if (targetIndex < 0) return
        var previous = targetIndex > 0 ? orderedTasks[targetIndex - 1] : null
        var next = targetIndex < orderedTasks.length - 1 ? orderedTasks[targetIndex + 1] : null
        var previousOrder = previous ? Number(previous.sortOrder || 0) : 0
        var nextOrder = next ? Number(next.sortOrder || 0) : 0
        var newOrder = 0
        if (previous && next && previousOrder > 0 && nextOrder > 0 && nextOrder - previousOrder > 1) {
            newOrder = Math.floor((previousOrder + nextOrder) / 2)
        } else if (!previous && next && nextOrder > 1000) {
            newOrder = nextOrder - 1000
        } else if (previous && !next && previousOrder > 0) {
            newOrder = previousOrder + 1000
        }
        if (newOrder > 0) {
            saveSortOrderDraft(movedTask, newOrder)
        } else {
            for (var j = 0; j < orderedTasks.length; ++j) {
                saveSortOrderDraft(orderedTasks[j], (j + 1) * 1000)
            }
        }
        applyCurrentViewFilter()
        statusText = i18n.tr("Manual order updated.")
        syncStateText = i18n.tr("Waiting to sync")
        syncStateColor = "#b37a2a"
        scheduleDirtyAutoSync()
    }

    function saveSortOrderDraft(task, sortOrder) {
        if (Number(task.sortOrder || 0) === Number(sortOrder || 0)) return
        var updated = {}
        for (var key in task) {
            updated[key] = task[key]
        }
        updated.sortOrder = Number(sortOrder || 0)
        updated.localStatus = updated.isNew === true ? tasksCache.statusCreated : tasksCache.statusEdited
        updated.dirty = true
        updated.localModified = Date.now()
        upsertTask(updated)
        tasksCache.saveLocalDraft(updated)
    }

    function parseJsonMap(text) {
        try {
            var parsed = JSON.parse(String(text || "{}"))
            return parsed || {}
        } catch (e) {
            return {}
        }
    }

    function applyCurrentViewFilter() {
        sortMode = currentSortMode()
        sortAscending = sortSettings.sortAscending
        if (viewMode === "calendarTasks") {
            entries = visibleTasks(tasksForCurrentScope(), true)
        } else if (viewMode === "myTasks") {
            entries = visibleTasks(allTasks, true)
        }
        updateDirtySummary()
        updateConflictSummary()
    }

    function currentSortScope() {
        if (viewMode === "calendarTasks" && selectedCalendarHref.length > 0) {
            return sortScopeForCalendar(selectedCalendarHref)
        }
        return accountKey() + "|myTasks"
    }

    function sortScopeForCalendar(calendarHref) {
        return accountKey() + "|" + String(calendarHref || "")
    }

    function currentSortMode() {
        var key = currentSortScope()
        if (sortModeByScope && sortModeByScope[key]) {
            return sortModeByScope[key]
        }
        if (viewMode === "calendarTasks" && selectedCalendarHref.length > 0) {
            return "due"
        }
        return sortSettings.sortMode
    }

    function sortModeForCalendar(calendarHref) {
        var key = sortScopeForCalendar(calendarHref)
        if (sortModeByScope && sortModeByScope[key]) {
            return sortModeByScope[key]
        }
        return "due"
    }

    function visibleSortCalendars() {
        var result = []
        for (var i = 0; i < calendars.length; ++i) {
            if (String(calendars[i].href || "").length > 0) {
                result.push(calendars[i])
            }
        }
        return result
    }

    function visibleSortScopes() {
        if (viewMode === "calendarTasks" && selectedCalendarHref.length > 0) {
            return [currentSortScope()]
        }
        var result = []
        for (var i = 0; i < calendars.length; ++i) {
            if (String(calendars[i].href || "").length > 0) {
                result.push(accountKey() + "|" + calendars[i].href)
            }
        }
        result.push(accountKey() + "|myTasks")
        return result
    }

    function updateDirtySummary() {
        dirtyTasksCount = tasksCache.loadLocalChanges().length
    }

    function updateConflictSummary() {
        var count = 0
        for (var i = 0; i < allTasks.length; ++i) {
            if (allTasks[i] && allTasks[i].conflict === true) {
                count += 1
            }
        }
        conflictTasksCount = count
    }

    function refreshMenuCounts() {
        menuRevision += 1
    }

    function markUpToDateIfClean() {
        updateDirtySummary()
        if (dirtyTasksCount > 0) {
            syncStateText = i18n.tr("Waiting to sync")
            syncStateColor = "#b37a2a"
        } else {
            syncStateText = i18n.tr("Up to date")
            syncStateColor = "#5a8f3c"
        }
    }

    function firstConflictTask() {
        for (var i = 0; i < allTasks.length; ++i) {
            if (allTasks[i] && allTasks[i].conflict === true) {
                return allTasks[i]
            }
        }
        return null
    }

    function serverConflictTask(task) {
        if (!task || !task.rawTodo || String(task.rawTodo).length === 0) {
            return null
        }
        var parsed = api.parseTodo(task.rawTodo, task.href || "", task.conflictEtag || task.etag || "")
        parsed.calendarHref = task.calendarHref || ""
        parsed.calendarTitle = task.calendarTitle || ""
        return parsed
    }

    function conflictPreviewText(task, version) {
        var source = version === "server" ? serverConflictTask(task) : task
        if (!source) {
            return i18n.tr("Server version is not available.")
        }
        var parts = []
        parts.push(source.title || i18n.tr("Untitled task"))
        parts.push(i18n.tr("Status: %1").arg(statusSubtitle(source.status, source.completed)))
        if (String(source.dueText || "").length > 0) parts.push(i18n.tr("Due: %1").arg(source.dueText))
        if (String(source.startText || "").length > 0) parts.push(i18n.tr("Start: %1").arg(source.startText))
        if (String(source.priorityText || "").length > 0) parts.push(i18n.tr("Priority: %1").arg(source.priorityText))
        if (String(source.percentComplete || "").length > 0) parts.push(i18n.tr("Progress: %1%").arg(source.percentComplete))
        if (String(source.tags || "").length > 0) parts.push(i18n.tr("Tags: %1").arg(source.tags))
        if (String(source.description || "").length > 0) {
            parts.push("")
            parts.push(source.description)
        }
        return parts.join("\n")
    }

    function tasksForCurrentScope() {
        if (viewMode === "calendarTasks" && selectedCalendarHref.length > 0) {
            var scoped = []
            for (var i = 0; i < allTasks.length; ++i) {
                if (sameCalendarHref(allTasks[i].calendarHref, selectedCalendarHref)) {
                    scoped.push(allTasks[i])
                }
            }
            return scoped
        }
        if (viewMode === "calendarList") {
            return []
        }
        return allTasks
    }

    function completedTasksForCurrentScope() {
        var source = tasksForCurrentScope()
        var result = []
        for (var i = 0; i < source.length; ++i) {
            var task = source[i]
            if (task && task.type === "task" && task.completed && !task.cancelled) {
                result.push(task)
            }
        }
        return result
    }

    function countTasksForCalendar(calendarHref) {
        var href = normalizedCalendarHref(calendarHref)
        var count = 0
        for (var i = 0; i < allTasks.length; ++i) {
            var task = allTasks[i]
            if (task && task.type === "task" && !task.deleted && !task.completed && sameCalendarHref(task.calendarHref, href)) {
                count += 1
            }
        }
        return count
    }

    function calendarHrefForTask(task) {
        if (!task) return ""
        var href = String(task.calendarHref || "")
        if (href.length > 0) return href
        var taskHref = String(task.href || "")
        if (taskHref.length === 0) return ""
        var clean = taskHref.replace(/[?#].*$/, "")
        var slash = clean.lastIndexOf("/")
        return slash >= 0 ? clean.substring(0, slash + 1) : ""
    }

    function normalizedCalendarHref(value) {
        var href = String(value || "").trim()
        if (href.length === 0) return ""
        try {
            href = decodeURIComponent(href)
        } catch (e) {
        }
        var marker = "/remote.php/dav/calendars/"
        var markerIndex = href.indexOf(marker)
        if (markerIndex >= 0) {
            href = href.slice(markerIndex)
        }
        href = href.replace(/[?#].*$/, "")
        href = href.replace(/\/+$/, "")
        return href.toLowerCase()
    }

    function hrefOwnerFingerprint(value) {
        var href = normalizedCalendarHref(value)
        var marker = "/remote.php/dav/calendars/"
        var index = href.indexOf(marker)
        if (index < 0) return "none"
        var rest = href.slice(index + marker.length)
        var slash = rest.indexOf("/")
        var owner = slash >= 0 ? rest.slice(0, slash) : rest
        return owner.length > 0 ? "h" + stableHash(owner) : "none"
    }

    function stableHash(value) {
        var text = String(value || "")
        var hash = 0
        for (var i = 0; i < text.length; ++i) {
            hash = ((hash << 5) - hash + text.charCodeAt(i)) & 0x7fffffff
        }
        return hash.toString(36)
    }

    function sameCalendarHref(left, right) {
        var a = normalizedCalendarHref(left)
        var b = normalizedCalendarHref(right)
        return a.length > 0 && b.length > 0 && a === b
    }

    function normalizedCalendarTitle(value) {
        return String(value || "").trim().toLowerCase()
    }

    function sameCalendarTitle(left, right) {
        var a = normalizedCalendarTitle(left)
        var b = normalizedCalendarTitle(right)
        return a.length > 0 && b.length > 0 && a === b
    }

    function toggleShowCompletedTasks() {
        showCompletedTasks = !showCompletedTasks
        if (viewMode === "calendarTasks") {
            entries = visibleTasks(tasksForCurrentScope(), true)
        } else if (viewMode === "myTasks") {
            entries = visibleTasks(allTasks, true)
        }
    }

    function isHiddenUntilFuture(value) {
        var text = String(value || "")
        if (text.length < 8) return false
        var now = new Date()
        var today = now.getFullYear() * 10000 + (now.getMonth() + 1) * 100 + now.getDate()
        var dateValue = parseInt(text.substring(0, 8), 10)
        return dateValue > today
    }

    function normalizeDateText(value) {
        var text = String(value || "").trim()
        if (text.length === 0) return ""
        var compact = text.replace(/-/g, "")
        if (/^\d{8}$/.test(compact)) {
            return compact.substring(0, 4) + "-" + compact.substring(4, 6) + "-" + compact.substring(6, 8)
        }
        return text
    }

    function normalizeDateCompact(value) {
        var text = String(value || "").trim().replace(/-/g, "")
        return /^\d{8}$/.test(text) ? text : ""
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

    function normalizeStatusText(value, completed) {
        var text = String(value || "").toUpperCase()
        if (text === "COMPLETED" || completed === true) return "COMPLETED"
        if (text === "IN-PROCESS") return "IN-PROCESS"
        if (text === "CANCELLED") return "CANCELLED"
        return "NEEDS-ACTION"
    }

    function statusSubtitle(status, completed) {
        if (completed) return i18n.tr("Completed")
        var text = String(status || "").toUpperCase()
        if (text === "IN-PROCESS") return i18n.tr("In progress")
        if (text === "CANCELLED") return i18n.tr("Canceled")
        return i18n.tr("Open task")
    }

    function formatPriorityText(value) {
        var priority = parseInt(value || "0", 10)
        if (!priority) return ""
        if (priority <= 4) return i18n.tr("High")
        if (priority === 5) return i18n.tr("Medium")
        return i18n.tr("Low")
    }

    function applyAccountSelection(accountId, displayName, providerId, serviceId, serverUrl, avatarUrl) {
        accountRequestGeneration += 1
        stopAccountActivity()
        applyingAccountSelection = true
        accountSettings.accountId = accountId
        accountSettings.displayName = displayName || ""
        accountSettings.providerId = providerId || ""
        accountSettings.serviceId = serviceId || ""
        accountSettings.serverUrl = serverUrl || ""
        accountSettings.avatarUrl = avatarUrl || ""
        applyingAccountSelection = false

        session.setAccount(accountId, providerId || "", serviceId || "", serverUrl || "")
        clearAccountData()
        forceFullRefresh = true
        activeAccountKey = accountKeyFor(accountId, providerId, serviceId, serverUrl)
        tasksCache.setScope(activeAccountKey)
        tasksCache.clearCleanServerDataForCurrentScope()
        skipNextCachedLoad = true
        refreshTimer.restart()
    }

    function handleAccountChanged() {
        if (applyingAccountSelection) {
            return
        }

        var key = accountKey()
        if (key === activeAccountKey) {
            return
        }

        accountRequestGeneration += 1
        stopAccountActivity()
        clearAccountData()
        forceFullRefresh = true
        activeAccountKey = key
        tasksCache.setScope(activeAccountKey)
        tasksCache.clearCleanServerDataForCurrentScope()
        skipNextCachedLoad = true
        if (accountSettings.accountId > 0 && accountSettings.serviceId.length > 0 && accountSettings.serverUrl.length > 0) {
            refreshTimer.restart()
        }
    }

    function stopAccountActivity() {
        refreshTimer.stop()
        autoDirtySyncTimer.stop()
        loading = false
        completionUpdateRunning = false
        taskUpdateRunning = false
        taskMoveRunning = false
        dirtySyncRunning = false
        dirtySyncAfterRefresh = false
        pendingCompletionTask = ({})
        pendingCompletionQueue = []
        pendingCompletionTotal = 0
        pendingUpdateTask = ({})
        pendingUpdateChanges = ({})
        pendingMoveQueue = []
        pendingMoveTargetCalendar = ({})
        pendingMoveTotal = 0
        pendingMoveMovedCount = 0
        pendingMoveFailedCount = 0
        pendingMoveSkippedCount = 0
        pendingCalendarTitle = ""
        pendingCalendarOperation = ""
        pendingCalendar = ({})
        pendingCalendarColor = ""
        pendingOpenCalendarTitle = ""
        dirtySyncQueue = []
        dirtySyncTotal = 0
        currentUserName = ""
        currentSecret = ""
        currentServerUrl = ""
        session.setAccount(accountSettings.accountId, accountSettings.providerId, accountSettings.serviceId, accountSettings.serverUrl)
        api.requestGeneration = accountRequestGeneration
    }

    function clearAccountData() {
        accountDataRevision += 1
        entries = []
        calendars = []
        allTasks = []
        pendingCalendars = []
        pendingTasks = []
        pendingCalendarIndex = 0
        completionUpdateRunning = false
        taskUpdateRunning = false
        taskMoveRunning = false
        dirtySyncRunning = false
        dirtySyncAfterRefresh = false
        pendingCompletionTask = ({})
        pendingCompletionQueue = []
        pendingCompletionTotal = 0
        pendingUpdateTask = ({})
        pendingUpdateChanges = ({})
        pendingMoveQueue = []
        pendingMoveTargetCalendar = ({})
        pendingMoveTotal = 0
        pendingMoveMovedCount = 0
        pendingMoveFailedCount = 0
        pendingMoveSkippedCount = 0
        pendingCalendarTitle = ""
        pendingCalendarOperation = ""
        pendingCalendar = ({})
        pendingCalendarColor = ""
        pendingOpenCalendarTitle = ""
        dirtySyncQueue = []
        dirtySyncTotal = 0
        conflictTasksCount = 0
        showCompletedTasks = false
        currentUserName = ""
        currentSecret = ""
        currentServerUrl = ""
        viewMode = "myTasks"
        titleText = i18n.tr("My Tasks")
        selectedCalendarHref = ""
        selectedCalendarTitle = ""
        accountAvatarUrl = accountSettings.avatarUrl || ""
        loading = false
        statusText = accountSettings.accountId > 0
            ? i18n.tr("Account changed. Refreshing...")
            : i18n.tr("Select an account to load tasks.")
        syncStateText = accountSettings.accountId > 0
            ? i18n.tr("Refreshing")
            : i18n.tr("No account")
        syncStateColor = "#b37a2a"
    }

    function accountKey() {
        return accountKeyFor(accountSettings.accountId, accountSettings.providerId, accountSettings.serviceId, accountSettings.serverUrl)
    }

    function accountKeyFor(accountId, providerId, serviceId, serverUrl) {
        return String(accountId)
            + "|" + String(providerId || "")
            + "|" + String(serviceId || "")
            + "|" + String(serverUrl || "")
    }

    function isCurrentAccountResponse(accountId, serviceId, serverUrl) {
        if (typeof desktopTestAuthEnabled !== "undefined" && desktopTestAuthEnabled
                && Number(accountId || 0) === -1
                && String(serviceId || "") === "desktop-test-env") {
            return true
        }
        return Number(accountId || 0) === Number(accountSettings.accountId || 0)
            && String(serviceId || "") === String(accountSettings.serviceId || "")
            && String(serverUrl || "").replace(/\/+$/, "") === String(accountSettings.serverUrl || "").replace(/\/+$/, "")
    }

    function isCurrentApiGeneration(generation) {
        return Number(generation || 0) === Number(accountRequestGeneration || 0)
    }

    function findCalendarByTitle(title) {
        var wanted = String(title || "").trim().toLowerCase()
        if (wanted.length === 0) {
            return null
        }
        for (var i = 0; i < calendars.length; ++i) {
            var calendar = calendars[i]
            if (String(calendar.title || "").trim().toLowerCase() === wanted) {
                return calendar
            }
        }
        return null
    }

    function avatarUrl(serverUrl, userName) {
        if (!serverUrl || !userName) return ""
        return String(serverUrl).replace(/\/+$/, "") + "/index.php/avatar/" + encodeURIComponent(userName) + "/64"
    }

    Timer {
        id: refreshTimer
        interval: 150
        repeat: false
        onTriggered: controller.refresh()
    }

    Component.onCompleted: {
        activeAccountKey = accountKey()
        session.setAccount(accountSettings.accountId, accountSettings.providerId, accountSettings.serviceId, accountSettings.serverUrl)
        refresh()
    }
}
