import QtQuick
import Vados

// A row of loose controls on the ground (history, view), assembling left to right on the launch like the toolbar.
Row {
    id: root

    spacing: Theme.rem * 0.3
    height: Theme.rem * 2

    function enter(delay: int) {
        for (let index = 0; index < children.length; ++index) {
            const control = children[index]
            control.opacity = 0
            control.scale = 0.92
            enterTimer.createObject(root, { target: control, delay: delay + index * Motion.launchStaggerHorizontal * 2 })
        }
    }

    Component {
        id: enterTimer
        SequentialAnimation {
            id: animation
            property var target
            property int delay: 0
            running: true
            PauseAnimation { duration: animation.delay }
            ParallelAnimation {
                NumberAnimation { target: animation.target; property: "opacity"; to: 1; duration: Motion.launchPanelEnter; easing.type: Motion.enter }
                NumberAnimation { target: animation.target; property: "scale"; to: 1; duration: Motion.launchPanelEnter; easing.type: Motion.enterProminent }
            }
            onFinished: animation.destroy()
        }
    }
}
