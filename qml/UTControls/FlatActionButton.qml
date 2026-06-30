import QtQuick 2.7
import Lomiri.Components 1.3

Rectangle {
    id: root

    signal clicked()

    property alias text: label.text
    property bool accent: false
    readonly property real buttonImplicitWidth: label.implicitWidth + units.gu(2)

    radius: units.gu(0.4)
    color: mouse.pressed ? (accent ? Qt.rgba(0.17, 0.5, 0.72, 0.18) : Qt.rgba(1, 1, 1, 0.08)) : "transparent"

    Label {
        id: label
        anchors.centerIn: parent
        color: root.accent ? "#2c7fb8" : theme.palette.normal.backgroundText
        opacity: root.accent ? 1 : 0.78
        font.bold: root.accent
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        onClicked: root.clicked()
    }
}

