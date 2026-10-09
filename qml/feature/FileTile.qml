import QtQuick
import Vados

// One file in the grid. At rest it is only a glyph and a name on the ground; the box appears under the pointer, and a selected tile sets its picture aside — shrunk a little, ringed in the accent, ticked (VAS motion §6.10: the selected shrink).
Item {
    id: root

    required property int index
    required property string name
    required property string path
    required property bool isDirectory
    required property string kind
    required property string suffix
    required property string sizeText
    required property bool isSelected
    required property bool isCut
    required property bool canThumbnail
    required property bool isSymlink
    required property bool isHidden
    property var pane

    readonly property bool isHovered: hover.hovered
    readonly property bool isCarried: pane.carriedPaths.indexOf(path) !== -1
    readonly property bool isDropTarget: drop.containsDrag && drop.isAccepting
    readonly property bool isRenaming: pane.renamingPath === path
    readonly property bool isCurrent: pane.model.currentIndex === index && pane.isKeyboardFocused
    readonly property bool hasThumbnail: thumbnail.status === Image.Ready
    property real enterShift: 0

    width: pane.cellWidth
    height: pane.cellHeight
    transform: Translate { x: root.enterShift }

    function hitTest(localX: real, localY: real): bool {
        return localX >= body.x && localX <= body.x + body.width && localY >= body.y && localY <= body.y + body.height
    }

    // #region ── enter and leave ───────────────────────────────────────────────────────────────
    function enterDelay(): int {
        const columns = Math.max(1, pane.columns)
        const x = (index % columns) * pane.cellWidth
        const y = Math.floor(index / columns) * pane.cellHeight - pane.contentY
        return Motion.positionalDelay(x, y, pane.viewWidth, pane.viewHeight, Motion.navigateStaggerVertical, Motion.navigateStaggerHorizontal)
    }

    function playEnter(delay: int) {
        leaveAnimation.stop()
        enterAnimation.stop()
        enterAnimation.delay = delay
        enterAnimation.start()
    }

    function playLeave() {
        enterAnimation.stop()
        leaveAnimation.start()
    }

    Component.onCompleted: {
        if (pane.isEntering)
            playEnter(enterDelay())
        else if (pane.isHeld)
            opacity = 0
    }

    Connections {
        target: root.pane
        function onLeaveRequested() { root.playLeave() }
        function onEnterRequested() { root.playEnter(root.enterDelay()) }
    }

    SequentialAnimation {
        id: enterAnimation
        property int delay: 0
        // Travel carries direction: going into a folder its contents come from the right, coming back out they come from the left.
        ScriptAction {
            script: {
                root.opacity = 0
                root.scale = Motion.isLite ? 1 : 0.92
                root.enterShift = Motion.isLite ? 0 : (pane.direction === "out" ? -Theme.rem * 0.9 : pane.direction === "into" ? Theme.rem * 0.9 : 0)
            }
        }
        PauseAnimation { duration: enterAnimation.delay }
        ParallelAnimation {
            NumberAnimation { target: root; property: "opacity"; to: 1; duration: Motion.navigateEnter * 0.8; easing.type: Motion.enter }
            NumberAnimation { target: root; property: "scale"; to: 1; duration: Motion.navigateEnter; easing.type: Motion.enterProminent }
            NumberAnimation { target: root; property: "enterShift"; to: 0; duration: Motion.navigateEnter; easing.type: Motion.enter }
        }
    }

    ParallelAnimation {
        id: leaveAnimation
        NumberAnimation { target: root; property: "opacity"; to: 0; duration: Motion.navigateLeave; easing.type: Motion.leave }
        NumberAnimation { target: root; property: "scale"; to: 0.97; duration: Motion.navigateLeave; easing.type: Motion.leave }
    }
    // #endregion ───────────────────────────────────────────────────────────────────────────────

    Item {
        id: body
        anchors.fill: parent
        anchors.margins: Theme.rem * 0.16
        opacity: root.isCarried ? 0.3 : root.isCut ? 0.45 : root.isHidden && !root.isSelected && !root.isHovered ? 0.5 : 1
        // The drop swell is its own property, so it layers onto the entrance instead of fighting it for `scale`.
        transform: Scale {
            origin.x: body.width / 2
            origin.y: body.height / 2
            xScale: root.isDropTarget ? 1.06 : mouseDown.isPressed ? 0.96 : 1
            yScale: xScale
            Behavior on xScale { NumberAnimation { duration: Motion.stateChange; easing.type: Motion.enterProminent } }
        }
        Behavior on opacity { NumberAnimation { duration: Motion.hover } }

        Squircle {
            anchors.fill: parent
            radius: Theme.squircle
            readonly property bool isBoxed: root.isHovered || root.isSelected || root.isDropTarget || root.isCurrent
            fillColor: isBoxed ? Theme.sunken : Theme.alpha(Theme.sunken, 0)
            borderColor: root.isDropTarget ? Theme.mix(Theme.accent, Theme.border, 0.5) : isBoxed ? (root.isHovered ? Theme.mix(Theme.accent, Theme.border, 0.3) : Theme.border) : Theme.alpha(Theme.border, 0)
            insetWidth: root.isSelected ? 2 : root.isCurrent ? 1 : 0
            insetColor: root.isCurrent && !root.isSelected ? Theme.alpha(Theme.accent, 0.5) : Theme.accent
            glowColor: Theme.accent
            glowOpacity: (root.isHovered && !Motion.isLite) || root.isDropTarget ? 1 : 0
            glowPosition: root.isDropTarget ? Qt.point(width / 2, height / 2) : hover.point.position
            glowRadius: root.isDropTarget ? width : Theme.rem * 6
            Behavior on fillColor { ColorAnimation { duration: Motion.hover } }
            Behavior on borderColor { ColorAnimation { duration: Motion.hover } }
            Behavior on glowOpacity { NumberAnimation { duration: Motion.hover } }
        }

        Item {
            id: preview
            width: pane.previewSize
            height: pane.previewSize
            anchors.horizontalCenter: parent.horizontalCenter
            y: Theme.rem * 0.45
            scale: root.isSelected ? 0.9 : 1
            Behavior on scale { NumberAnimation { duration: Motion.stateChange; easing.type: Motion.enterProminent } }

            Glyph {
                id: icon
                anchors.centerIn: parent
                anchors.verticalCenterOffset: root.isDirectory ? 0 : -Theme.rem * 0.2
                width: parent.width * (root.isDirectory ? 0.78 : 0.62)
                height: width
                opacity: root.hasThumbnail ? 0 : 1
                name: root.isDirectory ? (root.isDropTarget ? "folder-open" : "folder") : root.kind === "text" || root.kind === "code" || root.kind === "image" || root.kind === "video" || root.kind === "audio" || root.kind === "archive" || root.kind === "document" || root.kind === "executable" ? root.kind : "file"
                ink: Theme.textBright
                Behavior on ink { ColorAnimation { duration: Motion.hover } }
                Behavior on opacity { NumberAnimation { duration: 160 } }
            }

            Text {
                visible: !root.isDirectory && !root.hasThumbnail && root.suffix.length > 0 && root.suffix.length <= 5 && pane.zoom > 0
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: -Theme.rem * 0.1
                text: root.suffix.toUpperCase()
                color: root.isSelected ? Theme.accentInk : Theme.textFaint
                font.family: Theme.mono
                font.pixelSize: Theme.labelSize * 0.9
                font.letterSpacing: Theme.labelSpacing * 0.6
            }

            SquircleImage {
                id: thumbnail
                anchors.fill: parent
                visible: root.canThumbnail
                opacity: status === Image.Ready ? 1 : 0
                source: root.canThumbnail ? "image://thumbnail/" + encodeURIComponent(root.path) : ""
                sourceSize: Qt.size(Math.ceil(pane.previewSize * Screen.devicePixelRatio), Math.ceil(pane.previewSize * Screen.devicePixelRatio))
                radius: Theme.squircle
                insetWidth: root.isSelected ? 2 : 0
                insetColor: Theme.accent
                Behavior on opacity { NumberAnimation { duration: 160 } }
            }

            Glyph {
                visible: root.isSymlink
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                width: Theme.rem * 0.75
                height: width
                name: "link"
                ink: Theme.textMuted
            }

            Item {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: -Theme.rem * 0.2
                width: Theme.rem * 1.05
                height: width
                scale: root.isSelected ? 1 : 0
                Behavior on scale { NumberAnimation { duration: Motion.stateChange; easing.type: root.isSelected ? Motion.enterProminent : Motion.leaveLarge } }

                Squircle {
                    anchors.fill: parent
                    radius: width / 2
                    exponent: 2
                    fillColor: Theme.accent
                    borderWidth: 0
                }

                Glyph {
                    anchors.centerIn: parent
                    width: parent.width * 0.62
                    height: width
                    name: "check"
                    ink: Theme.isLightColor(Theme.accent) ? Theme.sunkenDeep : "#ffffff"
                }
            }
        }

        FadeText {
            id: label
            visible: !root.isRenaming
            anchors.top: preview.bottom
            anchors.topMargin: Theme.rem * 0.4
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - Theme.rem * 0.5
            horizontalAlignment: Text.AlignHCenter
            isMirrored: false
            maximumLineCount: 2
            text: root.name
            color: Theme.accentInk
            font.weight: Font.Bold
            font.pixelSize: pane.tileLabelSize
            lineHeight: 1.1
        }

        Text {
            visible: pane.zoom > 0 && !root.isRenaming
            anchors.top: label.bottom
            anchors.topMargin: Theme.rem * 0.12
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.sizeText
            color: Theme.textLabel
            font.family: Theme.mono
            font.pixelSize: Theme.smallSize * 0.9
        }

        RenameField {
            visible: root.isRenaming
            active: root.isRenaming
            anchors.top: preview.bottom
            anchors.topMargin: Theme.rem * 0.3
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - Theme.rem * 0.2
            path: root.path
            name: root.name
            isDirectory: root.isDirectory
            pane: root.pane
            horizontalAlignment: TextInput.AlignHCenter
        }
    }

    HoverHandler {
        id: hover
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    }

    QtObject {
        id: mouseDown
        readonly property bool isPressed: pane.pressedIndex === root.index
    }

    DropArea {
        id: drop
        anchors.fill: body
        enabled: root.isDirectory && !root.isCarried
        property bool isAccepting: false
        onEntered: event => {
            isAccepting = pane.workspace.acceptDrag(event, root.path, root, drop)
            if (isAccepting)
                springTimer.restart()
        }
        onPositionChanged: event => { if (isAccepting) pane.workspace.updateDrag(event, root.path, root, drop) }
        onExited: {
            isAccepting = false
            springTimer.stop()
            pane.workspace.leaveDrag(root)
        }
        onDropped: event => {
            springTimer.stop()
            isAccepting = false
            pane.workspace.dropOnto(event, root.path, root, drop)
        }
    }

    // Spring-loaded folders: hold a drag over a folder and it opens under the pointer, so a drop can go several levels deep without letting go.
    Timer {
        id: springTimer
        interval: Motion.springLoad
        onTriggered: if (drop.containsDrag) pane.navigate(root.path, {})
    }
}
