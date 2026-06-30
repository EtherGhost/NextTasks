import QtQuick 2.7
import Lomiri.Components 1.3
import Lomiri.Content 1.3

Page {
    id: page
    title: i18n.tr("Share")
    function debugLog() {}

    property string shareTitle: ""
    property string shareText: ""

    signal shareFinished()
    signal shareFailed(string message)

    ContentPeerPicker {
        id: picker
        anchors {
            fill: parent
            topMargin: page.header ? page.header.height : 0
        }
        visible: true
        showTitle: false
        contentType: ContentType.Text
        handler: ContentHandler.Share

        onPeerSelected: page.shareToPeer(peer)
        onCancelPressed: page.shareFinished()
    }

    Component {
        id: contentItemComponent

        ContentItem {
        }
    }

    function shareToPeer(peer) {
        var url = contentHubBridge ? contentHubBridge.writeSharedTextFile(shareTitle, shareText) : ""
        if (!url || String(url).length === 0) {
            shareFailed(i18n.tr("The task text could not be prepared for sharing."))
            return
        }

        var transfer = peer.request()
        var item = contentItemComponent.createObject(page)
        item.name = shareTitle && shareTitle.length > 0 ? shareTitle : i18n.tr("Shared")
        item.url = url
        item.text = shareText
        transfer.items = [ item ]
        transfer.state = ContentTransfer.Charged
        debugLog("NextTasks ContentHub share requested textLength=" + shareText.length)
        page.shareFinished()
    }
}
