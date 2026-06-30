import QtQuick 2.7
import Lomiri.Components 1.3

Item {
    id: root

    property var model: []
    property Component delegate
    property bool reorderEnabled: true
    property int longPressDelay: 700
    property real autoScrollEdge: units.gu(8)
    property bool refreshing: false
    property bool pullToRefreshEnabled: true
    property real pullRefreshThreshold: units.gu(7)
    property color refreshIndicatorColor: "#2c7fb8"
    property string pullToRefreshText: "Pull to refresh"
    property string releaseToRefreshText: "Release to refresh"
    property string refreshingText: "Refreshing..."
    property bool swipeActionsEnabled: false
    property bool swipeRightEnabled: true
    property bool swipeLeftEnabled: true
    property bool swipeActionsReversed: false
    property real swipeActionThreshold: units.gu(8)
    property string swipeRightText: "Delete"
    property string swipeLeftText: "Star"
    property color swipeRightColor: "#c7162b"
    property color swipeLeftColor: "#2c7fb8"
    property bool selectionEnabled: false
    property bool selectionMode: false
    property int selectedCount: 0

    signal moveRequested(int fromIndex, int toIndex)
    signal dragStarted(int index)
    signal dragEnded(int fromIndex, int toIndex)
    signal refreshRequested()
    signal swipeRightRequested(int index, var itemData)
    signal swipeLeftRequested(int index, var itemData)
    signal selectionModeStarted(int index, var itemData)
    signal selectionChanged(var selectedItems)
    signal selectionCleared()

    property bool dragActive: false
    property var selectedKeys: ({})
    property var draggedItem: ({})
    property int draggedFromIndex: -1
    property int dragCurrentIndex: -1
    property real pointerX: 0
    property real pointerY: 0
    property real dragOffsetX: 0
    property real dragOffsetY: 0
    property real dragVisualWidth: 0
    property real dragVisualHeight: 0
    property real lastPointerLocalY: 0
    property int autoScrollDirection: 0
    property real displacedPulseValue: 0
    property bool suppressPullRefreshAfterDrag: false

    onModelChanged: rebuildVisualModel()
    Component.onCompleted: rebuildVisualModel()
    onDraggedItemChanged: applyDelegateProperties(dragLoader, dragCurrentIndex, draggedItem, false)
    onDragCurrentIndexChanged: applyDelegateProperties(dragLoader, dragCurrentIndex, draggedItem, false)
    onDragActiveChanged: applyDelegateProperties(dragLoader, dragCurrentIndex, draggedItem, false)
    onSelectionEnabledChanged: {
        if (!selectionEnabled) {
            clearSelection()
        }
    }

    function sourceCount() {
        if (!model) {
            return 0
        }
        if (model.count !== undefined) {
            return model.count
        }
        if (model.length !== undefined) {
            return model.length
        }
        return 0
    }

    function sourceItemAt(index) {
        if (!model || index < 0 || index >= sourceCount()) {
            return ({})
        }
        if (model.get !== undefined) {
            return model.get(index)
        }
        return model[index]
    }

    function normalizedItem(item, index) {
        var output = {"__sourceIndex": index}
        if (item !== null && typeof item === "object") {
            for (var key in item) {
                output[key] = item[key]
            }
        } else {
            output.value = item
        }
        return output
    }

    function rebuildVisualModel() {
        if (dragActive) {
            return
        }
        visualModel.clear()
        var count = sourceCount()
        for (var i = 0; i < count; ++i) {
            visualModel.append(normalizedItem(sourceItemAt(i), i))
        }
        if (selectionMode) {
            selectedCount = selectedItems().length
            selectionMode = selectedCount > 0
            selectionChanged(selectedItems())
            if (!selectionMode) {
                selectionCleared()
            }
        }
    }

    function visualItemAt(index) {
        if (index < 0 || index >= visualModel.count) {
            return ({})
        }
        return visualModel.get(index)
    }

    function selectionKey(item) {
        if (item && item.__sourceIndex !== undefined) {
            return String(item.__sourceIndex)
        }
        return JSON.stringify(item)
    }

    function rowSelected(item) {
        return selectedKeys[selectionKey(item)] === true
    }

    function selectedItems() {
        var result = []
        for (var i = 0; i < visualModel.count; ++i) {
            var item = visualItemAt(i)
            if (rowSelected(item)) {
                result.push({"index": i, "item": item})
            }
        }
        return result
    }

    function setRowSelected(item, selected) {
        var key = selectionKey(item)
        var next = {}
        for (var existingKey in selectedKeys) {
            next[existingKey] = selectedKeys[existingKey]
        }
        if (selected) {
            next[key] = true
        } else {
            delete next[key]
        }
        selectedKeys = next
        selectedCount = selectedItems().length
        selectionMode = selectedCount > 0
        if (!selectionMode) {
            selectionCleared()
        }
        selectionChanged(selectedItems())
    }

    function toggleRowSelection(index, item) {
        if (!selectionEnabled) {
            return
        }
        if (!selectionMode) {
            selectionMode = true
            selectionModeStarted(index, item)
        }
        setRowSelected(item, !rowSelected(item))
    }

    function clearSelection() {
        selectedKeys = ({})
        selectedCount = 0
        if (selectionMode) {
            selectionMode = false
            selectionCleared()
            selectionChanged([])
        }
    }

    function moveDraggedToIndex(targetIndex) {
        if (!dragActive || visualModel.count <= 0) {
            return
        }
        targetIndex = Math.max(0, Math.min(visualModel.count - 1, targetIndex))
        if (targetIndex === dragCurrentIndex) {
            return
        }

        visualModel.move(dragCurrentIndex, targetIndex, 1)
        dragCurrentIndex = targetIndex
        displacedPulse.restart()
    }

    function updateInsertionFromLocalY(localY) {
        if (!dragActive || !reorderEnabled) {
            return
        }

        var contentY = localY + list.contentY
        if (contentY <= list.delegateBaseHeight / 2) {
            moveDraggedToIndex(0)
            return
        }

        // Qt 5.12 does not expose itemAtIndex(), so use indexAt() offset by
        // half the observed row height. This mirrors Android's "view under
        // pointer" behavior without requiring direct delegate lookup.
        var hit = list.indexAt(list.width / 2, contentY + list.delegateBaseHeight / 2)
        if (hit >= 0) {
            moveDraggedToIndex(hit)
            return
        }

        if (contentY >= list.contentHeight - units.gu(2)) {
            moveDraggedToIndex(visualModel.count - 1)
        }
    }

    function beginDrag(item, index, sceneX, sceneY, visualWidth, visualHeight) {
        if ((!reorderEnabled && !selectionEnabled) || index < 0 || index >= visualModel.count) {
            return false
        }
        draggedItem = item
        draggedFromIndex = index
        dragCurrentIndex = index
        list.pullRefreshArmed = false
        pointerX = sceneX
        pointerY = sceneY
        lastPointerLocalY = 0
        dragOffsetX = visualWidth / 2
        dragOffsetY = units.gu(2.4)
        dragVisualWidth = visualWidth
        dragVisualHeight = visualHeight
        dragActive = true
        dragStarted(index)
        return true
    }

    function updateDrag(sceneX, sceneY) {
        if (!dragActive) {
            return
        }
        pointerX = sceneX
        pointerY = sceneY

        var local = list.mapFromItem(root, sceneX, sceneY)
        lastPointerLocalY = local.y
        updateInsertionFromLocalY(local.y)

        if (local.y <= autoScrollEdge) {
            autoScrollDirection = -1
            autoScrollTimer.start()
        } else if (local.y >= list.height - autoScrollEdge) {
            autoScrollDirection = 1
            autoScrollTimer.start()
        } else {
            autoScrollTimer.stop()
        }
    }

    function finishDrag() {
        if (!dragActive) {
            return
        }

        var from = draggedFromIndex
        var to = dragCurrentIndex
        var item = draggedItem
        var selectionTap = selectionEnabled && from === to
        suppressPullRefreshAfterDrag = true
        dragActive = false
        autoScrollTimer.stop()
        draggedItem = ({})
        draggedFromIndex = -1
        dragCurrentIndex = -1
        list.pullRefreshArmed = false
        suppressPullRefreshTimer.restart()

        if (selectionTap) {
            toggleRowSelection(from, item)
            return
        }
        dragEnded(from, to)
        if (from !== to) {
            moveRequested(from, to)
        }
    }

    function applyDelegateProperties(loader, rowIndex, rowItem, isPlaceholder) {
        if (!loader.item) {
            return
        }
        loader.item.itemData = rowItem
        loader.item.itemIndex = rowIndex
        loader.item.placeholder = isPlaceholder
        loader.item.dragging = root.dragActive
        loader.item.selected = rowSelected(rowItem)
        loader.item.selectionMode = selectionMode
    }

    ListModel {
        id: visualModel
    }

    SequentialAnimation {
        id: displacedPulse
        NumberAnimation { target: root; property: "displacedPulseValue"; to: 1; duration: 75; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "displacedPulseValue"; to: 0; duration: 170; easing.type: Easing.OutCubic }
    }

    Timer {
        id: autoScrollTimer
        interval: 80
        repeat: true
        onTriggered: {
            if (!root.dragActive) {
                stop()
                return
            }
            var distance = root.autoScrollDirection < 0
                ? Math.max(0, root.autoScrollEdge - root.lastPointerLocalY)
                : Math.max(0, root.lastPointerLocalY - (list.height - root.autoScrollEdge))
            var pressure = Math.max(0.25, Math.min(1.0, distance / root.autoScrollEdge))
            var step = units.gu(0.9) + pressure * units.gu(3.8)
            list.contentY = Math.max(0, Math.min(list.contentHeight - list.height, list.contentY + root.autoScrollDirection * step))
            root.updateInsertionFromLocalY(root.lastPointerLocalY)
        }
    }

    Timer {
        id: suppressPullRefreshTimer
        interval: 350
        onTriggered: root.suppressPullRefreshAfterDrag = false
    }

    ListView {
        id: list
        anchors.fill: parent
        clip: true
        interactive: !root.dragActive
        boundsBehavior: root.pullToRefreshEnabled && !root.dragActive ? Flickable.DragOverBounds : Flickable.StopAtBounds
        spacing: units.gu(1)
        model: visualModel
        property real delegateBaseHeight: units.gu(9.4)
        property bool pullRefreshArmed: false

        onContentYChanged: {
            if (root.suppressPullRefreshAfterDrag) {
                pullRefreshArmed = false
                return
            }
            if (root.pullToRefreshEnabled && contentY < -root.pullRefreshThreshold && !root.refreshing && !root.dragActive) {
                pullRefreshArmed = true
            }
        }

        onMovementEnded: {
            if (root.suppressPullRefreshAfterDrag) {
                pullRefreshArmed = false
                return
            }
            if (root.pullToRefreshEnabled && pullRefreshArmed && !root.refreshing && !root.dragActive) {
                root.refreshRequested()
            }
            pullRefreshArmed = false
        }

        move: Transition {
            NumberAnimation { properties: "x,y"; duration: 155; easing.type: Easing.OutCubic }
        }

        moveDisplaced: Transition {
            NumberAnimation { properties: "x,y"; duration: 155; easing.type: Easing.OutCubic }
        }

        displaced: Transition {
            NumberAnimation { properties: "x,y"; duration: 155; easing.type: Easing.OutCubic }
        }

        delegate: Item {
            id: row
            width: list.width
            height: Math.max(list.delegateBaseHeight, delegateLoader.implicitHeight + units.gu(2))
            property var rowItem: root.visualItemAt(index)
            property bool isDragged: root.dragActive && index === root.dragCurrentIndex
            property real swipeOffset: swipeContent.x
            property bool swipeActive: false
            property real swipeStartX: 0
            property real swipeStartY: 0
            property bool verticalGesture: false

            onHeightChanged: {
                if (!root.dragActive && height > 0) {
                    list.delegateBaseHeight = height
                }
            }

            Rectangle {
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    bottom: parent.bottom
                    margins: units.gu(1.1)
                }
                visible: row.isDragged
                radius: units.gu(0.7)
                color: Qt.rgba(0.17, 0.62, 0.27, 0.13)
                border.width: 1
                border.color: Qt.rgba(0.17, 0.62, 0.27, 0.55)
            }

            Rectangle {
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    bottom: parent.bottom
                    margins: units.gu(1)
                }
                visible: root.swipeActionsEnabled && root.swipeRightEnabled && row.swipeOffset > units.gu(0.5)
                radius: units.gu(0.7)
                color: root.swipeActionsReversed ? root.swipeLeftColor : root.swipeRightColor

                Label {
                    anchors {
                        left: parent.left
                        verticalCenter: parent.verticalCenter
                        leftMargin: units.gu(1.2)
                    }
                    text: root.swipeActionsReversed ? root.swipeLeftText : root.swipeRightText
                    color: "white"
                    font.bold: true
                }
            }

            Rectangle {
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    bottom: parent.bottom
                    margins: units.gu(1)
                }
                visible: root.swipeActionsEnabled && root.swipeLeftEnabled && row.swipeOffset < -units.gu(0.5)
                radius: units.gu(0.7)
                color: root.swipeActionsReversed ? root.swipeRightColor : root.swipeLeftColor

                Label {
                    anchors {
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        rightMargin: units.gu(1.2)
                    }
                    text: root.swipeActionsReversed ? root.swipeRightText : root.swipeLeftText
                    color: "white"
                    font.bold: true
                }
            }

            Item {
                id: swipeContent
                width: parent.width
                height: parent.height
                x: 0
                y: 0

                Behavior on x {
                    enabled: !row.swipeActive
                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                }

                Loader {
                    id: delegateLoader
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        bottom: parent.bottom
                        margins: units.gu(1)
                    }
                    sourceComponent: root.delegate ? root.delegate : defaultDelegate
                    opacity: row.isDragged ? 0.06 : 1
                    scale: row.isDragged ? 0.88 : (root.dragActive ? 1.0 + root.displacedPulseValue * 0.006 : 1)

                    Behavior on opacity { NumberAnimation { duration: 120 } }
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                    onLoaded: root.applyDelegateProperties(delegateLoader, index, row.rowItem, row.isDragged)
                }

                Binding { target: delegateLoader.item; property: "selected"; value: root.rowSelected(row.rowItem); when: delegateLoader.item !== null }
                Binding { target: delegateLoader.item; property: "selectionMode"; value: root.selectionMode; when: delegateLoader.item !== null }
            }

            onRowItemChanged: root.applyDelegateProperties(delegateLoader, index, rowItem, isDragged)
            onIsDraggedChanged: root.applyDelegateProperties(delegateLoader, index, rowItem, isDragged)

            MouseArea {
                id: swipeMouse
                anchors.fill: parent
                enabled: root.reorderEnabled || root.swipeActionsEnabled || root.selectionEnabled
                preventStealing: root.dragActive || row.swipeActive
                onPressed: {
                    row.swipeStartX = mouse.x
                    row.swipeStartY = mouse.y
                    row.swipeActive = false
                    row.verticalGesture = false
                }
                onPressAndHold: {
                    if (root.selectionMode && root.selectionEnabled) {
                        return
                    }
                    if (!root.reorderEnabled && !root.selectionEnabled) {
                        return
                    }
                    if (row.verticalGesture) {
                        return
                    }
                    if (Math.abs(swipeContent.x) > units.gu(1)) {
                        return
                    }
                    var p = mapToItem(root, mouse.x, mouse.y)
                    root.beginDrag(row.rowItem, index, p.x, p.y, row.width - units.gu(2), delegateLoader.height)
                }
                onPositionChanged: {
                    if (root.dragActive) {
                        if (index !== root.dragCurrentIndex) {
                            return
                        }
                        var p = mapToItem(root, mouse.x, mouse.y)
                        root.updateDrag(p.x, p.y)
                        return
                    }

                    if (root.swipeActionsEnabled) {
                        var dx = mouse.x - row.swipeStartX
                        var dy = mouse.y - row.swipeStartY
                        if (!row.swipeActive && !row.verticalGesture && Math.abs(dy) > units.gu(1.2) && Math.abs(dy) > Math.abs(dx) * 1.15) {
                            row.verticalGesture = true
                            mouse.accepted = false
                            return
                        }
                        if (row.verticalGesture) {
                            mouse.accepted = false
                            return
                        }
                        if (!row.swipeActive && Math.abs(dx) > units.gu(1.5) && Math.abs(dx) > Math.abs(dy) * 1.25) {
                            row.swipeActive = true
                        }
                        if (row.swipeActive) {
                            var limit = Math.max(root.swipeActionThreshold * 1.6, units.gu(10))
                            var minX = root.swipeLeftEnabled ? -limit : 0
                            var maxX = root.swipeRightEnabled ? limit : 0
                            swipeContent.x = Math.max(minX, Math.min(maxX, dx))
                        }
                    }
                }
                onReleased: {
                    if (root.dragActive) {
                        root.finishDrag()
                        return
                    }
                    var wasSwipeActive = row.swipeActive
                    if (root.swipeActionsEnabled) {
                        if (row.swipeActive && root.swipeRightEnabled && swipeContent.x > root.swipeActionThreshold) {
                            swipeContent.x = 0
                            if (root.swipeActionsReversed) root.swipeLeftRequested(index, row.rowItem)
                            else root.swipeRightRequested(index, row.rowItem)
                        } else if (row.swipeActive && root.swipeLeftEnabled && swipeContent.x < -root.swipeActionThreshold) {
                            swipeContent.x = 0
                            if (root.swipeActionsReversed) root.swipeRightRequested(index, row.rowItem)
                            else root.swipeLeftRequested(index, row.rowItem)
                        } else {
                            swipeContent.x = 0
                        }
                        row.swipeActive = false
                        row.verticalGesture = false
                    }
                    if (!wasSwipeActive && root.selectionMode && root.selectionEnabled) {
                        root.toggleRowSelection(index, row.rowItem)
                    }
                }
                onCanceled: {
                    if (root.dragActive) {
                        root.finishDrag()
                    }
                    swipeContent.x = 0
                    row.swipeActive = false
                    row.verticalGesture = false
                }
            }
        }
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: units.gu(1)
        width: refreshPullLabel.implicitWidth + units.gu(2)
        height: refreshPullLabel.implicitHeight + units.gu(0.9)
        radius: height / 2
        color: root.refreshIndicatorColor
        opacity: root.pullToRefreshEnabled && !root.dragActive && !root.suppressPullRefreshAfterDrag && (list.contentY < -units.gu(2) || root.refreshing) ? 0.92 : 0
        z: 30

        Behavior on opacity { NumberAnimation { duration: 120 } }

        Label {
            id: refreshPullLabel
            anchors.centerIn: parent
            text: root.refreshing
                ? root.refreshingText
                : list.contentY < -root.pullRefreshThreshold
                ? root.releaseToRefreshText
                : root.pullToRefreshText
            color: "white"
            font.bold: true
            fontSize: "small"
        }
    }

    Rectangle {
        visible: root.dragActive
        x: Math.max(units.gu(0.5), Math.min(root.width - width - units.gu(0.5), root.pointerX - root.dragOffsetX))
        y: Math.max(units.gu(0.5), Math.min(root.height - height - units.gu(0.5), root.pointerY - root.dragOffsetY))
        width: root.dragVisualWidth * 0.97
        height: root.dragVisualHeight * 0.97
        radius: units.gu(0.7)
        color: theme.palette.normal.background
        border.width: 2
        border.color: "#2c9f45"
        opacity: 0.90
        z: 20

        Rectangle {
            anchors {
                fill: parent
                margins: -units.gu(0.35)
            }
            radius: parent.radius + units.gu(0.35)
            color: "black"
            opacity: 0.16
            z: -1
        }

        Loader {
            id: dragLoader
            anchors {
                fill: parent
                margins: units.gu(0.3)
            }
            active: root.dragActive
            sourceComponent: root.delegate ? root.delegate : defaultDelegate
            onLoaded: root.applyDelegateProperties(dragLoader, root.dragCurrentIndex, root.draggedItem, false)
        }

        Binding { target: dragLoader.item; property: "selected"; value: root.rowSelected(root.draggedItem); when: dragLoader.item !== null }
        Binding { target: dragLoader.item; property: "selectionMode"; value: root.selectionMode; when: dragLoader.item !== null }
    }

    Component {
        id: defaultDelegate

        Rectangle {
            property var itemData: ({})
            property int itemIndex: -1
            property bool placeholder: false
            property bool dragging: false
            property bool selected: false
            property bool selectionMode: false

            implicitHeight: units.gu(7.4)
            radius: units.gu(0.7)
            color: selected ? Qt.rgba(0.17, 0.5, 0.72, 0.22) : theme.palette.normal.background
            border.width: 1
            border.color: selected ? "#2c7fb8" : theme.palette.normal.base

            Label {
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    margins: units.gu(1)
                }
                text: itemData.title || itemData.label || itemData.value || ("Item " + (itemIndex + 1))
                elide: Text.ElideRight
            }
        }
    }
}
