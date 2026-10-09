import QtQuick
import Vados

// Where you are: the full path, always, as segments you can click or drop onto. A path longer than the bar shrinks to fit before anything is cut. Click the empty end of the bar, or press Ctrl+L, to type a path instead.
Item {
    id: root

    property var workspace
    readonly property var pane: workspace ? workspace.activePane : null
    readonly property string path: pane ? pane.path : ""
    property bool isEditing: false
    property var completions: []
    readonly property var segments: {
        if (path.length === 0)
            return []
        if (path === "trash:///")
            return [{ name: "Trash", path: path, isRoot: true }]
        const list = [{ name: "/", path: "/", isRoot: true }]
        let walked = ""
        for (const part of path.split("/").filter(part => part.length > 0)) {
            walked += "/" + part
            list.push({ name: part, path: walked, isRoot: false })
        }
        return list
    }

    implicitHeight: Theme.rem * 2

    function edit() {
        isEditing = true
        input.text = path === "trash:///" ? path : path + (path === "/" ? "" : "/")
        input.forceActiveFocus()
        input.selectAll()
        updateCompletions()
    }

    function stopEditing() {
        isEditing = false
        completions = []
        if (pane)
            pane.forceActiveFocus()
    }

    function commit() {
        const target = System.expandPath(input.text)
        stopEditing()
        if (target.length > 0)
            workspace.command("navigate", target)
    }

    function updateCompletions() {
        completions = System.completePath(input.text)
    }

    Squircle {
        anchors.fill: parent
        radius: Theme.squircleSmall
        fillColor: Theme.sunkenDeep
        borderColor: root.isEditing ? Theme.mix(Theme.accent, Theme.border, 0.55) : backgroundMouse.containsMouse ? Theme.borderHover : Theme.borderStrong
        Behavior on borderColor { ColorAnimation { duration: Motion.hover } }
    }

    MouseArea {
        id: backgroundMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.IBeamCursor
        onClicked: root.edit()
    }

    Item {
        id: viewport
        visible: !root.isEditing
        anchors.fill: parent
        anchors.leftMargin: Theme.rem * 0.35
        anchors.rightMargin: Theme.rem * 0.35
        clip: true
        // Shrink to fit, down to 60%; only past that does the start fade out, keeping the end in view (VAS typography).
        readonly property real fitScale: crumbs.implicitWidth > 0 ? Math.max(0.6, Math.min(1, width / crumbs.implicitWidth)) : 1
        readonly property bool isOverflowing: crumbs.implicitWidth * fitScale > width

        layer.enabled: isOverflowing
        layer.effect: ShaderEffect {
            property variant source
            readonly property size itemSize: Qt.size(width, height)
            readonly property real fadeWidth: Theme.rem * 1.6
            readonly property real fadeTop: 0
            readonly property real isMirrored: 1
            fragmentShader: "qrc:/shaders/fadeEdge.frag.qsb"
        }

        Row {
            id: crumbs
            x: viewport.isOverflowing ? viewport.width - implicitWidth * viewport.fitScale : 0
            height: parent.height
            transformOrigin: Item.Left
            scale: viewport.fitScale
            spacing: 0

            Repeater {
                model: root.segments

                delegate: Row {
                    id: crumb
                    required property var modelData
                    required property int index
                    readonly property bool isLast: index === root.segments.length - 1
                    height: parent.height

                    Text {
                        visible: crumb.index > 1
                        anchors.verticalCenter: parent.verticalCenter
                        text: "/"
                        color: Theme.textLabel
                        font.family: Theme.mono
                        font.pixelSize: Theme.bodySize
                    }

                    Item {
                        id: segment
                        anchors.verticalCenter: parent.verticalCenter
                        width: segmentText.implicitWidth + Theme.rem * (crumb.modelData.isRoot ? 0.5 : 0.4)
                        height: Theme.rem * 1.45
                        readonly property bool isDropTarget: segmentDrop.containsDrag && segmentDrop.isAccepting

                        Squircle {
                            anchors.fill: parent
                            radius: Theme.squircleSmall
                            fillColor: segmentMouse.containsMouse || segment.isDropTarget ? Theme.raised : Theme.alpha(Theme.raised, 0)
                            borderColor: segment.isDropTarget ? Theme.accent : Theme.alpha(Theme.border, 0)
                            Behavior on fillColor { ColorAnimation { duration: Motion.press } }
                        }

                        Text {
                            id: segmentText
                            anchors.centerIn: parent
                            text: crumb.modelData.name
                            color: crumb.isLast ? Theme.accentInk : segmentMouse.containsMouse ? Theme.textBright : Theme.textBody
                            font.family: Theme.mono
                            font.pixelSize: Theme.bodySize
                            font.weight: crumb.isLast ? Font.Bold : Font.Normal
                        }

                        MouseArea {
                            id: segmentMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: event => {
                                if (event.button === Qt.MiddleButton)
                                    root.workspace.openTab(crumb.modelData.path)
                                else if (!crumb.isLast || root.pane.model.mode !== "folder")
                                    root.workspace.command("navigate", crumb.modelData.path)
                            }
                        }

                        DropArea {
                            id: segmentDrop
                            anchors.fill: parent
                            property bool isAccepting: false
                            onEntered: event => { isAccepting = root.workspace.acceptDrag(event, crumb.modelData.path, segment, segmentDrop) }
                            onPositionChanged: event => { if (isAccepting) root.workspace.updateDrag(event, crumb.modelData.path, segment, segmentDrop) }
                            onExited: { isAccepting = false; root.workspace.leaveDrag(segment) }
                            onDropped: event => { isAccepting = false; root.workspace.dropOnto(event, crumb.modelData.path, segment, segmentDrop) }
                        }
                    }
                }
            }
        }
    }

    TextInput {
        id: input
        visible: root.isEditing
        anchors.fill: parent
        anchors.leftMargin: Theme.rem * 0.7
        anchors.rightMargin: Theme.rem * 0.7
        verticalAlignment: TextInput.AlignVCenter
        color: Theme.textBright
        selectionColor: Theme.alpha(Theme.accent, 0.35)
        selectedTextColor: Theme.textBright
        font.family: Theme.mono
        font.pixelSize: Theme.bodySize
        clip: true
        selectByMouse: true
        onTextEdited: root.updateCompletions()
        // A click on a completion takes focus for a moment before handing it back; only a focus that stays gone ends the edit.
        onActiveFocusChanged: if (!activeFocus && root.isEditing) focusLossTimer.restart()
        Keys.onReturnPressed: root.commit()
        Keys.onEnterPressed: root.commit()
        Keys.onEscapePressed: root.stopEditing()
        Keys.onTabPressed: {
            if (root.completions.length > 0) {
                text = root.completions[0] + "/"
                root.updateCompletions()
            }
        }
        Keys.onDownPressed: if (root.completions.length > 0) { text = root.completions[0] + "/"; root.updateCompletions() }
    }

    Timer {
        id: focusLossTimer
        interval: 160
        onTriggered: if (!input.activeFocus && root.isEditing) root.stopEditing()
    }

    MenuSheet {
        id: completionSheet
        anchors.top: parent.bottom
        anchors.topMargin: Theme.rem * 0.35
        x: Theme.rem * 0.4
        z: 200
        width: Math.min(root.width, Theme.rem * 22)
        readonly property bool shouldShow: root.isEditing && root.completions.length > 0
        onShouldShowChanged: shouldShow ? open() : close()

        Repeater {
            model: root.completions
            delegate: MenuRow {
                required property string modelData
                width: completionSheet.column.width
                text: ""
                glyph: "folder"

                FadeText {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.rem * 2
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.rem * 0.6
                    anchors.verticalCenter: parent.verticalCenter
                    // The folder's own name; the path it sits in is already in the field above.
                    text: modelData.substring(modelData.lastIndexOf("/") + 1)
                    color: Theme.textBody
                    font.pixelSize: Theme.smallSize
                }

                onTriggered: {
                    input.text = modelData + "/"
                    input.forceActiveFocus()
                    root.updateCompletions()
                }
            }
        }
    }
}
