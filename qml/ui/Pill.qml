import QtQuick
import Vados

// A capsule action: one verb, uppercase, Mono at label tracking. Danger pills are filled red with dark ink, because the one irreversible tap must be the easiest to find (VAS confirm and undo).
Item {
    id: root

    property string text: ""
    property string glyph: ""
    property bool isDanger: false
    property bool isOn: false
    property bool isEnabled: true
    property color accent: Theme.accent
    property color fillColor: isDanger ? Theme.danger : Theme.sunken
    property real textScale: 1
    readonly property bool isHovered: mouse.containsMouse
    signal clicked

    implicitHeight: Theme.rem * 1.9
    implicitWidth: row.implicitWidth + Theme.rem * 1.3
    opacity: isEnabled ? 1 : 0.38

    transform: Scale {
        origin.x: root.width / 2
        origin.y: root.height / 2
        xScale: mouse.pressed && root.isEnabled ? 0.96 : 1
        yScale: xScale
        Behavior on xScale { NumberAnimation { duration: Motion.press; easing.type: Motion.state } }
    }

    Squircle {
        anchors.fill: parent
        radius: height / 2
        exponent: 3
        fillColor: root.fillColor
        borderColor: root.isDanger ? Theme.danger : root.isHovered && root.isEnabled ? Theme.borderHover : Theme.borderStrong
        insetWidth: root.isOn ? 2 : 0
        insetColor: root.accent
        Behavior on borderColor { ColorAnimation { duration: Motion.hover } }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Theme.rem * 0.4

        Glyph {
            visible: root.glyph.length > 0
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.rem * 0.85
            height: width
            name: root.glyph
            ink: root.isDanger ? Theme.sunkenDeep : root.isOn ? Theme.inkFor(root.accent) : Theme.textBody
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.text.toUpperCase()
            color: root.isDanger ? Theme.sunkenDeep : root.isOn ? Theme.inkFor(root.accent) : root.isHovered ? Theme.textBright : Theme.textBody
            font.family: Theme.mono
            font.pixelSize: Theme.labelSize * root.textScale
            font.letterSpacing: Theme.labelSpacing * 0.7 * root.textScale
            font.weight: Font.Medium
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: if (root.isEnabled) root.clicked()
    }
}
