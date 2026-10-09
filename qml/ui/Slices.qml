import QtQuick
import QtQuick.Shapes
import Vados

// The diagonal slice behind every room (VAS surface): two slanted layers of the accent at low opacity, parked off the left edge and swept in with the room. Nothing else in the app uses a diagonal.
Item {
    id: root

    property color accent: Theme.accent
    property real backReveal: 0
    property real frontReveal: 0
    readonly property real sliceWidth: width * 0.6

    function enter(delay: int) {
        leaveAnimation.stop()
        enterAnimation.delay = delay
        enterAnimation.restart()
    }

    function leave() {
        enterAnimation.stop()
        leaveAnimation.restart()
    }

    function showNow() {
        enterAnimation.stop()
        leaveAnimation.stop()
        backReveal = 1
        frontReveal = 1
    }

    // The front layer trails the back by 0.1s: one slice is a wipe, two at different rakes and speeds is parallax.
    SequentialAnimation {
        id: enterAnimation
        property int delay: 0
        PauseAnimation { duration: enterAnimation.delay }
        ParallelAnimation {
            NumberAnimation { target: root; property: "backReveal"; to: 1; duration: Motion.sliceEnter; easing.type: Motion.enterProminent }
            SequentialAnimation {
                PauseAnimation { duration: Motion.sliceLayerOffset }
                NumberAnimation { target: root; property: "frontReveal"; to: 1; duration: Motion.sliceEnter; easing.type: Motion.enterProminent }
            }
        }
    }

    ParallelAnimation {
        id: leaveAnimation
        NumberAnimation { target: root; property: "backReveal"; to: 0; duration: Motion.sliceLeave; easing.type: Motion.leaveLarge }
        NumberAnimation { target: root; property: "frontReveal"; to: 0; duration: Motion.sliceLeave; easing.type: Motion.leaveLarge }
    }

    Shape {
        x: -root.width * 0.1 - (1 - root.backReveal) * root.sliceWidth * 1.15
        width: root.sliceWidth
        height: root.height
        opacity: 0.06
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: 0
            strokeColor: "transparent"
            fillColor: root.accent
            startX: 0; startY: 0
            PathLine { x: root.sliceWidth; y: 0 }
            PathLine { x: root.sliceWidth * 0.62; y: root.height }
            PathLine { x: 0; y: root.height }
        }
    }

    Shape {
        x: -root.width * 0.1 - (1 - root.frontReveal) * root.sliceWidth * 1.15
        width: root.sliceWidth
        height: root.height
        opacity: 0.04
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: 0
            strokeColor: "transparent"
            fillColor: root.accent
            startX: 0; startY: 0
            PathLine { x: root.sliceWidth * 0.78; y: 0 }
            PathLine { x: root.sliceWidth * 0.4; y: root.height }
            PathLine { x: 0; y: root.height }
        }
    }
}
