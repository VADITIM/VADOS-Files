import QtQuick
import Vados

// The right-click menu. Rows that do not apply stay in place, greyed (VAS glass sheet §6), so the menu for a file is always the same shape and the hand learns where things are.
Item {
    id: root

    property var workspace
    property var pane: null
    property var entries: []
    property var applications: []
    property var placeRow: null
    property int highlighted: -1
    readonly property bool isOpen: sheet.isOpen

    // Read off the sheets' opacity, not their visibility: a child of a hidden item reports itself hidden, and the menu would never open.
    visible: sheet.opacity > 0 || submenu.opacity > 0

    // #region ── entries ───────────────────────────────────────────────────────────────────────
    function divider(): var {
        return { isDivider: true }
    }

    function buildEntries(isOnItem: bool): var {
        const model = pane.model
        const selected = model.selectedPaths()
        const count = selected.length
        const single = count === 1 ? model.get(model.indexOfPath(selected[0])) : null
        const hasClipboard = System.clipboardPaths.length > 0
        const hasFolder = selected.some(path => System.isDirectory(path))
        if (model.mode === "trash") {
            if (isOnItem)
                return [
                    { text: "Restore", glyph: "restore", command: "restore" },
                    divider(),
                    { text: "Delete for good", glyph: "trash", command: "deletePermanently", shortcut: "Shift Del", isDanger: true }
                ]
            return [
                { text: "Select all", glyph: "check", command: "selectAll", shortcut: "Ctrl A", isEnabled: model.count > 0 },
                divider(),
                { text: "Empty trash", glyph: "trash", command: "emptyTrash", isDanger: true, isEnabled: model.count > 0 }
            ]
        }
        if (isOnItem) {
            const isPinned = single && single.isDirectory && PlacesModel.isPinned(single.path)
            return [
                { text: "Open", glyph: single && single.isDirectory ? "folder-open" : "forward", command: "open", shortcut: "Enter" },
                { text: "Open with", glyph: "grid", submenu: true, isEnabled: single !== null && !single.isDirectory },
                { text: "Open in new tab", glyph: "plus", command: "openInTab", isEnabled: hasFolder },
                divider(),
                { text: "Cut", glyph: "cut", command: "cut", shortcut: "Ctrl X" },
                { text: "Copy", glyph: "copy", command: "copy", shortcut: "Ctrl C" },
                { text: "Paste into", glyph: "paste", command: "paste", argument: single && single.isDirectory ? single.path : "", isEnabled: hasClipboard && single !== null && single.isDirectory },
                { text: "Duplicate", glyph: "copy", command: "duplicate", shortcut: "Ctrl D" },
                { text: "Rename", glyph: "pencil", command: "rename", shortcut: "F2", isEnabled: count === 1 && model.mode === "folder" },
                divider(),
                { text: "Compress", glyph: "archive", command: "compress" },
                { text: "Extract here", glyph: "archive", command: "extract", isEnabled: single !== null && single.kind === "archive" },
                { text: "Copy path", glyph: "link", command: "copyPath", shortcut: "Ctrl Shift C" },
                { text: isPinned ? "Unpin from sidebar" : "Pin to sidebar", glyph: "star", command: "pin", isEnabled: single !== null && single.isDirectory },
                divider(),
                { text: "Move to trash", glyph: "trash", command: "trash", shortcut: "Del", isDanger: true }
            ]
        }
        const isFolder = model.mode === "folder"
        const isHere = PlacesModel.isPinned(pane.path)
        return [
            { text: "New folder", glyph: "folder", command: "newFolder", shortcut: "Ctrl Shift N", isEnabled: isFolder },
            { text: "New file", glyph: "file", command: "newFile", isEnabled: isFolder },
            { text: "Paste", glyph: "paste", command: "paste", shortcut: "Ctrl V", isEnabled: hasClipboard && isFolder },
            divider(),
            { text: "Select all", glyph: "check", command: "selectAll", shortcut: "Ctrl A", isEnabled: model.count > 0 },
            { text: "Open terminal here", glyph: "terminal", command: "terminal", shortcut: "Ctrl Alt T" },
            { text: "Copy path", glyph: "link", command: "copyPath" },
            { text: isHere ? "Unpin this folder" : "Pin this folder", glyph: "star", command: "pin", isEnabled: isFolder },
            divider(),
            { text: Settings.showHidden ? "Hide hidden files" : "Show hidden files", glyph: "grid", command: "hidden", shortcut: "Ctrl H" },
            { text: "Refresh", glyph: "restore", command: "refresh", shortcut: "F5" }
        ]
    }
    // #endregion ───────────────────────────────────────────────────────────────────────────────

    // #region ── open and close ────────────────────────────────────────────────────────────────
    function open(targetPane: var, point: point, isOnItem: bool) {
        pane = targetPane
        placeRow = null
        entries = buildEntries(isOnItem)
        const count = pane.model.selectedCount
        sheet.label = isOnItem ? (count === 1 ? System.nameOf(pane.model.selectedPaths()[0]) : count + " items") : workspace.titleFor(pane.path)
        present(point)
    }

    // After a right-button drag, Windows asks what the drop should be. The default the keys would have picked comes first.
    function openDropChoice(paths: var, target: string, point: point, defaultAction: int) {
        placeRow = null
        pane = workspace.activePane
        const isSameFolder = paths.every(path => System.parentOf(path) === target)
        const choices = [
            { text: "Move here", glyph: "cut", action: Qt.MoveAction, isEnabled: !isSameFolder },
            { text: "Copy here", glyph: "copy", action: Qt.CopyAction },
            { text: "Link here", glyph: "link", action: Qt.LinkAction }
        ].map(choice => ({ text: choice.text, glyph: choice.glyph, isEnabled: choice.isEnabled !== false, command: "dropTransfer", argument: { paths: paths, target: target, action: choice.action }, rank: choice.action === defaultAction ? 0 : 1 }))
        choices.sort((first, second) => first.rank - second.rank)
        entries = choices.concat([divider(), { text: "Cancel", glyph: "close", command: "cancel" }])
        sheet.label = workspace.countText(paths.length) + " → " + System.nameOf(target)
        present(point)
    }

    function openForPlace(row: var, point: point) {
        placeRow = row
        pane = workspace.activePane
        const list = [{ text: "Open", glyph: "folder-open", command: "navigate", argument: row.path }, { text: "Open in new tab", glyph: "plus", command: "tab", argument: row.path }]
        if (row.section === "pinned")
            list.push(divider(),
                      { text: "Rename", glyph: "pencil", command: "renamePin", argument: row.path, shortcut: "F2" },
                      { text: "Icon and colour", glyph: "star", command: "pinIcon", argument: { row: row.index, icon: row.icon } },
                      { text: "Unpin", glyph: "close", command: "unpin", argument: row.path, isDanger: true })
        else if (row.isMounted && !PlacesModel.isPinned(row.path))
            list.push(divider(), { text: "Pin", glyph: "star", command: "pinPath", argument: row.path })
        if (row.key === "trash")
            list.push(divider(), { text: "Empty trash", glyph: "trash", command: "emptyTrash", isDanger: true })
        if (row.canEject && row.isMounted)
            list.push(divider(), { text: "Eject", glyph: "eject", command: "eject", argument: row.device })
        entries = list
        sheet.label = row.name
        present(point)
    }

    function present(point: point) {
        highlighted = -1
        submenu.close()
        // The menu's corner sits on the pointer; near the right or bottom edge it opens to the other side, so the corner under the pointer is always the one it grows from.
        const margin = Theme.rem * 0.5
        const isLeftward = point.x + sheet.width > root.width - margin
        const isUpward = point.y + sheet.implicitHeight > root.height - margin
        sheet.x = Math.max(margin, isLeftward ? point.x - sheet.width : point.x)
        sheet.y = Math.max(margin, isUpward ? point.y - sheet.implicitHeight : point.y)
        sheet.transformOrigin = isUpward ? (isLeftward ? Item.BottomRight : Item.BottomLeft) : (isLeftward ? Item.TopRight : Item.TopLeft)
        sheet.open()
        focusCatcher.forceActiveFocus()
    }

    function close() {
        submenu.close()
        sheet.close()
        if (pane)
            pane.forceActiveFocus()
    }

    function trigger(entry: var) {
        if (!entry || entry.isDivider || entry.isEnabled === false)
            return
        if (entry.submenu) {
            openApplications()
            return
        }
        close()
        switch (entry.command) {
        case "tab": workspace.openTab(entry.argument); break
        case "unpin": PlacesModel.unpin(entry.argument); break
        case "pinPath": PlacesModel.pin(entry.argument); break
        case "renamePin": workspace.renamingPin = entry.argument; break
        case "pinIcon": workspace.openIconPicker(entry.argument.row, entry.argument.icon, Qt.point(sheet.x, sheet.y)); break
        case "eject": PlacesModel.unmount(entry.argument); break
        case "dropTransfer": FileOperations.transfer(entry.argument.paths, entry.argument.target, entry.argument.action); break
        case "cancel": break
        default: workspace.command(entry.command, entry.argument)
        }
    }

    function openApplications() {
        const selected = pane.model.selectedPaths()
        if (selected.length !== 1)
            return
        applications = System.applicationsFor(selected[0])
        let rowItem = null
        for (let index = 0; index < rows.count; ++index)
            if (rows.itemAt(index).entry && rows.itemAt(index).entry.submenu)
                rowItem = rows.itemAt(index)
        const anchor = rowItem ? rowItem.mapToItem(root, rowItem.width, 0) : Qt.point(sheet.x + sheet.width, sheet.y)
        submenu.x = anchor.x + submenu.width + Theme.rem * 0.4 > root.width ? sheet.x - submenu.width - Theme.rem * 0.3 : anchor.x + Theme.rem * 0.4
        submenu.y = Math.min(anchor.y - Theme.rem * 1.9, root.height - submenu.implicitHeight - Theme.rem * 0.5)
        submenu.open()
    }
    // #endregion ───────────────────────────────────────────────────────────────────────────────

    MouseArea {
        anchors.fill: parent
        enabled: sheet.isOpen
        acceptedButtons: Qt.AllButtons
        onPressed: root.close()
        onWheel: root.close()
    }

    Item {
        id: focusCatcher
        focus: sheet.isOpen
        Keys.onEscapePressed: root.close()
        Keys.onUpPressed: {
            let next = root.highlighted
            do { next = (next - 1 + root.entries.length) % root.entries.length } while (root.entries[next].isDivider || root.entries[next].isEnabled === false)
            root.highlighted = next
        }
        Keys.onDownPressed: {
            let next = root.highlighted
            do { next = (next + 1) % root.entries.length } while (root.entries[next].isDivider || root.entries[next].isEnabled === false)
            root.highlighted = next
        }
        Keys.onReturnPressed: root.trigger(root.entries[root.highlighted])
        Keys.onEnterPressed: root.trigger(root.entries[root.highlighted])
        Keys.onRightPressed: if (root.highlighted >= 0 && root.entries[root.highlighted].submenu) root.openApplications()
    }

    MenuSheet {
        id: sheet
        width: Theme.rem * 15
        isAnchored: true

        Repeater {
            id: rows
            model: root.entries

            delegate: Item {
                id: slot
                required property var modelData
                required property int index
                readonly property var entry: modelData
                width: sheet.column.width
                height: modelData.isDivider ? Theme.rem * 0.55 : row.implicitHeight

                Rectangle {
                    visible: slot.modelData.isDivider === true
                    anchors.verticalCenter: parent.verticalCenter
                    x: Theme.rem * 0.6
                    width: parent.width * 0.45
                    height: 1
                    color: Theme.border
                }

                MenuRow {
                    id: row
                    visible: !slot.modelData.isDivider
                    width: parent.width
                    text: slot.modelData.text || ""
                    glyph: slot.modelData.glyph || ""
                    shortcut: slot.modelData.shortcut || ""
                    isEnabled: slot.modelData.isEnabled !== false
                    isDanger: slot.modelData.isDanger === true
                    hasSubmenu: slot.modelData.submenu === true
                    isHighlighted: root.highlighted === slot.index
                    onHovered: {
                        root.highlighted = slot.index
                        if (slot.modelData.submenu === true)
                            submenuTimer.restart()
                        else if (submenu.isOpen)
                            submenu.close()
                    }
                    onTriggered: root.trigger(slot.modelData)
                }
            }
        }
    }

    Timer {
        id: submenuTimer
        interval: 180
        onTriggered: root.openApplications()
    }

    MenuSheet {
        id: submenu
        label: "open with"
        width: Theme.rem * 13

        Repeater {
            model: root.applications

            delegate: MenuRow {
                required property var modelData
                width: submenu.column.width
                text: modelData.name
                glyph: modelData.isDefault ? "check" : ""
                onTriggered: {
                    root.close()
                    root.workspace.command("openWith", modelData.file)
                }
            }
        }

        Text {
            visible: root.applications.length === 0
            x: Theme.rem * 0.6
            height: Theme.rem * 1.8
            verticalAlignment: Text.AlignVCenter
            text: "No application claims this kind of file."
            color: Theme.textFaint
            font.family: Theme.mono
            font.pixelSize: Theme.smallSize
        }
    }
}
