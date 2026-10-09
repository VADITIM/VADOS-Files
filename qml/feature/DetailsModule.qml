import QtQuick
import Vados

// What is selected, read out: the picture, the name, and the facts as labelled values. With nothing selected it describes the folder itself.
Item {
    id: root

    property var workspace
    readonly property alias module: frame
    readonly property var pane: workspace ? workspace.activePane : null
    property var info: ({})
    property var entry: ({})
    property int selectionCount: 0
    // The column's room follows the switch at once; Workspace animates the width, so the module slides in and out and pushes the panes.
    property bool isOccupying: Settings.showDetails
    property string measuredPath: ""
    property string measuredText: ""
    readonly property var fields: buildFields()

    clip: true

    function buildFields() {
        if (!pane)
            return []
        if (selectionCount > 1) {
            const list = [{ label: "Selected", value: selectionCount + " items" }]
            if (pane.model.selectedSize > 0)
                list.push({ label: "Files total", value: System.formatSize(pane.model.selectedSize) })
            return list
        }
        if (!info.path)
            return []
        const list = []
        if (pane.model.mode === "trash" && entry.originalPath)
            list.push({ label: "Was in", value: entry.originalPath.substring(0, entry.originalPath.lastIndexOf("/")) || "/" })
        list.push({ label: "Kind", value: info.kindText || info.mimeType })
        if (info.isDirectory && selectionCount === 0)
            list.push({ label: "Contains", value: pane.model.totalCount + (pane.model.totalCount === 1 ? " item" : " items") + (pane.model.totalSize > 0 ? ", " + System.formatSize(pane.model.totalSize) + " in files" : "") })
        else if (info.isDirectory)
            list.push({ label: "Contains", value: measuredPath === info.path ? measuredText : "counting…" })
        else
            list.push({ label: "Size", value: info.sizeText })
        list.push({ label: "Modified", value: info.modifiedText })
        if (info.createdText)
            list.push({ label: "Created", value: info.createdText })
        list.push({ label: "Permissions", value: info.permissions + "  " + info.owner + ":" + info.group })
        if (info.linkTarget)
            list.push({ label: "Points to", value: info.linkTarget })
        list.push({ label: "Where", value: info.parent })
        return list
    }

    function update() {
        if (!pane)
            return
        const selected = pane.model.selectedPaths()
        selectionCount = selected.length
        let path = ""
        if (selected.length === 1) {
            path = selected[0]
            entry = pane.model.get(pane.model.indexOfPath(path))
        } else if (selected.length === 0 && pane.model.mode === "folder") {
            path = pane.path
            entry = { path: path, isDirectory: true, kind: "folder", canThumbnail: false, name: System.nameOf(path) }
        } else {
            entry = {}
        }
        info = path.length > 0 ? System.details(path) : ({})
        // Only a folder someone picked is walked; the folder being shown is described from its listing, or opening HOME would walk the whole disk.
        if (info.isDirectory && selected.length === 1 && measuredPath !== path) {
            measuredText = ""
            System.measureFolder(path)
        }
        refreshAnimation.restart()
    }

    Timer {
        id: updateTimer
        interval: 60
        onTriggered: root.update()
    }

    onPaneChanged: updateTimer.restart()

    Connections {
        target: root.pane ? root.pane.model : null
        function onSelectionChanged() { updateTimer.restart() }
        function onPathChanged() { updateTimer.restart() }
    }

    Connections {
        target: System
        function onFolderMeasured(path, bytes, files, folders) {
            root.measuredPath = path
            root.measuredText = files + (files === 1 ? " file, " : " files, ") + folders + (folders === 1 ? " folder · " : " folders · ") + System.formatSize(bytes)
        }
    }

    Connections {
        target: Settings
        function onShowDetailsChanged() {
            root.isOccupying = Settings.showDetails
            if (Settings.showDetails) {
                frame.enter(0)
                root.update()
            }
        }
    }

    // A change of what is described is a consequence of the click: the facts dip and come straight back, no travel.
    NumberAnimation {
        id: refreshAnimation
        target: content
        property: "opacity"
        from: 0.25
        to: 1
        duration: 180
        easing.type: Motion.enter
    }

    Module {
        id: frame
        width: workspace ? workspace.detailsWidth : Theme.rem * 14
        height: parent.height
        label: root.selectionCount > 1 ? "selection" : "details"
        sidePadding: Theme.rem * 0.8
        visible: opacity > 0

        Flickable {
            id: scroller
            anchors.fill: parent
            contentHeight: content.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: content
                width: scroller.width
                spacing: Theme.rem * 0.75

                Item {
                    width: parent.width
                    height: width * 0.8

                    Squircle {
                        anchors.fill: parent
                        fillColor: Theme.sunkenDeep
                        borderColor: Theme.border
                    }

                    Glyph {
                        anchors.centerIn: parent
                        width: parent.height * 0.48
                        height: width
                        visible: !picture.visible || picture.status !== Image.Ready
                        name: root.selectionCount > 1 ? "grid" : root.entry.isDirectory ? "folder" : ["text", "code", "image", "video", "audio", "archive", "document", "executable"].indexOf(root.entry.kind) !== -1 ? root.entry.kind : root.info.path ? "file" : "details"
                        ink: root.entry.isDirectory || root.selectionCount > 1 ? Theme.textBright : Theme.textIcon
                    }

                    SquircleImage {
                        id: picture
                        anchors.fill: parent
                        anchors.margins: 1
                        visible: root.selectionCount <= 1 && root.entry.canThumbnail === true
                        source: visible ? "image://thumbnail/" + encodeURIComponent(root.entry.path) : ""
                        sourceSize: Qt.size(512, 512)
                        radius: Theme.squircle
                        borderWidth: 0
                    }
                }

                Text {
                    width: parent.width
                    text: root.selectionCount > 1 ? root.selectionCount + " items" : root.info.path ? System.nameOf(root.info.path) : ""
                    color: Theme.textBright
                    font.family: Theme.mono
                    font.pixelSize: Theme.bodySize * 1.08
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    maximumLineCount: 4
                    textFormat: Text.PlainText
                }

                Rectangle {
                    width: parent.width * 0.45
                    height: 1
                    color: Theme.border
                }

                Repeater {
                    model: root.fields

                    delegate: Column {
                        required property var modelData
                        width: content.width
                        spacing: Theme.rem * 0.15

                        Text {
                            text: modelData.label.toUpperCase()
                            color: Theme.textLabel
                            font.family: Theme.mono
                            font.pixelSize: Theme.labelSize * 0.92
                            font.letterSpacing: Theme.labelSpacing
                        }

                        Text {
                            width: parent.width
                            text: modelData.value
                            color: Theme.textBody
                            font.family: Theme.mono
                            font.pixelSize: Theme.smallSize
                            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                            textFormat: Text.PlainText
                        }
                    }
                }

                Row {
                    spacing: Theme.rem * 0.3
                    visible: root.selectionCount === 1 && root.pane && root.pane.model.mode !== "trash"

                    Pill {
                        text: "open"
                        onClicked: root.workspace.command("open")
                    }

                    Pill {
                        text: "copy path"
                        onClicked: root.workspace.command("copyPath")
                    }
                }
            }
        }
    }
}
