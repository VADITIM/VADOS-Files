import QtQuick
import Vados

// One file in the details list. Same states as the tile, laid along a line: the box appears under the pointer, the selected row carries the inset ring.
Item {
    id: root

    required property int index
    required property string name
    required property string path
    required property bool isDirectory
    required property string kind
    required property string suffix
    required property string sizeText
    required property string modifiedText
    required property string mimeType
    required property bool isSelected
    required property bool isCut
    required property bool canThumbnail
    required property bool isSymlink
    required property bool isHidden
    required property string originalPath
    required property string deletedAtText
    property var pane

    readonly property bool isHovered: hover.hovered
    readonly property bool isCarried: pane.carriedPaths.indexOf(path) !== -1
    readonly property bool isDropTarget: drop.containsDrag && drop.isAccepting
    readonly property bool isRenaming: pane.renamingPath === path
    readonly property bool isCurrent: pane.model.currentIndex === index && pane.isKeyboardFocused
    readonly property bool isTrash: pane.model.mode === "trash"
    readonly property bool isSearch: pane.model.mode === "search"
    property real enterShift: 0

    width: pane.viewWidth
    height: pane.rowHeight
    transform: Translate { x: root.enterShift }

    function hitTest(localX: real, localY: real): bool {
        return localX >= 0 && localX <= Math.max(nameColumn.x + nameColumn.width, width * 0.6)
    }

    // #region ── enter and leave ───────────────────────────────────────────────────────────────
    function enterDelay(): int {
        const y = index * pane.rowHeight - pane.contentY
        return Motion.positionalDelay(0, y, pane.viewWidth, pane.viewHeight, Motion.navigateStaggerVertical, Motion.navigateStaggerHorizontal)
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
        ScriptAction {
            script: {
                root.opacity = 0
                root.enterShift = Motion.isLite ? 0 : (pane.direction === "out" ? -Theme.rem * 1.2 : Theme.rem * 1.2)
            }
        }
        PauseAnimation { duration: enterAnimation.delay }
        ParallelAnimation {
            NumberAnimation { target: root; property: "opacity"; to: 1; duration: Motion.navigateEnter * 0.8; easing.type: Motion.enter }
            NumberAnimation { target: root; property: "enterShift"; to: 0; duration: Motion.navigateEnter; easing.type: Motion.enterProminent }
        }
    }

    ParallelAnimation {
        id: leaveAnimation
        NumberAnimation { target: root; property: "opacity"; to: 0; duration: Motion.navigateLeave; easing.type: Motion.leave }
    }
    // #endregion ───────────────────────────────────────────────────────────────────────────────

    Item {
        id: body
        anchors.fill: parent
        anchors.topMargin: 1
        anchors.bottomMargin: 1
        opacity: root.isCarried ? 0.3 : root.isCut ? 0.45 : root.isHidden && !root.isSelected && !root.isHovered ? 0.5 : 1
        transform: Scale {
            origin.x: body.width / 2
            origin.y: body.height / 2
            xScale: root.isDropTarget ? 1.012 : pane.pressedIndex === root.index ? 0.99 : 1
            yScale: root.isDropTarget ? 1.08 : xScale
            Behavior on xScale { NumberAnimation { duration: Motion.stateChange; easing.type: Motion.enterProminent } }
            Behavior on yScale { NumberAnimation { duration: Motion.stateChange; easing.type: Motion.enterProminent } }
        }
        Behavior on opacity { NumberAnimation { duration: Motion.hover } }

        Squircle {
            anchors.fill: parent
            radius: Theme.squircleSmall
            readonly property bool isBoxed: root.isHovered || root.isSelected || root.isDropTarget || root.isCurrent
            fillColor: isBoxed ? Theme.sunken : Theme.alpha(Theme.sunken, 0)
            borderColor: isBoxed ? (root.isHovered || root.isDropTarget ? Theme.mix(Theme.accent, Theme.border, 0.3) : Theme.border) : Theme.alpha(Theme.border, 0)
            insetWidth: root.isSelected ? 2 : root.isCurrent ? 1 : 0
            insetColor: root.isCurrent && !root.isSelected ? Theme.alpha(Theme.accent, 0.5) : Theme.accent
            glowColor: Theme.accent
            glowOpacity: (root.isHovered && !Motion.isLite) || root.isDropTarget ? 1 : 0
            glowPosition: hover.point.position
            glowRadius: Theme.rem * 8
            Behavior on fillColor { ColorAnimation { duration: Motion.hover } }
            Behavior on borderColor { ColorAnimation { duration: Motion.hover } }
            Behavior on glowOpacity { NumberAnimation { duration: Motion.hover } }
        }

        Item {
            id: preview
            x: Theme.rem * 0.5
            anchors.verticalCenter: parent.verticalCenter
            width: pane.rowHeight * 0.66
            height: width
            scale: root.isSelected ? 0.88 : 1
            Behavior on scale { NumberAnimation { duration: Motion.stateChange; easing.type: Motion.enterProminent } }

            Glyph {
                anchors.fill: parent
                opacity: thumbnail.status === Image.Ready ? 0 : 1
                name: root.isDirectory ? (root.isDropTarget ? "folder-open" : "folder") : ["text", "code", "image", "video", "audio", "archive", "document", "executable"].indexOf(root.kind) !== -1 ? root.kind : "file"
                ink: Theme.textBright
            }

            SquircleImage {
                id: thumbnail
                anchors.fill: parent
                visible: root.canThumbnail
                source: root.canThumbnail ? "image://thumbnail/" + encodeURIComponent(root.path) : ""
                sourceSize: Qt.size(Math.ceil(width * 2 * Screen.devicePixelRatio), Math.ceil(height * 2 * Screen.devicePixelRatio))
                radius: Theme.rem * 0.35
                borderWidth: 0
            }
        }

        FadeText {
            id: nameColumn
            visible: !root.isRenaming
            anchors.left: preview.right
            anchors.leftMargin: Theme.rem * 0.6
            anchors.right: sizeColumn.left
            anchors.rightMargin: Theme.rem
            anchors.verticalCenter: parent.verticalCenter
            text: root.isSearch ? root.name + "   " + root.path.substring(pane.model.path.length + 1, root.path.length - root.name.length - 1) : root.name
            color: Theme.accentInk
            font.weight: Font.Bold
            font.pixelSize: Theme.bodySize
        }

        RenameField {
            visible: root.isRenaming
            active: root.isRenaming
            anchors.left: preview.right
            anchors.leftMargin: Theme.rem * 0.4
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(Theme.rem * 18, sizeColumn.x - x - Theme.rem)
            height: parent.height - Theme.rem * 0.2
            path: root.path
            name: root.name
            isDirectory: root.isDirectory
            pane: root.pane
        }

        Text {
            id: sizeColumn
            anchors.right: modifiedColumn.left
            anchors.verticalCenter: parent.verticalCenter
            width: pane.sizeColumnWidth
            horizontalAlignment: Text.AlignRight
            rightPadding: Theme.rem
            text: root.sizeText
            color: Theme.textMuted
            font.family: Theme.mono
            font.pixelSize: Theme.smallSize
        }

        Text {
            id: modifiedColumn
            anchors.right: kindColumn.left
            anchors.verticalCenter: parent.verticalCenter
            width: pane.modifiedColumnWidth
            text: root.isTrash ? root.deletedAtText : root.modifiedText
            color: Theme.textMuted
            font.family: Theme.mono
            font.pixelSize: Theme.smallSize
        }

        FadeText {
            id: kindColumn
            anchors.right: parent.right
            anchors.rightMargin: Theme.rem * 0.6
            anchors.verticalCenter: parent.verticalCenter
            width: pane.kindColumnWidth
            text: root.isTrash ? root.originalPath.substring(0, root.originalPath.lastIndexOf("/")) : root.isDirectory ? "folder" : root.suffix.length > 0 ? root.kind + " · " + root.suffix : root.kind
            color: Theme.textMuted
            font.pixelSize: Theme.smallSize
        }
    }

    HoverHandler {
        id: hover
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    }

    DropArea {
        id: drop
        anchors.fill: body
        enabled: root.isDirectory && !root.isCarried && !root.isTrash
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

    Timer {
        id: springTimer
        interval: Motion.springLoad
        onTriggered: if (drop.containsDrag) pane.navigate(root.path, {})
    }
}
