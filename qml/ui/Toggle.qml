import QtQuick
import Vados

// Nothing with two states is a switch (VAS controls §1): a row whose mark is lit with an inset ring when it is on.
Item {
    id: root

    property string text: ""
    property string detail: ""
    property bool isOn: false
    signal toggled

    implicitHeight: Math.max(Theme.rem * 2, words.implicitHeight + Theme.rem * 0.8)

    Column {
        id: words
        anchors.left: parent.left
        anchors.right: mark.left
        anchors.rightMargin: Theme.rem
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.rem * 0.15

        Text {
            text: root.text.toUpperCase()
            color: mouse.containsMouse ? Theme.textBright : Theme.textBody
            font.family: Theme.mono
            font.pixelSize: Theme.labelSize * 1.05
            font.letterSpacing: Theme.labelSpacing * 0.45
        }

        Text {
            visible: root.detail.length > 0
            width: parent.width
            text: root.detail
            color: Theme.textFaint
            font.family: Theme.mono
            font.pixelSize: Theme.smallSize
            wrapMode: Text.WordWrap
        }
    }

    IconButton {
        id: mark
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.rem * 1.5
        height: width
        glyphSize: Theme.rem * 0.75
        glyph: root.isOn ? "check" : ""
        isOn: root.isOn
        onClicked: root.toggled()
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        anchors.rightMargin: mark.width + Theme.rem
        hoverEnabled: true
        onClicked: root.toggled()
    }
}
