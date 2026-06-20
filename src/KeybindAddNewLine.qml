pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    signal clicked()

    implicitWidth: contentRow.implicitWidth + 24
    implicitHeight: 32
    radius: Appearance.rounding.full
    color: clickArea.containsMouse
        ? Appearance.colors.colLayer1Hover
        : "transparent"
    border.width: 1
    border.color: Appearance.colors.colOutlineVariant

    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }

    Row {
        id: contentRow
        anchors.centerIn: parent
        spacing: 6
        MaterialSymbol {
            anchors.verticalCenter: parent.verticalCenter
            text: "add"; iconSize: 18
            color: Appearance.m3colors.m3onSurfaceVariant
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: "Add keybind"
            color: Appearance.m3colors.m3onSurfaceVariant
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
    }

    MouseArea {
        id: clickArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
