import QtQuick
import Vados

// The controls over the folder: the path, the filter, and the details switch. History sits above the places; the view controls and settings sit in the top band (Workspace). They sit on the ground, not in a module — they are the machine's controls, not content.
Item {
    id: root

    property var workspace
    readonly property var pane: workspace ? workspace.activePane : null
    readonly property var controls: [pathBar, searchField, detailsButton]

    implicitHeight: Theme.rem * 2

    function editPath() {
        pathBar.edit()
    }

    function focusSearch() {
        searchField.focusField()
    }

    // The controls assemble left to right like everything else on screen, each on its own share of the stagger.
    function enter(delay: int) {
        for (const control of controls) {
            const offset = Motion.positionalDelay(control.x, 0, root.width, 1, 0, Motion.launchStaggerHorizontal * 2)
            control.opacity = 0
            control.scale = 0.92
            enterTimer.createObject(root, { target: control, delay: delay + offset })
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

    PathBar {
        id: pathBar
        workspace: root.workspace
        anchors.left: parent.left
        anchors.right: searchField.left
        anchors.rightMargin: Theme.rem * 0.5
        height: parent.height
    }

    SearchField {
        id: searchField
        workspace: root.workspace
        anchors.right: viewRow.left
        anchors.rightMargin: Theme.rem * 0.5
        // A button until it is wanted: it opens to a short field on a click or Ctrl+F, and folds back when it is empty and loses focus. The path takes the room back.
        width: isExpanded ? Math.max(Theme.rem * 5, Math.min(Theme.rem * 8.5, (root.width - viewRow.width - Theme.rem) / 3)) : Theme.rem * 2
        Behavior on width { NumberAnimation { duration: Motion.stateChange; easing.type: Motion.enterProminent } }
        height: parent.height
    }

    Row {
        id: viewRow
        anchors.right: parent.right
        spacing: Theme.rem * 0.3
        height: parent.height

        IconButton {
            id: detailsButton
            glyph: "details"
            hint: "details · alt p"
            isOn: Settings.showDetails
            onClicked: root.workspace.command("details")
        }
    }
}
