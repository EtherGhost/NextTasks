import QtQuick 2.7
import Ubuntu.Content 1.3

Item {
    id: handler
    visible: false

    signal sharedTextReceived(string title, string content)
    signal importFailed(string message)

    property int maxImportedCharacters: 1000000
    property var processedTransferRefs: []
    property var processedContentKeys: ({})

    Component.onCompleted: {
        console.log("NextTasks ContentHub import handler ready hasPending=" + ContentHub.hasPending
                    + " finishedImports=" + finishedImportCount())
        Qt.callLater(restorePendingImports)
    }

    Connections {
        target: ContentHub

        onImportRequested: handler.handleImportRequested(transfer)

        onFinishedImportsChanged: {
            console.log("NextTasks ContentHub finishedImports changed count=" + handler.finishedImportCount())
            handler.processFinishedImports()
        }
    }

    Timer {
        id: pendingImportTimer
        interval: 250
        repeat: false
        onTriggered: handler.processFinishedImports()
    }

    function restorePendingImports() {
        console.log("NextTasks ContentHub restore pending hasPending=" + ContentHub.hasPending
                    + " finishedImports=" + finishedImportCount())
        if (ContentHub.hasPending) {
            ContentHub.restoreImports()
        }
        pendingImportTimer.restart()
    }

    function finishedImportCount() {
        return ContentHub.finishedImports ? ContentHub.finishedImports.length : 0
    }

    function processFinishedImports() {
        var count = finishedImportCount()
        if (count <= 0) {
            console.log("NextTasks ContentHub no finished imports to process")
            return
        }
        console.log("NextTasks ContentHub processing finished imports count=" + count)
        for (var i = 0; i < count; ++i) {
            handleImportRequested(ContentHub.finishedImports[i])
        }
    }

    function handleImportRequested(transfer) {
        var count = transfer && transfer.items ? transfer.items.length : 0
        console.log("NextTasks ContentHub import requested itemCount=" + count)
        if (wasTransferProcessed(transfer)) {
            console.log("NextTasks ContentHub import skipped already processed transfer")
            return
        }
        if (!transfer || !transfer.items || transfer.items.length === 0) {
            markTransferCollected(transfer)
            importFailed(i18n.tr("No shared content was received."))
            return
        }

        var textParts = []
        var title = ""
        for (var i = 0; i < transfer.items.length; ++i) {
            var item = transfer.items[i]
            if (!title && item && item.name && String(item.name).trim().length > 0) {
                title = String(item.name).trim()
            }
            var text = textFromItem(item)
            if (text.length > 0) {
                textParts.push(text)
            }
        }

        var content = textParts.join("\n\n").trim()
        if (content.length === 0) {
            markTransferProcessed(transfer, "")
            markTransferCollected(transfer)
            importFailed(i18n.tr("The shared content did not contain readable text."))
            return
        }
        if (content.length > maxImportedCharacters) {
            content = content.slice(0, maxImportedCharacters)
            console.log("NextTasks ContentHub import truncated length=" + content.length)
        }

        if (wasContentProcessed(content)) {
            console.log("NextTasks ContentHub import skipped duplicate content textLength=" + content.length)
            markTransferProcessed(transfer, content)
            markTransferCollected(transfer)
            return
        }

        markTransferProcessed(transfer, content)
        markTransferCollected(transfer)
        console.log("NextTasks ContentHub import received textLength=" + content.length)
        sharedTextReceived(title, content)
    }

    function textFromItem(item) {
        if (!item) {
            return ""
        }

        if (item.text && String(item.text).length > 0) {
            console.log("NextTasks ContentHub import read item text length=" + String(item.text).length)
            return String(item.text)
        }

        var url = item.url || ""
        if (url && String(url).length > 0 && contentHubBridge) {
            var fileText = contentHubBridge.readTextFile(url)
            if (fileText && fileText.length > 0) {
                console.log("NextTasks ContentHub import read local file length=" + fileText.length)
                return fileText
            }
            console.log("NextTasks ContentHub import local file was empty or unreadable")
        }

        if (item.name && String(item.name).length > 0) {
            console.log("NextTasks ContentHub import using item name length=" + String(item.name).length)
            return String(item.name)
        }

        return ""
    }

    function markTransferCollected(transfer) {
        if (!transfer) {
            return
        }
        try {
            transfer.state = ContentTransfer.Collected
            if (transfer.finalize) {
                transfer.finalize()
            }
        } catch (error) {
            console.log("NextTasks ContentHub import finalize failed: " + error)
        }
    }

    function wasTransferProcessed(transfer) {
        return transfer && processedTransferRefs.indexOf(transfer) >= 0
    }

    function wasContentProcessed(content) {
        var key = contentKey(content)
        var now = Date.now()
        var seenAt = processedContentKeys[key] || 0
        return seenAt > 0 && (now - seenAt) < 30000
    }

    function markTransferProcessed(transfer, content) {
        if (transfer && processedTransferRefs.indexOf(transfer) < 0) {
            processedTransferRefs.push(transfer)
            if (processedTransferRefs.length > 20) {
                processedTransferRefs.shift()
            }
        }
        var key = contentKey(content)
        if (key.length > 0) {
            processedContentKeys[key] = Date.now()
        }
    }

    function contentKey(content) {
        var text = String(content || "")
        if (text.length === 0) {
            return ""
        }
        var hash = 0
        for (var i = 0; i < text.length; ++i) {
            hash = ((hash << 5) - hash + text.charCodeAt(i)) | 0
        }
        return String(text.length) + ":" + String(hash)
    }
}
