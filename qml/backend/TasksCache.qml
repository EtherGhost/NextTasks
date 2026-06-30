import QtQuick 2.7
import QtQuick.LocalStorage 2.0 as Sql

Item {
    id: cache
    function debugLog() {}

    readonly property string statusClean: ""
    readonly property string statusEdited: "LOCAL_EDITED"
    readonly property string statusCreated: "LOCAL_CREATED"
    readonly property string statusDeleted: "LOCAL_DELETED"

    property var database: null
    property string databaseName: "NextTasksSyncV3"

    function setScope(scopeKey) {
        var scopedName = "NextTasksSyncV3_" + safeScopeName(scopeKey)
        if (databaseName === scopedName) {
            return
        }
        database = null
        databaseName = scopedName
        debugLog("NextTasks TasksCache scope changed")
    }

    function safeScopeName(scopeKey) {
        var value = String(scopeKey || "default").replace(/[^A-Za-z0-9_]/g, "_")
        if (value.length === 0) return "default"
        return value.length > 96 ? value.slice(0, 96) : value
    }

    function canonicalCalendarHref(value) {
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

    function db() {
        if (database) return database
        database = Sql.LocalStorage.openDatabaseSync(databaseName, "1.0", "NextTasks sync cache", 8 * 1024 * 1024)
        database.transaction(function(tx) {
            tx.executeSql(
                "CREATE TABLE IF NOT EXISTS calendars (" +
                "href TEXT PRIMARY KEY, " +
                "title TEXT NOT NULL, " +
                "ctag TEXT DEFAULT '', " +
                "color TEXT DEFAULT '', " +
                "read_only INTEGER DEFAULT 0, " +
                "updated_at INTEGER NOT NULL)"
            )
            tx.executeSql(
                "CREATE TABLE IF NOT EXISTS deleted_calendars (" +
                "href TEXT PRIMARY KEY, " +
                "title TEXT DEFAULT '', " +
                "deleted_at INTEGER NOT NULL)"
            )
            addColumnIfMissing(tx, "calendars", "color", "TEXT DEFAULT ''")
            addColumnIfMissing(tx, "calendars", "read_only", "INTEGER DEFAULT 0")
            tx.executeSql(
                "CREATE TABLE IF NOT EXISTS tasks (" +
                "task_key TEXT PRIMARY KEY, " +
                "href TEXT DEFAULT '', " +
                "uid TEXT DEFAULT '', " +
                "calendar_href TEXT DEFAULT '', " +
                "calendar_title TEXT DEFAULT '', " +
                "title TEXT NOT NULL, " +
                "subtitle TEXT DEFAULT '', " +
                "detail TEXT DEFAULT '', " +
                "due TEXT DEFAULT '', " +
                "due_text TEXT DEFAULT '', " +
                "description TEXT DEFAULT '', " +
                "priority TEXT DEFAULT '', " +
                "priority_text TEXT DEFAULT '', " +
                "percent_complete TEXT DEFAULT '', " +
                "location TEXT DEFAULT '', " +
                "url TEXT DEFAULT '', " +
                "tags TEXT DEFAULT '', " +
                "status_value TEXT DEFAULT '', " +
                "created TEXT DEFAULT '', " +
                "created_text TEXT DEFAULT '', " +
                "last_modified TEXT DEFAULT '', " +
                "last_modified_text TEXT DEFAULT '', " +
                "sort_order INTEGER DEFAULT 0, " +
                "start_value TEXT DEFAULT '', " +
                "start_text TEXT DEFAULT '', " +
                "parent_uid TEXT DEFAULT '', " +
                "read_only INTEGER DEFAULT 0, " +
                "etag TEXT DEFAULT '', " +
                "raw_todo TEXT DEFAULT '', " +
                "completed INTEGER DEFAULT 0, " +
                "cancelled INTEGER DEFAULT 0, " +
                "hidden_until TEXT DEFAULT '', " +
                "local_status TEXT DEFAULT '', " +
                "local_modified INTEGER DEFAULT 0, " +
                "conflict INTEGER DEFAULT 0, " +
                "conflict_etag TEXT DEFAULT '', " +
                "updated_at INTEGER NOT NULL)"
            )
            addColumnIfMissing(tx, "tasks", "conflict_etag", "TEXT DEFAULT ''")
            addColumnIfMissing(tx, "tasks", "sort_order", "INTEGER DEFAULT 0")
            addColumnIfMissing(tx, "tasks", "read_only", "INTEGER DEFAULT 0")
            tx.executeSql("CREATE INDEX IF NOT EXISTS idx_tasks_calendar ON tasks(calendar_href)")
            tx.executeSql("CREATE INDEX IF NOT EXISTS idx_tasks_local_status ON tasks(local_status, local_modified)")
            purgeDeletedCalendarTasks(tx)
        })
        return database
    }

    function addColumnIfMissing(tx, tableName, columnName, definition) {
        try {
            tx.executeSql("ALTER TABLE " + tableName + " ADD COLUMN " + columnName + " " + definition)
        } catch (e) {
        }
    }

    function loadCalendars() {
        var result = []
        db().readTransaction(function(tx) {
            var rows = tx.executeSql("SELECT href, title, ctag, color, read_only FROM calendars ORDER BY title COLLATE NOCASE ASC")
            for (var i = 0; i < rows.rows.length; ++i) {
                var row = rows.rows.item(i)
                result.push({
                    "type": "calendar",
                    "href": row.href || "",
                    "title": row.title || i18n.tr("Untitled"),
                    "ctag": row.ctag || "",
                    "color": row.color || "",
                    "readOnly": Number(row.read_only || 0) === 1
                })
            }
        })
        debugLog("NextTasks TasksCache loadCalendars count=" + result.length)
        return result
    }

    function loadAllTasks() {
        return loadTasksForCalendar("")
    }

    function clearCleanServerDataForCurrentScope() {
        db().transaction(function(tx) {
            tx.executeSql("DELETE FROM calendars")
            tx.executeSql("DELETE FROM tasks WHERE local_status IS NULL OR local_status = '' OR local_status = 'CLEAN'")
        })
        debugLog("NextTasks TasksCache cleared clean server data for current scope")
    }

    function loadTasksForCalendar(calendarHref) {
        var result = []
        var href = String(calendarHref || "")
        db().readTransaction(function(tx) {
            var rows = href.length > 0
                ? tx.executeSql("SELECT * FROM tasks WHERE calendar_href = ? ORDER BY title COLLATE NOCASE ASC", [href])
                : tx.executeSql("SELECT * FROM tasks ORDER BY calendar_title COLLATE NOCASE ASC, title COLLATE NOCASE ASC")
            for (var i = 0; i < rows.rows.length; ++i) {
                result.push(rowToTask(rows.rows.item(i)))
            }
        })
        debugLog("NextTasks TasksCache loadTasks count=" + result.length + " scoped=" + (href.length > 0 ? "true" : "false"))
        return result
    }

    function loadTask(task) {
        var key = taskKey(task)
        var result = null
        if (key.length === 0) return null
        db().readTransaction(function(tx) {
            var rows = tx.executeSql("SELECT * FROM tasks WHERE task_key = ?", [key])
            if (rows.rows.length > 0) {
                result = rowToTask(rows.rows.item(0))
            }
        })
        return result
    }

    function loadLocalChanges() {
        var result = []
        db().readTransaction(function(tx) {
            var rows = tx.executeSql(
                "SELECT * FROM tasks WHERE local_status IN (?, ?, ?) AND conflict = 0 ORDER BY local_modified ASC",
                [statusCreated, statusEdited, statusDeleted]
            )
            for (var i = 0; i < rows.rows.length; ++i) {
                var task = rowToTask(rows.rows.item(i))
                if (task.localStatus === statusCreated && !hasMeaningfulContent(task)) {
                    continue
                }
                result.push(task)
            }
        })
        debugLog("NextTasks TasksCache loadLocalChanges count=" + result.length)
        return result
    }

    function hasMeaningfulContent(task) {
        return String(task.title || "").trim().length > 0
            || String(task.description || "").trim().length > 0
            || String(task.due || task.dueText || "").trim().length > 0
            || String(task.start || task.startText || "").trim().length > 0
            || String(task.priority || "").trim().length > 0
            || String(task.location || "").trim().length > 0
            || String(task.url || "").trim().length > 0
            || String(task.tags || "").trim().length > 0
    }

    function replaceCalendars(calendars) {
        var now = Math.floor(Date.now() / 1000)
        var seen = {}
        db().transaction(function(tx) {
            for (var i = 0; i < (calendars || []).length; ++i) {
                var calendar = calendars[i]
                var href = String(calendar.href || "")
                if (href.length === 0) continue
                var canonicalHref = canonicalCalendarHref(href)
                var tombstoneRows = tx.executeSql("SELECT href FROM deleted_calendars WHERE href = ?", [canonicalHref])
                if (tombstoneRows.rows.length > 0) {
                    debugLog("NextTasks TasksCache replaceCalendars skipped tombstoned calendar")
                    continue
                }
                seen[canonicalHref] = true
                tx.executeSql(
                    "INSERT OR REPLACE INTO calendars (href, title, ctag, color, read_only, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
                    [href, calendar.title || i18n.tr("Untitled"), calendar.ctag || "", calendar.color || "", calendar.readOnly === true ? 1 : 0, now]
                )
            }
            var rows = tx.executeSql("SELECT href FROM calendars")
            for (var j = 0; j < rows.rows.length; ++j) {
                var oldHref = rows.rows.item(j).href || ""
                if (!seen[canonicalCalendarHref(oldHref)]) {
                    tx.executeSql("DELETE FROM calendars WHERE href = ?", [oldHref])
                    deleteTasksForCalendarHref(tx, oldHref, true)
                }
            }
            purgeDeletedCalendarTasks(tx)
        })
        debugLog("NextTasks TasksCache replaceCalendars count=" + (calendars ? calendars.length : 0))
    }

    function deleteCalendar(calendarHref) {
        var href = String(calendarHref || "")
        var canonicalHref = canonicalCalendarHref(href)
        if (href.length === 0) return
        var now = Math.floor(Date.now() / 1000)
        db().transaction(function(tx) {
            var rows = tx.executeSql("SELECT href, title FROM calendars")
            var title = ""
            for (var i = 0; i < rows.rows.length; ++i) {
                var row = rows.rows.item(i)
                var rowHref = row.href || ""
                if (canonicalCalendarHref(rowHref) === canonicalHref) {
                    title = title.length > 0 ? title : (row.title || "")
                    tx.executeSql("DELETE FROM calendars WHERE href = ?", [rowHref])
                    deleteTasksForCalendarHref(tx, rowHref, false)
                }
            }
            deleteTasksForCalendarHref(tx, href, false)
            tx.executeSql("INSERT OR REPLACE INTO deleted_calendars (href, title, deleted_at) VALUES (?, ?, ?)", [canonicalHref, title, now])
            purgeDeletedCalendarTasks(tx)
        })
        debugLog("NextTasks TasksCache deleteCalendar hrefAvailable=true")
    }

    function removeDeletedCalendarTombstone(calendarHref) {
        var canonicalHref = canonicalCalendarHref(calendarHref)
        if (canonicalHref.length === 0) return
        db().transaction(function(tx) {
            tx.executeSql("DELETE FROM deleted_calendars WHERE href = ?", [canonicalHref])
        })
        debugLog("NextTasks TasksCache restored deleted calendar tombstone")
    }

    function deleteTasksForCalendarHref(tx, calendarHref, cleanOnly) {
        var canonicalHref = canonicalCalendarHref(calendarHref)
        if (canonicalHref.length === 0) return
        var rows = tx.executeSql("SELECT task_key, calendar_href, local_status FROM tasks")
        for (var i = 0; i < rows.rows.length; ++i) {
            var row = rows.rows.item(i)
            if (canonicalCalendarHref(row.calendar_href || "") !== canonicalHref) {
                continue
            }
            if (cleanOnly && (row.local_status || statusClean) !== statusClean) {
                continue
            }
            tx.executeSql("DELETE FROM tasks WHERE task_key = ?", [row.task_key || ""])
        }
    }

    function purgeDeletedCalendarTasks(tx) {
        var tombstones = tx.executeSql("SELECT href FROM deleted_calendars")
        for (var i = 0; i < tombstones.rows.length; ++i) {
            deleteTasksForCalendarHref(tx, tombstones.rows.item(i).href || "", false)
        }
    }

    function replaceCalendarTasks(calendarHref, tasks) {
        var href = String(calendarHref || "")
        var now = Math.floor(Date.now() / 1000)
        var seen = {}
        db().transaction(function(tx) {
            for (var i = 0; i < (tasks || []).length; ++i) {
                var task = tasks[i]
                var key = taskKey(task)
                if (key.length === 0) continue
                seen[key] = true
                upsertServerTask(tx, task, now)
            }

            var rows = tx.executeSql("SELECT task_key, calendar_href, local_status FROM tasks")
            for (var j = 0; j < rows.rows.length; ++j) {
                var row = rows.rows.item(j)
                if (canonicalCalendarHref(row.calendar_href || "") !== canonicalCalendarHref(href)) {
                    continue
                }
                var oldKey = row.task_key || ""
                var localStatus = row.local_status || statusClean
                if (!seen[oldKey] && localStatus === statusClean) {
                    tx.executeSql("DELETE FROM tasks WHERE task_key = ?", [oldKey])
                }
            }
        })
        debugLog("NextTasks TasksCache replaceCalendarTasks count=" + (tasks ? tasks.length : 0))
    }

    function saveLocalDraft(task) {
        var now = Math.floor(Date.now() / 1000)
        db().transaction(function(tx) {
            var key = taskKey(task)
            var rows = key.length > 0 ? tx.executeSql("SELECT local_status FROM tasks WHERE task_key = ?", [key]) : null
            var existingStatus = rows && rows.rows.length > 0 ? (rows.rows.item(0).local_status || statusClean) : statusClean
            var targetStatus = existingStatus === statusCreated || task.localStatus === statusCreated || task.isNew === true
                ? statusCreated
                : statusEdited
            upsertTaskRow(tx, task, targetStatus, now, false)
        })
        debugLog("NextTasks TasksCache saveLocalDraft keyAvailable=" + (taskKey(task).length > 0 ? "true" : "false"))
    }

    function createLocalTask(calendarHref, calendarTitle) {
        var now = Math.floor(Date.now() / 1000)
        var uid = "nexttasks-" + Date.now() + "-" + Math.floor(Math.random() * 1000000)
        var baseHref = String(calendarHref || "")
        var href = baseHref.length > 0
            ? baseHref.replace(/\/?$/, "/") + uid + ".ics"
            : uid + ".ics"
        var stamp = utcTimestamp()
        var rawTodo = [
            "BEGIN:VTODO",
            "UID:" + uid,
            "CREATED:" + stamp,
            "DTSTAMP:" + stamp,
            "LAST-MODIFIED:" + stamp,
            "STATUS:NEEDS-ACTION",
            "PERCENT-COMPLETE:0",
            "END:VTODO"
        ].join("\r\n")
        var task = {
            "type": "task",
            "title": "",
            "subtitle": i18n.tr("Open task"),
            "detail": "",
            "due": "",
            "dueText": "",
            "description": "",
            "priority": "",
            "priorityText": "",
            "percentComplete": "0",
            "location": "",
            "url": "",
            "tags": "",
            "status": "NEEDS-ACTION",
            "created": stamp,
            "createdText": "",
            "lastModified": stamp,
            "lastModifiedText": "",
            "sortOrder": 0,
            "start": "",
            "startText": "",
            "uid": uid,
            "parentUid": "",
            "readOnly": false,
            "href": href,
            "etag": "",
            "rawTodo": rawTodo,
            "completed": false,
            "cancelled": false,
            "hiddenUntil": "",
            "calendarHref": calendarHref || "",
            "calendarTitle": calendarTitle || "",
            "localStatus": statusCreated,
            "dirty": true,
            "isNew": true,
            "deleted": false,
            "conflict": false,
            "localModified": now
        }
        debugLog("NextTasks TasksCache createLocalTask keyAvailable=true stored=false")
        return task
    }

    function saveUploadedTask(task) {
        var now = Math.floor(Date.now() / 1000)
        db().transaction(function(tx) {
            var key = taskKey(task)
            var existingRows = tx.executeSql("SELECT local_status, local_modified, title, description, status_value, due, start_value, priority, percent_complete, location, url, tags, completed FROM tasks WHERE task_key = ?", [key])
            var oldKey = ""
            if (existingRows.rows.length === 0 && String(task.uid || "").length > 0) {
                var uidRows = tx.executeSql("SELECT task_key, local_status, local_modified, title, description, status_value, due, start_value, priority, percent_complete, location, url, tags, completed FROM tasks WHERE uid = ?", [task.uid || ""])
                if (uidRows.rows.length > 0) {
                    oldKey = uidRows.rows.item(0).task_key || ""
                    existingRows = uidRows
                }
            }
            var existing = existingRows.rows.length > 0 ? existingRows.rows.item(0) : null
            var existingDirty = existing && (existing.local_status || statusClean) !== statusClean
            var existingStatus = existing ? (existing.local_status || statusClean) : statusClean
            var existingLocalModified = existing ? Number(existing.local_modified || 0) : 0
            var uploadedLocalModified = Number(task.localModified || 0)
            if (existingDirty && existingLocalModified > uploadedLocalModified && !sameMeaningfulTaskFields(existing, task)) {
                if (existingStatus === statusCreated) {
                    tx.executeSql(
                        "UPDATE tasks SET local_status = ?, etag = ?, raw_todo = ?, conflict = 0, conflict_etag = '', updated_at = ? WHERE task_key = ?",
                        [statusEdited, task.etag || "", task.rawTodo || "", now, oldKey.length > 0 ? oldKey : key]
                    )
                    debugLog("NextTasks TasksCache saveUploadedTask converted newer created draft to edited")
                    return
                }
                tx.executeSql(
                    "UPDATE tasks SET etag = ?, raw_todo = ?, conflict = 0, conflict_etag = '', updated_at = ? WHERE task_key = ?",
                    [task.etag || "", task.rawTodo || "", now, oldKey.length > 0 ? oldKey : key]
                )
                debugLog("NextTasks TasksCache saveUploadedTask preserved newer local draft with refreshed etag")
                return
            }
            if (oldKey.length > 0 && oldKey !== key) {
                tx.executeSql("DELETE FROM tasks WHERE task_key = ?", [oldKey])
            }
            upsertTaskRow(tx, task, statusClean, now, false)
        })
        debugLog("NextTasks TasksCache saveUploadedTask keyAvailable=" + (taskKey(task).length > 0 ? "true" : "false"))
    }

    function markConflict(task, serverTask) {
        var key = taskKey(task)
        if (key.length === 0) return
        var now = Math.floor(Date.now() / 1000)
        var conflictEtag = serverTask && serverTask.etag ? serverTask.etag : ""
        var rawTodo = serverTask && serverTask.rawTodo ? serverTask.rawTodo : ""
        db().transaction(function(tx) {
            if (rawTodo.length > 0) {
                tx.executeSql(
                    "UPDATE tasks SET conflict = 1, conflict_etag = ?, raw_todo = ?, local_status = ?, updated_at = ? WHERE task_key = ?",
                    [conflictEtag, rawTodo, statusEdited, now, key]
                )
            } else {
                tx.executeSql(
                    "UPDATE tasks SET conflict = 1, conflict_etag = ?, local_status = ?, updated_at = ? WHERE task_key = ?",
                    [conflictEtag, statusEdited, now, key]
                )
            }
        })
        debugLog("NextTasks TasksCache markConflict keyAvailable=true")
    }

    function keepLocalTaskAfterConflict(task) {
        var key = taskKey(task)
        if (key.length === 0) return
        var now = Math.floor(Date.now() / 1000)
        db().transaction(function(tx) {
            tx.executeSql(
                "UPDATE tasks SET etag = CASE WHEN conflict_etag IS NOT NULL AND conflict_etag != '' THEN conflict_etag ELSE etag END, " +
                "conflict = 0, conflict_etag = '', updated_at = ? WHERE task_key = ?",
                [now, key]
            )
        })
        debugLog("NextTasks TasksCache keepLocalTaskAfterConflict keyAvailable=true")
    }

    function discardLocalTaskAndUseServer(task, serverTask) {
        var key = taskKey(task)
        if (key.length === 0 || !serverTask) return
        var now = Math.floor(Date.now() / 1000)
        serverTask.calendarHref = task.calendarHref || serverTask.calendarHref || ""
        serverTask.calendarTitle = task.calendarTitle || serverTask.calendarTitle || ""
        serverTask.href = task.href || serverTask.href || ""
        serverTask.etag = task.conflictEtag || serverTask.etag || task.etag || ""
        db().transaction(function(tx) {
            upsertTaskRow(tx, serverTask, statusClean, now, false)
        })
        debugLog("NextTasks TasksCache discardLocalTaskAndUseServer keyAvailable=true")
    }

    function markDeleted(task) {
        var key = taskKey(task)
        if (key.length === 0) return
        var now = Math.floor(Date.now() / 1000)
        db().transaction(function(tx) {
            var rows = tx.executeSql("SELECT local_status FROM tasks WHERE task_key = ?", [key])
            var existingStatus = rows.rows.length > 0 ? (rows.rows.item(0).local_status || statusClean) : statusClean
            if (existingStatus === statusCreated) {
                tx.executeSql("DELETE FROM tasks WHERE task_key = ?", [key])
            } else {
                tx.executeSql("UPDATE tasks SET local_status = ?, local_modified = ?, conflict = 0, updated_at = ? WHERE task_key = ?", [statusDeleted, now, now, key])
            }
        })
        debugLog("NextTasks TasksCache markDeleted keyAvailable=true")
    }

    function deleteTask(task) {
        var key = taskKey(task)
        if (key.length === 0) return
        db().transaction(function(tx) {
            tx.executeSql("DELETE FROM tasks WHERE task_key = ?", [key])
        })
        debugLog("NextTasks TasksCache deleteTask keyAvailable=true")
    }

    function upsertServerTask(tx, task, now) {
        var key = taskKey(task)
        var existingRows = tx.executeSql("SELECT local_status, etag, conflict FROM tasks WHERE task_key = ?", [key])
        var existing = existingRows.rows.length > 0 ? existingRows.rows.item(0) : null
        var localStatus = existing ? (existing.local_status || statusClean) : statusClean
        var dirty = localStatus !== statusClean
        var existingEtag = existing ? (existing.etag || "") : ""
        var incomingEtag = task.etag || ""
        var conflict = dirty && existingEtag.length > 0 && incomingEtag.length > 0 && existingEtag !== incomingEtag
        if (dirty) {
            tx.executeSql(
                "UPDATE tasks SET etag = ?, raw_todo = ?, conflict = ?, conflict_etag = ?, updated_at = ? WHERE task_key = ?",
                [existingEtag, task.rawTodo || "", conflict ? 1 : Number(existing && existing.conflict || 0), conflict ? incomingEtag : "", now, key]
            )
            return
        }
        upsertTaskRow(tx, task, statusClean, now, false)
    }

    function upsertTaskRow(tx, task, localStatus, now, keepLocalModified) {
        var key = taskKey(task)
        if (key.length === 0) return
        var localModified = keepLocalModified ? Number(task.localModified || 0) : (localStatus !== statusClean ? now : 0)
        tx.executeSql(
            "INSERT OR REPLACE INTO tasks (" +
            "task_key, href, uid, calendar_href, calendar_title, title, subtitle, detail, due, due_text, description, " +
            "priority, priority_text, percent_complete, location, url, tags, status_value, created, created_text, " +
            "last_modified, last_modified_text, sort_order, start_value, start_text, parent_uid, read_only, etag, raw_todo, completed, " +
            "cancelled, hidden_until, local_status, local_modified, conflict, conflict_etag, updated_at) " +
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            [
                key,
                task.href || "",
                task.uid || "",
                task.calendarHref || "",
                task.calendarTitle || "",
                task.title || "",
                task.subtitle || "",
                task.detail || "",
                task.due || "",
                task.dueText || "",
                task.description || "",
                task.priority || "",
                task.priorityText || "",
                task.percentComplete || "",
                task.location || "",
                task.url || "",
                task.tags || "",
                task.status || "",
                task.created || "",
                task.createdText || "",
                task.lastModified || "",
                task.lastModifiedText || "",
                Number(task.sortOrder || 0),
                task.start || "",
                task.startText || "",
                task.parentUid || "",
                task.readOnly === true ? 1 : 0,
                task.etag || "",
                task.rawTodo || "",
                task.completed ? 1 : 0,
                task.cancelled ? 1 : 0,
                task.hiddenUntil || "",
                localStatus || statusClean,
                localModified,
                task.conflict ? 1 : 0,
                task.conflictEtag || "",
                now
            ]
        )
    }

    function rowToTask(row) {
        var localStatus = row.local_status || statusClean
        return {
            "type": "task",
            "title": row.title || "",
            "subtitle": row.subtitle || "",
            "detail": row.detail || "",
            "due": row.due || "",
            "dueText": row.due_text || "",
            "description": row.description || "",
            "priority": row.priority || "",
            "priorityText": row.priority_text || "",
            "percentComplete": row.percent_complete || "",
            "location": row.location || "",
            "url": row.url || "",
            "tags": row.tags || "",
            "status": row.status_value || "",
            "created": row.created || "",
            "createdText": row.created_text || "",
            "lastModified": row.last_modified || "",
            "lastModifiedText": row.last_modified_text || "",
            "sortOrder": Number(row.sort_order || 0),
            "start": row.start_value || "",
            "startText": row.start_text || "",
            "uid": row.uid || "",
            "parentUid": row.parent_uid || "",
            "readOnly": Number(row.read_only || 0) === 1,
            "href": row.href || "",
            "etag": row.etag || "",
            "rawTodo": row.raw_todo || "",
            "completed": Number(row.completed || 0) === 1,
            "cancelled": Number(row.cancelled || 0) === 1,
            "hiddenUntil": row.hidden_until || "",
            "calendarHref": row.calendar_href || "",
            "calendarTitle": row.calendar_title || "",
            "localStatus": localStatus,
            "dirty": localStatus !== statusClean,
            "isNew": localStatus === statusCreated,
            "deleted": localStatus === statusDeleted,
            "conflict": Number(row.conflict || 0) === 1,
            "conflictEtag": row.conflict_etag || "",
            "localModified": Number(row.local_modified || 0)
        }
    }

    function taskKey(task) {
        if (!task) return ""
        return String(task.href || task.uid || task.title || "")
    }

    function sameMeaningfulTaskFields(row, task) {
        if (!row || !task) return false
        return String(row.title || "") === String(task.title || "")
            && String(row.description || "") === String(task.description || "")
            && normalizeStatus(row.status_value, Number(row.completed || 0) === 1) === normalizeStatus(task.status, task.completed === true)
            && String(row.due || "") === String(task.due || "")
            && String(row.start_value || "") === String(task.start || "")
            && String(row.priority || "") === String(task.priority || "")
            && String(row.percent_complete || "") === String(task.percentComplete || "")
            && String(row.location || "") === String(task.location || "")
            && String(row.url || "") === String(task.url || "")
            && String(row.tags || "") === String(task.tags || "")
            && Number(row.sort_order || 0) === Number(task.sortOrder || 0)
    }

    function normalizeStatus(value, completed) {
        var text = String(value || "").toUpperCase()
        if (text === "COMPLETED" || completed === true) return "COMPLETED"
        if (text === "IN-PROCESS") return "IN-PROCESS"
        if (text === "CANCELLED") return "CANCELLED"
        return "NEEDS-ACTION"
    }

    function utcTimestamp() {
        var now = new Date()
        function pad(value) { return value < 10 ? "0" + value : String(value) }
        return now.getUTCFullYear()
            + pad(now.getUTCMonth() + 1)
            + pad(now.getUTCDate())
            + "T"
            + pad(now.getUTCHours())
            + pad(now.getUTCMinutes())
            + pad(now.getUTCSeconds())
            + "Z"
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
}
