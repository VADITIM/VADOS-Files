import QtQuick
import Vados

// Rename in place. The stem is selected and the extension left alone, so typing replaces the name and keeps the file opening in the same application.
Item {
    id: root

    property bool active: false
    property string path: ""
    property string name: ""
    property bool isDirectory: false
    property var pane
    property alias horizontalAlignment: input.horizontalAlignment
    property bool isCommitting: false

    implicitHeight: input.implicitHeight + Theme.rem * 0.5

    onActiveChanged: {
        if (!active)
            return
        input.text = name
        input.forceActiveFocus()
        const dot = name.lastIndexOf(".")
        input.select(0, isDirectory || dot <= 0 ? name.length : dot)
    }

    function commit() {
        if (!active || isCommitting)
            return
        isCommitting = true
        const problem = FileOperations.rename(path, input.text)
        isCommitting = false
        if (problem.length > 0) {
            pane.workspace.showError(problem)
            input.forceActiveFocus()
            return
        }
        const parent = path.substring(0, path.lastIndexOf("/"))
        pane.expectSelection([parent + "/" + input.text.trim()])
        pane.renamingPath = ""
        pane.forceActiveFocus()
    }

    function cancel() {
        pane.renamingPath = ""
        pane.forceActiveFocus()
    }

    Squircle {
        anchors.fill: parent
        radius: Theme.squircleSmall
        fillColor: Theme.sunkenDeep
        borderColor: Theme.accent
        borderWidth: 1
    }

    TextInput {
        id: input
        anchors.fill: parent
        anchors.margins: Theme.rem * 0.25
        verticalAlignment: TextInput.AlignVCenter
        color: Theme.textBright
        selectionColor: Theme.alpha(Theme.accent, 0.35)
        selectedTextColor: Theme.textBright
        font.family: Theme.mono
        font.pixelSize: Theme.bodySize * 0.93
        clip: true
        selectByMouse: true
        Keys.onReturnPressed: root.commit()
        Keys.onEnterPressed: root.commit()
        Keys.onEscapePressed: root.cancel()
        onActiveFocusChanged: if (!activeFocus && root.active) root.commit()
    }
}
