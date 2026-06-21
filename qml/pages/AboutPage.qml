import QtQuick 2.7
import QtQuick.Layouts 1.3
import Lomiri.Components 1.3

Page {
    id: page

    property var appController
    readonly property string appVersion: typeof nexttasksAppVersion !== "undefined" ? nexttasksAppVersion : "development"

    header: PageHeader {
        title: i18n.tr("About")
    }

    Flickable {
        anchors {
            fill: parent
            topMargin: page.header.height
        }
        contentWidth: width
        contentHeight: contentColumn.height + units.gu(3)
        clip: true

        ColumnLayout {
            id: contentColumn
            width: parent.width
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: units.gu(2)
            }
            spacing: units.gu(1.4)

            Image {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: units.gu(12)
                Layout.preferredHeight: units.gu(12)
                source: "qrc:/assets/logo.svg"
                fillMode: Image.PreserveAspectFit
            }

            Label {
                Layout.fillWidth: true
                text: appController.appName
                horizontalAlignment: Text.AlignHCenter
                fontSize: "x-large"
                font.bold: true
            }

            Label {
                Layout.fillWidth: true
                text: i18n.tr("Version %1").arg(page.appVersion)
                horizontalAlignment: Text.AlignHCenter
                color: theme.palette.normal.backgroundText
                font.bold: true
            }

            Label {
                Layout.fillWidth: true
                text: appController.appDescription
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: theme.palette.normal.base
            }

            Label {
                Layout.fillWidth: true
                text: i18n.tr("License")
                font.bold: true
            }

            Label {
                Layout.fillWidth: true
                text: i18n.tr("This project is licensed under the MIT License.")
                wrapMode: Text.WordWrap
            }

            Label {
                Layout.fillWidth: true
                text: "Copyright (c) 2026 Etherghost"
                wrapMode: Text.WordWrap
                opacity: 0.75
            }

            Label {
                Layout.fillWidth: true
                text: i18n.tr("This project is not affiliated with, endorsed by, or sponsored by Nextcloud GmbH or the Nextcloud project. Nextcloud is a trademark of its respective owners.")
                wrapMode: Text.WordWrap
                opacity: 0.75
            }
        }
    }
}
