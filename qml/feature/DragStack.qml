import QtQuick
import Vados

// The picture that rides under the pointer during a drag: the carried files as a small leaning stack with a count, rendered off-screen the moment a press lands on a selection so it is ready before the pointer has moved far enough to start the drag.
Item {
    id: root

    property var pane
    property var image: null
    property var entries: []
    property int count: 0
    readonly property point hotSpot: Qt.point(width * 0.5 * Screen.devicePixelRatio, height * 0.55 * Screen.devicePixelRatio)

    width: Theme.rem * 3.4
    height: Theme.rem * 3.4

    function prepare(paths: var, sourceItem: var) {
        image = null
        count = paths.length
        entries = paths.slice(0, 3).map(path => pane.model.get(pane.model.indexOfPath(path)))
        grabTimer.restart()
    }

    // One frame for the cards to take their content, then the grab.
    Timer {
        id: grabTimer
        interval: 16
        onTriggered: root.grabToImage(result => { root.image = result.image }, Qt.size(root.width * Screen.devicePixelRatio, root.height * Screen.devicePixelRatio))
    }

    Repeater {
        model: root.entries.length

        delegate: Item {
            id: card
            required property int index
            readonly property var entry: root.entries[root.entries.length - 1 - index]
            readonly property int depth: root.entries.length - 1 - index
            width: Theme.rem * 2.3
            height: width
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: depth === 0 ? 0 : depth === 1 ? -Theme.rem * 0.35 : Theme.rem * 0.35
            anchors.verticalCenterOffset: depth * Theme.rem * 0.1
            rotation: depth === 0 ? 0 : depth === 1 ? -8 : 8

            Squircle {
                anchors.fill: parent
                fillColor: Theme.panelSolid
                borderColor: card.depth === 0 ? Theme.mix(Theme.accent, Theme.border, 0.55) : Theme.borderStrong
            }

            Glyph {
                anchors.centerIn: parent
                width: parent.width * 0.55
                height: width
                visible: !picture.visible || picture.status !== Image.Ready
                name: card.entry && card.entry.isDirectory ? "folder" : card.entry && ["text", "code", "image", "video", "audio", "archive", "document", "executable"].indexOf(card.entry.kind) !== -1 ? card.entry.kind : "file"
                ink: card.entry && card.entry.isDirectory ? Theme.accentInk : Theme.textBody
            }

            SquircleImage {
                id: picture
                anchors.fill: parent
                anchors.margins: 2
                visible: card.entry && card.entry.canThumbnail
                source: visible ? "image://thumbnail/" + encodeURIComponent(card.entry.path) : ""
                sourceSize: Qt.size(Math.ceil(root.pane.previewSize * Screen.devicePixelRatio), Math.ceil(root.pane.previewSize * Screen.devicePixelRatio))
                borderWidth: 0
                radius: Theme.squircle
            }
        }
    }

    Item {
        visible: root.count > 1
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.rem * 0.35
        width: Math.max(height, countText.implicitWidth + Theme.rem * 0.6)
        height: Theme.rem * 1.25

        Squircle {
            anchors.fill: parent
            radius: height / 2
            exponent: 3
            fillColor: Theme.accent
            borderWidth: 0
        }

        Text {
            id: countText
            anchors.centerIn: parent
            text: root.count
            color: Theme.isLightColor(Theme.accent) ? Theme.sunkenDeep : "#ffffff"
            font.family: Theme.mono
            font.pixelSize: Theme.labelSize
            font.weight: Font.Bold
        }
    }
}
