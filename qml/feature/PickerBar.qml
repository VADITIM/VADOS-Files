import QtQuick
import Vados

// The band under the folder while the window is a file picker (another app asked through the portal): what is being asked, the name to save under, the filter, and the two ways out. On the ground like the toolbar — these are the machine's controls, not content.
Item {
    id: root

    property var workspace
    readonly property var pane: workspace ? workspace.activePane : null
    readonly property bool isSave: Picker.mode === "save"
    property alias name: nameInput.text
    readonly property var controls: [label, isSave ? nameField : caption, filterPill, closePill, acceptPill]

    implicitHeight: Theme.rem * 2

    function focusName() {
        nameInput.forceActiveFocus()
        // The stem is selected and the extension kept, so typing renames without losing the type.
        const dot = nameInput.text.lastIndexOf(".")
        nameInput.select(0, dot > 0 ? dot : nameInput.text.length)
    }

    // The files the accept would hand over right now, named; re-read whenever the selection moves.
    function selectionText(count: int): string {
        if (!pane)
            return ""
        const names = pane.model.selectedPaths().filter(path => Picker.mode === "folder" ? System.isDirectory(path) : !System.isDirectory(path)).map(path => System.nameOf(path))
        if (Picker.mode === "folder")
            return names.length > 0 ? names.join(", ") : System.nameOf(pane.path)
        return names.length > 0 ? names.join(", ") : (Picker.isMultiple ? "Pick one or more files." : "Pick a file.")
    }

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

    // Clicking a file while saving takes its name, the way every save dialog does; the accept then asks before replacing it.
    Connections {
        target: root.isSave && root.pane ? root.pane.model : null
        function onSelectionChanged() {
            const paths = root.pane.model.selectedPaths()
            if (paths.length === 1 && !System.isDirectory(paths[0]))
                nameInput.text = System.nameOf(paths[0])
        }
    }

    Text {
        id: label
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, root.width * 0.22)
        elide: Text.ElideRight
        text: (Picker.title.length > 0 ? Picker.title : Picker.mode === "save" ? "Save as" : Picker.mode === "folder" ? "Pick folder" : "Open").toUpperCase()
        color: Theme.accentInk
        font.family: Theme.mono
        font.pixelSize: Theme.labelSize
        font.letterSpacing: Theme.labelSpacing * 0.7
        font.weight: Font.Medium
    }

    Text {
        id: caption
        visible: !root.isSave
        anchors.left: label.right
        anchors.leftMargin: Theme.rem * 0.9
        anchors.right: filterPill.visible ? filterPill.left : closePill.left
        anchors.rightMargin: Theme.rem * 0.6
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideMiddle
        text: root.selectionText(root.pane ? root.pane.model.selectedCount : 0)
        color: root.pane && root.pane.model.selectedCount > 0 || Picker.mode === "folder" ? Theme.textBright : Theme.textFaint
        font.family: Theme.mono
        font.pixelSize: Theme.bodySize
    }

    Item {
        id: nameField
        visible: root.isSave
        anchors.left: label.right
        anchors.leftMargin: Theme.rem * 0.9
        anchors.right: filterPill.visible ? filterPill.left : closePill.left
        anchors.rightMargin: Theme.rem * 0.6
        height: parent.height

        Squircle {
            anchors.fill: parent
            radius: Theme.squircleSmall
            fillColor: Theme.sunkenDeep
            borderColor: nameInput.activeFocus ? Theme.mix(Theme.accent, Theme.border, 0.55) : nameMouse.containsMouse ? Theme.borderHover : Theme.borderStrong
            Behavior on borderColor { ColorAnimation { duration: Motion.hover } }
        }

        Text {
            anchors.left: nameInput.left
            anchors.verticalCenter: parent.verticalCenter
            visible: nameInput.text.length === 0
            text: "NAME"
            color: Theme.textFaint
            font.family: Theme.mono
            font.pixelSize: Theme.labelSize
            font.letterSpacing: Theme.labelSpacing * 0.6
        }

        MouseArea {
            id: nameMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.IBeamCursor
            onClicked: nameInput.forceActiveFocus()
        }

        TextInput {
            id: nameInput
            anchors.left: parent.left
            anchors.leftMargin: Theme.rem * 0.6
            anchors.right: parent.right
            anchors.rightMargin: Theme.rem * 0.6
            anchors.verticalCenter: parent.verticalCenter
            text: Picker.suggestedName
            color: Theme.textBright
            selectionColor: Theme.alpha(Theme.accent, 0.35)
            selectedTextColor: Theme.textBright
            font.family: Theme.mono
            font.pixelSize: Theme.bodySize
            clip: true
            selectByMouse: true
            Keys.onReturnPressed: root.workspace.pick()
            Keys.onEnterPressed: root.workspace.pick()
            Keys.onEscapePressed: if (root.pane) root.pane.forceActiveFocus()
            Keys.onUpPressed: if (root.pane) root.pane.forceActiveFocus()
        }
    }

    // One pill, cycled by clicking: the filters are few and named by the asking app.
    Pill {
        id: filterPill
        visible: Picker.filters.length > 1
        anchors.right: closePill.left
        anchors.rightMargin: Theme.rem * 0.5
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, root.width * 0.25)
        text: Picker.filters.length > 0 ? Picker.filters[root.workspace.pickerFilter].name : ""
        onClicked: root.workspace.pickerFilter = (root.workspace.pickerFilter + 1) % Picker.filters.length
    }

    Pill {
        id: closePill
        anchors.right: acceptPill.left
        anchors.rightMargin: Theme.rem * 0.5
        anchors.verticalCenter: parent.verticalCenter
        text: "close"
        onClicked: Picker.cancel()
    }

    Pill {
        id: acceptPill
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: Picker.acceptLabel
        isOn: true
        fillColor: Theme.accent
        isEnabled: root.isSave ? nameInput.text.trim().length > 0 : Picker.mode === "folder" || (root.pane !== null && root.pane.model.selectedCount > 0)
        onClicked: root.workspace.pick()
    }
}
