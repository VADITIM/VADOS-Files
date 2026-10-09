import QtQuick
import QtQuick.Window
import Vados

Window {
    id: window

    width: Settings.windowWidth
    height: Settings.windowHeight
    minimumWidth: 900
    minimumHeight: 560
    visible: true
    title: Picker.isActive && Picker.title.length > 0 ? Picker.title : workspace.activePane && workspace.activePane.path.length > 0 ? System.nameOf(workspace.activePane.path) + " — VAD/OS Files" : "VAD/OS Files"
    // The ground is set once, at the root, and nothing overrides it (VAS palette).
    color: Theme.ground

    onWidthChanged: saveTimer.restart()
    onHeightChanged: saveTimer.restart()
    onScreenChanged: Theme.screenWidth = screen.width

    Component.onCompleted: Theme.screenWidth = screen.width

    Timer {
        id: saveTimer
        interval: 500
        onTriggered: {
            Settings.windowWidth = window.width
            Settings.windowHeight = window.height
        }
    }

    Workspace {
        id: workspace
        objectName: "workspace"
        anchors.fill: parent
        focus: true
    }
}
