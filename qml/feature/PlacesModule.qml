import QtQuick
import Vados

// The left column: the user's pins (PINNED: reorder by dragging, rename, change icon, unpin), the drives, and the transfers while any are running.
// Every row is also a drop target that springs open when a drag waits on it; dragging a folder out of a pane opens a slot to pin it.
Item {
    id: root

    property var workspace
    readonly property var modules: [pinnedModule, drivesModule].filter(module => module.visible)
    readonly property var activePane: workspace ? workspace.activePane : null
    // Exactly one pin is lit: the one pinned at this folder, else the room root it sits in.
    readonly property string litPath: {
        PlacesModel.pinCount
        return activePane && activePane.path.length > 0 ? PlacesModel.litPathFor(activePane.path) : ""
    }

    Column {
        id: stack
        width: parent.width
        spacing: Theme.gap

        Module {
            id: pinnedModule
            width: parent.width
            height: topPadding + list.height + slot.height + bottomPadding
            label: "pinned"
            topPadding: Theme.rem * 2.3
            sidePadding: Theme.rem * 0.45
            bottomPadding: Theme.rem * 0.5

            ListView {
                id: list
                objectName: "pinList"
                width: parent.width
                height: contentHeight
                interactive: false
                cacheBuffer: 100000
                model: PlacesModel
                // A hairline between the runs of pins: home/downloads/system, the rest, the trash.
                section.property: "group"
                section.criteria: ViewSection.FullString
                section.delegate: Item {
                    required property string section
                    width: list.width
                    height: section === "0" ? 0 : Theme.rem * 0.7
                    clip: true
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        x: Theme.rem * 0.55
                        width: parent.width - Theme.rem * 1.1
                        height: 1
                        color: Theme.border
                    }
                }
                // Where the pointer is during a reorder, in the list's own coordinates.
                property real dragY: 0

                delegate: PlaceRow {
                    workspace: root.workspace
                    pinList: list
                    litPath: root.litPath
                    visible: section === "pinned"
                    width: list.width
                }

                // The rows make room for a pin being dragged past, and for one added or taken away.
                displaced: Transition {
                    NumberAnimation { properties: "y"; duration: Motion.stateChange; easing.type: Motion.enterProminent }
                }
                move: Transition {
                    NumberAnimation { properties: "y"; duration: Motion.stateChange; easing.type: Motion.enterProminent }
                }
                add: Transition {
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Motion.stateChange; easing.type: Motion.enter }
                    NumberAnimation { property: "scale"; from: 0.9; to: 1; duration: Motion.stateChange; easing.type: Motion.enterProminent }
                }
                remove: Transition {
                    NumberAnimation { property: "opacity"; to: 0; duration: Motion.hover; easing.type: Motion.leave }
                }
            }

            // Opens under the pins while folders are dragged out of a pane; dropping there pins them.
            Item {
                id: slot
                anchors.top: list.bottom
                width: parent.width
                height: root.workspace && root.workspace.isCarrying ? Theme.rem * 2 : 0
                clip: true
                Behavior on height { NumberAnimation { duration: Motion.stateChange; easing.type: Motion.enterProminent } }
                readonly property bool isTarget: slotDrop.containsDrag

                Squircle {
                    anchors.fill: parent
                    anchors.topMargin: Theme.rem * 0.2
                    radius: Theme.squircleSmall
                    fillColor: slot.isTarget ? Theme.sunken : Theme.alpha(Theme.sunken, 0)
                    borderColor: slot.isTarget ? Theme.accent : Theme.borderHover
                    Behavior on borderColor { ColorAnimation { duration: Motion.hover } }
                }

                Row {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: Theme.rem * 0.1
                    spacing: Theme.rem * 0.4

                    Glyph {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Theme.rem * 0.8
                        height: width
                        name: "star"
                        ink: slot.isTarget ? Theme.accentInk : Theme.textMuted
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "PIN HERE"
                        color: slot.isTarget ? Theme.accentInk : Theme.textMuted
                        font.family: Theme.mono
                        font.pixelSize: Theme.labelSize
                        font.letterSpacing: Theme.labelSpacing * 0.6
                    }
                }

                DropArea {
                    id: slotDrop
                    anchors.fill: parent
                    onEntered: event => {
                        if (event.hasUrls)
                            event.accept(Qt.LinkAction)
                    }
                    // Pinning commits to nothing on disk; accepted as a link so the source does nothing either.
                    onDropped: event => {
                        for (const path of System.localPaths(event.urls))
                            if (System.isDirectory(path))
                                PlacesModel.pin(path)
                        event.accept(Qt.LinkAction)
                    }
                }
            }
        }

        Module {
            id: drivesModule
            width: parent.width
            visible: drivesColumn.implicitHeight > 0
            height: topPadding + drivesColumn.implicitHeight + bottomPadding
            topPadding: Theme.rem * 0.5
            sidePadding: Theme.rem * 0.45
            bottomPadding: Theme.rem * 0.5

            Column {
                id: drivesColumn
                width: parent.width
                Repeater {
                    model: PlacesModel
                    delegate: PlaceRow {
                        workspace: root.workspace
                        litPath: root.litPath
                        visible: section === "drives"
                        width: drivesColumn.width
                    }
                }
            }
        }
    }

    // Pins the folder being shown.
    IconButton {
        anchors.right: parent.right
        anchors.rightMargin: Theme.rem * 0.35
        y: Theme.rem * 0.45
        width: Theme.rem * 1.4
        height: width
        glyphSize: Theme.rem * 0.7
        glyph: "plus"
        hint: "pin this folder"
        isEnabled: root.activePane !== null && root.activePane.model.mode === "folder" && !PlacesModel.isPinned(root.activePane.path) && PlacesModel.pinCount >= 0
        onClicked: PlacesModel.pin(root.activePane.path)
    }

    TransfersModule {
        anchors.bottom: parent.bottom
        width: parent.width
        maximumHeight: parent.height - stack.height - Theme.gap
    }
}
