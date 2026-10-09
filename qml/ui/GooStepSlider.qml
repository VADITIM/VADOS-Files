import QtQuick
import Vados

// A handful of discrete steps is a rail of slots with one liquid dot (VAS interaction): the dot follows the pointer continuously, merges into the slot it reaches, settles on release, and commits once.
Item {
    id: root

    property int count: 4
    property int value: 0
    property real position: value
    readonly property real slotSize: Theme.rem * 0.6
    readonly property real spacing: Theme.rem * 1.05
    signal committed(int value)

    implicitWidth: spacing * (count - 1) + slotSize + Theme.rem
    implicitHeight: Theme.rem * 1.6

    onValueChanged: if (!mouse.pressed) settle.restartTo(value)

    function positionAt(x: real): real {
        const start = (width - (count - 1) * spacing) / 2
        return Math.max(0, Math.min(count - 1, (x - start) / spacing))
    }

    ShaderEffect {
        anchors.fill: parent
        readonly property size itemSize: Qt.size(width, height)
        readonly property real slotCount: root.count
        readonly property real slotSize: root.slotSize
        readonly property real spacing: root.spacing
        readonly property real dotPosition: root.position
        readonly property real dotRadius: root.slotSize * 0.42
        readonly property real blend: Theme.rem * 0.55
        readonly property color railColor: Theme.alpha(Theme.textIcon, mouse.containsMouse ? 0.45 : 0.3)
        readonly property color flowColor: Theme.accentInk
        fragmentShader: "qrc:/shaders/gooRail.frag.qsb"
    }

    NumberAnimation {
        id: settle
        target: root
        property: "position"
        easing.type: Motion.enterProminent
        function restartTo(target: real) {
            stop()
            to = target
            // Over the share of the distance that is left, so a release near a slot does not crawl (VAS motion §14).
            duration = Math.max(90, Motion.stateChange * Math.min(1, Math.abs(target - root.position) * 1.5))
            start()
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: event => { settle.stop(); root.position = root.positionAt(event.x) }
        onPositionChanged: event => { if (pressed) root.position = root.positionAt(event.x) }
        onReleased: {
            const step = Math.round(root.position)
            settle.restartTo(step)
            if (step !== root.value)
                root.committed(step)
        }
        onWheel: wheel => {
            const step = Math.max(0, Math.min(root.count - 1, root.value + (wheel.angleDelta.y > 0 ? 1 : -1)))
            if (step !== root.value)
                root.committed(step)
        }
    }
}
