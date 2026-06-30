import QtQuick 2.7
import Lomiri.Components 1.3

Rectangle {
    id: root

    signal clicked()

    property alias text: label.text

    radius: units.gu(0.4)
    color: mouse.pressed ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

    Label {
        id: label
        anchors.centerIn: parent
        color: theme.palette.normal.backgroundText
        font.pixelSize: units.gu(2.6)
        font.bold: true
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        onClicked: root.clicked()
    }
}

