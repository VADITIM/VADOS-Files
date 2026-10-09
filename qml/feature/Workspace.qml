import QtQuick
import Vados

// The window's contents and the one funnel every input goes through (VAS interaction: every input path funnels into one change function). Keys, menus, buttons and drops all call `command` or the drag functions here, so a pending confirm, a lock or a room change applies to all of them alike.
FocusScope {
    id: workspace

    property var activePane: null
    property var primaryPane: null
    property bool isSecondaryActive: false
    property int activeTabIndex: 0
    property string currentRoomKey: ""
    property string pendingMountDevice: ""
    property var dragTarget: null
    property bool hasLaunched: false
    readonly property alias tabs: tabModel
    // Children that carry a `workspace` property cannot be handed `workspace` by id — inside them the name means their own property. They are handed this.
    readonly property var workspaceItem: workspace
    readonly property real sideWidth: Theme.rem * Math.max(7, Math.min(22, Settings.sideWidthRem))
    readonly property real detailsWidth: Theme.rem * 14

    // #region ── rooms ─────────────────────────────────────────────────────────────────────────
    function roomKeyFor(path: string): string {
        if (path === "trash:///")
            return "trash"
        const tint = PlacesModel.tintFor(path)
        return tint.length > 0 ? tint : PlacesModel.placeFor(path).key
    }

    // A colour chosen for a pin takes effect at once where the user is standing.
    Connections {
        target: PlacesModel
        function onPinsChanged() {
            if (!workspace.activePane || !workspace.hasLaunched)
                return
            const key = workspace.roomKeyFor(workspace.activePane.path)
            if (key === workspace.currentRoomKey)
                return
            workspace.currentRoomKey = key
            Theme.accent = Theme.accentFor(key)
        }
    }

    function titleFor(path: string): string {
        return System.nameOf(path)
    }

    function labelFor(pane: var): string {
        if (!pane)
            return ""
        if (pane.model.mode === "search")
            return "search"
        if (pane.model.mode === "trash")
            return "trash"
        return pane.path.length > 0 ? PlacesModel.placeFor(pane.path).name : ""
    }

    function captionFor(pane: var): string {
        if (!pane)
            return ""
        const model = pane.model
        const total = model.count
        const items = total === 1 ? "1 item" : total + " items"
        if (model.isSearching)
            return items + " found so far."
        if (model.selectedCount > 0) {
            const size = model.selectedSize > 0 ? ", " + System.formatSize(model.selectedSize) : ""
            return model.selectedCount + " of " + items + " selected" + size + "."
        }
        if (model.filter.length > 0)
            return items + " matching “" + model.filter + "”."
        return items + (model.mode === "folder" && model.totalSize > 0 ? ", " + System.formatSize(model.totalSize) + " in files." : ".")
    }

    // Called when a pane starts to leave; the cut comes after the ordinary leave, room change or not.
    function beginRoomChange(pane: var, target: string): int {
        return Motion.navigateLeave
    }

    // The cut: nothing of either folder is on screen, so this is where the room's colour changes (VAS palette: the accent changes on the cut, never on the click).
    function paneCut(pane: var) {
        if (pane !== activePane)
            return
        if (pane.model.mode === "folder" && pane.path !== "trash:///")
            Settings.lastPath = pane.path
        const key = roomKeyFor(pane.path)
        if (key === currentRoomKey)
            return
        currentRoomKey = key
        Theme.accent = Theme.accentFor(key)
    }

    function setActivePane(pane: var) {
        if (!pane || pane === activePane)
            return
        if (activePane)
            activePane.isActive = false
        activePane = pane
        pane.isActive = true
        isSecondaryActive = pane === secondaryPane
        const key = roomKeyFor(pane.path)
        if (key === currentRoomKey || !hasLaunched)
            return
        currentRoomKey = key
        Theme.accent = Theme.accentFor(key)
    }
    // #endregion ───────────────────────────────────────────────────────────────────────────────

    // #region ── tabs ──────────────────────────────────────────────────────────────────────────
    function openTab(path: string) {
        tabModel.append({ initialPath: path })
        switchTab(tabModel.count - 1)
    }

    function closeTab(index: int) {
        if (tabModel.count <= 1) {
            Qt.quit()
            return
        }
        const wasActive = index === activeTabIndex
        tabModel.remove(index)
        if (index < activeTabIndex || activeTabIndex >= tabModel.count)
            activeTabIndex = Math.max(0, activeTabIndex - 1)
        if (wasActive || index <= activeTabIndex)
            Qt.callLater(syncPrimary)
    }

    function switchTab(index: int) {
        if (index < 0 || index >= tabModel.count)
            return
        if (index === activeTabIndex && primaryPane === paneRepeater.itemAt(index))
            return
        if (primaryPane && primaryPane.visible)
            primaryPane.leaveRequested()
        tabTimer.index = index
        tabTimer.restart()
    }

    property int paneRevision: 0
    function paneAt(index: int, revision: int): var {
        return paneRepeater.itemAt(index)
    }

    function syncPrimary() {
        const pane = paneRepeater.itemAt(activeTabIndex)
        if (!pane)
            return
        primaryPane = pane
        if (!isSecondaryActive || !Settings.isSplit)
            setActivePane(pane)
        pane.forceActiveFocus()
    }

    Timer {
        id: tabTimer
        property int index: 0
        interval: Motion.navigateLeave
        onTriggered: {
            workspace.activeTabIndex = index
            workspace.isSecondaryActive = false
            workspace.syncPrimary()
            if (workspace.primaryPane)
                workspace.primaryPane.replayEnter()
        }
    }

    ListModel {
        id: tabModel
    }
    // #endregion ───────────────────────────────────────────────────────────────────────────────

    // #region ── commands ──────────────────────────────────────────────────────────────────────
    function selectedOrCurrent(pane: var): var {
        const selected = pane.model.selectedPaths()
        if (selected.length > 0)
            return selected
        const current = pane.model.get(pane.model.currentIndex)
        return current.path ? [current.path] : []
    }

    function command(name: string, argument: var) {
        const pane = activePane
        if (name !== "confirm" && name !== "contextMenu")
            confirmHost.clearConfirm()
        if (!pane)
            return
        const model = pane.model
        const isTrash = model.mode === "trash"
        switch (name) {
        case "back": pane.goBack(); break
        case "forward": pane.goForward(); break
        case "up": pane.goUp(); break
        case "home": pane.navigate(System.homePath, {}); break
        case "refresh": pane.refresh(); break
        case "navigate": pane.navigate(argument, {}); break
        case "open": pane.activateSelection(); break
        case "openInTab":
            for (const path of model.selectedPaths())
                if (System.isDirectory(path))
                    openTab(path)
            break
        case "newTab": openTab(pane.model.mode === "folder" ? pane.path : System.homePath); break
        case "closeTab": closeTab(activeTabIndex); break
        case "nextTab": switchTab((activeTabIndex + 1) % tabModel.count); break
        case "previousTab": switchTab((activeTabIndex - 1 + tabModel.count) % tabModel.count); break
        case "split": toggleSplit(); break
        case "details": Settings.showDetails = !Settings.showDetails; break
        case "hidden": Settings.showHidden = !Settings.showHidden; break
        case "viewGrid": if (Settings.viewMode !== "grid") pane.reflow(() => Settings.viewMode = "grid"); break
        case "viewList": if (Settings.viewMode !== "list") pane.reflow(() => Settings.viewMode = "list"); break
        case "toggleView": pane.reflow(() => Settings.viewMode = Settings.viewMode === "grid" ? "list" : "grid"); break
        case "zoomIn": Settings.zoomLevel = Math.min(3, Settings.zoomLevel + 1); break
        case "zoomOut": Settings.zoomLevel = Math.max(0, Settings.zoomLevel - 1); break
        case "zoom": Settings.zoomLevel = argument; break
        case "sort": pane.reflow(() => { Settings.sortKey = argument; Settings.sortDescending = argument === "modified" || argument === "size" }); break
        case "sortReverse": pane.reflow(() => Settings.sortDescending = !Settings.sortDescending); break
        case "rename": {
            const targets = selectedOrCurrent(pane)
            if (targets.length === 1 && !isTrash && model.mode !== "search") {
                pane.ensureVisible(model.indexOfPath(targets[0]))
                pane.renamingPath = targets[0]
            }
            break
        }
        case "newFolder":
        case "newFile": {
            if (model.mode !== "folder")
                break
            const created = name === "newFolder" ? FileOperations.createFolder(pane.path) : FileOperations.createFile(pane.path)
            if (created.length > 0) {
                pane.expectSelection([created])
                renameTimer.pane = pane
                renameTimer.path = created
                renameTimer.attempts = 0
                renameTimer.restart()
            }
            break
        }
        case "copy":
        case "cut": {
            const targets = model.selectedPaths()
            if (targets.length > 0 && !isTrash)
                System.copyPaths(targets, name === "cut")
            break
        }
        case "paste": {
            const sources = System.clipboardPaths
            if (sources.length === 0 || model.mode !== "folder")
                break
            const destination = argument && argument.length > 0 ? argument : pane.path
            if (System.isClipboardCut) {
                FileOperations.move(sources, destination)
                System.clearClipboard()
            } else {
                FileOperations.copy(sources, destination)
            }
            break
        }
        case "duplicate": if (!isTrash) FileOperations.duplicate(model.selectedPaths()); break
        case "trash": {
            const targets = selectedOrCurrent(pane)
            if (targets.length === 0)
                break
            if (isTrash) {
                command("deletePermanently")
                break
            }
            // As on Windows: Delete goes straight to the trash, and the undo pill brings it back. Only deleting for good asks first.
            FileOperations.trash(targets)
            break
        }
        case "deletePermanently": {
            const targets = selectedOrCurrent(pane)
            if (targets.length > 0)
                confirmHost.confirm(countText(targets.length) + " deleted for good. This cannot be undone.", () => FileOperations.deletePermanently(targets), true)
            break
        }
        case "restore": if (isTrash) FileOperations.restore(model.selectedPaths()); break
        case "emptyTrash": confirmHost.confirm("Everything in the trash deleted for good.", () => FileOperations.emptyTrash(), true); break
        case "selectAll": model.selectAll(); break
        case "invertSelection": {
            const rows = []
            for (let index = 0; index < model.count; ++index)
                if (!model.isSelected(index))
                    rows.push(index)
            model.selectRows(rows, [])
            break
        }
        case "undo": if (FileOperations.canUndo) FileOperations.undo(); break
        case "quickLook": quickLook.toggle(pane); break
        case "copyPath": {
            const targets = model.selectedPaths()
            System.copyText(targets.length > 0 ? targets.join("\n") : pane.path)
            confirmHost.offer(targets.length > 1 ? "Paths copied" : "Path copied", null, 1600)
            break
        }
        case "terminal": System.openTerminal(model.mode === "folder" ? pane.path : System.homePath, Settings.terminalCommand); break
        case "compress": if (!isTrash) FileOperations.compress(model.selectedPaths()); break
        case "extract":
            for (const path of model.selectedPaths())
                FileOperations.extract(path)
            break
        case "pin": {
            const target = model.selectedPaths().length === 1 && System.isDirectory(model.selectedPaths()[0]) ? model.selectedPaths()[0] : pane.path
            if (PlacesModel.isPinned(target))
                PlacesModel.unpin(target)
            else
                PlacesModel.pin(target)
            break
        }
        case "openWith": System.openWith(argument, model.selectedPaths()); break
        case "focusPath": toolbar.editPath(); break
        case "search": toolbar.focusSearch(); break
        case "settings": settingsSheet.toggle(); break
        case "contextMenu": {
            const item = pane.itemForIndex(model.currentIndex)
            const point = item ? item.mapToItem(workspace, item.width / 2, item.height / 2) : pane.mapToItem(workspace, pane.width / 2, pane.height / 3)
            openContextMenu(pane, point, model.selectedCount > 0)
            break
        }
        }
    }

    function countText(count: int): string {
        return count === 1 ? "1 item" : count + " items"
    }

    function toggleSplit() {
        Settings.isSplit = !Settings.isSplit
        if (Settings.isSplit) {
            if (secondaryPane.path.length === 0)
                secondaryPane.navigate(primaryPane ? primaryPane.path : System.homePath, { isInitial: true })
            secondaryPane.frame.enter(Motion.navigateLeave)
            secondaryPane.replayEnter()
        } else {
            if (activePane === secondaryPane)
                setActivePane(primaryPane)
            primaryPane.forceActiveFocus()
        }
    }

    // A new folder is named in place the moment it appears, the way Explorer does it.
    Timer {
        id: renameTimer
        property var pane
        property string path: ""
        property int attempts: 0
        interval: 60
        repeat: true
        onTriggered: {
            attempts += 1
            if (pane.model.indexOfPath(path) >= 0) {
                stop()
                pane.ensureVisible(pane.model.indexOfPath(path))
                pane.renamingPath = path
            } else if (attempts > 30) {
                stop()
            }
        }
    }

    function openContextMenu(pane: var, point: point, isOnItem: bool) {
        contextMenu.open(pane, point, isOnItem)
    }

    function openPlaceMenu(row: var, point: point) {
        contextMenu.openForPlace(row, point)
    }

    // The pin being renamed in place in the sidebar, by path; empty when none is.
    property string renamingPin: ""
    // True while files are being dragged out of a pane, so the sidebar can offer its pin slot.
    property bool isCarrying: false

    function openIconPicker(row: int, icon: string, point: point) {
        iconPicker.open(row, icon, point)
    }

    function showError(message: string) {
        confirmHost.offer(message, null, 3200, true)
    }
    // #endregion ───────────────────────────────────────────────────────────────────────────────

    // #region ── picker ────────────────────────────────────────────────────────────────────────
    // Only in force when another app asked for a file through the portal (Picker.isActive).
    property int pickerFilter: Math.max(0, Math.min(Picker.initialFilter, Picker.filters.length - 1))
    readonly property var pickerPatterns: Picker.isActive && Picker.filters.length > 0 ? Picker.filters[pickerFilter].patterns : []

    // The accept, from the button, Enter, or activating a file: hands the answer back, or walks into a folder when that is all the selection holds.
    function pick() {
        const pane = activePane
        if (!pane || !Picker.isActive)
            return
        const model = pane.model
        const selected = model.selectedPaths()
        if (Picker.mode === "save") {
            const name = pickerBar.name.trim()
            if (name.length === 0 || model.mode !== "folder")
                return
            const target = name.startsWith("/") ? name : pane.path + "/" + name
            if (System.isDirectory(target)) {
                pane.navigate(target, { direction: "into" })
                return
            }
            if (System.exists(target)) {
                confirmHost.confirm("“" + System.nameOf(target) + "” replaced.", () => Picker.accept([target], pickerFilter), true)
                return
            }
            Picker.accept([target], pickerFilter)
            return
        }
        if (Picker.mode === "folder") {
            const folders = selected.filter(path => System.isDirectory(path))
            if (folders.length > 0)
                Picker.accept(Picker.isMultiple ? folders : [folders[0]], pickerFilter)
            else if (model.mode === "folder")
                Picker.accept([pane.path], pickerFilter)
            return
        }
        const files = selected.filter(path => !System.isDirectory(path))
        if (files.length === 0) {
            if (selected.length === 1)
                pane.navigate(selected[0], { direction: "into" })
            return
        }
        Picker.accept(Picker.isMultiple ? files : [files[0]], pickerFilter)
    }

    // Activating one file: opening picks it, saving takes its name and asks before replacing it.
    function pickFile(path: string) {
        if (Picker.mode === "save")
            pickerBar.name = System.nameOf(path)
        else if (Picker.mode === "open")
            activePane.model.selectPaths([path])
        pick()
    }
    // #endregion ───────────────────────────────────────────────────────────────────────────────

    // #region ── drag and drop ─────────────────────────────────────────────────────────────────
    // What a drop would do, decided the way Windows decides: Ctrl copies, Shift moves, Ctrl+Shift links, and with no key a drop moves within one drive and copies across drives.
    function dropActionFor(paths: var, target: string): int {
        const modifiers = System.keyboardModifiers()
        if ((modifiers & Qt.ControlModifier) && (modifiers & Qt.ShiftModifier))
            return Qt.LinkAction
        if (modifiers & Qt.ControlModifier)
            return Qt.CopyAction
        if (modifiers & Qt.ShiftModifier)
            return Qt.MoveAction
        if (target === "trash:///")
            return Qt.MoveAction
        for (const path of paths)
            if (!FileOperations.isSameDevice(path, target))
                return Qt.CopyAction
        return Qt.MoveAction
    }

    function verbFor(action: int, target: string): string {
        if (target === "trash:///")
            return "Trash"
        if (isRightDrag)
            return "Drop on"
        return action === Qt.CopyAction ? "Copy to" : action === Qt.LinkAction ? "Link in" : "Move to"
    }

    function acceptDrag(event: var, target: string, item: var, area: var): bool {
        if (!event.hasUrls)
            return false
        const paths = System.localPaths(event.urls)
        if (paths.length === 0)
            return false
        for (const path of paths) {
            // A folder cannot go inside itself, and a drop onto its own folder with no key held is nothing.
            if (target === path || target.startsWith(path + "/"))
                return false
        }
        const action = dropActionFor(paths, target)
        const isSameFolder = paths.every(path => System.parentOf(path) === target)
        if (isSameFolder && action === Qt.MoveAction && !isRightDrag)
            return false
        event.accept(action)
        dragTarget = item
        dropHint.show(verbFor(action, target), target === "trash:///" ? "" : System.nameOf(target), area.mapToItem(workspace, event.x, event.y))
        return true
    }

    function updateDrag(event: var, target: string, item: var, area: var) {
        const paths = System.localPaths(event.urls)
        const action = dropActionFor(paths, target)
        event.accept(action)
        dropHint.show(verbFor(action, target), target === "trash:///" ? "" : System.nameOf(target), area.mapToItem(workspace, event.x, event.y))
    }

    function leaveDrag(item: var) {
        if (dragTarget === item)
            dropHint.hide()
    }

    function dropOnto(event: var, target: string, item: var, area: var) {
        const paths = System.localPaths(event.urls)
        dropHint.hide()
        if (paths.length === 0)
            return
        const point = area.mapToItem(workspace, event.x, event.y)
        if (target === "trash:///") {
            event.accept(Qt.MoveAction)
            Qt.callLater(() => FileOperations.trash(paths))
            return
        }
        const action = dropActionFor(paths, target)
        if (isRightDrag) {
            // The source never deletes, so accepting as a copy commits to nothing; the menu decides after the drag has let go.
            event.accept(Qt.CopyAction)
            Qt.callLater(() => contextMenu.openDropChoice(paths, target, point, action))
            return
        }
        event.accept(action)
        // Defer the work past the end of the drag: the source's nested drag loop is still unwinding, and a job started inside it would report into a pane that has not let go yet.
        Qt.callLater(() => FileOperations.transfer(paths, target, action))
        ripple.play(item ? item.mapToItem(workspace, item.width / 2, item.height / 2 - Theme.rem * 0.6) : point)
    }

    // Set for the life of a drag started with the right button (Windows): the drop asks instead of acting.
    property bool isRightDrag: false

    function beginCarry(pane: var, paths: var, isRight: bool) {
        isRightDrag = isRight
        isCarrying = paths.some(path => System.isDirectory(path))
        quickLook.close()
    }

    function endCarry(pane: var, action: int) {
        isRightDrag = false
        isCarrying = false
        dropHint.hide()
    }
    // #endregion ───────────────────────────────────────────────────────────────────────────────

    // #region ── launch ────────────────────────────────────────────────────────────────────────
    // The one time the app runs at the portfolio's full tempo: every module assembles diagonally from the top-left, and the labels are swept on by their bars.
    function launch() {
        const panes = [primaryPane].concat(Settings.isSplit ? [secondaryPane] : [])
        const modules = places.modules.concat(panes.map(pane => pane.frame)).concat(Settings.showDetails ? [details.module] : [])
        const delayOf = item => {
            const point = item.mapToItem(workspace, 0, 0)
            return Motion.positionalDelay(point.x, point.y, workspace.width, workspace.height, Motion.launchStaggerVertical, Motion.launchStaggerHorizontal) + 60
        }
        for (const module of modules) {
            module.isFullTempo = true
            module.enter(delayOf(module))
        }
        toolbar.enter(delayOf(toolbar))
        tabStrip.enter(delayOf(tabStrip))
        historyControls.enter(delayOf(historyControls))
        viewControls.enter(delayOf(viewControls))
        if (Picker.isActive)
            pickerBar.enter(delayOf(pickerBar))
        for (const pane of panes)
            pane.release(delayOf(pane.frame) + 140)
        hasLaunched = true
        restoreTempo.restart()
        if (Picker.mode === "save")
            pickerBar.focusName()
    }

    Timer {
        id: restoreTempo
        interval: 1600
        onTriggered: {
            for (const module of places.modules.concat([details.module, secondaryPane.frame]))
                module.isFullTempo = false
            for (let index = 0; index < paneRepeater.count; ++index)
                paneRepeater.itemAt(index).frame.isFullTempo = false
        }
    }

    Component.onCompleted: {
        let start = System.initialPath
        if (start.length === 0 && Settings.lastPath.length > 0 && System.isDirectory(Settings.lastPath))
            start = Settings.lastPath
        if (start.length === 0)
            start = System.homePath
        currentRoomKey = roomKeyFor(start)
        Theme.accent = Theme.accentFor(currentRoomKey)
        tabModel.append({ initialPath: start })
        if (Settings.isSplit)
            secondaryPane.navigate(start, { isInitial: true })
        launchTimer.start()
    }

    Timer {
        id: launchTimer
        interval: Motion.launchDelay
        onTriggered: workspace.launch()
    }
    // #endregion ───────────────────────────────────────────────────────────────────────────────

    Connections {
        target: FileOperations
        function onJobFinished(jobId, verb, count, summary, isUndoable, paths, destination) {
            for (const pane of [workspace.primaryPane, workspace.secondaryPane])
                if (pane && pane.path === destination && paths.length > 0 && verb !== "trash" && verb !== "delete")
                    pane.expectSelection(paths)
            if (summary.length > 0 && verb !== "rename")
                confirmHost.offer(summary, isUndoable ? () => FileOperations.undo() : null, verb === "trash" ? Motion.undoTrash : Motion.undoMove)
        }
        function onFailed(message) { workspace.showError(message) }
        function onConflict(jobId, name, destination) { confirmHost.askConflict(jobId, name, destination) }
    }

    Connections {
        target: PlacesModel
        function onFailed(message) { workspace.showError(message) }
        function onMounted(device, path) {
            if (device === workspace.pendingMountDevice) {
                workspace.pendingMountDevice = ""
                workspace.command("navigate", path)
            }
        }
    }

    // #region ── layout ────────────────────────────────────────────────────────────────────────
    // The top band: history over the places, tabs over the folder, the view controls over the layout switches.
    readonly property real bandHeight: Theme.rem * 2
    readonly property real bandGap: Theme.rem * 0.5

    ControlRow {
        id: historyControls
        x: Theme.gap
        y: Theme.gap
        readonly property var pane: workspace.activePane

        IconButton {
            glyph: "back"
            hint: "back · alt ←"
            isEnabled: historyControls.pane !== null && historyControls.pane.backStack.length > 0
            onClicked: workspace.command("back")
        }
        IconButton {
            glyph: "forward"
            hint: "forward · alt →"
            isEnabled: historyControls.pane !== null && historyControls.pane.forwardStack.length > 0
            onClicked: workspace.command("forward")
        }
        IconButton {
            glyph: "up"
            hint: "up · alt ↑"
            isEnabled: historyControls.pane !== null && (System.parentOf(historyControls.pane.path).length > 0 || historyControls.pane.model.mode === "search")
            onClicked: workspace.command("up")
        }
    }

    PlacesModule {
        id: places
        workspace: workspaceItem
        x: Theme.gap
        y: Theme.gap + workspace.bandHeight + workspace.bandGap
        width: workspace.sideWidth
        height: parent.height - y - Theme.gap
    }

    // The divider between the sidebar and the folder: drag it to resize the sidebar, double-click to put it back.
    MouseArea {
        id: divider
        objectName: "sideDivider"
        x: places.x + places.width
        y: places.y
        width: Theme.gap
        height: places.height
        hoverEnabled: true
        cursorShape: Qt.SplitHCursor
        property real pressX: 0
        property real startRem: 0
        onPressed: event => {
            pressX = mapToItem(workspace, event.x, 0).x
            startRem = Settings.sideWidthRem
        }
        onPositionChanged: event => {
            if (!pressed)
                return
            const delta = mapToItem(workspace, event.x, 0).x - pressX
            Settings.sideWidthRem = Math.round(Math.max(7, Math.min(22, startRem + delta / Theme.rem)) * 20) / 20
        }
        onDoubleClicked: Settings.sideWidthRem = 10

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            width: 2
            height: parent.pressed ? parent.height * 0.5 : Theme.rem * 2.4
            radius: 1
            color: parent.pressed ? Theme.accent : Theme.borderHover
            opacity: parent.pressed || parent.containsMouse ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.hover } }
            Behavior on height { NumberAnimation { duration: Motion.stateChange; easing.type: Motion.enterProminent } }
        }
    }

    Item {
        id: center
        anchors.left: places.right
        anchors.leftMargin: Theme.gap
        anchors.right: details.left
        anchors.rightMargin: Theme.gap * Math.min(1, details.width / workspace.detailsWidth)
        anchors.top: parent.top
        anchors.topMargin: Theme.gap
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.gap

        TabStrip {
            id: tabStrip
            workspace: workspaceItem
            anchors.verticalCenter: viewControls.verticalCenter
            anchors.left: parent.left
            anchors.right: viewControls.left
            anchors.rightMargin: Theme.gap
        }

        ControlRow {
            id: viewControls
            // Pinned to the window's top-right corner, not the centre column, so it stays put while the details column slides.
            x: workspace.width - Theme.gap - center.x - width

            IconButton {
                glyph: "grid"
                hint: "grid · ctrl 1"
                isOn: Settings.viewMode === "grid"
                onClicked: workspace.command("viewGrid")
            }
            IconButton {
                glyph: "list"
                hint: "list, one per row · ctrl 2"
                isOn: Settings.viewMode === "list"
                onClicked: workspace.command("viewList")
            }
            GooStepSlider {
                anchors.verticalCenter: parent.verticalCenter
                count: 4
                value: Settings.zoomLevel
                onCommitted: step => workspace.command("zoom", step)
            }
            IconButton {
                glyph: "settings"
                hint: "settings · ctrl ,"
                onClicked: workspace.command("settings")
            }
        }

        Toolbar {
            id: toolbar
            workspace: workspaceItem
            // Above the panes, so the path completions drop over the folder instead of under it.
            z: 10
            y: workspace.bandHeight + workspace.bandGap
            width: parent.width
        }

        Item {
            id: paneArea
            anchors.top: toolbar.bottom
            anchors.topMargin: Theme.gap
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: pickerBar.visible ? pickerBar.top : parent.bottom
            anchors.bottomMargin: pickerBar.visible ? Theme.gap : 0
            readonly property real primaryWidth: Settings.isSplit ? (width - Theme.gap) / 2 : width

            Repeater {
                id: paneRepeater
                model: tabModel
                onItemAdded: workspace.paneRevision += 1
                onItemRemoved: workspace.paneRevision += 1

                delegate: FolderPane {
                    id: tabPane
                    required property int index
                    required property string initialPath
                    workspace: workspaceItem
                    width: paneArea.primaryWidth
                    height: paneArea.height
                    visible: index === workspace.activeTabIndex
                    isHeld: !workspace.hasLaunched
                    onCut: workspace.paneCut(tabPane)
                    Component.onCompleted: {
                        navigate(initialPath, { isInitial: true })
                        if (workspace.hasLaunched) {
                            frame.showNow()
                        } else if (index === 0) {
                            workspace.primaryPane = tabPane
                            workspace.setActivePane(tabPane)
                            tabPane.forceActiveFocus()
                        }
                    }
                }
            }

            FolderPane {
                id: secondaryPane
                workspace: workspaceItem
                x: paneArea.primaryWidth + Theme.gap
                width: paneArea.primaryWidth
                height: paneArea.height
                visible: Settings.isSplit
                isHeld: !workspace.hasLaunched
                onCut: workspace.paneCut(secondaryPane)
            }
        }

        PickerBar {
            id: pickerBar
            workspace: workspaceItem
            visible: Picker.isActive
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
        }
    }

    DetailsModule {
        id: details
        workspace: workspaceItem
        anchors.right: parent.right
        anchors.rightMargin: Theme.gap
        y: Theme.gap + workspace.bandHeight + workspace.bandGap
        // Below about 1000px the details column steps aside, so the path and filter keep their room; it comes back when the window widens.
        readonly property bool isShown: isOccupying && workspace.width >= Theme.rem * 50
        visible: workspace.width >= Theme.rem * 50
        // The column slides: its width opens from the right edge and the folder beside it is pushed in, frame by frame.
        width: isShown ? workspace.detailsWidth : 0
        Behavior on width { NumberAnimation { duration: Motion.overlayEnter; easing.type: Motion.enter } }
        height: parent.height - y - Theme.gap
    }
    // #endregion ───────────────────────────────────────────────────────────────────────────────

    // #region ── overlays ──────────────────────────────────────────────────────────────────────
    DropHint {
        id: dropHint
    }

    Item {
        id: ripple
        width: Theme.rem * 4
        height: width
        opacity: 0
        visible: opacity > 0

        function play(point: point) {
            x = point.x - width / 2
            y = point.y - height / 2
            rippleAnimation.restart()
        }

        Squircle {
            anchors.fill: parent
            radius: width / 2
            exponent: 2
            fillColor: Theme.alpha(Theme.accent, 0.12)
            borderColor: Theme.accent
            borderWidth: 2
        }

        // Consequence: one shot, immediate, tied to the drop.
        ParallelAnimation {
            id: rippleAnimation
            NumberAnimation { target: ripple; property: "scale"; from: 0.3; to: 1.5; duration: 380; easing.type: Easing.OutCubic }
            NumberAnimation { target: ripple; property: "opacity"; from: 1; to: 0; duration: 380; easing.type: Motion.leave }
        }
    }

    ConfirmHost {
        id: confirmHost
        objectName: "confirmHost"
        workspace: workspaceItem
        anchors.fill: parent
    }

    QuickLook {
        id: quickLook
        workspace: workspaceItem
        anchors.fill: parent
    }

    ContextMenu {
        id: contextMenu
        workspace: workspaceItem
        anchors.fill: parent
    }

    IconPicker {
        id: iconPicker
        anchors.fill: parent
    }

    SettingsSheet {
        id: settingsSheet
        workspace: workspaceItem
        anchors.fill: parent
    }
    // #endregion ───────────────────────────────────────────────────────────────────────────────

    // #region ── shortcuts ─────────────────────────────────────────────────────────────────────
    Shortcut { sequence: "Ctrl+T"; onActivated: workspace.command("newTab") }
    Shortcut { sequence: "Ctrl+W"; onActivated: workspace.command("closeTab") }
    Shortcut { sequences: ["Ctrl+Tab", "Ctrl+PgDown"]; onActivated: workspace.command("nextTab") }
    Shortcut { sequences: ["Ctrl+Shift+Tab", "Ctrl+PgUp"]; onActivated: workspace.command("previousTab") }
    Shortcut { sequences: ["Ctrl+L", "F6"]; onActivated: workspace.command("focusPath") }
    Shortcut { sequence: "Ctrl+F"; onActivated: workspace.command("search") }
    Shortcut { sequence: "F3"; onActivated: workspace.command("split") }
    Shortcut { sequence: "Alt+P"; onActivated: workspace.command("details") }
    Shortcut { sequence: "Ctrl+H"; onActivated: workspace.command("hidden") }
    Shortcut { sequence: "Ctrl+1"; onActivated: workspace.command("viewGrid") }
    Shortcut { sequence: "Ctrl+2"; onActivated: workspace.command("viewList") }
    Shortcut { sequences: ["Ctrl+=", "Ctrl++"]; onActivated: workspace.command("zoomIn") }
    Shortcut { sequence: "Ctrl+-"; onActivated: workspace.command("zoomOut") }
    Shortcut { sequence: "Ctrl+,"; onActivated: workspace.command("settings") }
    Shortcut { sequence: "Alt+Left"; onActivated: workspace.command("back") }
    Shortcut { sequence: "Alt+Right"; onActivated: workspace.command("forward") }
    Shortcut { sequence: "Alt+Up"; onActivated: workspace.command("up") }
    Shortcut { sequence: "Alt+Home"; onActivated: workspace.command("home") }
    Shortcut { sequence: "Ctrl+Alt+T"; onActivated: workspace.command("terminal") }
    // #endregion ───────────────────────────────────────────────────────────────────────────────
}
