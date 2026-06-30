import QtQuick 2.7
import QtQuick.Layouts 1.3
import Qt.labs.settings 1.0
import Lomiri.Components 1.3
import "../NextCommon" as NextCommon

NextCommon.SettingsShell {
    id: page

    property var appController

    title: i18n.tr("Settings")

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
            appController.showReadOnlyLists = appSettings.showReadOnlyLists
            page.applyListControlSettingsToController()
        }
    }

    function switchTrackColor(checked) {
        return checked ? "#2c7fb8" : Qt.rgba(0.5, 0.5, 0.5, 0.22)
    }

    function setSyncOnStartup(value) {
        appSettings.syncOnStartup = value
        if (appController) {
            appController.syncOnStartup = value
        }
    }

    function setShowReadOnlyLists(value) {
        appSettings.showReadOnlyLists = value
        if (appController) {
            appController.showReadOnlyLists = value
        }
    }

    function setMultiSelectEnabled(value) {
        appSettings.multiSelectEnabled = value
        page.applyListControlSettingsToController()
    }

    function setListControlSetting(key, value) {
        appSettings[key] = value
        if (key === "levelZeroDragDropEnabled" && !value) {
            appSettings.childDragDropEnabled = false
        }
        page.applyListControlSettingsToController()
    }

    function listControlRows() {
        return [
            {"key": "swipeActionsEnabled", "label": i18n.tr("Swipe actions")},
            {"key": "swipeActionsReversed", "label": i18n.tr("Reverse left/right actions")},
            {"key": "pullToRefreshEnabled", "label": i18n.tr("Pull to refresh")},
            {"key": "dragForMoveEnabled", "label": i18n.tr("Drag to move")},
            {"key": "levelZeroDragDropEnabled", "label": i18n.tr("Level 0 drag/drop")},
            {"key": "childDragDropEnabled", "label": i18n.tr("Children drag/drop"), "requires": "levelZeroDragDropEnabled"},
            {"key": "defaultExpanded", "label": i18n.tr("Expanded by default")},
            {"key": "treeLinesEnabled", "label": i18n.tr("Show tree lines")},
            {"key": "multiSelectEnabled", "label": i18n.tr("Bulk selection")}
        ]
    }

    function applyListControlSettingsToController() {
        if (!appController) {
            return
        }
        appController.multiSelectEnabled = appSettings.multiSelectEnabled
        appController.swipeActionsEnabled = appSettings.swipeActionsEnabled
        appController.swipeActionsReversed = appSettings.swipeActionsReversed
        appController.pullToRefreshEnabled = appSettings.pullToRefreshEnabled
        appController.dragForMoveEnabled = appSettings.dragForMoveEnabled
        appController.levelZeroDragDropEnabled = appSettings.levelZeroDragDropEnabled
        appController.childDragDropEnabled = appSettings.childDragDropEnabled
        appController.defaultExpanded = appSettings.defaultExpanded
        appController.treeLinesEnabled = appSettings.treeLinesEnabled
    }

    NextCommon.SettingsCard {
        Label {
            Layout.fillWidth: true
            text: i18n.tr("Sync")
            font.bold: true
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: units.gu(1)

            Label {
                Layout.fillWidth: true
                text: i18n.tr("Sync on startup")
                elide: Text.ElideRight
            }

            Rectangle {
                Layout.preferredWidth: units.gu(6.2)
                Layout.preferredHeight: units.gu(3.2)
                radius: height / 2
                color: page.switchTrackColor(appSettings.syncOnStartup)
                border.width: 0

                Rectangle {
                    width: units.gu(2.6)
                    height: units.gu(2.6)
                    radius: width / 2
                    color: "white"
                    anchors.verticalCenter: parent.verticalCenter
                    x: appSettings.syncOnStartup ? parent.width - width - units.gu(0.3) : units.gu(0.3)
                    Behavior on x { NumberAnimation { duration: 110 } }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: page.setSyncOnStartup(!appSettings.syncOnStartup)
                }
            }
        }
    }

    NextCommon.SettingsCard {
        Label {
            Layout.fillWidth: true
            text: i18n.tr("List interaction")
            font.bold: true
        }

        Label {
            Layout.fillWidth: true
            text: i18n.tr("Configure list gestures and tree-list behavior.")
            wrapMode: Text.WordWrap
            opacity: 0.72
        }

        Repeater {
            model: page.listControlRows()

            RowLayout {
                Layout.fillWidth: true
                spacing: units.gu(1)

                readonly property bool rowEnabled: !modelData.requires || appSettings[modelData.requires] === true

                Label {
                    Layout.fillWidth: true
                    text: modelData.label
                    elide: Text.ElideRight
                    opacity: parent.rowEnabled ? 1.0 : 0.45
                }

                Rectangle {
                    Layout.preferredWidth: units.gu(6.2)
                    Layout.preferredHeight: units.gu(3.2)
                    radius: height / 2
                    color: parent.rowEnabled ? page.switchTrackColor(appSettings[modelData.key] === true) : Qt.rgba(0.5, 0.5, 0.5, 0.14)
                    border.width: 0
                    opacity: parent.rowEnabled ? 1.0 : 0.55

                    Rectangle {
                        width: units.gu(2.6)
                        height: units.gu(2.6)
                        radius: width / 2
                        color: "white"
                        anchors.verticalCenter: parent.verticalCenter
                        x: appSettings[modelData.key] === true ? parent.width - width - units.gu(0.3) : units.gu(0.3)
                        Behavior on x { NumberAnimation { duration: 110 } }
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: parent.parent.rowEnabled
                        onClicked: page.setListControlSetting(modelData.key, !(appSettings[modelData.key] === true))
                    }
                }
            }
        }
    }

    NextCommon.SettingsCard {
        Label {
            Layout.fillWidth: true
            text: i18n.tr("Read-only lists")
            font.bold: true
        }

        Label {
            Layout.fillWidth: true
            text: i18n.tr("Some servers expose Deck cards as read-only task lists. You can hide them from NextTasks.")
            wrapMode: Text.WordWrap
            opacity: 0.72
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: units.gu(1)

            Label {
                Layout.fillWidth: true
                text: i18n.tr("Show read-only lists")
                elide: Text.ElideRight
            }

            Rectangle {
                Layout.preferredWidth: units.gu(6.2)
                Layout.preferredHeight: units.gu(3.2)
                radius: height / 2
                color: page.switchTrackColor(appSettings.showReadOnlyLists)
                border.width: 0

                Rectangle {
                    width: units.gu(2.6)
                    height: units.gu(2.6)
                    radius: width / 2
                    color: "white"
                    anchors.verticalCenter: parent.verticalCenter
                    x: appSettings.showReadOnlyLists ? parent.width - width - units.gu(0.3) : units.gu(0.3)
                    Behavior on x { NumberAnimation { duration: 110 } }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: page.setShowReadOnlyLists(!appSettings.showReadOnlyLists)
                }
            }
        }
    }
}
