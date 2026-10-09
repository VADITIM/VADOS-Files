import QtQuick
import Vados

// Open folders as pills. A new tab gives it room in two steps: the neighbours slide, then the pill pops into the space (VAS motion §6.9).
Item {
    id: root

    property var workspace

    height: Theme.rem * 1.7

    function enter(delay: int) {
        row.opacity = 0
        row.scale = 0.92
        enterAnimation.delay = delay
        enterAnimation.restart()
    }

    SequentialAnimation {
        id: enterAnimation
        property int delay: 0
        PauseAnimation { duration: enterAnimation.delay }
        ParallelAnimation {
            NumberAnimation { target: row; property: "opacity"; to: 1; duration: Motion.launchPanelEnter; easing.type: Motion.enter }
            NumberAnimation { target: row; property: "scale"; to: 1; duration: Motion.launchPanelEnter; easing.type: Motion.enterProminent }
        }
    }

    Row {
        id: row
        height: parent.height
        transformOrigin: Item.Left
        spacing: Theme.rem * 0.3

        add: Transition {
            SequentialAnimation {
                PropertyAction { property: "scale"; value: 0 }
                PauseAnimation { duration: 120 }
                NumberAnimation { property: "scale"; to: 1; duration: Motion.stateChange; easing.type: Motion.enterProminent }
            }
        }
        move: Transition {
            NumberAnimation { property: "x"; duration: Motion.stateChange; easing.type: Motion.state }
        }

        Repeater {
            model: root.workspace ? root.workspace.tabs : null

            delegate: Item {
                id: tab
                required property int index
                readonly property var pane: root.workspace.paneAt(index, root.workspace.paneRevision)
                readonly property bool isCurrent: index === root.workspace.activeTabIndex
                readonly property bool isDropTarget: tabDrop.containsDrag
                readonly property string title: pane && pane.path.length > 0 ? System.nameOf(pane.path) : "…"
                width: Math.min(Theme.rem * 11, titleText.implicitWidth + Theme.rem * 3.2)
                height: row.height

                transform: Scale {
                    origin.x: tab.width / 2
                    origin.y: tab.height / 2
                    xScale: tabMouse.pressed ? 0.96 : tab.isDropTarget ? 1.05 : 1
                    yScale: xScale
                    Behavior on xScale { NumberAnimation { duration: Motion.press; easing.type: Motion.state } }
                }

                Squircle {
                    anchors.fill: parent
                    radius: height / 2
                    exponent: 3
                    fillColor: tab.isCurrent ? Theme.sunken : tabMouse.containsMouse ? Theme.alpha(Theme.sunken, 0.7) : Theme.alpha(Theme.sunken, 0.35)
                    borderColor: tab.isCurrent ? Theme.border : Theme.alpha(Theme.border, 0.6)
                    insetWidth: tab.isCurrent ? 2 : 0
                    insetColor: Theme.accent
                    Behavior on fillColor { ColorAnimation { duration: Motion.hover } }
                }

                Glyph {
                    id: tabIcon
                    x: Theme.rem * 0.6
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.rem * 0.75
                    height: width
                    name: "folder"
                    ink: tab.isCurrent ? Theme.accentInk : Theme.textIcon
                }

                FadeText {
                    id: titleText
                    anchors.left: tabIcon.right
                    anchors.leftMargin: Theme.rem * 0.4
                    anchors.right: closeMark.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: tab.title
                    color: tab.isCurrent ? Theme.textBright : Theme.textMuted
                    font.pixelSize: Theme.smallSize
                }

                IconButton {
                    id: closeMark
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.rem * 0.3
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.rem * 1.1
                    height: width
                    glyphSize: Theme.rem * 0.5
                    glyph: "close"
                    opacity: tabMouse.containsMouse || containsHover ? 1 : 0
                    readonly property bool containsHover: isHovered
                    onClicked: root.workspace.closeTab(tab.index)
                }

                MouseArea {
                    id: tabMouse
                    anchors.fill: parent
                    anchors.rightMargin: closeMark.width + Theme.rem * 0.3
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: event => {
                        if (event.button === Qt.MiddleButton)
                            root.workspace.closeTab(tab.index)
                        else
                            root.workspace.switchTab(tab.index)
                    }
                }

                DropArea {
                    id: tabDrop
                    anchors.fill: parent
                    onEntered: tabSpring.restart()
                    onExited: tabSpring.stop()
                }

                Timer {
                    id: tabSpring
                    interval: Motion.springLoad * 0.7
                    onTriggered: if (tabDrop.containsDrag) root.workspace.switchTab(tab.index)
                }
            }
        }

        IconButton {
            width: row.height
            height: row.height
            glyph: "plus"
            glyphSize: Theme.rem * 0.7
            hint: "new tab · ctrl t"
            onClicked: root.workspace.command("newTab")
        }
    }
}
