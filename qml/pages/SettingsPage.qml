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
        property bool syncWhileActive: true
        property bool syncOnStartup: true
        property string swipeActionLayout: "ut"
    }

    NextCommon.SettingsCard {
        Label {
            Layout.fillWidth: true
            text: i18n.tr("Sync")
            font.bold: true
        }

        CheckBox {
            text: i18n.tr("Sync while app is active")
            checked: appSettings.syncWhileActive
            onCheckedChanged: appSettings.syncWhileActive = checked
        }

        CheckBox {
            text: i18n.tr("Sync on startup")
            checked: appSettings.syncOnStartup
            onCheckedChanged: appSettings.syncOnStartup = checked
        }

        Label {
            Layout.fillWidth: true
            text: i18n.tr("These settings are placeholders until the app-specific API, cache, and sync controller are implemented.")
            wrapMode: Text.WordWrap
            opacity: 0.72
        }
    }

    NextCommon.SettingsCard {
        Label {
            Layout.fillWidth: true
            text: i18n.tr("Swipe actions")
            font.bold: true
        }

        Label {
            Layout.fillWidth: true
            text: i18n.tr("Choose where destructive swipe actions should appear. Ubuntu Touch style is the default.")
            wrapMode: Text.WordWrap
            opacity: 0.72
        }

        Repeater {
            model: [
                {"value": "ut", "label": i18n.tr("Ubuntu Touch style"), "description": i18n.tr("Use platform conventions for swipe actions.")},
                {"value": "android", "label": i18n.tr("Android style"), "description": i18n.tr("Match the Android client where practical.")}
            ]

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: units.gu(6.5)
                radius: units.gu(0.5)
                color: appSettings.swipeActionLayout === modelData.value ? Qt.rgba(0.17, 0.5, 0.72, 0.16) : "transparent"
                border.width: 1
                border.color: "#7a7a7a"

                RowLayout {
                    anchors {
                        fill: parent
                        margins: units.gu(1)
                    }
                    spacing: units.gu(1)

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: units.gu(0.2)

                        Label {
                            Layout.fillWidth: true
                            text: modelData.label
                            font.bold: appSettings.swipeActionLayout === modelData.value
                            elide: Text.ElideRight
                        }

                        Label {
                            Layout.fillWidth: true
                            text: modelData.description
                            textSize: Label.Small
                            opacity: 0.72
                            elide: Text.ElideRight
                        }
                    }

                    Label {
                        text: appSettings.swipeActionLayout === modelData.value ? "\u2713" : ""
                        color: "#2c7fb8"
                        font.bold: true
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: appSettings.swipeActionLayout = modelData.value
                }
            }
        }
    }
}
