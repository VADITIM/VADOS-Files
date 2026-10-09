import QtQuick
import Vados

// A squircle control with a glyph. Lit is an inset ring in the accent, never a thicker border and never a tinted cell (VAS surface: a grid of controls).
Item {
    id: root

    property string glyph: ""
    property string hint: ""
    property bool isOn: false
    property bool isEnabled: true
    property bool isDanger: false
    property color accent: Theme.accent
    property real glyphSize: Theme.rem * 0.95
    readonly property bool isHovered: mouse.containsMouse
    signal clicked

    implicitWidth: Theme.rem * 2
    implicitHeight: Theme.rem * 2
    opacity: isEnabled ? 1 : 0.38
    z: isHovered ? 50 : 0

    Item {
        id: face
        anchors.fill: parent
        transform: Scale {
            origin.x: face.width / 2
            origin.y: face.height / 2
            xScale: mouse.pressed && root.isEnabled ? 0.94 : 1
            yScale: xScale
            Behavior on xScale { NumberAnimation { duration: Motion.press; easing.type: Motion.state } }
        }

        Squircle {
            anchors.fill: parent
            radius: Theme.squircleSmall
            fillColor: Theme.sunken
            borderColor: root.isHovered && root.isEnabled ? Theme.borderHover : Theme.borderStrong
            insetWidth: root.isOn ? 2 : 0
            insetColor: root.isDanger ? Theme.danger : root.accent
            Behavior on borderColor { ColorAnimation { duration: Motion.hover } }
        }

        Glyph {
            anchors.centerIn: parent
            width: root.glyphSize
            height: root.glyphSize
            name: root.glyph
            ink: root.isDanger ? Theme.danger : root.isOn ? Theme.inkFor(root.accent) : root.isHovered && root.isEnabled ? Theme.textBody : Theme.textIcon
            Behavior on ink { ColorAnimation { duration: Motion.hover } }
        }
    }

    // The hint is an extra, never the only way to learn a control: every control here also has a key.
    Rectangle {
        id: hintBox
        visible: opacity > 0
        opacity: hintTimer.isShown ? 1 : 0
        anchors.top: parent.bottom
        anchors.topMargin: Theme.rem * 0.4
        anchors.horizontalCenter: parent.horizontalCenter
        width: hintText.implicitWidth + Theme.rem
        height: hintText.implicitHeight + Theme.rem * 0.5
        color: Theme.panelSolid
        border.color: Theme.borderStrong
        radius: Theme.rem * 0.3
        Behavior on opacity { NumberAnimation { duration: Motion.hover } }

        Text {
            id: hintText
            anchors.centerIn: parent
            text: root.hint.toUpperCase()
            color: Theme.textMuted
            font.family: Theme.mono
            font.pixelSize: Theme.labelSize
            font.letterSpacing: Theme.labelSpacing * 0.5
        }
    }

    Timer {
        id: hintTimer
        property bool isShown: false
        interval: 650
        running: root.isHovered && root.hint.length > 0 && !mouse.pressed
        onTriggered: isShown = true
        onRunningChanged: if (!running) isShown = false
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.isEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (root.isEnabled) root.clicked()
    }
}
