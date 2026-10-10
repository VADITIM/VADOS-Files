import QtQuick
import Vados

// Space previews the current file. The preview grows out of its tile and shrinks back into the tile it ends on (VAS components 16: the flight from a tile); the arrows step through the folder without closing it.
Item {
    id: root

    property var workspace
    property var pane: null
    property var entry: ({})

    // A photo or video goes to VAD/OS Gallery with the folder's other photos, in the order this pane shows them.
    function openEntry() {
        if (System.isMedia(entry.path) && pane && pane.model)
            System.openMedia(entry.path, pane.model.mediaPaths())
        else
            System.open(entry.path)
    }
    property string textContent: ""
    property real progress: 0
    property bool isOpen: false
    property rect origin: Qt.rect(width / 2, height / 2, 1, 1)
    readonly property rect target: {
        const panelWidth = Math.min(width * 0.72, Theme.rem * 46)
        const panelHeight = height * 0.8
        return Qt.rect((width - panelWidth) / 2, (height - panelHeight) / 2, panelWidth, panelHeight)
    }
    readonly property string previewKind: entry.kind === "image" ? "image" : (entry.kind === "text" || entry.kind === "code") && textContent.length > 0 ? "text" : "info"

    visible: progress > 0.001

    function toggle(targetPane: var) {
        if (isOpen)
            close()
        else
            open(targetPane)
    }

    function rectOf(index: int): rect {
        const item = pane ? pane.itemForIndex(index) : null
        if (!item)
            return Qt.rect(width / 2 - Theme.rem, height / 2 - Theme.rem, Theme.rem * 2, Theme.rem * 2)
        const point = item.mapToItem(root, 0, 0)
        return Qt.rect(point.x, point.y, item.width, item.height)
    }

    function load(index: int) {
        entry = pane.model.get(index)
        textContent = entry.kind === "text" || entry.kind === "code" ? System.textPreview(entry.path, 48000) : ""
        if (entry.isDirectory)
            System.measureFolder(entry.path)
    }

    function open(targetPane: var) {
        pane = targetPane
        let index = pane.model.currentIndex
        const selected = pane.model.selectedPaths()
        if (selected.length > 0 && !pane.model.isSelected(index))
            index = pane.model.indexOfPath(selected[0])
        if (index < 0)
            return
        load(index)
        origin = rectOf(index)
        isOpen = true
        closeAnimation.stop()
        openAnimation.restart()
        keyCatcher.forceActiveFocus()
    }

    function close() {
        if (!isOpen)
            return
        isOpen = false
        // Back into the tile it ends on, not the one it started from: a preview that stepped through the folder lands where the selection now is.
        origin = rectOf(pane.model.currentIndex)
        openAnimation.stop()
        closeAnimation.restart()
        pane.forceActiveFocus()
    }

    function step(delta: int) {
        pane.moveCurrent(delta, false, false)
        load(pane.model.currentIndex)
        stepAnimation.restart()
    }

    NumberAnimation {
        id: openAnimation
        target: root
        property: "progress"
        to: 1
        duration: 300
        easing.type: Easing.OutBack
        easing.overshoot: 1.1
    }

    // The way back is the same shape run quicker and without the overshoot: one state change, so one movement, both ways (VAS motion §12).
    NumberAnimation {
        id: closeAnimation
        target: root
        property: "progress"
        to: 0
        duration: 190
        easing.type: Motion.leave
    }

    SequentialAnimation {
        id: stepAnimation
        NumberAnimation { target: content; property: "opacity"; to: 0.15; duration: 60 }
        NumberAnimation { target: content; property: "opacity"; to: 1; duration: 160; easing.type: Motion.enter }
    }

    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: Math.min(1, Math.max(0, root.progress)) * 0.3

        MouseArea {
            anchors.fill: parent
            enabled: root.isOpen
            acceptedButtons: Qt.AllButtons
            onPressed: root.close()
            onWheel: wheel => root.step(wheel.angleDelta.y > 0 ? -1 : 1)
        }
    }

    Item {
        id: panel
        x: root.origin.x + (root.target.x - root.origin.x) * root.progress
        y: root.origin.y + (root.target.y - root.origin.y) * root.progress
        width: Math.max(1, root.origin.width + (root.target.width - root.origin.width) * root.progress)
        height: Math.max(1, root.origin.height + (root.target.height - root.origin.height) * root.progress)

        Squircle {
            anchors.fill: parent
            fillColor: Theme.panelSolid
            borderColor: Theme.mix(Theme.accent, Theme.border, 0.35)
        }

        MouseArea {
            anchors.fill: parent
            onDoubleClicked: if (root.entry.path) root.openEntry()
        }

        Item {
            id: content
            anchors.fill: parent
            anchors.margins: Theme.rem
            // Content arrives after the shape does, so the flight reads as one box travelling and not a picture being stretched.
            visible: root.progress > 0.55
            opacity: 1

            Text {
                id: kindLabel
                text: (root.entry.isDirectory ? "folder" : root.entry.kind || "").toUpperCase() + (root.entry.suffix ? " · " + root.entry.suffix.toUpperCase() : "")
                color: Theme.textLabel
                font.family: Theme.mono
                font.pixelSize: Theme.labelSize
                font.letterSpacing: Theme.labelSpacing
            }

            FadeText {
                id: nameText
                anchors.top: kindLabel.bottom
                anchors.topMargin: Theme.rem * 0.3
                width: parent.width
                text: root.entry.name || ""
                color: Theme.textBright
                font.pixelSize: Theme.bodySize * 1.25
            }

            Item {
                id: stage
                anchors.top: nameText.bottom
                anchors.topMargin: Theme.rem * 0.7
                anchors.bottom: footer.top
                anchors.bottomMargin: Theme.rem * 0.6
                width: parent.width

                Image {
                    id: picture
                    anchors.fill: parent
                    visible: root.previewKind === "image"
                    source: visible && root.entry.path ? "file://" + encodeURI(root.entry.path).replace(/#/g, "%23").replace(/\?/g, "%3F") : ""
                    sourceSize: Qt.size(root.target.width * Screen.devicePixelRatio, root.target.height * Screen.devicePixelRatio)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    autoTransform: true
                    smooth: true
                    mipmap: true
                }

                Flickable {
                    id: textView
                    anchors.fill: parent
                    visible: root.previewKind === "text"
                    contentHeight: textBody.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Squircle {
                        width: textView.width
                        height: Math.max(textView.height, textBody.implicitHeight)
                        fillColor: Theme.sunkenDeep
                        borderColor: Theme.border
                    }

                    Text {
                        id: textBody
                        width: textView.width
                        padding: Theme.rem * 0.8
                        text: root.textContent
                        color: Theme.textBody
                        font.family: Theme.mono
                        font.pixelSize: Theme.smallSize
                        wrapMode: Text.WrapAnywhere
                        textFormat: Text.PlainText
                    }
                }

                Column {
                    anchors.centerIn: parent
                    visible: root.previewKind === "info" || (root.previewKind === "image" && picture.status !== Image.Ready)
                    spacing: Theme.rem * 0.6

                    Glyph {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Theme.rem * 5
                        height: width
                        name: root.entry.isDirectory ? "folder" : ["text", "code", "image", "video", "audio", "archive", "document", "executable"].indexOf(root.entry.kind) !== -1 ? root.entry.kind : "file"
                        ink: root.entry.isDirectory ? Theme.textBright : Theme.textIcon
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.entry.isDirectory ? root.measured : (root.entry.sizeText || "") + (root.entry.modifiedText ? "  ·  " + root.entry.modifiedText : "")
                        color: Theme.textMuted
                        font.family: Theme.mono
                        font.pixelSize: Theme.smallSize
                    }
                }
            }

            Row {
                id: footer
                anchors.bottom: parent.bottom
                spacing: Theme.rem * 0.35

                Pill { text: "open"; onClicked: { root.openEntry(); root.close() } }
                Pill { text: "close"; onClicked: root.close() }
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: footer.verticalCenter
                text: "SPACE CLOSES  ·  ← → STEPS"
                color: Theme.textFaint
                font.family: Theme.mono
                font.pixelSize: Theme.labelSize * 0.9
                font.letterSpacing: Theme.labelSpacing * 0.5
            }
        }
    }

    property string measured: ""
    Connections {
        target: System
        function onFolderMeasured(path, bytes, files, folders) {
            if (path === root.entry.path)
                root.measured = files + " files, " + folders + " folders · " + System.formatSize(bytes)
        }
    }

    Item {
        id: keyCatcher
        focus: root.isOpen
        Keys.onPressed: event => {
            switch (event.key) {
            case Qt.Key_Space:
            case Qt.Key_Escape: root.close(); break
            case Qt.Key_Left: root.step(-1); break
            case Qt.Key_Right: root.step(1); break
            case Qt.Key_Up: root.step(root.pane.viewMode === "grid" ? -root.pane.columns : -1); break
            case Qt.Key_Down: root.step(root.pane.viewMode === "grid" ? root.pane.columns : 1); break
            case Qt.Key_Return:
            case Qt.Key_Enter: root.openEntry(); root.close(); break
            default: return
            }
            event.accepted = true
        }
    }
}
