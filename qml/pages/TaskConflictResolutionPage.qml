import QtQuick 2.7
import QtQuick.Layouts 1.3
import Lomiri.Components 1.3

Page {
    id: page

    property var tasksController
    property var task: ({})
    property string selectedVersion: "local"

    header: PageHeader {
        title: i18n.tr("Conflict")
    }

    ColumnLayout {
        anchors {
            top: header.bottom
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            margins: units.gu(2)
        }
        spacing: units.gu(1.25)

        Label {
            Layout.fillWidth: true
            text: task.title || i18n.tr("Untitled task")
            font.bold: true
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        Label {
            Layout.fillWidth: true
            text: i18n.tr("The server changed this task while you had local edits. Review one version, then choose which version to keep.")
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            opacity: 0.82
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: units.gu(1)

            Button {
                Layout.fillWidth: true
                text: i18n.tr("Server version")
                color: page.selectedVersion === "server" ? "#c7162b" : theme.palette.normal.background
                onClicked: page.selectedVersion = "server"
            }

            Button {
                Layout.fillWidth: true
                text: i18n.tr("Local version")
                color: page.selectedVersion === "local" ? "#c65d00" : theme.palette.normal.background
                onClicked: page.selectedVersion = "local"
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: units.gu(0.5)
            color: "transparent"
            border.width: 1
            border.color: page.selectedVersion === "server" ? "#c7162b" : "#c65d00"

            ColumnLayout {
                anchors {
                    fill: parent
                    margins: units.gu(1)
                }
                spacing: units.gu(0.75)

                Label {
                    Layout.fillWidth: true
                    text: page.selectedVersion === "server"
                        ? page.serverConflictMetadata()
                        : page.localConflictMetadata()
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    opacity: 0.72
                }

                TextArea {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    readOnly: true
                    text: tasksController
                        ? tasksController.conflictPreviewText(task, page.selectedVersion)
                        : ""
                }
            }
        }

        Button {
            Layout.fillWidth: true
            text: page.selectedVersion === "server"
                ? i18n.tr("Use server version")
                : i18n.tr("Keep local version")
            enabled: task.conflict === true && tasksController && !tasksController.loading
            onClicked: {
                if (page.selectedVersion === "server") {
                    tasksController.discardLocalTaskAndUseServer(task)
                } else {
                    tasksController.keepLocalTaskAfterConflict(task)
                }
                pageStack.pop()
            }
        }
    }

    function serverConflictMetadata() {
        var serverTask = tasksController ? tasksController.serverConflictTask(task) : null
        if (!serverTask) {
            return i18n.tr("Server version is not available.")
        }
        return task.conflictEtag && task.conflictEtag.length > 0
            ? i18n.tr("Server version - ETag available")
            : i18n.tr("Server version")
    }

    function localConflictMetadata() {
        return task.localModified && task.localModified > 0
            ? i18n.tr("Local version - unsynced")
            : i18n.tr("Local version")
    }
}
