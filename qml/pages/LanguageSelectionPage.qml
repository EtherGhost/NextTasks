import QtQuick 2.7
import QtQuick.Layouts 1.3
import Qt.labs.settings 1.0
import Lomiri.Components 1.3

Page {
    id: page

    property var appController

    property var languageOptions: [
        { "code": "", "label": i18n.tr("Follow system language"), "detail": i18n.tr("Default") },
        { "code": "en", "label": "English", "detail": i18n.tr("Built-in source language") },
        { "code": "sv", "label": "Svenska", "detail": i18n.tr("Initial translation") },
        { "code": "da", "label": "Dansk", "detail": i18n.tr("AI-assisted starter translation") },
        { "code": "de", "label": "Deutsch", "detail": i18n.tr("AI-assisted starter translation") },
        { "code": "es", "label": "Español", "detail": i18n.tr("AI-assisted starter translation") },
        { "code": "fi", "label": "Suomi", "detail": i18n.tr("AI-assisted starter translation") },
        { "code": "fr", "label": "Français", "detail": i18n.tr("AI-assisted starter translation") },
        { "code": "it", "label": "Italiano", "detail": i18n.tr("AI-assisted starter translation") },
        { "code": "nb", "label": "Norsk bokmål", "detail": i18n.tr("AI-assisted starter translation") },
        { "code": "nl", "label": "Nederlands", "detail": i18n.tr("AI-assisted starter translation") },
        { "code": "pl", "label": "Polski", "detail": i18n.tr("AI-assisted starter translation") },
        { "code": "ru", "label": "Русский", "detail": i18n.tr("AI-assisted starter translation") },
        { "code": "uk", "label": "Українська", "detail": i18n.tr("AI-assisted starter translation") }
    ]

    header: PageHeader {
        title: i18n.tr("Language")
    }

    Settings {
        id: appSettings
        property string languageCode: ""
    }

    ColumnLayout {
        anchors {
            fill: parent
            topMargin: page.header.height + units.gu(1)
            leftMargin: units.gu(1.5)
            rightMargin: units.gu(1.5)
            bottomMargin: units.gu(1.5)
        }
        spacing: units.gu(1)

        Label {
            Layout.fillWidth: true
            text: i18n.tr("Choose the language this app should use. Restart the app after changing language.")
            wrapMode: Text.WordWrap
        }

        ListView {
            id: languageList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: units.gu(0.6)
            model: page.languageOptions

            delegate: Rectangle {
                readonly property bool selected: modelData.code === appSettings.languageCode

                width: languageList.width
                height: units.gu(6)
                radius: units.gu(0.5)
                color: selected ? "#1f6feb" : theme.palette.normal.background
                border.width: selected ? 0 : 1
                border.color: "#7a7a7a"

                RowLayout {
                    anchors {
                        fill: parent
                        leftMargin: units.gu(1)
                        rightMargin: units.gu(1)
                    }
                    spacing: units.gu(1)

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: units.gu(0.1)

                        Label {
                            Layout.fillWidth: true
                            text: modelData.label
                            color: selected ? "white" : theme.palette.normal.backgroundText
                            font.bold: selected
                            elide: Text.ElideRight
                        }

                        Label {
                            Layout.fillWidth: true
                            text: modelData.detail
                            color: selected ? "white" : "#7a7a7a"
                            fontSize: "small"
                            elide: Text.ElideRight
                        }
                    }

                    Label {
                        visible: selected
                        text: "✓"
                        color: "white"
                        font.pixelSize: units.gu(2.4)
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: appSettings.languageCode = modelData.code
                }
            }
        }
    }
}
