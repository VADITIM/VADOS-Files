import QtQuick
import Vados

// One action in a menu sheet. A row that does not apply stays in its place, greyed, so the menu keeps one layout (VAS glass sheet §6).
Item {
    id: root

    property string text: ""
    property string glyph: ""
    property string shortcut: ""
    property bool isEnabled: true
    property bool isDanger: false
    property bool hasSubmenu: false
    property bool isHighlighted: false
    readonly property bool isActive: (mouse.containsMouse || isHighlighted) && isEnabled
    signal triggered
    signal hovered

    implicitHeight: Theme.rem * 1.85
    opacity: isEnabled ? 1 : 0.38

    transform: Scale {
        origin.x: root.width / 2
        origin.y: root.height / 2
        xScale: mouse.pressed && root.isEnabled ? 0.98 : 1
        yScale: xScale
        Behavior on xScale { NumberAnimation { duration: Motion.press } }
    }

    Squircle {
        anchors.fill: parent
        radius: Theme.squircleSmall
        fillColor: root.isActive ? Theme.raised : "transparent"
        borderColor: "transparent"
        borderWidth: 0
        Behavior on fillColor { ColorAnimation { duration: Motion.press } }
    }

    Glyph {
        id: icon
        x: Theme.rem * 0.6
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.rem * 0.9
        height: width
        name: root.glyph
        visible: root.glyph.length > 0
        ink: root.isDanger ? Theme.danger : root.isActive ? Theme.accentInk : Theme.textIcon
    }

    Text {
        anchors.left: parent.left
        anchors.leftMargin: Theme.rem * 2
        anchors.right: shortcutText.left
        anchors.rightMargin: Theme.rem * 0.5
        anchors.verticalCenter: parent.verticalCenter
        text: root.text.toUpperCase()
        color: root.isDanger ? Theme.danger : root.isActive ? Theme.textBright : Theme.textBody
        font.family: Theme.mono
        font.pixelSize: Theme.labelSize * 1.05
        font.letterSpacing: Theme.labelSpacing * 0.45
        elide: Text.ElideNone
        clip: true
    }

    Text {
        id: shortcutText
        anchors.right: parent.right
        anchors.rightMargin: Theme.rem * 0.6
        anchors.verticalCenter: parent.verticalCenter
        text: root.hasSubmenu ? "" : root.shortcut
        color: Theme.textFaint
        font.family: Theme.mono
        font.pixelSize: Theme.labelSize
    }

    Glyph {
        visible: root.hasSubmenu
        anchors.right: parent.right
        anchors.rightMargin: Theme.rem * 0.5
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.rem * 0.7
        height: width
        name: "chevron"
        ink: root.isActive ? Theme.accentInk : Theme.textIcon
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onContainsMouseChanged: if (containsMouse) root.hovered()
        onClicked: if (root.isEnabled) root.triggered()
    }
}
