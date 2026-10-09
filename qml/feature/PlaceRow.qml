import QtQuick
import Vados

// One row in the sidebar: a pin or a drive. The one you are in is lit — inset ring — and nothing else about the row changes.
// A pin can be dragged up and down to reorder, and renamed in place.
Item {
    id: root

    required property string name
    required property string path
    required property string key
    required property string section
    required property string device
    required property string detail
    required property bool isMounted
    required property bool canEject
    required property real usage
    required property string icon
    required property string accentKey
    required property int index
    property var workspace
    // The ListView of pins, for reordering; null for drive rows.
    property var pinList: null
    property string litPath: ""

    readonly property var activePane: workspace ? workspace.activePane : null
    readonly property bool isCurrent: {
        if (!activePane || activePane.path.length === 0)
            return false
        if (section === "drives")
            return isMounted && (activePane.path === path || activePane.path.startsWith(path + "/"))
        return path === litPath
    }
    readonly property bool isPin: section === "pinned"
    readonly property bool isRenaming: isPin && workspace !== null && workspace.renamingPin === path
    property bool isReordering: false
    property real grabOffset: 0
    readonly property bool isDropTarget: drop.containsDrag && drop.isAccepting
    readonly property bool isHovered: mouse.containsMouse
    readonly property bool hasDetail: section === "drives"

    implicitHeight: Theme.rem * (hasDetail ? 2.55 : 1.8)
    height: visible ? implicitHeight : 0

    readonly property string glyph: icon.length > 0 ? icon : "folder"

    z: isReordering ? 10 : 0
    transform: [
        Scale {
            origin.x: root.width / 2
            origin.y: root.height / 2
            xScale: root.isReordering ? 1.05 : root.isDropTarget ? 1.04 : mouse.pressed ? 0.98 : 1
            yScale: xScale
            Behavior on xScale { NumberAnimation { duration: Motion.stateChange; easing.type: Motion.enterProminent } }
        },
        // While reordering the row rides the pointer; measured from its own y, so it stays under the hand while the list moves it.
        Translate {
            y: root.isReordering && root.pinList ? root.pinList.dragY - root.grabOffset - root.y : 0
        }
    ]

    Squircle {
        anchors.fill: parent
        anchors.topMargin: 1
        anchors.bottomMargin: 1
        radius: Theme.squircleSmall
        fillColor: root.isReordering ? Theme.raised : root.isHovered || root.isDropTarget || root.isCurrent ? Theme.sunken : Theme.alpha(Theme.sunken, 0)
        borderColor: root.isReordering ? Theme.borderStrong : root.isDropTarget ? Theme.mix(Theme.accent, Theme.border, 0.5) : root.isHovered ? Theme.border : Theme.alpha(Theme.border, 0)
        insetWidth: root.isCurrent ? 2 : 0
        insetColor: Theme.accent
        glowOpacity: root.isDropTarget ? 1 : 0
        glowRadius: width
        Behavior on fillColor { ColorAnimation { duration: Motion.hover } }
        Behavior on borderColor { ColorAnimation { duration: Motion.hover } }
    }

    Glyph {
        id: iconGlyph
        x: Theme.rem * 0.55
        y: root.hasDetail ? Theme.rem * 0.45 : (root.height - height) / 2
        width: Theme.rem * 0.95
        height: width
        name: root.glyph
        opacity: root.isMounted ? 1 : 0.5
        ink: Theme.inkFor(Theme.accentFor(root.accentKey))
        Behavior on ink { ColorAnimation { duration: Motion.hover } }
    }

    FadeText {
        visible: !root.isRenaming
        anchors.left: iconGlyph.right
        anchors.leftMargin: Theme.rem * 0.55
        anchors.right: eject.visible ? eject.left : parent.right
        anchors.rightMargin: Theme.rem * 0.4
        anchors.verticalCenter: iconGlyph.verticalCenter
        text: root.name
        color: root.isCurrent ? Theme.textBright : root.isHovered ? Theme.textBody : Theme.textMuted
        font.pixelSize: Theme.bodySize
    }

    // Renaming a pin in place: Enter keeps it, Escape or an empty name gives the old one back, clicking away keeps it.
    TextInput {
        id: renameInput
        visible: root.isRenaming
        anchors.left: iconGlyph.right
        anchors.leftMargin: Theme.rem * 0.55
        anchors.right: parent.right
        anchors.rightMargin: Theme.rem * 0.4
        anchors.verticalCenter: iconGlyph.verticalCenter
        color: Theme.textBright
        selectionColor: Theme.alpha(Theme.accent, 0.35)
        selectedTextColor: Theme.textBright
        font.family: Theme.mono
        font.pixelSize: Theme.bodySize
        clip: true
        selectByMouse: true
        property bool isDone: false

        function finish(isKept: bool) {
            if (isDone)
                return
            isDone = true
            if (isKept && text.trim().length > 0)
                PlacesModel.renamePin(root.index, text)
            root.workspace.renamingPin = ""
            if (root.workspace.activePane)
                root.workspace.activePane.forceActiveFocus()
        }

        onVisibleChanged: {
            if (!visible)
                return
            isDone = false
            text = root.name
            forceActiveFocus()
            selectAll()
        }
        Keys.onReturnPressed: finish(true)
        Keys.onEnterPressed: finish(true)
        Keys.onEscapePressed: finish(false)
        onActiveFocusChanged: if (!activeFocus && visible) finish(true)
    }

    Item {
        visible: root.hasDetail
        anchors.left: iconGlyph.right
        anchors.leftMargin: Theme.rem * 0.55
        anchors.right: parent.right
        anchors.rightMargin: Theme.rem * 0.6
        y: Theme.rem * 1.5
        height: Theme.rem * 0.7

        Text {
            id: detailText
            text: root.detail
            color: Theme.textFaint
            font.family: Theme.mono
            font.pixelSize: Theme.smallSize * 0.9
        }

        // A reading may carry the accent; the container may not become it. The fill is clipped inside its own hairline (VAS surface).
        Rectangle {
            visible: root.usage >= 0
            anchors.left: detailText.right
            anchors.leftMargin: Theme.rem * 0.4
            anchors.right: parent.right
            anchors.verticalCenter: detailText.verticalCenter
            height: 4
            radius: 2
            color: "transparent"
            border.color: Theme.borderControl
            border.width: 1

            Rectangle {
                x: 1
                y: 1
                height: parent.height - 2
                width: Math.max(0, (parent.width - 2) * Math.max(0, root.usage))
                radius: 1
                color: root.usage > 0.9 ? Theme.danger : Theme.inkFor(Theme.accentFor("drive"))
            }
        }
    }

    IconButton {
        id: eject
        visible: root.canEject && root.isMounted
        anchors.right: parent.right
        anchors.rightMargin: Theme.rem * 0.3
        y: Theme.rem * 0.25
        width: Theme.rem * 1.3
        height: width
        glyph: "eject"
        glyphSize: Theme.rem * 0.7
        hint: "eject"
        onClicked: PlacesModel.unmount(root.device)
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        anchors.rightMargin: eject.visible ? eject.width + Theme.rem * 0.4 : 0
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        cursorShape: root.isReordering ? Qt.ClosedHandCursor : Qt.PointingHandCursor
        enabled: !root.isRenaming
        property real pressY: 0
        property bool wasReordering: false

        onPressed: event => {
            wasReordering = false
            if (root.pinList)
                pressY = mapToItem(root.pinList, event.x, event.y).y
        }
        onPositionChanged: event => {
            if (!pressed || !root.isPin || !root.pinList || !(pressedButtons & Qt.LeftButton))
                return
            const listY = mapToItem(root.pinList, event.x, event.y).y
            if (!root.isReordering) {
                if (Math.abs(listY - pressY) < Theme.rem * 0.4)
                    return
                root.grabOffset = pressY - root.y
                root.isReordering = true
            }
            root.pinList.dragY = listY
            const target = root.pinList.indexAt(root.width / 2, Math.max(0, Math.min(listY, root.pinList.contentHeight - 1)))
            if (target >= 0 && target < PlacesModel.pinCount && target !== root.index)
                PlacesModel.movePin(root.index, target)
        }
        onReleased: {
            if (root.isReordering) {
                root.isReordering = false
                wasReordering = true
            }
        }
        onCanceled: root.isReordering = false

        onClicked: event => {
            if (wasReordering)
                return
            if (event.button === Qt.RightButton) {
                root.workspace.openPlaceMenu(root, mapToItem(root.workspace, event.x, event.y))
                return
            }
            if (!root.isMounted) {
                root.workspace.pendingMountDevice = root.device
                PlacesModel.mount(root.device)
                return
            }
            if (event.button === Qt.MiddleButton)
                root.workspace.openTab(root.path)
            else
                root.workspace.command("navigate", root.path)
        }
    }

    DropArea {
        id: drop
        anchors.fill: parent
        enabled: root.isMounted
        property bool isAccepting: false
        onEntered: event => {
            isAccepting = root.workspace.acceptDrag(event, root.path, root, drop)
            if (isAccepting && root.path !== "trash:///")
                springTimer.restart()
        }
        onPositionChanged: event => { if (isAccepting) root.workspace.updateDrag(event, root.path, root, drop) }
        onExited: {
            isAccepting = false
            springTimer.stop()
            root.workspace.leaveDrag(root)
        }
        onDropped: event => {
            springTimer.stop()
            isAccepting = false
            root.workspace.dropOnto(event, root.path, root, drop)
        }
    }

    Timer {
        id: springTimer
        interval: Motion.springLoad
        onTriggered: if (drop.containsDrag) root.workspace.command("navigate", root.path)
    }
}
