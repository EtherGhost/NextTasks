import QtQuick 2.7
import "AuthCore.js" as AuthCore

Item {
    id: api
    function debugLog() {}

    property int requestGeneration: 0
    property var pendingNativeCalendarLoads: ({})
    property var pendingNativeCompletion: ({})
    property var pendingNativeWrite: ({})
    property var pendingNativeDeleteTask: ({})
    property var pendingNativeFetches: ({})
    property var pendingNativeTrashLoads: ({})
    property var pendingNativeTrashRestores: ({})

    signal calendarsLoaded(var entries, int generation)
    signal tasksLoaded(string calendarTitle, string calendarHref, var entries, int generation)
    signal taskCompletionUpdated(bool completed, int generation)
    signal taskCompletionFailed(string message, int generation)
    signal taskUpdated(var task, int generation)
    signal taskUpdateFailed(string message, int generation)
    signal taskCreated(var task, int generation)
    signal taskCreateFailed(string message, int generation)
    signal taskDeleted(var task, int generation)
    signal taskDeleteFailed(string message, int generation)
    signal taskMoved(var sourceTask, var movedTask, int generation)
    signal taskMoveFailed(string message, int generation)
    signal taskConflict(var localTask, var serverTask, string message, int generation)
    signal calendarCreated(int generation)
    signal calendarCreateFailed(string message, int generation)
    signal calendarUpdated(int generation)
    signal calendarUpdateFailed(string message, int generation)
    signal calendarDeleted(int generation)
    signal calendarDeleteFailed(string message, int generation)
    signal trashLoaded(var items, string trashBinHref, int retentionSeconds, int generation)
    signal trashLoadFailed(string message, int generation)
    signal trashItemRestored(var item, int generation)
    signal trashItemRestoreFailed(string message, int generation)
    signal failed(string message, int generation)

    Connections {
        target: typeof calDavNetwork !== "undefined" ? calDavNetwork : null
        onCalendarCreated: api.calendarCreated(generation)
        onCalendarCreateFailed: api.calendarCreateFailed(message, generation)
        onCalendarUpdated: api.calendarUpdated(generation)
        onCalendarUpdateFailed: api.calendarUpdateFailed(message, generation)
        onCalendarDeleted: api.calendarDeleted(generation)
        onCalendarDeleteFailed: api.calendarDeleteFailed(message, generation)
        onTaskMoved: api.handleNativeTaskMoved(sourceHref, destinationHref, etag, generation)
        onTaskMoveFailed: api.taskMoveFailed(message, generation)
        onUserLookupLoaded: api.handleNativeUserLookupLoaded(responseText, generation)
        onUserLookupFailed: api.handleNativeUserLookupFailed(message, generation)
        onCalendarsLoaded: api.handleNativeCalendarsLoaded(responseText, calendarHomeHref, generation)
        onCalendarsLoadFailed: api.failed(message, generation)
        onTasksLoaded: api.handleNativeTasksLoaded(calendarTitle, calendarHref, responseText, generation)
        onTasksLoadFailed: api.failed(message, generation)
        onTaskPutFinished: api.handleNativeTaskPutFinished(kind, href, etag, status, generation)
        onTaskPutFailed: api.handleNativeTaskPutFailed(kind, message, generation)
        onTaskDeleteFinished: api.handleNativeTaskDeleteFinished(status, generation)
        onTaskDeleteFailed: api.taskDeleteFailed(message, generation)
        onTaskFetched: api.handleNativeTaskFetched(kind, responseText, status, generation)
        onTaskFetchFailed: api.handleNativeTaskFetchFailed(kind, message, generation)
        onTrashCollectionsLoaded: api.handleNativeTrashCollectionsLoaded(responseText, calendarHomeHref, generation)
        onTrashCollectionsLoadFailed: api.handleNativeTrashLoadFailed(message, generation)
        onTrashObjectsLoaded: api.handleNativeTrashObjectsLoaded(responseText, trashBinHref, generation)
        onTrashObjectsLoadFailed: api.handleNativeTrashLoadFailed(message, generation)
        onTrashItemRestored: api.handleNativeTrashItemRestored(trashItemHref, generation)
        onTrashItemRestoreFailed: api.handleNativeTrashItemRestoreFailed(message, generation)
    }

    function loadCalendars(serverUrl, userName, secret) {
        var generation = requestGeneration
        var base = AuthCore.normalizeServerUrl(serverUrl)
        if (base.length === 0 || userName.length === 0 || secret.length === 0) {
            failed(i18n.tr("Account credentials are incomplete."), generation)
            return
        }
        if (typeof calDavNetwork !== "undefined") {
            pendingNativeCalendarLoads[String(generation)] = {
                "base": base,
                "userName": userName,
                "secret": secret
            }
            debugLog("NextTasks TasksApi native user lookup generation=" + generation)
            calDavNetwork.lookupUser(generation, base, userName, secret)
            return
        }
        lookupNextcloudUserId(base, userName, secret, generation, function(userId) {
            if (String(userId || "").length > 0) {
                loadCalendarsFromHome(base, userName, secret, "/remote.php/dav/calendars/" + encodeURIComponent(userId) + "/", generation)
                return
            }
            discoverCalendarHome(base, userName, secret, generation, function(calendarHomeHref) {
                loadCalendarsFromHome(base, userName, secret, calendarHomeHref, generation)
            })
        })
    }

    function lookupNextcloudUserId(base, userName, secret, generation, callback) {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", authenticatedUrl(base + "/ocs/v2.php/cloud/user?format=json", userName))
        xhr.timeout = 10000
        xhr.setRequestHeader("Authorization", "Basic " + Qt.btoa(userName + ":" + secret))
        xhr.setRequestHeader("OCS-APIRequest", "true")
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status < 200 || xhr.status >= 300) {
                debugLog("NextTasks TasksApi user lookup failed httpStatus=" + xhr.status)
                callback("")
                return
            }
            var userId = ""
            try {
                var parsed = JSON.parse(xhr.responseText || "{}")
                userId = String(parsed && parsed.ocs && parsed.ocs.data && parsed.ocs.data.id ? parsed.ocs.data.id : "")
            } catch (e) {
                debugLog("NextTasks TasksApi user lookup JSON parse failed")
            }
            debugLog(
                "NextTasks TasksApi user lookup result"
                + " generation=" + generation
                + " userIdHash=" + AuthCore.stableHash(userId)
                + " accountUserHash=" + AuthCore.stableHash(userName)
            )
            callback(userId)
        }
        xhr.onerror = function() {
            debugLog("NextTasks TasksApi user lookup network error")
            callback("")
        }
        xhr.ontimeout = function() {
            debugLog("NextTasks TasksApi user lookup timeout")
            callback("")
        }
        xhr.send()
    }

    function loadCalendarsFromHome(base, userName, secret, calendarHomeHref, generation) {
        var home = String(calendarHomeHref || "")
        if (home.length === 0) {
            home = "/remote.php/dav/calendars/" + encodeURIComponent(userName) + "/"
        }
        if (home.charAt(0) !== "/" && home.indexOf("http") !== 0) {
            home = "/" + home
        }
        var url = authenticatedUrl(home.indexOf("http") === 0 ? home : base + home, userName)
        debugLog(
            "NextTasks TasksApi PROPFIND calendars"
            + " generation=" + generation
            + " serverUrlConfigured=" + AuthCore.hasValue(base)
            + " discoveredHome=" + AuthCore.hasValue(calendarHomeHref)
            + " homeOwner=" + hrefOwnerFingerprint(home)
        )
        var xhr = new XMLHttpRequest()
        xhr.open("PROPFIND", url)
        xhr.timeout = 15000
        xhr.setRequestHeader("Authorization", "Basic " + Qt.btoa(userName + ":" + secret))
        xhr.setRequestHeader("Depth", "1")
        xhr.setRequestHeader("Content-Type", "application/xml; charset=utf-8")
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status < 200 || xhr.status >= 300) {
                debugLog("NextTasks TasksApi PROPFIND calendars failed httpStatus=" + xhr.status)
                failed(i18n.tr("Tasks calendar request failed with HTTP %1.").arg(xhr.status), generation)
                return
            }
            var entries = parseCalendars(xhr.responseText, userName, home)
            debugLog(
                "NextTasks TasksApi PROPFIND calendars success"
                + " generation=" + generation
                + " entries=" + entries.length
                + " owners=" + calendarOwnerSummary(entries)
            )
            calendarsLoaded(entries, generation)
        }
        xhr.onerror = function() {
            debugLog("NextTasks TasksApi PROPFIND calendars network error")
            failed(i18n.tr("Tasks calendar request failed because the network request could not be completed."), generation)
        }
        xhr.ontimeout = function() {
            debugLog("NextTasks TasksApi PROPFIND calendars timeout")
            failed(i18n.tr("Tasks calendar request timed out."), generation)
        }
        xhr.send("<?xml version=\"1.0\"?><d:propfind xmlns:d=\"DAV:\" xmlns:cs=\"http://calendarserver.org/ns/\" xmlns:c=\"urn:ietf:params:xml:ns:caldav\" xmlns:x1=\"http://apple.com/ns/ical/\"><d:prop><d:displayname/><cs:getctag/><c:supported-calendar-component-set/><x1:calendar-color/><d:current-user-privilege-set/></d:prop></d:propfind>")
    }

    function discoverCalendarHome(base, userName, secret, generation, callback) {
        var fallback = function() {
            callback("")
        }
        var xhr = new XMLHttpRequest()
        xhr.open("PROPFIND", authenticatedUrl(base + "/remote.php/dav/", userName))
        xhr.timeout = 10000
        xhr.setRequestHeader("Authorization", "Basic " + Qt.btoa(userName + ":" + secret))
        xhr.setRequestHeader("Depth", "0")
        xhr.setRequestHeader("Content-Type", "application/xml; charset=utf-8")
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status < 200 || xhr.status >= 300) {
                debugLog("NextTasks TasksApi principal discovery failed httpStatus=" + xhr.status)
                fallback()
                return
            }
            var principalHref = nestedHref(xhr.responseText, "current-user-principal")
            if (principalHref.length === 0) {
                debugLog("NextTasks TasksApi principal discovery returned no principal")
                fallback()
                return
            }
            discoverCalendarHomeFromPrincipal(base, userName, secret, principalHref, generation, callback)
        }
        xhr.onerror = fallback
        xhr.ontimeout = fallback
        xhr.send("<?xml version=\"1.0\"?><d:propfind xmlns:d=\"DAV:\"><d:prop><d:current-user-principal/></d:prop></d:propfind>")
    }

    function discoverCalendarHomeFromPrincipal(base, userName, secret, principalHref, generation, callback) {
        var href = String(principalHref || "")
        var url = authenticatedUrl(href.indexOf("http") === 0 ? href : base + (href.charAt(0) === "/" ? href : "/" + href), userName)
        var xhr = new XMLHttpRequest()
        xhr.open("PROPFIND", url)
        xhr.timeout = 10000
        xhr.setRequestHeader("Authorization", "Basic " + Qt.btoa(userName + ":" + secret))
        xhr.setRequestHeader("Depth", "0")
        xhr.setRequestHeader("Content-Type", "application/xml; charset=utf-8")
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status < 200 || xhr.status >= 300) {
                debugLog("NextTasks TasksApi calendar-home discovery failed httpStatus=" + xhr.status)
                callback("")
                return
            }
            var calendarHomeHref = nestedHref(xhr.responseText, "calendar-home-set")
            debugLog(
                "NextTasks TasksApi calendar-home discovery result"
                + " generation=" + generation
                + " homeAvailable=" + AuthCore.hasValue(calendarHomeHref)
                + " principalOwner=" + hrefOwnerFingerprint(principalHref)
                + " homeOwner=" + hrefOwnerFingerprint(calendarHomeHref)
            )
            callback(calendarHomeHref)
        }
        xhr.onerror = function() { callback("") }
        xhr.ontimeout = function() { callback("") }
        xhr.send("<?xml version=\"1.0\"?><d:propfind xmlns:d=\"DAV:\" xmlns:c=\"urn:ietf:params:xml:ns:caldav\"><d:prop><c:calendar-home-set/></d:prop></d:propfind>")
    }

    function loadTasks(serverUrl, userName, secret, calendarHref, calendarTitle) {
        var generation = requestGeneration
        var base = AuthCore.normalizeServerUrl(serverUrl)
        if (base.length === 0 || userName.length === 0 || secret.length === 0 || String(calendarHref || "").length === 0) {
            failed(i18n.tr("Account credentials are incomplete."), generation)
            return
        }
        if (typeof calDavNetwork !== "undefined") {
            debugLog("NextTasks TasksApi native PROPFIND tasks serverUrlConfigured=" + AuthCore.hasValue(base))
            calDavNetwork.loadTasks(generation, base, userName, secret, calendarHref, calendarTitle || i18n.tr("Tasks"))
            return
        }
        var url = authenticatedUrl(calendarHref.indexOf("http") === 0 ? calendarHref : base + calendarHref, userName)
        debugLog("NextTasks TasksApi PROPFIND tasks serverUrlConfigured=" + AuthCore.hasValue(base))
        var xhr = new XMLHttpRequest()
        xhr.open("PROPFIND", url)
        xhr.timeout = 15000
        xhr.setRequestHeader("Authorization", "Basic " + Qt.btoa(userName + ":" + secret))
        xhr.setRequestHeader("Depth", "1")
        xhr.setRequestHeader("Content-Type", "application/xml; charset=utf-8")
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status < 200 || xhr.status >= 300) {
                debugLog("NextTasks TasksApi PROPFIND tasks failed httpStatus=" + xhr.status)
                failed(i18n.tr("Tasks request failed with HTTP %1.").arg(xhr.status), generation)
                return
            }
            var entries = parseTasks(xhr.responseText)
            debugLog("NextTasks TasksApi PROPFIND tasks success entries=" + entries.length)
            tasksLoaded(calendarTitle || i18n.tr("Tasks"), calendarHref || "", entries, generation)
        }
        xhr.onerror = function() {
            debugLog("NextTasks TasksApi PROPFIND tasks network error")
            failed(i18n.tr("Tasks request failed because the network request could not be completed."), generation)
        }
        xhr.ontimeout = function() {
            debugLog("NextTasks TasksApi PROPFIND tasks timeout")
            failed(i18n.tr("Tasks request timed out."), generation)
        }
        xhr.send("<?xml version=\"1.0\"?><d:propfind xmlns:d=\"DAV:\" xmlns:c=\"urn:ietf:params:xml:ns:caldav\"><d:prop><d:getetag/><c:calendar-data/></d:prop></d:propfind>")
    }

    function handleNativeUserLookupLoaded(responseText, generation) {
        var pending = pendingNativeCalendarLoads[String(generation)]
        var pendingTrash = pendingNativeTrashLoads[String(generation)]
        if (!pending) {
            if (pendingTrash) {
                handleNativeTrashUserLookupLoaded(responseText, generation)
                return
            }
            debugLog("NextTasks TasksApi ignored native user lookup for stale generation=" + generation)
            return
        }
        var userId = ""
        try {
            var parsed = JSON.parse(responseText || "{}")
            userId = String(parsed && parsed.ocs && parsed.ocs.data && parsed.ocs.data.id ? parsed.ocs.data.id : "")
        } catch (e) {
            debugLog("NextTasks TasksApi native user lookup JSON parse failed")
        }
        if (userId.length === 0) {
            userId = String(pending.userName || "")
        }
        var home = "/remote.php/dav/calendars/" + encodeURIComponent(userId) + "/"
        debugLog(
            "NextTasks TasksApi native user lookup result"
            + " generation=" + generation
            + " userIdHash=" + AuthCore.stableHash(userId)
            + " accountUserHash=" + AuthCore.stableHash(pending.userName)
        )
        debugLog(
            "NextTasks TasksApi native PROPFIND calendars"
            + " generation=" + generation
            + " serverUrlConfigured=" + AuthCore.hasValue(pending.base)
            + " homeOwner=" + hrefOwnerFingerprint(home)
        )
        calDavNetwork.loadCalendars(generation, pending.base, pending.userName, pending.secret, home)
    }

    function handleNativeUserLookupFailed(message, generation) {
        var pending = pendingNativeCalendarLoads[String(generation)]
        var pendingTrash = pendingNativeTrashLoads[String(generation)]
        if (!pending) {
            if (pendingTrash) {
                var trashHome = "/remote.php/dav/calendars/" + encodeURIComponent(pendingTrash.userName) + "/"
                debugLog("NextTasks TasksApi native trash user lookup failed; falling back to account username")
                calDavNetwork.loadTrashCollections(generation, pendingTrash.base, pendingTrash.userName, pendingTrash.secret, trashHome)
                return
            }
            failed(message, generation)
            return
        }
        var home = "/remote.php/dav/calendars/" + encodeURIComponent(pending.userName) + "/"
        debugLog("NextTasks TasksApi native user lookup failed; falling back to account username")
        calDavNetwork.loadCalendars(generation, pending.base, pending.userName, pending.secret, home)
    }

    function handleNativeCalendarsLoaded(responseText, calendarHomeHref, generation) {
        delete pendingNativeCalendarLoads[String(generation)]
        var entries = parseCalendars(responseText, "", calendarHomeHref)
        debugLog(
            "NextTasks TasksApi native PROPFIND calendars success"
            + " generation=" + generation
            + " entries=" + entries.length
            + " owners=" + calendarOwnerSummary(entries)
        )
        calendarsLoaded(entries, generation)
    }

    function handleNativeTasksLoaded(calendarTitle, calendarHref, responseText, generation) {
        var entries = parseTasks(responseText)
        debugLog("NextTasks TasksApi native PROPFIND tasks success entries=" + entries.length)
        tasksLoaded(calendarTitle || i18n.tr("Tasks"), calendarHref || "", entries, generation)
    }

    function loadTrash(serverUrl, userName, secret, calendarHomeHref) {
        var generation = requestGeneration
        var base = AuthCore.normalizeServerUrl(serverUrl)
        var home = String(calendarHomeHref || "")
        if (typeof calDavNetwork === "undefined") {
            trashLoadFailed(i18n.tr("Trash bin is not available."), generation)
            return
        }
        if (base.length === 0 || userName.length === 0 || secret.length === 0) {
            trashLoadFailed(i18n.tr("Trash bin request is incomplete."), generation)
            return
        }
        pendingNativeTrashLoads[String(generation)] = {
            "base": base,
            "userName": userName,
            "secret": secret,
            "collections": [],
            "trashBinHref": "",
            "retentionSeconds": 0
        }
        if (home.length === 0) {
            debugLog("NextTasks TasksApi native trash user lookup generation=" + generation)
            calDavNetwork.lookupUser(generation, base, userName, secret)
            return
        }
        debugLog("NextTasks TasksApi PROPFIND trash collections")
        calDavNetwork.loadTrashCollections(generation, base, userName, secret, home)
    }

    function handleNativeTrashUserLookupLoaded(responseText, generation) {
        var pending = pendingNativeTrashLoads[String(generation)]
        if (!pending) {
            return
        }
        var userId = ""
        try {
            var parsed = JSON.parse(responseText || "{}")
            userId = String(parsed && parsed.ocs && parsed.ocs.data && parsed.ocs.data.id ? parsed.ocs.data.id : "")
        } catch (e) {
            debugLog("NextTasks TasksApi native trash user lookup JSON parse failed")
        }
        if (userId.length === 0) {
            userId = String(pending.userName || "")
        }
        var home = "/remote.php/dav/calendars/" + encodeURIComponent(userId) + "/"
        debugLog(
            "NextTasks TasksApi native trash user lookup result"
            + " generation=" + generation
            + " userIdHash=" + AuthCore.stableHash(userId)
            + " accountUserHash=" + AuthCore.stableHash(pending.userName)
            + " homeOwner=" + hrefOwnerFingerprint(home)
        )
        calDavNetwork.loadTrashCollections(generation, pending.base, pending.userName, pending.secret, home)
    }

    function restoreTrashItem(serverUrl, userName, secret, item, trashBinHref) {
        var generation = requestGeneration
        var base = AuthCore.normalizeServerUrl(serverUrl)
        var href = String(item && item.href ? item.href : "")
        var bin = String(trashBinHref || "")
        if (typeof calDavNetwork === "undefined") {
            trashItemRestoreFailed(i18n.tr("Trash restore is not available."), generation)
            return
        }
        if (base.length === 0 || userName.length === 0 || secret.length === 0 || href.length === 0 || bin.length === 0) {
            trashItemRestoreFailed(i18n.tr("Trash restore request is incomplete."), generation)
            return
        }
        pendingNativeTrashRestores[String(generation)] = item || ({})
        debugLog("NextTasks TasksApi MOVE restore trash item type=" + String(item && item.type ? item.type : ""))
        calDavNetwork.restoreTrashItem(generation, base, userName, secret, href, bin)
    }

    function handleNativeTrashCollectionsLoaded(responseText, calendarHomeHref, generation) {
        var pending = pendingNativeTrashLoads[String(generation)]
        if (!pending) {
            return
        }
        var parsed = parseTrashCollections(responseText, calendarHomeHref)
        pending.collections = parsed.items
        pending.trashBinHref = parsed.trashBinHref.length > 0 ? parsed.trashBinHref : calendarHomeHref
        pending.retentionSeconds = parsed.retentionSeconds
        debugLog(
            "NextTasks TasksApi trash collections parsed"
            + " generation=" + generation
            + " deletedCalendars=" + pending.collections.length
            + " trashBinAvailable=" + AuthCore.hasValue(pending.trashBinHref)
            + " homeOwner=" + hrefOwnerFingerprint(calendarHomeHref)
        )
        if (pending.trashBinHref.length === 0) {
            delete pendingNativeTrashLoads[String(generation)]
            trashLoaded(pending.collections, "", pending.retentionSeconds, generation)
            return
        }
        debugLog("NextTasks TasksApi REPORT trash objects")
        calDavNetwork.loadTrashObjects(generation, pending.base, pending.userName, pending.secret, pending.trashBinHref)
    }

    function trashBinHrefForCalendarHome(calendarHomeHref) {
        var home = String(calendarHomeHref || "")
        if (home.length === 0) {
            return ""
        }
        if (!/\/trashbin\/?$/i.test(home)) {
            if (!home.endsWith("/")) {
                home += "/"
            }
            home += "trashbin/"
        }
        return home
    }

    function handleNativeTrashObjectsLoaded(responseText, trashBinHref, generation) {
        var pending = pendingNativeTrashLoads[String(generation)]
        if (!pending) {
            return
        }
        delete pendingNativeTrashLoads[String(generation)]
        var objects = parseTrashObjects(responseText)
        var combined = pending.collections.concat(objects)
        debugLog("NextTasks TasksApi trash loaded items=" + combined.length
                    + " deletedCalendars=" + pending.collections.length
                    + " deletedTasks=" + objects.length)
        trashLoaded(combined, trashBinHref || pending.trashBinHref, pending.retentionSeconds, generation)
    }

    function handleNativeTrashLoadFailed(message, generation) {
        delete pendingNativeTrashLoads[String(generation)]
        trashLoadFailed(message, generation)
    }

    function handleNativeTrashItemRestored(trashItemHref, generation) {
        var item = pendingNativeTrashRestores[String(generation)] || ({})
        delete pendingNativeTrashRestores[String(generation)]
        trashItemRestored(item, generation)
    }

    function handleNativeTrashItemRestoreFailed(message, generation) {
        delete pendingNativeTrashRestores[String(generation)]
        trashItemRestoreFailed(message, generation)
    }

    function createCalendar(serverUrl, userName, secret, title) {
        var generation = requestGeneration
        var displayName = String(title || "").trim()
        if (typeof calDavNetwork === "undefined") {
            calendarCreateFailed(i18n.tr("Task list creation is not available."), generation)
            return
        }
        if (AuthCore.normalizeServerUrl(serverUrl).length === 0 || userName.length === 0 || secret.length === 0 || displayName.length === 0) {
            calendarCreateFailed(i18n.tr("Task list name is required."), generation)
            return
        }
        debugLog("NextTasks TasksApi MKCOL calendar via native helper")
        calDavNetwork.createCalendar(generation, serverUrl, userName, secret, displayName)
    }

    function updateCalendar(serverUrl, userName, secret, calendarHref, title, color) {
        var generation = requestGeneration
        if (typeof calDavNetwork === "undefined") {
            calendarUpdateFailed(i18n.tr("Task list update is not available."), generation)
            return
        }
        if (AuthCore.normalizeServerUrl(serverUrl).length === 0 || userName.length === 0 || secret.length === 0 || String(calendarHref || "").length === 0 || String(title || "").trim().length === 0) {
            calendarUpdateFailed(i18n.tr("Task list name is required."), generation)
            return
        }
        debugLog("NextTasks TasksApi PROPPATCH calendar via native helper")
        calDavNetwork.updateCalendar(generation, serverUrl, userName, secret, calendarHref, String(title || "").trim(), String(color || ""))
    }

    function deleteCalendar(serverUrl, userName, secret, calendarHref) {
        var generation = requestGeneration
        if (typeof calDavNetwork === "undefined") {
            calendarDeleteFailed(i18n.tr("Task list deletion is not available."), generation)
            return
        }
        if (AuthCore.normalizeServerUrl(serverUrl).length === 0 || userName.length === 0 || secret.length === 0 || String(calendarHref || "").length === 0) {
            calendarDeleteFailed(i18n.tr("Task list delete request is incomplete."), generation)
            return
        }
        debugLog("NextTasks TasksApi DELETE calendar via native helper")
        calDavNetwork.deleteCalendar(generation, serverUrl, userName, secret, calendarHref)
    }

    function updateTaskCompletion(serverUrl, userName, secret, task, completed) {
        var generation = requestGeneration
        var base = AuthCore.normalizeServerUrl(serverUrl)
        var href = String(task && task.href ? task.href : "")
        var rawTodo = String(task && task.rawTodo ? task.rawTodo : "")
        if (base.length === 0 || userName.length === 0 || secret.length === 0 || href.length === 0 || rawTodo.length === 0) {
            taskCompletionFailed(i18n.tr("Task update data is incomplete."), generation)
            return
        }

        var body = wrapCalendar(updatedCompletionTodo(rawTodo, completed))
        if (typeof calDavNetwork !== "undefined") {
            pendingNativeCompletion = {
                "completed": completed
            }
            debugLog("NextTasks TasksApi native PUT task completion serverUrlConfigured=" + AuthCore.hasValue(base) + " completed=" + completed)
            calDavNetwork.putTask(generation, serverUrl, userName, secret, href, body, String(task.etag || ""), false, "completion")
            return
        }
        var url = authenticatedUrl(href.indexOf("http") === 0 ? href : base + href, userName)
        debugLog("NextTasks TasksApi PUT task completion serverUrlConfigured=" + AuthCore.hasValue(base) + " completed=" + completed)
        var xhr = new XMLHttpRequest()
        xhr.open("PUT", url)
        xhr.timeout = 15000
        xhr.setRequestHeader("Authorization", "Basic " + Qt.btoa(userName + ":" + secret))
        xhr.setRequestHeader("Content-Type", "text/calendar; charset=utf-8")
        if (String(task.etag || "").length > 0) {
            xhr.setRequestHeader("If-Match", task.etag)
        }
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status === 412) {
                debugLog("NextTasks TasksApi PUT task completion conflict")
                taskCompletionFailed(i18n.tr("Server version changed. Refresh tasks and try again."), generation)
                return
            }
            if (xhr.status < 200 || xhr.status >= 300) {
                debugLog("NextTasks TasksApi PUT task completion failed httpStatus=" + xhr.status)
                taskCompletionFailed(i18n.tr("Task update failed with HTTP %1.").arg(xhr.status), generation)
                return
            }
            debugLog("NextTasks TasksApi PUT task completion success")
            taskCompletionUpdated(completed, generation)
        }
        xhr.onerror = function() {
            debugLog("NextTasks TasksApi PUT task completion network error")
            taskCompletionFailed(i18n.tr("Task update failed because the network request could not be completed."), generation)
        }
        xhr.ontimeout = function() {
            debugLog("NextTasks TasksApi PUT task completion timeout")
            taskCompletionFailed(i18n.tr("Task update timed out."), generation)
        }
        xhr.send(body)
    }

    function updateTask(serverUrl, userName, secret, task, changes) {
        var generation = requestGeneration
        var base = AuthCore.normalizeServerUrl(serverUrl)
        var href = String(task && task.href ? task.href : "")
        var rawTodo = String(task && task.rawTodo ? task.rawTodo : "")
        if (base.length === 0 || userName.length === 0 || secret.length === 0 || href.length === 0 || rawTodo.length === 0) {
            taskUpdateFailed(i18n.tr("Task update data is incomplete."), generation)
            return
        }

        var updatedTodo = updatedTaskTodo(rawTodo, changes || {})
        var body = wrapCalendar(updatedTodo)
        if (typeof calDavNetwork !== "undefined") {
            pendingNativeWrite = {
                "serverUrl": serverUrl,
                "userName": userName,
                "secret": secret,
                "href": href,
                "sourceTask": task,
                "fallbackTodo": updatedTodo,
                "fallbackEtag": task.etag || "",
                "kind": "update"
            }
            debugLog("NextTasks TasksApi native PUT task fields serverUrlConfigured=" + AuthCore.hasValue(base))
            calDavNetwork.putTask(generation, serverUrl, userName, secret, href, body, String(task.etag || ""), false, "update")
            return
        }
        var url = authenticatedUrl(href.indexOf("http") === 0 ? href : base + href, userName)
        debugLog("NextTasks TasksApi PUT task fields serverUrlConfigured=" + AuthCore.hasValue(base))
        var xhr = new XMLHttpRequest()
        xhr.open("PUT", url)
        xhr.timeout = 15000
        xhr.setRequestHeader("Authorization", "Basic " + Qt.btoa(userName + ":" + secret))
        xhr.setRequestHeader("Content-Type", "text/calendar; charset=utf-8")
        if (String(task.etag || "").length > 0) {
            xhr.setRequestHeader("If-Match", task.etag)
        }
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status === 412) {
                debugLog("NextTasks TasksApi PUT task fields conflict")
                fetchConflictTask(serverUrl, userName, secret, task, i18n.tr("Server version changed. Local task was not uploaded."), generation)
                return
            }
            if (xhr.status < 200 || xhr.status >= 300) {
                debugLog("NextTasks TasksApi PUT task fields failed httpStatus=" + xhr.status)
                taskUpdateFailed(i18n.tr("Task update failed with HTTP %1.").arg(xhr.status), generation)
                return
            }
            debugLog("NextTasks TasksApi PUT task fields success")
            var responseEtag = decodeName(xhr.getResponseHeader("ETag") || xhr.getResponseHeader("Etag") || "")
            fetchWrittenTask(serverUrl, userName, secret, href, task, updatedTodo, responseEtag.length > 0 ? responseEtag : (task.etag || ""), "update", generation)
        }
        xhr.onerror = function() {
            debugLog("NextTasks TasksApi PUT task fields network error")
            taskUpdateFailed(i18n.tr("Task update failed because the network request could not be completed."), generation)
        }
        xhr.ontimeout = function() {
            debugLog("NextTasks TasksApi PUT task fields timeout")
            taskUpdateFailed(i18n.tr("Task update timed out."), generation)
        }
        xhr.send(body)
    }

    function createTask(serverUrl, userName, secret, task, changes) {
        var generation = requestGeneration
        var base = AuthCore.normalizeServerUrl(serverUrl)
        var href = String(task && task.href ? task.href : "")
        var rawTodo = String(task && task.rawTodo ? task.rawTodo : "")
        if (base.length === 0 || userName.length === 0 || secret.length === 0 || href.length === 0 || rawTodo.length === 0) {
            taskCreateFailed(i18n.tr("Task create data is incomplete."), generation)
            return
        }

        var updatedTodo = updatedTaskTodo(rawTodo, changes || {})
        var body = wrapCalendar(updatedTodo)
        if (typeof calDavNetwork !== "undefined") {
            pendingNativeWrite = {
                "serverUrl": serverUrl,
                "userName": userName,
                "secret": secret,
                "href": href,
                "sourceTask": task,
                "fallbackTodo": updatedTodo,
                "fallbackEtag": "",
                "kind": "create"
            }
            debugLog("NextTasks TasksApi native PUT new task serverUrlConfigured=" + AuthCore.hasValue(base))
            calDavNetwork.putTask(generation, serverUrl, userName, secret, href, body, "", true, "create")
            return
        }
        var url = authenticatedUrl(href.indexOf("http") === 0 ? href : base + href, userName)
        debugLog("NextTasks TasksApi PUT new task serverUrlConfigured=" + AuthCore.hasValue(base))
        var xhr = new XMLHttpRequest()
        xhr.open("PUT", url)
        xhr.timeout = 15000
        xhr.setRequestHeader("Authorization", "Basic " + Qt.btoa(userName + ":" + secret))
        xhr.setRequestHeader("Content-Type", "text/calendar; charset=utf-8")
        xhr.setRequestHeader("If-None-Match", "*")
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status === 409 || xhr.status === 412) {
                debugLog("NextTasks TasksApi PUT new task conflict httpStatus=" + xhr.status)
                taskCreateFailed(i18n.tr("Server rejected the new task because that resource already exists."), generation)
                return
            }
            if (xhr.status < 200 || xhr.status >= 300) {
                debugLog("NextTasks TasksApi PUT new task failed httpStatus=" + xhr.status)
                taskCreateFailed(i18n.tr("Task create failed with HTTP %1.").arg(xhr.status), generation)
                return
            }
            debugLog("NextTasks TasksApi PUT new task success")
            var responseEtag = decodeName(xhr.getResponseHeader("ETag") || xhr.getResponseHeader("Etag") || "")
            fetchWrittenTask(serverUrl, userName, secret, href, task, updatedTodo, responseEtag, "create", generation)
        }
        xhr.onerror = function() {
            debugLog("NextTasks TasksApi PUT new task network error")
            taskCreateFailed(i18n.tr("Task create failed because the network request could not be completed."), generation)
        }
        xhr.ontimeout = function() {
            debugLog("NextTasks TasksApi PUT new task timeout")
            taskCreateFailed(i18n.tr("Task create timed out."), generation)
        }
        xhr.send(body)
    }

    function deleteTask(serverUrl, userName, secret, task) {
        var generation = requestGeneration
        var base = AuthCore.normalizeServerUrl(serverUrl)
        var href = String(task && task.href ? task.href : "")
        if (base.length === 0 || userName.length === 0 || secret.length === 0 || href.length === 0) {
            taskDeleteFailed(i18n.tr("Task delete data is incomplete."), generation)
            return
        }

        if (typeof calDavNetwork !== "undefined") {
            pendingNativeDeleteTask = {
                "task": task,
                "serverUrl": serverUrl,
                "userName": userName,
                "secret": secret
            }
            debugLog("NextTasks TasksApi native DELETE task serverUrlConfigured=" + AuthCore.hasValue(base))
            calDavNetwork.deleteTaskObject(generation, serverUrl, userName, secret, href, String(task.etag || ""))
            return
        }
        var url = authenticatedUrl(href.indexOf("http") === 0 ? href : base + href, userName)
        debugLog("NextTasks TasksApi DELETE task serverUrlConfigured=" + AuthCore.hasValue(base))
        var xhr = new XMLHttpRequest()
        xhr.open("DELETE", url)
        xhr.timeout = 15000
        xhr.setRequestHeader("Authorization", "Basic " + Qt.btoa(userName + ":" + secret))
        if (String(task.etag || "").length > 0) {
            xhr.setRequestHeader("If-Match", task.etag)
        }
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status === 404 || xhr.status === 410) {
                debugLog("NextTasks TasksApi DELETE task already gone")
                taskDeleted(task, generation)
                return
            }
            if (xhr.status === 412) {
                debugLog("NextTasks TasksApi DELETE task conflict")
                fetchConflictTask(serverUrl, userName, secret, task, i18n.tr("Server version changed. Local delete was not uploaded."), generation)
                return
            }
            if (xhr.status < 200 || xhr.status >= 300) {
                debugLog("NextTasks TasksApi DELETE task failed httpStatus=" + xhr.status)
                taskDeleteFailed(i18n.tr("Task delete failed with HTTP %1.").arg(xhr.status), generation)
                return
            }
            debugLog("NextTasks TasksApi DELETE task success")
            taskDeleted(task, generation)
        }
        xhr.onerror = function() {
            debugLog("NextTasks TasksApi DELETE task network error")
            taskDeleteFailed(i18n.tr("Task delete failed because the network request could not be completed."), generation)
        }
        xhr.ontimeout = function() {
            debugLog("NextTasks TasksApi DELETE task timeout")
            taskDeleteFailed(i18n.tr("Task delete timed out."), generation)
        }
        xhr.send()
    }

    function moveTask(serverUrl, userName, secret, task, targetCalendar) {
        var generation = requestGeneration
        if (typeof calDavNetwork === "undefined") {
            taskMoveFailed(i18n.tr("Task move is not available."), generation)
            return
        }
        var base = AuthCore.normalizeServerUrl(serverUrl)
        var sourceHref = String(task && task.href ? task.href : "")
        var targetHref = String(targetCalendar && targetCalendar.href ? targetCalendar.href : "")
        if (base.length === 0 || userName.length === 0 || secret.length === 0 || sourceHref.length === 0 || targetHref.length === 0) {
            taskMoveFailed(i18n.tr("Task move data is incomplete."), generation)
            return
        }
        var destinationHref = destinationTaskHref(sourceHref, targetHref, task)
        if (destinationHref.length === 0 || destinationHref === sourceHref) {
            taskMoveFailed(i18n.tr("Choose a different task list."), generation)
            return
        }
        pendingNativeMoveSourceTask = task
        pendingNativeMoveTargetCalendar = targetCalendar
        pendingNativeMoveDestinationHref = destinationHref
        debugLog("NextTasks TasksApi MOVE task via native helper")
        calDavNetwork.moveTask(generation, serverUrl, userName, secret, sourceHref, destinationHref)
    }

    property var pendingNativeMoveSourceTask: ({})
    property var pendingNativeMoveTargetCalendar: ({})
    property string pendingNativeMoveDestinationHref: ""

    function handleNativeTaskMoved(sourceHref, destinationHref, etag, generation) {
        var source = pendingNativeMoveSourceTask || ({})
        var calendar = pendingNativeMoveTargetCalendar || ({})
        var moved = {}
        for (var key in source) {
            moved[key] = source[key]
        }
        moved.href = destinationHref || pendingNativeMoveDestinationHref || ""
        moved.etag = decodeName(etag || "")
        moved.calendarHref = calendar.href || moved.calendarHref || ""
        moved.calendarTitle = calendar.title || moved.calendarTitle || ""
        moved.localStatus = "CLEAN"
        moved.dirty = false
        moved.isNew = false
        moved.deleted = false
        moved.conflict = false
        pendingNativeMoveSourceTask = ({})
        pendingNativeMoveTargetCalendar = ({})
        pendingNativeMoveDestinationHref = ""
        taskMoved(source, moved, generation)
    }

    function destinationTaskHref(sourceHref, targetCalendarHref, task) {
        var source = String(sourceHref || "")
        var target = String(targetCalendarHref || "")
        if (source.length === 0 || target.length === 0) {
            return ""
        }
        while (target.length > 0 && target.charAt(target.length - 1) !== "/") {
            target += "/"
        }
        var cleanSource = source
        while (cleanSource.length > 0 && cleanSource.charAt(cleanSource.length - 1) === "/") {
            cleanSource = cleanSource.substring(0, cleanSource.length - 1)
        }
        var slash = cleanSource.lastIndexOf("/")
        var fileName = slash >= 0 ? cleanSource.substring(slash + 1) : cleanSource
        if (fileName.length === 0) {
            fileName = String(task && task.uid ? task.uid : Date.now()) + ".ics"
        }
        return target + fileName
    }

    function handleNativeTaskPutFinished(kind, href, etag, status, generation) {
        var code = Number(status || 0)
        if (kind === "completion") {
            var completed = pendingNativeCompletion.completed === true
            pendingNativeCompletion = ({})
            if (code === 412) {
                debugLog("NextTasks TasksApi native PUT task completion conflict")
                taskCompletionFailed(i18n.tr("Server version changed. Refresh tasks and try again."), generation)
                return
            }
            if (code < 200 || code >= 300) {
                debugLog("NextTasks TasksApi native PUT task completion failed httpStatus=" + code)
                taskCompletionFailed(i18n.tr("Task update failed with HTTP %1.").arg(code), generation)
                return
            }
            debugLog("NextTasks TasksApi native PUT task completion success")
            taskCompletionUpdated(completed, generation)
            return
        }

        var pending = pendingNativeWrite || ({})
        pendingNativeWrite = ({})
        if (kind === "update" && code === 412) {
            debugLog("NextTasks TasksApi native PUT task fields conflict")
            fetchConflictTask(pending.serverUrl || "", pending.userName || "", pending.secret || "", pending.sourceTask || null, i18n.tr("Server version changed. Local task was not uploaded."), generation)
            return
        }
        if (kind === "create" && (code === 409 || code === 412)) {
            debugLog("NextTasks TasksApi native PUT new task conflict httpStatus=" + code)
            taskCreateFailed(i18n.tr("Server rejected the new task because that resource already exists."), generation)
            return
        }
        if (code < 200 || code >= 300) {
            debugLog("NextTasks TasksApi native PUT task failed httpStatus=" + code + " kind=" + kind)
            if (kind === "create") {
                taskCreateFailed(i18n.tr("Task create failed with HTTP %1.").arg(code), generation)
            } else {
                taskUpdateFailed(i18n.tr("Task update failed with HTTP %1.").arg(code), generation)
            }
            return
        }
        debugLog("NextTasks TasksApi native PUT task success kind=" + kind)
        fetchWrittenTask(
            pending.serverUrl || "",
            pending.userName || "",
            pending.secret || "",
            href || pending.href || "",
            pending.sourceTask || ({}),
            pending.fallbackTodo || "",
            decodeName(etag || "") || pending.fallbackEtag || "",
            kind,
            generation
        )
    }

    function handleNativeTaskPutFailed(kind, message, generation) {
        if (kind === "completion") {
            pendingNativeCompletion = ({})
            taskCompletionFailed(message, generation)
            return
        }
        var pendingKind = String(kind || "")
        pendingNativeWrite = ({})
        if (pendingKind === "create") {
            taskCreateFailed(message, generation)
        } else {
            taskUpdateFailed(message, generation)
        }
    }

    function handleNativeTaskDeleteFinished(status, generation) {
        var code = Number(status || 0)
        var pending = pendingNativeDeleteTask || ({})
        pendingNativeDeleteTask = ({})
        var task = pending.task || ({})
        if (code === 404 || code === 410) {
            debugLog("NextTasks TasksApi native DELETE task already gone")
            taskDeleted(task, generation)
            return
        }
        if (code === 412) {
            debugLog("NextTasks TasksApi native DELETE task conflict")
            fetchConflictTask(pending.serverUrl || "", pending.userName || "", pending.secret || "", task, i18n.tr("Server version changed. Local delete was not uploaded."), generation)
            return
        }
        if (code < 200 || code >= 300) {
            debugLog("NextTasks TasksApi native DELETE task failed httpStatus=" + code)
            taskDeleteFailed(i18n.tr("Task delete failed with HTTP %1.").arg(code), generation)
            return
        }
        debugLog("NextTasks TasksApi native DELETE task success")
        taskDeleted(task, generation)
    }

    function fetchConflictTask(serverUrl, userName, secret, localTask, message, generation) {
        var base = AuthCore.normalizeServerUrl(serverUrl)
        var href = String(localTask && localTask.href ? localTask.href : "")
        if (base.length === 0 || userName.length === 0 || secret.length === 0 || href.length === 0) {
            taskConflict(localTask, null, message, generation)
            return
        }
        if (typeof calDavNetwork !== "undefined") {
            pendingNativeFetches[nativeFetchKey("conflict", generation)] = {
                "localTask": localTask,
                "message": message
            }
            debugLog("NextTasks TasksApi native PROPFIND conflict task serverUrlConfigured=" + AuthCore.hasValue(base))
            calDavNetwork.fetchTaskObject(generation, serverUrl, userName, secret, href, "conflict")
            return
        }
        var url = authenticatedUrl(href.indexOf("http") === 0 ? href : base + href, userName)
        debugLog("NextTasks TasksApi PROPFIND conflict task serverUrlConfigured=" + AuthCore.hasValue(base))
        var xhr = new XMLHttpRequest()
        xhr.open("PROPFIND", url)
        xhr.timeout = 15000
        xhr.setRequestHeader("Authorization", "Basic " + Qt.btoa(userName + ":" + secret))
        xhr.setRequestHeader("Depth", "0")
        xhr.setRequestHeader("Content-Type", "application/xml; charset=utf-8")
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status < 200 || xhr.status >= 300) {
                debugLog("NextTasks TasksApi PROPFIND conflict task failed httpStatus=" + xhr.status)
                taskConflict(localTask, null, message, generation)
                return
            }
            var entries = parseTasks(xhr.responseText)
            var serverTask = entries.length > 0 ? entries[0] : null
            if (serverTask) {
                serverTask.calendarTitle = localTask.calendarTitle || ""
                serverTask.calendarHref = localTask.calendarHref || ""
            }
            taskConflict(localTask, serverTask, message, generation)
        }
        xhr.onerror = function() {
            debugLog("NextTasks TasksApi PROPFIND conflict task network error")
            taskConflict(localTask, null, message, generation)
        }
        xhr.ontimeout = function() {
            debugLog("NextTasks TasksApi PROPFIND conflict task timeout")
            taskConflict(localTask, null, message, generation)
        }
        xhr.send("<?xml version=\"1.0\"?><d:propfind xmlns:d=\"DAV:\" xmlns:c=\"urn:ietf:params:xml:ns:caldav\"><d:prop><d:getetag/><c:calendar-data/></d:prop></d:propfind>")
    }

    function fetchWrittenTask(serverUrl, userName, secret, href, sourceTask, fallbackTodo, fallbackEtag, kind, generation) {
        var base = AuthCore.normalizeServerUrl(serverUrl)
        var taskHref = String(href || "")
        if (base.length === 0 || userName.length === 0 || secret.length === 0 || taskHref.length === 0) {
            emitWrittenTaskFallback(sourceTask, taskHref, fallbackTodo, fallbackEtag, kind, generation)
            return
        }
        if (typeof calDavNetwork !== "undefined") {
            pendingNativeFetches[nativeFetchKey(kind || "update", generation)] = {
                "sourceTask": sourceTask,
                "href": taskHref,
                "fallbackTodo": fallbackTodo,
                "fallbackEtag": fallbackEtag,
                "kind": kind
            }
            debugLog("NextTasks TasksApi native PROPFIND written task kind=" + kind + " serverUrlConfigured=" + AuthCore.hasValue(base))
            calDavNetwork.fetchTaskObject(generation, serverUrl, userName, secret, taskHref, String(kind || "update"))
            return
        }

        var url = authenticatedUrl(taskHref.indexOf("http") === 0 ? taskHref : base + taskHref, userName)
        debugLog("NextTasks TasksApi PROPFIND written task kind=" + kind + " serverUrlConfigured=" + AuthCore.hasValue(base))
        var xhr = new XMLHttpRequest()
        xhr.open("PROPFIND", url)
        xhr.timeout = 15000
        xhr.setRequestHeader("Authorization", "Basic " + Qt.btoa(userName + ":" + secret))
        xhr.setRequestHeader("Depth", "0")
        xhr.setRequestHeader("Content-Type", "application/xml; charset=utf-8")
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status < 200 || xhr.status >= 300) {
                debugLog("NextTasks TasksApi PROPFIND written task failed httpStatus=" + xhr.status + " kind=" + kind)
                emitWrittenTaskFallback(sourceTask, taskHref, fallbackTodo, fallbackEtag, kind, generation)
                return
            }
            var entries = parseTasks(xhr.responseText)
            var parsed = entries.length > 0 ? entries[0] : null
            if (!parsed) {
                emitWrittenTaskFallback(sourceTask, taskHref, fallbackTodo, fallbackEtag, kind, generation)
                return
            }
            parsed.calendarTitle = sourceTask.calendarTitle || ""
            parsed.calendarHref = sourceTask.calendarHref || ""
            parsed.localModified = Number(sourceTask.localModified || 0)
            debugLog("NextTasks TasksApi PROPFIND written task success kind=" + kind + " etagAvailable=" + AuthCore.hasValue(parsed.etag))
            if (kind === "create") {
                taskCreated(parsed, generation)
            } else {
                taskUpdated(parsed, generation)
            }
        }
        xhr.onerror = function() {
            debugLog("NextTasks TasksApi PROPFIND written task network error kind=" + kind)
            emitWrittenTaskFallback(sourceTask, taskHref, fallbackTodo, fallbackEtag, kind, generation)
        }
        xhr.ontimeout = function() {
            debugLog("NextTasks TasksApi PROPFIND written task timeout kind=" + kind)
            emitWrittenTaskFallback(sourceTask, taskHref, fallbackTodo, fallbackEtag, kind, generation)
        }
        xhr.send("<?xml version=\"1.0\"?><d:propfind xmlns:d=\"DAV:\" xmlns:c=\"urn:ietf:params:xml:ns:caldav\"><d:prop><d:getetag/><c:calendar-data/></d:prop></d:propfind>")
    }

    function handleNativeTaskFetched(kind, responseText, status, generation) {
        var key = String(kind || "")
        var pendingKey = nativeFetchKey(key, generation)
        var pending = pendingNativeFetches[pendingKey] || ({})
        delete pendingNativeFetches[pendingKey]
        var code = Number(status || 0)
        if (key === "conflict") {
            var localTask = pending.localTask || null
            var message = pending.message || i18n.tr("Server version changed. Local task was not uploaded.")
            if (code < 200 || code >= 300) {
                debugLog("NextTasks TasksApi native PROPFIND conflict task failed httpStatus=" + code)
                taskConflict(localTask, null, message, generation)
                return
            }
            var conflictEntries = parseTasks(responseText)
            var serverTask = conflictEntries.length > 0 ? conflictEntries[0] : null
            if (serverTask && localTask) {
                serverTask.calendarTitle = localTask.calendarTitle || ""
                serverTask.calendarHref = localTask.calendarHref || ""
            }
            taskConflict(localTask, serverTask, message, generation)
            return
        }

        if (code < 200 || code >= 300) {
            debugLog("NextTasks TasksApi native PROPFIND written task failed httpStatus=" + code + " kind=" + key)
            emitWrittenTaskFallback(pending.sourceTask || ({}), pending.href || "", pending.fallbackTodo || "", pending.fallbackEtag || "", pending.kind || key, generation)
            return
        }
        var entries = parseTasks(responseText)
        var parsed = entries.length > 0 ? entries[0] : null
        if (!parsed) {
            emitWrittenTaskFallback(pending.sourceTask || ({}), pending.href || "", pending.fallbackTodo || "", pending.fallbackEtag || "", pending.kind || key, generation)
            return
        }
        var sourceTask = pending.sourceTask || ({})
        parsed.calendarTitle = sourceTask.calendarTitle || ""
        parsed.calendarHref = sourceTask.calendarHref || ""
        parsed.localModified = Number(sourceTask.localModified || 0)
        debugLog("NextTasks TasksApi native PROPFIND written task success kind=" + key + " etagAvailable=" + AuthCore.hasValue(parsed.etag))
        if ((pending.kind || key) === "create") {
            taskCreated(parsed, generation)
        } else {
            taskUpdated(parsed, generation)
        }
    }

    function handleNativeTaskFetchFailed(kind, message, generation) {
        var key = String(kind || "")
        var pendingKey = nativeFetchKey(key, generation)
        var pending = pendingNativeFetches[pendingKey] || ({})
        delete pendingNativeFetches[pendingKey]
        if (key === "conflict") {
            taskConflict(pending.localTask || null, null, pending.message || message, generation)
            return
        }
        emitWrittenTaskFallback(pending.sourceTask || ({}), pending.href || "", pending.fallbackTodo || "", pending.fallbackEtag || "", pending.kind || key, generation)
    }

    function nativeFetchKey(kind, generation) {
        return String(generation) + ":" + String(kind || "")
    }

    function emitWrittenTaskFallback(sourceTask, href, fallbackTodo, fallbackEtag, kind, generation) {
        var fallback = parseTodo(fallbackTodo, href, fallbackEtag || "")
        fallback.calendarTitle = sourceTask.calendarTitle || ""
        fallback.calendarHref = sourceTask.calendarHref || ""
        fallback.localModified = Number(sourceTask.localModified || 0)
        debugLog("NextTasks TasksApi using written task fallback kind=" + kind + " etagAvailable=" + AuthCore.hasValue(fallback.etag))
        if (kind === "create") {
            taskCreated(fallback, generation)
        } else {
            taskUpdated(fallback, generation)
        }
    }

    function parseCalendars(xml, userName, calendarHomeHref) {
        var entries = []
        var home = normalizedDavHref(calendarHomeHref)
        var responseRe = /<[^:>]*:?response[\s\S]*?<\/[^:>]*:?response>/g
        var matches = String(xml || "").match(responseRe) || []
        for (var i = 0; i < matches.length; ++i) {
            var block = matches[i]
            var href = textOf(block, "href")
            var name = decodeName(textOf(block, "displayname"))
            var normalizedHref = normalizedDavHref(href)
            if (!supportsTodo(block)) {
                continue
            }
            if (home.length > 0 && normalizedHref.indexOf(home + "/") !== 0) {
                debugLog(
                    "NextTasks TasksApi skipped calendar outside discovered home"
                    + " homeOwner=" + hrefOwnerFingerprint(home)
                    + " hrefOwner=" + hrefOwnerFingerprint(href)
                )
                continue
            }
            if (!name || href.replace(/\/+$/, "").match(new RegExp("/calendars/" + escapeRegExp(userName) + "$"))) {
                continue
            }
            var readOnly = calendarReadOnly(block)
            entries.push({"title": name, "subtitle": readOnly ? i18n.tr("Read-only task calendar") : i18n.tr("Task calendar"), "detail": textOf(block, "getctag"), "href": href, "type": "calendar", "color": normalizeCalendarColor(textOf(block, "calendar-color")), "readOnly": readOnly})
        }
        return entries
    }

    function calendarReadOnly(block) {
        var text = String(block || "")
        var hasRead = /<[^:>]*:?read\s*\/?>/i.test(text)
        var hasWrite = /<[^:>]*:?write\s*\/?>/i.test(text)
            || /<[^:>]*:?write-content\s*\/?>/i.test(text)
            || /<[^:>]*:?write-properties\s*\/?>/i.test(text)
            || /<[^:>]*:?bind\s*\/?>/i.test(text)
            || /<[^:>]*:?unbind\s*\/?>/i.test(text)
        return hasRead && !hasWrite
    }

    function normalizeCalendarColor(value) {
        var text = String(value || "").trim()
        if (text.length === 0) return ""
        if (text.charAt(0) !== "#") text = "#" + text
        return /^#[0-9A-Fa-f]{6}$/.test(text) ? text.toUpperCase() : ""
    }

    function supportsTodo(block) {
        var text = String(block || "")
        return /<[^:>]*:?comp[^>]*name=["']VTODO["'][^>]*\/?>/i.test(text)
    }

    function parseTasks(xml) {
        var entries = []
        var responseRe = /<[^:>]*:?response[\s\S]*?<\/[^:>]*:?response>/g
        var matches = String(xml || "").match(responseRe) || []
        for (var i = 0; i < matches.length; ++i) {
            var block = matches[i]
            var data = decodeName(textOf(block, "calendar-data"))
            var href = textOf(block, "href")
            var etag = decodeName(textOf(block, "getetag"))
            var todos = data.match(/BEGIN:VTODO[\s\S]*?END:VTODO/g) || []
            for (var j = 0; j < todos.length; ++j) {
                var todo = parseTodo(todos[j], href, etag)
                if (todo.title.length > 0) {
                    entries.push(todo)
                }
            }
        }
        entries.sort(function(a, b) {
            if (a.completed !== b.completed) return a.completed ? 1 : -1
            return String(a.due || "").localeCompare(String(b.due || ""))
        })
        return entries
    }

    function parseTrashCollections(xml, calendarHomeHref) {
        var result = {
            "items": [],
            "trashBinHref": "",
            "retentionSeconds": 0
        }
        var home = normalizedDavHref(calendarHomeHref)
        var responseRe = /<[^:>]*:?response[\s\S]*?<\/[^:>]*:?response>/g
        var matches = String(xml || "").match(responseRe) || []
        for (var i = 0; i < matches.length; ++i) {
            var block = matches[i]
            var href = textOf(block, "href")
            var normalizedHref = normalizedDavHref(href)
            if (home.length > 0 && normalizedHref.indexOf(home + "/") !== 0 && normalizedHref !== home) {
                continue
            }
            if (/<[^:>]*:?trash-bin(?:\s|>|\/)/i.test(block)) {
                result.trashBinHref = href
                result.retentionSeconds = parseInt(textOf(block, "trash-bin-retention-duration"), 10) || 0
                continue
            }
            if (!/<[^:>]*:?deleted-calendar(?:\s|>|\/)/i.test(block)) {
                continue
            }
            var title = decodeName(textOf(block, "displayname")) || i18n.tr("Untitled list")
            result.items.push({
                "type": "trashCalendar",
                "title": title,
                "subtitle": i18n.tr("Deleted task list"),
                "href": href,
                "sourceCalendarUri": textOf(block, "source-calendar-uri") || textOf(block, "calendar-uri"),
                "deletedAt": textOf(block, "deleted-at"),
                "deletedAtText": formatDateValue(textOf(block, "deleted-at")),
                "color": normalizeCalendarColor(textOf(block, "calendar-color"))
            })
        }
        return result
    }

    function parseTrashObjects(xml) {
        var entries = []
        var responseRe = /<[^:>]*:?response[\s\S]*?<\/[^:>]*:?response>/g
        var matches = String(xml || "").match(responseRe) || []
        for (var i = 0; i < matches.length; ++i) {
            var block = matches[i]
            var href = textOf(block, "href")
            var etag = decodeName(textOf(block, "getetag"))
            var deletedAt = textOf(block, "deleted-at")
            var calendarUri = textOf(block, "calendar-uri") || textOf(block, "source-calendar-uri")
            var data = decodeName(textOf(block, "calendar-data"))
            var todos = data.match(/BEGIN:VTODO[\s\S]*?END:VTODO/g) || []
            for (var j = 0; j < todos.length; ++j) {
                var todo = parseTodo(todos[j], href, etag)
                entries.push({
                    "type": "trashTask",
                    "title": todo.title || i18n.tr("Untitled task"),
                    "subtitle": i18n.tr("Deleted task"),
                    "href": href,
                    "uid": todo.uid || "",
                    "calendarUri": calendarUri || "",
                    "deletedAt": deletedAt,
                    "deletedAtText": formatDateValue(deletedAt),
                    "rawTodo": todo.rawTodo || ""
                })
            }
        }
        return entries
    }

    function parseTodo(todoText, href, etag) {
        var lines = unfoldLines(todoText)
        var summary = propertyValue(lines, "SUMMARY")
        var status = propertyValue(lines, "STATUS")
        var due = propertyValue(lines, "DUE")
        var description = propertyValue(lines, "DESCRIPTION")
        var priority = propertyValue(lines, "PRIORITY")
        var percentComplete = propertyValue(lines, "PERCENT-COMPLETE")
        var location = propertyValue(lines, "LOCATION")
        var url = propertyValue(lines, "URL")
        var categories = propertyValue(lines, "CATEGORIES")
        var created = propertyValue(lines, "CREATED")
        var lastModified = propertyValue(lines, "LAST-MODIFIED")
        var sortOrder = propertyValue(lines, "X-APPLE-SORT-ORDER")
        var uid = propertyValue(lines, "UID")
        var statusUpper = status.toUpperCase()
        var completed = statusUpper === "COMPLETED" || propertyValue(lines, "COMPLETED").length > 0
        var cancelled = statusUpper === "CANCELLED"
        var start = propertyValue(lines, "DTSTART")
        var relatedTo = propertyValue(lines, "RELATED-TO")
        return {
            "title": summary || i18n.tr("Untitled task"),
            "subtitle": statusSubtitle(statusUpper, completed),
            "detail": due.length > 0 ? i18n.tr("Due %1").arg(formatDateValue(due)) : "",
            "due": due,
            "dueText": formatDateValue(due),
            "description": description,
            "priority": priority,
            "priorityText": formatPriority(priority),
            "percentComplete": percentComplete,
            "location": location,
            "url": url,
            "tags": categories,
            "status": statusUpper || (completed ? "COMPLETED" : "NEEDS-ACTION"),
            "created": created,
            "createdText": formatDateValue(created),
            "lastModified": lastModified,
            "lastModifiedText": formatDateValue(lastModified),
            "sortOrder": normalizeSortOrder(sortOrder),
            "start": start,
            "startText": formatDateValue(start),
            "uid": uid,
            "parentUid": relatedTo,
            "href": href || "",
            "etag": etag || "",
            "rawTodo": todoText,
            "completed": completed,
            "cancelled": cancelled,
            "hiddenUntil": start,
            "type": "task"
        }
    }

    function unfoldLines(text) {
        var raw = String(text || "").replace(/\r\n/g, "\n").replace(/\r/g, "\n").split("\n")
        var lines = []
        for (var i = 0; i < raw.length; ++i) {
            if ((raw[i].charAt(0) === " " || raw[i].charAt(0) === "\t") && lines.length > 0) {
                lines[lines.length - 1] += raw[i].substring(1)
            } else {
                lines.push(raw[i])
            }
        }
        return lines
    }

    function updatedCompletionTodo(todoText, completed) {
        var lines = unfoldLines(todoText)
        lines = removeProperty(lines, "STATUS")
        lines = removeProperty(lines, "COMPLETED")
        lines = removeProperty(lines, "PERCENT-COMPLETE")
        lines = removeProperty(lines, "LAST-MODIFIED")

        var insertAt = Math.max(1, lines.length - 1)
        var stamp = utcTimestamp()
        var additions = completed
            ? ["STATUS:COMPLETED", "COMPLETED:" + stamp, "PERCENT-COMPLETE:100", "LAST-MODIFIED:" + stamp]
            : ["STATUS:NEEDS-ACTION", "PERCENT-COMPLETE:0", "LAST-MODIFIED:" + stamp]
        for (var i = additions.length - 1; i >= 0; --i) {
            lines.splice(insertAt, 0, additions[i])
        }
        return lines.join("\r\n")
    }

    function updatedTaskTodo(todoText, changes) {
        var lines = unfoldLines(todoText)
        var completed = changes.completed === true
        var stamp = utcTimestamp()

        lines = removeProperty(lines, "SUMMARY")
        lines = removeProperty(lines, "DESCRIPTION")
        lines = removeProperty(lines, "DTSTART")
        lines = removeProperty(lines, "DUE")
        lines = removeProperty(lines, "PRIORITY")
        lines = removeProperty(lines, "LOCATION")
        lines = removeProperty(lines, "URL")
        lines = removeProperty(lines, "CATEGORIES")
        lines = removeProperty(lines, "RELATED-TO")
        lines = removeProperty(lines, "STATUS")
        lines = removeProperty(lines, "COMPLETED")
        lines = removeProperty(lines, "PERCENT-COMPLETE")
        lines = removeProperty(lines, "X-APPLE-SORT-ORDER")
        lines = removeProperty(lines, "LAST-MODIFIED")

        var additions = []
        if (String(changes.title || "").trim().length > 0) {
            additions.push("SUMMARY:" + escapeIcs(String(changes.title || "")))
        }
        if (String(changes.description || "").length > 0) {
            additions.push("DESCRIPTION:" + escapeIcs(changes.description))
        }
        var startValue = normalizeDateInput(changes.start)
        if (startValue.length > 0) {
            additions.push("DTSTART;VALUE=DATE:" + startValue)
        }
        var dueValue = normalizeDateInput(changes.due)
        if (dueValue.length > 0) {
            additions.push("DUE;VALUE=DATE:" + dueValue)
        }
        var priority = normalizePriority(changes.priority)
        if (priority.length > 0 && priority !== "0") {
            additions.push("PRIORITY:" + priority)
        }
        if (String(changes.location || "").length > 0) {
            additions.push("LOCATION:" + escapeIcs(changes.location))
        }
        if (String(changes.url || "").length > 0) {
            additions.push("URL:" + escapeIcs(changes.url))
        }
        if (String(changes.tags || "").length > 0) {
            additions.push("CATEGORIES:" + escapeCategories(changes.tags))
        }
        if (String(changes.parentUid || "").length > 0) {
            additions.push("RELATED-TO:" + escapeIcs(changes.parentUid))
        }
        var status = normalizeStatus(changes.status, completed)
        var percent = normalizePercent(changes.percentComplete)
        if (status === "COMPLETED") {
            additions.push("STATUS:COMPLETED")
            additions.push("COMPLETED:" + stamp)
            additions.push("PERCENT-COMPLETE:100")
        } else if (status === "CANCELLED") {
            additions.push("STATUS:CANCELLED")
            additions.push("PERCENT-COMPLETE:" + percent)
        } else if (status === "IN-PROCESS") {
            additions.push("STATUS:IN-PROCESS")
            additions.push("PERCENT-COMPLETE:" + Math.max(10, percent))
        } else {
            additions.push("STATUS:NEEDS-ACTION")
            additions.push("PERCENT-COMPLETE:" + percent)
        }
        var sortOrder = normalizeSortOrder(changes.sortOrder)
        if (sortOrder > 0) {
            additions.push("X-APPLE-SORT-ORDER:" + sortOrder)
        }
        additions.push("LAST-MODIFIED:" + stamp)

        var insertAt = Math.max(1, lines.length - 1)
        for (var i = additions.length - 1; i >= 0; --i) {
            lines.splice(insertAt, 0, additions[i])
        }
        return lines.join("\r\n")
    }

    function removeProperty(lines, name) {
        var result = []
        var prefix = name.toUpperCase()
        for (var i = 0; i < lines.length; ++i) {
            var line = String(lines[i] || "")
            var upper = line.toUpperCase()
            if (upper.indexOf(prefix + ":") === 0 || upper.indexOf(prefix + ";") === 0) {
                continue
            }
            result.push(line)
        }
        return result
    }

    function wrapCalendar(todoText) {
        return [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//NextTasks//Ubuntu Touch//EN",
            String(todoText || ""),
            "END:VCALENDAR",
            ""
        ].join("\r\n")
    }

    function utcTimestamp() {
        var now = new Date()
        function pad(value) {
            return value < 10 ? "0" + value : String(value)
        }
        return now.getUTCFullYear()
            + pad(now.getUTCMonth() + 1)
            + pad(now.getUTCDate())
            + "T"
            + pad(now.getUTCHours())
            + pad(now.getUTCMinutes())
            + pad(now.getUTCSeconds())
            + "Z"
    }

    function propertyValue(lines, name) {
        var prefix = name.toUpperCase()
        for (var i = 0; i < lines.length; ++i) {
            var line = String(lines[i] || "")
            var upper = line.toUpperCase()
            if (upper.indexOf(prefix + ":") === 0 || upper.indexOf(prefix + ";") === 0) {
                var idx = line.indexOf(":")
                return idx >= 0 ? unescapeIcs(line.substring(idx + 1)) : ""
            }
        }
        return ""
    }

    function unescapeIcs(value) {
        return String(value || "").replace(/\\n/g, "\n").replace(/\\,/g, ",").replace(/\\;/g, ";").replace(/\\\\/g, "\\")
    }

    function escapeIcs(value) {
        return String(value || "")
            .replace(/\\/g, "\\\\")
            .replace(/\r\n/g, "\n")
            .replace(/\r/g, "\n")
            .replace(/\n/g, "\\n")
            .replace(/,/g, "\\,")
            .replace(/;/g, "\\;")
    }

    function escapeCategories(value) {
        var parts = String(value || "").split(",")
        var result = []
        for (var i = 0; i < parts.length; ++i) {
            var tag = parts[i].trim()
            if (tag.length > 0) {
                result.push(escapeIcs(tag))
            }
        }
        return result.join(",")
    }

    function normalizeDateInput(value) {
        var text = String(value || "").trim()
        if (text.length === 0) return ""
        var compact = text.replace(/-/g, "")
        if (/^\d{8}$/.test(compact)) return compact
        return ""
    }

    function normalizePriority(value) {
        var text = String(value || "").trim()
        if (text.length === 0) return "0"
        var parsed = parseInt(text, 10)
        if (!parsed || parsed < 0) return "0"
        if (parsed > 9) return "9"
        return String(parsed)
    }

    function normalizePercent(value) {
        var parsed = parseInt(String(value || "0"), 10)
        if (!parsed || parsed < 0) return 0
        if (parsed > 100) return 100
        return parsed
    }

    function normalizeSortOrder(value) {
        var parsed = parseInt(String(value || "0"), 10)
        if (!parsed || parsed < 0) return 0
        return parsed
    }

    function normalizeStatus(value, completed) {
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

    function formatDateValue(value) {
        var text = String(value || "")
        if (text.length >= 15) return text.substring(0, 4) + "-" + text.substring(4, 6) + "-" + text.substring(6, 8) + " " + text.substring(9, 11) + ":" + text.substring(11, 13)
        if (text.length >= 8) return text.substring(0, 4) + "-" + text.substring(4, 6) + "-" + text.substring(6, 8)
        return text
    }

    function formatPriority(value) {
        var priority = parseInt(value || "0", 10)
        if (!priority) return ""
        if (priority <= 4) return i18n.tr("High")
        if (priority === 5) return i18n.tr("Medium")
        return i18n.tr("Low")
    }

    function escapeRegExp(value) { return String(value).replace(/[.*+?^${}()|[\]\\]/g, "\\$&") }
    function authenticatedUrl(url, userName) {
        var value = String(url || "")
        var user = encodeURIComponent(String(userName || ""))
        if (value.length === 0 || user.length === 0 || value.indexOf("://") < 0) {
            return value
        }
        if (value.indexOf("://") >= 0 && value.indexOf("@") > value.indexOf("://") && value.indexOf("@") < value.indexOf("/", value.indexOf("://") + 3)) {
            return value
        }
        return value.replace("://", "://" + user + "@")
    }
    function normalizedDavHref(value) {
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
        var href = normalizedDavHref(value)
        var marker = "/remote.php/dav/calendars/"
        var index = href.indexOf(marker)
        if (index < 0) return "none"
        var rest = href.slice(index + marker.length)
        var slash = rest.indexOf("/")
        var owner = slash >= 0 ? rest.slice(0, slash) : rest
        return owner.length > 0 ? "h" + stableHash(owner) : "none"
    }
    function calendarOwnerSummary(entries) {
        var counts = {}
        for (var i = 0; i < (entries || []).length; ++i) {
            var owner = hrefOwnerFingerprint(entries[i] && entries[i].href ? entries[i].href : "")
            counts[owner] = (counts[owner] || 0) + 1
        }
        var parts = []
        for (var key in counts) {
            parts.push(key + ":" + counts[key])
        }
        return parts.join(",")
    }
    function stableHash(value) {
        var text = String(value || "")
        var hash = 0
        for (var i = 0; i < text.length; ++i) {
            hash = ((hash << 5) - hash + text.charCodeAt(i)) & 0x7fffffff
        }
        return hash.toString(36)
    }
    function textOf(block, localName) {
        var re = new RegExp("<[^:>]*:?" + localName + "[^>]*>([\\s\\S]*?)<\\/[^:>]*:?" + localName + ">", "i")
        var m = re.exec(block)
        return m ? String(m[1]).replace(/<[^>]+>/g, "").trim() : ""
    }
    function propBlock(block, localName) {
        var re = new RegExp("<[^:>]*:?" + localName + "[^>]*>([\\s\\S]*?)<\\/[^:>]*:?" + localName + ">", "i")
        var m = re.exec(block)
        return m ? String(m[1]) : ""
    }
    function nestedHref(block, localName) {
        var re = new RegExp("<[^:>]*:?" + localName + "[^>]*>([\\s\\S]*?)<\\/[^:>]*:?" + localName + ">", "i")
        var m = re.exec(String(block || ""))
        if (!m) return ""
        return decodeName(textOf(m[1], "href"))
    }
    function decodeName(value) {
        return String(value || "")
            .replace(/&#13;/g, "\r")
            .replace(/&#10;/g, "\n")
            .replace(/&amp;/g, "&")
            .replace(/&lt;/g, "<")
            .replace(/&gt;/g, ">")
            .replace(/&quot;/g, "\"")
            .replace(/&apos;/g, "'")
    }
}
