import QtQuick 2.7
import QtQuick.Layouts 1.3
import Lomiri.Components 1.3

Item {
    id: root

    property var model: []
    property Component delegate
    property Component sectionDelegate

    property string sectionKeyRole: "id"
    property string sectionTitleRole: "title"
    property string sectionItemsRole: "items"
    property string itemKeyRole: "id"
    property string itemChildrenRole: "children"

    property bool reorderEnabled: true
    property bool levelZeroDragDropEnabled: true
    property bool childDragDropEnabled: true
    property bool subItemDropEnabled: true
    property bool crossListDragEnabled: false
    property bool defaultExpanded: true
    property bool treeLinesEnabled: true
    property bool refreshing: false
    property bool pullToRefreshEnabled: true
    property bool swipeActionsEnabled: false
    property bool swipeRightEnabled: true
    property bool swipeLeftEnabled: true
    property bool swipeActionsReversed: false
    property bool autoMeasureDelegateHeight: true
    property bool selectionEnabled: false
    property bool selectionMode: false
    property int selectedCount: 0

    property real cardHeight: units.gu(7.6)
    property real sectionHeight: units.gu(5.2)
    property real taskSpacing: units.gu(2.6)
    property real subTaskSpacing: units.gu(1.8)
    property real dropPreviewHeight: cardHeight
    property real indentWidth: units.gu(2.2)
    property real treeLineWidth: 2
    property color treeLineColor: Qt.rgba(0.17, 0.5, 0.72, 0.55)
    property real dragAreaLeftMargin: 0
    property real autoScrollEdge: units.gu(8)
    property real outdentIntentThreshold: units.gu(5.5)
    property real dragStartThreshold: units.gu(1.2)
    property real pullRefreshThreshold: units.gu(7)
    property real swipeActionThreshold: units.gu(8)
    property color refreshIndicatorColor: "#2c7fb8"
    property string pullToRefreshText: "Pull to refresh"
    property string releaseToRefreshText: "Release to refresh"
    property string refreshingText: "Refreshing..."
    property string swipeRightText: "Delete"
    property string swipeLeftText: "Star"
    property color swipeRightColor: "#c7162b"
    property color swipeLeftColor: "#2c7fb8"

    signal moveRequested(var fromSectionId, int fromIndex, var toSectionId, int toIndex, var item, var fromParentId, var toParentId)
    signal subItemRequested(var fromSectionId, int fromIndex, var parentSectionId, int parentIndex, var item, var parentItem, var fromParentId)
    signal outdentRequested(var fromSectionId, int fromIndex, var toParentId, int toIndex, var item, var fromParentId)
    signal dragStarted(var sectionId, int index, var item, var parentId)
    signal dragEnded(var sectionId, int fromIndex, var toSectionId, int toIndex, var item, var fromParentId, var toParentId)
    signal refreshRequested()
    signal swipeRightRequested(var sectionId, int index, var item, var parentId)
    signal swipeLeftRequested(var sectionId, int index, var item, var parentId)
    signal itemClicked(var sectionId, int index, var item, var parentId)
    signal selectionModeStarted(var sectionId, int index, var item, var parentId)
    signal selectionChanged(var selectedItems)
    signal selectionCleared()

    property var visibleRows: []
    property var expandedOverrides: ({})
    property var selectedKeys: ({})
    property bool dragActive: false
    property bool dragMoved: false
    property bool outdentIntent: false
    property var draggedItem: ({})
    property var draggedFromSectionId: ""
    property var draggedFromParentId: ""
    property int draggedFromIndex: -1
    property real pointerX: 0
    property real pointerY: 0
    property real dragStartX: 0
    property real dragStartY: 0
    property real dragWidth: 0
    property real dragHeight: 0
    property int dragDepth: 0
    property var hoverSectionId: ""
    property var hoverLevelParentId: ""
    property var hoverParentId: ""
    property var hoverParentItem: ({})
    property int hoverIndex: -1
    property int autoScrollDirection: 0
    property bool suppressPullRefreshAfterDrag: false

    onModelChanged: rebuildRows()
    onExpandedOverridesChanged: rebuildRows()
    onDefaultExpandedChanged: rebuildRows()
    onSelectionEnabledChanged: {
        if (!selectionEnabled) {
            clearSelection()
        }
    }
    Component.onCompleted: rebuildRows()

    function valueOf(object, role, fallback) {
        if (object === undefined || object === null || role === undefined || role === null || String(role).length === 0) {
            return fallback
        }
        if (typeof object !== "object") {
            return fallback
        }
        try {
            var value = object[String(role)]
            return value === undefined || value === null ? fallback : value
        } catch (e) {
            return fallback
        }
    }

    function sectionId(section, index) {
        if (!section) {
            return "section-" + index
        }
        if (sectionKeyRole === "id") {
            return section.id === undefined || section.id === null ? "section-" + index : section.id
        }
        return valueOf(section, sectionKeyRole, "section-" + index)
    }

    function sectionTitle(section) {
        if (!section) {
            return ""
        }
        if (sectionTitleRole === "title") {
            return section.title === undefined || section.title === null ? "" : section.title
        }
        return valueOf(section, sectionTitleRole, "")
    }

    function sectionItems(section) {
        if (!section) {
            return []
        }
        if (sectionItemsRole === "items") {
            return section.items === undefined || section.items === null ? [] : section.items
        }
        return valueOf(section, sectionItemsRole, [])
    }

    function itemId(item) {
        if (!item) {
            return ""
        }
        if (itemKeyRole === "id") {
            return item.id === undefined || item.id === null ? "" : item.id
        }
        return valueOf(item, itemKeyRole, "")
    }

    function itemChildren(item) {
        if (!item) {
            return []
        }
        if (itemChildrenRole === "children") {
            return item.children === undefined || item.children === null ? [] : item.children
        }
        return valueOf(item, itemChildrenRole, [])
    }

    function selectionKey(section, parentId, item) {
        return String(section) + "|" + String(parentId || "") + "|" + String(itemId(item))
    }

    function rowSelected(section, parentId, item) {
        return selectedKeys[selectionKey(section, parentId, item)] === true
    }

    function selectedItems() {
        var result = []
        for (var i = 0; i < visibleRows.length; ++i) {
            var row = visibleRows[i]
            if (row.type === "item" && rowSelected(row.sectionId, row.parentId, row.item)) {
                result.push({
                    "sectionId": row.sectionId,
                    "parentId": row.parentId || "",
                    "index": row.index,
                    "item": row.item
                })
            }
        }
        return result
    }

    function setRowSelected(section, parentId, item, selected) {
        var key = selectionKey(section, parentId, item)
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

    function toggleRowSelection(section, index, item, parentId) {
        if (!selectionEnabled) {
            return
        }
        if (!selectionMode) {
            selectionMode = true
            selectionModeStarted(section, index, item, parentId || "")
        }
        setRowSelected(section, parentId || "", item, !rowSelected(section, parentId || "", item))
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

    function sectionIndexById(id) {
        var source = model || []
        for (var i = 0; i < source.length; ++i) {
            if (sectionId(source[i], i) === id) {
                return i
            }
        }
        return -1
    }

    function itemsForSectionId(id) {
        var index = sectionIndexById(id)
        return index >= 0 ? sectionItems(model[index]) : []
    }

    function findItemById(items, id) {
        var source = items || []
        for (var i = 0; i < source.length; ++i) {
            if (itemId(source[i]) === id) {
                return source[i]
            }
            var child = findItemById(itemChildren(source[i]), id)
            if (child) {
                return child
            }
        }
        return null
    }

    function parentIdForItem(items, id, parentId) {
        var source = items || []
        for (var i = 0; i < source.length; ++i) {
            if (itemId(source[i]) === id) {
                return parentId || ""
            }
            var found = parentIdForItem(itemChildren(source[i]), id, itemId(source[i]))
            if (found !== null) {
                return found
            }
        }
        return null
    }

    function indexInParent(items, parentId, id) {
        var siblings = items || []
        if (String(parentId || "").length > 0) {
            var parent = findItemById(items, parentId)
            siblings = parent ? itemChildren(parent) : []
        }
        for (var i = 0; i < siblings.length; ++i) {
            if (itemId(siblings[i]) === id) {
                return i
            }
        }
        return -1
    }

    function indexDepth(section, parentId, index) {
        for (var i = 0; i < visibleRows.length; ++i) {
            var row = visibleRows[i]
            if (row.type === "item"
                    && row.sectionId === section
                    && String(row.parentId || "") === String(parentId || "")
                    && row.index === index) {
                return row.depth || 0
            }
        }
        return 0
    }

    function nestedCount(items, parentId) {
        if (String(parentId || "").length === 0) {
            return (items || []).length
        }
        var parent = findItemById(items, parentId)
        return parent ? itemChildren(parent).length : 0
    }

    function itemExpanded(item) {
        var id = itemId(item)
        if (!item || id.length === 0 || itemChildren(item).length === 0) {
            return false
        }
        if (expandedOverrides[id] !== undefined) {
            return expandedOverrides[id] === true
        }
        return defaultExpanded
    }

    function toggleExpanded(item) {
        var id = itemId(item)
        if (!item || id.length === 0 || itemChildren(item).length === 0) {
            return
        }
        var next = {}
        for (var key in expandedOverrides) {
            next[key] = expandedOverrides[key]
        }
        next[id] = !itemExpanded(item)
        expandedOverrides = next
    }

    function copyLineSegments(segments) {
        var result = []
        var source = segments || []
        for (var i = 0; i < source.length; ++i) {
            result.push({"level": source[i].level, "continues": source[i].continues})
        }
        return result
    }

    function appendItemRows(rows, section, sectionIndex, items, parentId, depth, ancestorLineSegments) {
        var source = items || []
        var sid = sectionId(section, sectionIndex)
        for (var i = 0; i < source.length; ++i) {
            var item = source[i]
            var hasNextSibling = i < source.length - 1
            var lineSegments = copyLineSegments(ancestorLineSegments)
            if (depth > 0) {
                lineSegments.push({"level": depth, "continues": hasNextSibling})
            }
            rows.push({
                "type": "item",
                "sectionId": sid,
                "parentId": parentId || "",
                "index": i,
                "depth": depth,
                "item": item,
                "lineSegments": lineSegments
            })
            if (itemExpanded(item)) {
                var childLineSegments = copyLineSegments(ancestorLineSegments)
                if (depth > 0 && hasNextSibling) {
                    childLineSegments.push({"level": depth, "continues": true})
                }
                appendItemRows(rows, section, sectionIndex, itemChildren(item), itemId(item), depth + 1, childLineSegments)
            }
        }
    }

    function buildVisibleRows() {
        var rows = []
        var source = model || []
        for (var i = 0; i < source.length; ++i) {
            var section = source[i]
            rows.push({"type": "section", "sectionId": sectionId(section, i), "sectionIndex": i, "section": section, "title": sectionTitle(section)})
            appendItemRows(rows, section, i, sectionItems(section), "", 0, [])
            rows.push({"type": "sectionEnd", "sectionId": sectionId(section, i), "sectionIndex": i})
        }
        return rows
    }

    function rebuildRows() {
        visibleRows = buildVisibleRows()
    }

    function rowSpacing(depth) {
        return depth <= 0 ? taskSpacing : subTaskSpacing
    }

    function measuredDelegateHeight(loader) {
        if (!autoMeasureDelegateHeight || !loader) {
            return cardHeight
        }
        var height = cardHeight
        if (loader.implicitHeight > 0) {
            height = Math.max(height, loader.implicitHeight)
        }
        if (loader.item && loader.item.implicitHeight > 0) {
            height = Math.max(height, loader.item.implicitHeight)
        }
        return height
    }

    function activeDropPreviewHeight() {
        return Math.max(dropPreviewHeight, dragActive && dragHeight > 0 ? dragHeight : 0)
    }

    function setSortTarget(section, parentId, index) {
        if (String(parentId || "").length > 0 && !childDragDropEnabled) {
            return false
        }
        if (dragActive && !crossListDragEnabled && !outdentIntent
                && (section !== draggedFromSectionId || String(parentId || "") !== String(draggedFromParentId || ""))) {
            return false
        }
        hoverSectionId = section
        hoverLevelParentId = parentId || ""
        hoverIndex = index
        hoverParentId = ""
        hoverParentItem = ({})
        return true
    }

    function setSubtaskTarget(section, parentId, index, targetParentId, parentItem) {
        if (!subItemDropEnabled || !childDragDropEnabled || !targetParentId || targetParentId === itemId(draggedItem)) {
            return false
        }
        if (dragActive && !crossListDragEnabled
                && (section !== draggedFromSectionId || String(parentId || "") !== String(draggedFromParentId || ""))) {
            return false
        }
        if (findItemById(itemChildren(draggedItem), targetParentId)) {
            return false
        }
        hoverSectionId = section
        hoverLevelParentId = parentId || ""
        hoverIndex = index
        hoverParentId = targetParentId
        hoverParentItem = parentItem || ({})
        return true
    }

    function effectiveSortIndex(section, parentId, targetIndex) {
        var insertIndex = targetIndex
        if (dragActive
                && draggedFromSectionId === section
                && String(draggedFromParentId || "") === String(parentId || "")
                && draggedFromIndex < insertIndex) {
            insertIndex -= 1
        }
        return insertIndex
    }

    function isNoOpSortPreview(section, parentId, targetIndex) {
        return dragActive
            && draggedFromSectionId === section
            && String(draggedFromParentId || "") === String(parentId || "")
            && hoverSectionId === section
            && String(hoverLevelParentId || "") === String(parentId || "")
            && String(hoverParentId || "").length === 0
            && effectiveSortIndex(section, parentId, targetIndex) === draggedFromIndex
    }

    function shouldShowBefore(row) {
        return dragActive
            && row.type === "item"
            && hoverSectionId === row.sectionId
            && String(hoverLevelParentId || "") === String(row.parentId || "")
            && hoverIndex === row.index
            && String(hoverParentId || "").length === 0
            && !isNoOpSortPreview(row.sectionId, row.parentId, row.index)
    }

    function shouldShowAfter(row) {
        return dragActive
            && row.type === "item"
            && hoverSectionId === row.sectionId
            && String(hoverLevelParentId || "") === String(row.parentId || "")
            && hoverIndex === row.index + 1
            && row.index + 1 >= nestedCount(itemsForSectionId(row.sectionId), row.parentId)
            && String(hoverParentId || "").length === 0
            && !isNoOpSortPreview(row.sectionId, row.parentId, row.index + 1)
    }

    function updateOutdentIntent() {
        outdentIntent = String(draggedFromParentId || "").length > 0 && pointerX < dragStartX - outdentIntentThreshold
    }

    function applyOutdentIntent() {
        if (!outdentIntent) {
            return
        }
        var items = itemsForSectionId(draggedFromSectionId)
        var parentParentId = parentIdForItem(items, draggedFromParentId, "")
        if (parentParentId === null) {
            return
        }
        var parentIndex = indexInParent(items, parentParentId, draggedFromParentId)
        if (parentIndex >= 0) {
            setSortTarget(draggedFromSectionId, parentParentId, parentIndex + 1)
        }
    }

    function draggedRowData() {
        return {
            "type": "item",
            "sectionId": draggedFromSectionId,
            "parentId": draggedFromParentId || "",
            "index": draggedFromIndex,
            "depth": dragDepth,
            "item": draggedItem
        }
    }

    function updateDropTarget() {
        hoverSectionId = ""
        hoverLevelParentId = ""
        hoverParentId = ""
        hoverParentItem = ({})
        hoverIndex = -1

        var local = scroll.mapFromItem(root, pointerX, pointerY)
        var y = local.y + scroll.contentY
        for (var i = 0; i < rowRepeater.count; ++i) {
            var rowItem = rowRepeater.itemAt(i)
            if (!rowItem || rowItem.rowType !== "item") {
                continue
            }
            var rowTop = rowItem.y
            var rowBottom = rowTop + rowItem.height
            if (y < rowTop || y > rowBottom) {
                continue
            }
            var localY = y - rowTop
            var cardBodyHeight = Math.max(cardHeight, rowItem.cardBodyHeight || cardHeight)
            if (localY < rowItem.beforeHeight + cardBodyHeight * 0.34) {
                setSortTarget(rowItem.sectionId, rowItem.parentId, rowItem.itemIndex)
            } else if (localY > rowItem.beforeHeight + cardBodyHeight * 0.66) {
                setSortTarget(rowItem.sectionId, rowItem.parentId, rowItem.itemIndex + 1)
            } else {
                setSubtaskTarget(rowItem.sectionId, rowItem.parentId, rowItem.itemIndex + 1, rowItem.itemId, rowItem.rowData.item)
            }
            return
        }
        setSortTarget(draggedFromSectionId, draggedFromParentId, draggedFromIndex)
    }

    function beginDrag(item, section, parentId, index, x, y, width, height) {
        draggedItem = item
        draggedFromSectionId = section
        draggedFromParentId = parentId || ""
        draggedFromIndex = index
        pointerX = x
        pointerY = y
        dragStartX = x
        dragStartY = y
        dragWidth = width
        dragHeight = height
        dragDepth = indexDepth(section, parentId || "", index)
        dragMoved = false
        outdentIntent = false
        dragActive = true
        scroll.pullRefreshArmed = false
        dragStarted(section, index, item, parentId || "")
        updateDropTarget()
    }

    function updateDrag(x, y) {
        if (!dragActive) {
            return
        }
        pointerX = x
        pointerY = y
        if (!dragMoved && (Math.abs(pointerX - dragStartX) > dragStartThreshold || Math.abs(pointerY - dragStartY) > dragStartThreshold)) {
            dragMoved = true
        }
        updateOutdentIntent()
        updateDropTarget()
        applyOutdentIntent()
        if (pointerY < autoScrollEdge) {
            autoScrollDirection = -1
            autoScrollTimer.start()
        } else if (pointerY > height - autoScrollEdge) {
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
        var fromSection = draggedFromSectionId
        var fromParent = draggedFromParentId || ""
        var fromIndex = draggedFromIndex
        var toSection = hoverSectionId
        var toParent = hoverLevelParentId || ""
        var toIndex = hoverIndex
        var item = draggedItem
        var parentTarget = hoverParentId
        var parentItem = hoverParentItem
        var moved = dragMoved
        var outdent = outdentIntent && String(toParent) !== String(fromParent)
        var selectionTap = selectionEnabled
            && (!moved || (String(parentTarget || "").length === 0
                && !outdent
                && String(toSection || "") === String(fromSection || "")
                && String(toParent || "") === String(fromParent || "")
                && effectiveSortIndex(toSection, toParent, toIndex) === fromIndex))
        cancelDrag(false)
        if (selectionTap) {
            toggleRowSelection(fromSection, fromIndex, item, fromParent)
            suppressPullRefreshAfterDrag = true
            suppressPullRefreshTimer.restart()
            return
        }
        if (!moved || fromIndex < 0 || String(toSection || "").length === 0 || toIndex < 0) {
            return
        }
        if (String(parentTarget || "").length > 0) {
            subItemRequested(fromSection, fromIndex, toSection, toIndex, item, parentItem, fromParent)
        } else if (outdent) {
            outdentRequested(fromSection, fromIndex, toParent, toIndex, item, fromParent)
        } else {
            moveRequested(fromSection, fromIndex, toSection, toIndex, item, fromParent, toParent)
        }
        dragEnded(fromSection, fromIndex, toSection, toIndex, item, fromParent, toParent)
        suppressPullRefreshAfterDrag = true
        suppressPullRefreshTimer.restart()
    }

    function cancelDrag(clearStatus) {
        autoScrollTimer.stop()
        dragActive = false
        dragMoved = false
        outdentIntent = false
        draggedItem = ({})
        draggedFromSectionId = ""
        draggedFromParentId = ""
        draggedFromIndex = -1
        dragDepth = 0
        hoverSectionId = ""
        hoverLevelParentId = ""
        hoverParentId = ""
        hoverParentItem = ({})
        hoverIndex = -1
        dragStartX = 0
        dragStartY = 0
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
            scroll.contentY = Math.max(0, Math.min(scroll.contentHeight - scroll.height, scroll.contentY + root.autoScrollDirection * units.gu(2.6)))
            root.updateDropTarget()
            root.applyOutdentIntent()
        }
    }

    Timer {
        id: suppressPullRefreshTimer
        interval: 350
        onTriggered: root.suppressPullRefreshAfterDrag = false
    }

    Flickable {
        id: scroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: listContent.height
        interactive: !root.dragActive
        boundsBehavior: root.pullToRefreshEnabled && !root.dragActive ? Flickable.DragOverBounds : Flickable.StopAtBounds
        clip: true
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

        Column {
            id: listContent
            width: scroll.width
            spacing: 0

            Repeater {
                id: rowRepeater
                model: root.visibleRows

                Column {
                    id: rowContainer
                    property var rowData: modelData
                    property string rowType: modelData.type
                    property var sectionId: modelData.sectionId || ""
                    property var parentId: modelData.parentId || ""
                    property var itemId: modelData.type === "item" ? root.itemId(modelData.item) : ""
                    property int itemIndex: modelData.index === undefined ? -1 : modelData.index
                    property int rowDepth: modelData.depth === undefined ? 0 : modelData.depth
                    property real cardBodyHeight: root.cardHeight
                    property real swipeOffset: 0
                    property bool swipeActive: false
                    property bool verticalGesture: false
                    property bool selectionHandledByLongPress: false
                    property real swipeStartX: 0
                    property real swipeStartY: 0
                    readonly property real beforeHeight: beforeDrop.height

                    width: listContent.width
                    spacing: 0

                    Loader {
                        visible: rowData.type === "section"
                        width: parent.width
                        height: visible ? root.sectionHeight : 0
                        sourceComponent: root.sectionDelegate ? root.sectionDelegate : defaultSectionDelegate
                        onLoaded: {
                            item.sectionData = rowData.section || ({})
                            item.sectionId = rowData.sectionId || ""
                            item.sectionIndex = rowData.sectionIndex || 0
                        }
                    }

                    Item {
                        visible: rowData.type === "sectionEnd"
                        width: parent.width
                        height: visible ? root.taskSpacing : 0
                    }

                    Item {
                        id: beforeDrop
                        visible: rowData.type === "item"
                        x: root.indentWidth * rowDepth
                        width: Math.max(units.gu(16), parent.width - x)
                        height: root.shouldShowBefore(rowData)
                            ? root.activeDropPreviewHeight() + root.rowSpacing(rowDepth)
                            : (rowData.type === "item" ? root.rowSpacing(rowDepth) : 0)
                        Behavior on height { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }

                        Rectangle {
                            anchors {
                                left: parent.left
                                right: parent.right
                                top: parent.top
                                topMargin: root.rowSpacing(rowDepth) / 2
                            }
                            height: root.shouldShowBefore(rowData) ? root.activeDropPreviewHeight() : 0
                            radius: units.gu(0.6)
                            color: Qt.rgba(0.17, 0.62, 0.27, 0.18)
                            border.width: height > 0 ? 1 : 0
                            border.color: Qt.rgba(0.17, 0.62, 0.27, 0.7)
                            Behavior on height { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                        }
                    }

                    Item {
                        visible: rowData.type === "item"
                        width: parent.width
                        height: visible ? rowContainer.cardBodyHeight : 0

                        Rectangle {
                            visible: root.swipeActionsEnabled && root.swipeRightEnabled && swipeOffset > units.gu(0.5)
                            x: root.indentWidth * rowDepth
                            width: Math.max(units.gu(16), parent.width - x)
                            height: parent.height
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
                            visible: root.swipeActionsEnabled && root.swipeLeftEnabled && swipeOffset < -units.gu(0.5)
                            x: root.indentWidth * rowDepth
                            width: Math.max(units.gu(16), parent.width - x)
                            height: parent.height
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

                        Repeater {
                            model: root.treeLinesEnabled && rowDepth > 0 ? (rowData.lineSegments || []) : []

                            Rectangle {
                                x: root.indentWidth * modelData.level - root.indentWidth / 2
                                y: -beforeDrop.height
                                width: root.treeLineWidth
                                height: beforeDrop.height + (modelData.continues ? parent.height : parent.height / 2)
                                radius: width / 2
                                color: root.treeLineColor
                            }
                        }

                        Rectangle {
                            visible: root.treeLinesEnabled && rowDepth > 0
                            x: root.indentWidth * rowDepth - root.indentWidth / 2
                            y: parent.height / 2
                            width: root.indentWidth / 2
                            height: root.treeLineWidth
                            radius: height / 2
                            color: root.treeLineColor
                        }

                        Loader {
                            id: cardLoader
                            property real baseX: root.indentWidth * rowDepth
                            x: root.indentWidth * rowDepth + swipeOffset
                            width: Math.max(units.gu(16), parent.width - baseX)
                            height: rowContainer.cardBodyHeight
                            sourceComponent: root.delegate ? root.delegate : defaultItemDelegate
                            onLoaded: {
                                root.applyItemDelegateProperties(cardLoader, rowData)
                                rowContainer.cardBodyHeight = root.measuredDelegateHeight(cardLoader)
                            }
                        }

                        Binding { target: rowContainer; property: "cardBodyHeight"; value: root.measuredDelegateHeight(cardLoader); when: rowData.type === "item" && cardLoader.status === Loader.Ready }
                        Binding { target: cardLoader.item; property: "width"; value: cardLoader.width; when: cardLoader.item !== null }
                        Binding { target: cardLoader.item; property: "height"; value: cardLoader.height; when: cardLoader.item !== null }
                        Binding { target: cardLoader.item; property: "itemData"; value: rowData.item; when: cardLoader.item !== null && rowData.type === "item" }
                        Binding { target: cardLoader.item; property: "rowData"; value: rowData; when: cardLoader.item !== null && rowData.type === "item" }
                        Binding { target: cardLoader.item; property: "itemIndex"; value: itemIndex; when: cardLoader.item !== null && rowData.type === "item" }
                        Binding { target: cardLoader.item; property: "sectionId"; value: sectionId; when: cardLoader.item !== null && rowData.type === "item" }
                        Binding { target: cardLoader.item; property: "parentId"; value: parentId; when: cardLoader.item !== null && rowData.type === "item" }
                        Binding { target: cardLoader.item; property: "depth"; value: rowDepth; when: cardLoader.item !== null && rowData.type === "item" }
                        Binding { target: cardLoader.item; property: "expanded"; value: rowData.type === "item" && root.itemExpanded(rowData.item); when: cardLoader.item !== null }
                        Binding { target: cardLoader.item; property: "hasChildren"; value: rowData.type === "item" && root.itemChildren(rowData.item).length > 0; when: cardLoader.item !== null }
                        Binding { target: cardLoader.item; property: "placeholder"; value: rowData.type === "item" && root.dragActive && root.draggedFromSectionId === rowData.sectionId && String(root.draggedFromParentId || "") === String(rowData.parentId || "") && root.draggedFromIndex === rowData.index; when: cardLoader.item !== null }
                        Binding { target: cardLoader.item; property: "dragging"; value: root.dragActive; when: cardLoader.item !== null }
                        Binding { target: cardLoader.item; property: "parentTarget"; value: rowData.type === "item" && root.hoverParentId === root.itemId(rowData.item); when: cardLoader.item !== null }
                        Binding { target: cardLoader.item; property: "selected"; value: rowData.type === "item" && root.rowSelected(rowData.sectionId, rowData.parentId, rowData.item); when: cardLoader.item !== null }
                        Binding { target: cardLoader.item; property: "selectionMode"; value: root.selectionMode; when: cardLoader.item !== null }

                        MouseArea {
                            id: cardMouse
                            x: root.indentWidth * rowDepth + root.dragAreaLeftMargin
                            y: 0
                            width: Math.max(0, cardLoader.width - root.dragAreaLeftMargin)
                            height: cardLoader.height
                            preventStealing: root.dragActive || swipeActive
                            onPressed: {
                                swipeStartX = mouse.x
                                swipeStartY = mouse.y
                                swipeActive = false
                                verticalGesture = false
                                rowContainer.selectionHandledByLongPress = false
                            }
                            onPressAndHold: {
                                if (root.selectionMode && root.selectionEnabled) {
                                    return
                                }
                                if (swipeActive || Math.abs(swipeOffset) > units.gu(1)) {
                                    return
                                }
                                if (!root.reorderEnabled) {
                                    if (root.selectionEnabled) {
                                        root.toggleRowSelection(rowData.sectionId, rowData.index, rowData.item, rowData.parentId)
                                        rowContainer.selectionHandledByLongPress = true
                                        root.suppressPullRefreshAfterDrag = true
                                        root.suppressPullRefreshTimer.restart()
                                    }
                                    return
                                }
                                if (rowDepth === 0 && !root.levelZeroDragDropEnabled) {
                                    if (root.selectionEnabled) {
                                        root.toggleRowSelection(rowData.sectionId, rowData.index, rowData.item, rowData.parentId)
                                        rowContainer.selectionHandledByLongPress = true
                                        root.suppressPullRefreshAfterDrag = true
                                        root.suppressPullRefreshTimer.restart()
                                    }
                                    return
                                }
                                if (rowDepth > 0 && !root.childDragDropEnabled) {
                                    if (root.selectionEnabled) {
                                        root.toggleRowSelection(rowData.sectionId, rowData.index, rowData.item, rowData.parentId)
                                        rowContainer.selectionHandledByLongPress = true
                                        root.suppressPullRefreshAfterDrag = true
                                        root.suppressPullRefreshTimer.restart()
                                    }
                                    return
                                }
                                var p = cardMouse.mapToItem(root, mouse.x, mouse.y)
                                root.beginDrag(rowData.item, rowData.sectionId, rowData.parentId, rowData.index, p.x, p.y, cardLoader.width, cardLoader.height)
                            }
                            onPositionChanged: {
                                if (!root.dragActive || root.itemId(root.draggedItem) !== root.itemId(rowData.item)) {
                                    if (root.swipeActionsEnabled) {
                                        var dx = mouse.x - swipeStartX
                                        var dy = mouse.y - swipeStartY
                                        if (!swipeActive && !verticalGesture && Math.abs(dy) > units.gu(1.2) && Math.abs(dy) > Math.abs(dx) * 1.15) {
                                            verticalGesture = true
                                        }
                                        if (!swipeActive && !verticalGesture && Math.abs(dx) > units.gu(1.5) && Math.abs(dx) > Math.abs(dy) * 1.25) {
                                            swipeActive = true
                                        }
                                        if (swipeActive) {
                                            var limit = Math.max(root.swipeActionThreshold * 1.6, units.gu(10))
                                            var minX = root.swipeLeftEnabled ? -limit : 0
                                            var maxX = root.swipeRightEnabled ? limit : 0
                                            swipeOffset = Math.max(minX, Math.min(maxX, dx))
                                        }
                                    }
                                    return
                                }
                                var p = cardMouse.mapToItem(root, mouse.x, mouse.y)
                                root.updateDrag(p.x, p.y)
                            }
                            onReleased: {
                                if (root.dragActive && root.itemId(root.draggedItem) === root.itemId(rowData.item)) {
                                    root.finishDrag()
                                } else if (swipeActive) {
                                    var rightTriggered = root.swipeRightEnabled && swipeOffset > root.swipeActionThreshold
                                    var leftTriggered = root.swipeLeftEnabled && swipeOffset < -root.swipeActionThreshold
                                    swipeOffset = 0
                                    swipeActive = false
                                    verticalGesture = false
                                    if (rightTriggered) {
                                        root.swipeRightRequested(rowData.sectionId, rowData.index, rowData.item, rowData.parentId)
                                    } else if (leftTriggered) {
                                        root.swipeLeftRequested(rowData.sectionId, rowData.index, rowData.item, rowData.parentId)
                                    }
                                } else {
                                    swipeOffset = 0
                                    verticalGesture = false
                                    if (rowContainer.selectionHandledByLongPress) {
                                        rowContainer.selectionHandledByLongPress = false
                                    } else if (root.selectionMode && root.selectionEnabled) {
                                        root.toggleRowSelection(rowData.sectionId, rowData.index, rowData.item, rowData.parentId)
                                    } else {
                                        root.itemClicked(rowData.sectionId, rowData.index, rowData.item, rowData.parentId)
                                    }
                                }
                            }
                            onCanceled: {
                                if (root.dragActive && root.itemId(root.draggedItem) === root.itemId(rowData.item)) {
                                    root.cancelDrag()
                                }
                                swipeOffset = 0
                                swipeActive = false
                                verticalGesture = false
                                rowContainer.selectionHandledByLongPress = false
                            }
                        }
                    }

                    Item {
                        visible: rowData.type === "item"
                        x: root.indentWidth * rowDepth
                        width: Math.max(units.gu(16), parent.width - x)
                        height: root.shouldShowAfter(rowData) ? root.activeDropPreviewHeight() + root.rowSpacing(rowDepth) : 0
                        Behavior on height { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }

                        Rectangle {
                            anchors {
                                left: parent.left
                                right: parent.right
                                top: parent.top
                                topMargin: root.rowSpacing(rowDepth) / 2
                            }
                            height: root.shouldShowAfter(rowData) ? root.activeDropPreviewHeight() : 0
                            radius: units.gu(0.6)
                            color: Qt.rgba(0.17, 0.62, 0.27, 0.18)
                            border.width: height > 0 ? 1 : 0
                            border.color: Qt.rgba(0.17, 0.62, 0.27, 0.7)
                            Behavior on height { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                        }
                    }
                }
            }
        }
    }

    function applyItemDelegateProperties(loader, row) {
        if (!loader.item || !row || row.type !== "item") {
            return
        }
        loader.item.itemData = row.item
        loader.item.rowData = row
        loader.item.itemIndex = row.index
        loader.item.sectionId = row.sectionId
        loader.item.parentId = row.parentId
        loader.item.depth = row.depth
        loader.item.expanded = itemExpanded(row.item)
        loader.item.hasChildren = itemChildren(row.item).length > 0
        loader.item.placeholder = dragActive && draggedFromSectionId === row.sectionId && String(draggedFromParentId || "") === String(row.parentId || "") && draggedFromIndex === row.index
        loader.item.dragging = dragActive
        loader.item.parentTarget = hoverParentId === itemId(row.item)
        loader.item.selected = rowSelected(row.sectionId, row.parentId, row.item)
        loader.item.selectionMode = selectionMode
        if (loader.item.toggleExpanded) {
            loader.item.toggleExpanded.connect(function() { root.toggleExpanded(row.item) })
        }
    }

    Rectangle {
        anchors {
            horizontalCenter: parent.horizontalCenter
            top: parent.top
            topMargin: units.gu(1)
        }
        width: refreshPullLabel.implicitWidth + units.gu(2)
        height: refreshPullLabel.implicitHeight + units.gu(0.9)
        radius: height / 2
        color: root.refreshIndicatorColor
        opacity: root.pullToRefreshEnabled && !root.dragActive && !root.suppressPullRefreshAfterDrag && (scroll.contentY < -units.gu(2) || root.refreshing) ? 0.92 : 0
        z: 35
        Behavior on opacity { NumberAnimation { duration: 100 } }

        Label {
            id: refreshPullLabel
            anchors.centerIn: parent
            text: root.refreshing
                ? root.refreshingText
                : (scroll.contentY < -root.pullRefreshThreshold ? root.releaseToRefreshText : root.pullToRefreshText)
            color: "white"
            font.bold: true
            fontSize: "x-small"
        }
    }

    MouseArea {
        visible: root.dragActive
        enabled: root.dragActive
        anchors.fill: parent
        z: 45
        preventStealing: true
        onPositionChanged: {
            var p = mapToItem(root, mouse.x, mouse.y)
            root.updateDrag(p.x, p.y)
        }
        onReleased: root.finishDrag()
        onCanceled: root.cancelDrag()
    }

    Item {
        id: dragOverlay
        visible: root.dragActive
        x: Math.max(units.gu(0.5), Math.min(root.width - width - units.gu(0.5), root.pointerX - width / 2))
        y: Math.max(units.gu(0.5), Math.min(root.height - height - units.gu(0.5), root.pointerY - units.gu(2.2)))
        width: root.dragWidth * 0.96
        height: root.dragHeight * 0.96
        opacity: 0.9
        z: 50
        enabled: false

        Rectangle {
            anchors {
                fill: parent
                leftMargin: units.gu(0.25)
                topMargin: units.gu(0.35)
            }
            radius: units.gu(0.7)
            color: "black"
            opacity: 0.18
        }

        Loader {
            id: dragDelegateLoader
            anchors.fill: parent
            sourceComponent: root.delegate ? root.delegate : defaultItemDelegate
            onLoaded: root.applyItemDelegateProperties(dragDelegateLoader, root.draggedRowData())
        }

        Binding { target: dragDelegateLoader.item; property: "width"; value: dragOverlay.width; when: dragDelegateLoader.item !== null }
        Binding { target: dragDelegateLoader.item; property: "height"; value: dragOverlay.height; when: dragDelegateLoader.item !== null }
        Binding { target: dragDelegateLoader.item; property: "itemData"; value: root.draggedItem; when: dragDelegateLoader.item !== null }
        Binding { target: dragDelegateLoader.item; property: "rowData"; value: root.draggedRowData(); when: dragDelegateLoader.item !== null }
        Binding { target: dragDelegateLoader.item; property: "itemIndex"; value: root.draggedFromIndex; when: dragDelegateLoader.item !== null }
        Binding { target: dragDelegateLoader.item; property: "sectionId"; value: root.draggedFromSectionId; when: dragDelegateLoader.item !== null }
        Binding { target: dragDelegateLoader.item; property: "parentId"; value: root.draggedFromParentId; when: dragDelegateLoader.item !== null }
        Binding { target: dragDelegateLoader.item; property: "depth"; value: root.dragDepth; when: dragDelegateLoader.item !== null }
        Binding { target: dragDelegateLoader.item; property: "expanded"; value: root.itemExpanded(root.draggedItem); when: dragDelegateLoader.item !== null }
        Binding { target: dragDelegateLoader.item; property: "hasChildren"; value: root.itemChildren(root.draggedItem).length > 0; when: dragDelegateLoader.item !== null }
        Binding { target: dragDelegateLoader.item; property: "placeholder"; value: false; when: dragDelegateLoader.item !== null }
        Binding { target: dragDelegateLoader.item; property: "dragging"; value: true; when: dragDelegateLoader.item !== null }
        Binding { target: dragDelegateLoader.item; property: "parentTarget"; value: false; when: dragDelegateLoader.item !== null }
        Binding { target: dragDelegateLoader.item; property: "selected"; value: root.rowSelected(root.draggedFromSectionId, root.draggedFromParentId, root.draggedItem); when: dragDelegateLoader.item !== null }
        Binding { target: dragDelegateLoader.item; property: "selectionMode"; value: root.selectionMode; when: dragDelegateLoader.item !== null }

        Rectangle {
            id: childBadge
            visible: root.draggedItem && root.itemChildren(root.draggedItem).length > 0
            anchors {
                right: parent.right
                verticalCenter: parent.verticalCenter
                rightMargin: units.gu(1)
            }
            width: childBadgeLabel.implicitWidth + units.gu(1.2)
            height: units.gu(2.6)
            radius: height / 2
            color: "#2c7fb8"

            Label {
                id: childBadgeLabel
                anchors.centerIn: parent
                text: "+" + root.itemChildren(root.draggedItem).length
                color: "white"
                font.bold: true
                fontSize: "x-small"
            }
        }

        Rectangle {
            id: outdentBadge
            visible: root.outdentIntent
            anchors {
                right: childBadge.visible ? childBadge.left : parent.right
                verticalCenter: parent.verticalCenter
                rightMargin: units.gu(1)
            }
            width: outdentBadgeLabel.implicitWidth + units.gu(1.2)
            height: units.gu(2.6)
            radius: height / 2
            color: "#2c9f45"

            Label {
                id: outdentBadgeLabel
                anchors.centerIn: parent
                text: "< LEVEL"
                color: "white"
                font.bold: true
                fontSize: "x-small"
            }
        }
    }

    Component {
        id: defaultSectionDelegate

        Rectangle {
            property var sectionData: ({})
            property var sectionId: ""
            property int sectionIndex: -1

            width: parent ? parent.width : root.width
            height: root.sectionHeight
            radius: units.gu(0.7)
            color: Qt.rgba(0.17, 0.5, 0.72, 0.14)

            Label {
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    margins: units.gu(1)
                }
                text: root.sectionTitle(sectionData)
                font.bold: true
                elide: Text.ElideRight
            }
        }
    }

    Component {
        id: defaultItemDelegate

        Rectangle {
            property var itemData: ({})
            property var rowData: ({})
            property int itemIndex: -1
            property var sectionId: ""
            property var parentId: ""
            property int depth: 0
            property bool expanded: false
            property bool hasChildren: false
            property bool placeholder: false
            property bool dragging: false
            property bool parentTarget: false
            property bool selected: false
            property bool selectionMode: false
            signal toggleExpanded()

            width: parent ? parent.width : root.width
            implicitHeight: root.cardHeight
            height: implicitHeight
            radius: units.gu(0.7)
            color: selected ? Qt.rgba(0.17, 0.5, 0.72, 0.22) : (parentTarget ? Qt.rgba(0.17, 0.62, 0.27, 0.16) : theme.palette.normal.background)
            border.width: parentTarget ? 2 : 1
            border.color: selected ? "#2c7fb8" : (parentTarget ? "#2c9f45" : theme.palette.normal.base)
            opacity: placeholder ? 0.12 : 1

            Label {
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    margins: units.gu(1)
                }
                text: root.valueOf(itemData, "title", "")
                font.bold: true
                elide: Text.ElideRight
            }
        }
    }
}
