import QtQuick 2.7

QtObject {
    property string appName: ""
    property string appDescription: ""
    property string apiNote: ""
    property bool syncWhileActive: true
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

    signal accountChanged(int accountId, string displayName, string providerId, string serviceId, string serverUrl, string avatarUrl)
}
