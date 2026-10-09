import QtQuick
import Vados

// A pane over content that arrives from a sixth of its height below on the overshoot and leaves an eighth down, quicker, with no overshoot (VAS glass sheet §1). Solid rather than glass: it floats over thumbnails that would otherwise smear through it.
Item {
    id: root

    property string label: ""
    property bool isOpen: false
    property real offset: 0
    // Anchored to a pointer: it grows out of the corner at the pointer (set by `transformOrigin`) instead of rising from below.
    property bool isAnchored: false
    default property alias content: column.data
    readonly property alias column: column
    signal closed

    visible: opacity > 0
    opacity: 0
    implicitWidth: Theme.rem * 15
    implicitHeight: column.implicitHeight + (label.length > 0 ? Theme.rem * 2.3 : Theme.rem * 0.7) + Theme.rem * 0.35
    transform: Translate { y: root.offset }

    function open() {
        leaveAnimation.stop()
        isOpen = true
        enterAnimation.restart()
    }

    function close() {
        if (!isOpen)
            return
        isOpen = false
        enterAnimation.stop()
        leaveAnimation.restart()
    }

    ParallelAnimation {
        id: enterAnimation
        PropertyAction { target: root; property: "offset"; value: root.isAnchored ? 0 : root.height / 6 }
        PropertyAction { target: root; property: "scale"; value: root.isAnchored ? 0.86 : 0.96 }
        NumberAnimation { target: root; property: "opacity"; from: 0; to: 1; duration: Motion.overlayEnter * 0.6; easing.type: Motion.enter }
        NumberAnimation { target: root; property: "offset"; to: 0; duration: Motion.overlayEnter; easing.type: Motion.enterProminent }
        NumberAnimation { target: root; property: "scale"; to: 1; duration: Motion.overlayEnter; easing.type: Motion.enterProminent }
    }

    SequentialAnimation {
        id: leaveAnimation
        ParallelAnimation {
            NumberAnimation { target: root; property: "opacity"; to: 0; duration: Motion.overlayLeave; easing.type: Motion.leave }
            NumberAnimation { target: root; property: "offset"; to: root.isAnchored ? 0 : root.height / 8; duration: Motion.overlayLeave; easing.type: Motion.leave }
            NumberAnimation { target: root; property: "scale"; to: root.isAnchored ? 0.94 : 0.98; duration: Motion.overlayLeave; easing.type: Motion.leave }
        }
        ScriptAction { script: root.closed() }
    }

    Squircle {
        anchors.fill: parent
        fillColor: Theme.panelSolid
        borderColor: Theme.borderStrong
    }

    Text {
        visible: root.label.length > 0
        x: Theme.rem * 0.9
        y: Theme.rem * 0.75
        width: parent.width - Theme.rem * 1.8
        text: root.label.toUpperCase()
        color: Theme.textLabel
        font.family: Theme.mono
        font.pixelSize: Theme.labelSize
        font.letterSpacing: Theme.labelSpacing
        font.weight: Font.Medium
        elide: Text.ElideNone
        clip: true
    }

    Column {
        id: column
        x: Theme.rem * 0.35
        y: root.label.length > 0 ? Theme.rem * 1.95 : Theme.rem * 0.35
        width: parent.width - Theme.rem * 0.7
    }
}
