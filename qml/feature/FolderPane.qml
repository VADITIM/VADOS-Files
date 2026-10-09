import QtQuick
import QtQuick.Controls
import Vados

// One folder view: a module holding the grid or the list, its history, its selection, and the navigation choreography. A folder change is a menu transition at tool tempo — the outgoing contents leave at once while the next folder is read, and the incoming ones assemble diagonally once both are done.
FocusScope {
    id: pane

    required property var workspace
    property alias model: folderModel
    readonly property string path: folderModel.path
    property var backStack: []
    property var forwardStack: []
    property bool isActive: false
    property bool isEntering: false
    // Held while the window assembles: the first folder is read, but its contents wait for the launch choreography to call them in.
    property bool isHeld: false
    property bool isKeyboardFocused: false
    property string direction: "jump"
    property string renamingPath: ""
    property var carriedPaths: []
    property int pressedIndex: -1
    property int anchorIndex: -1
    property string targetPath: ""
    property bool isLeaveDone: true
    property var expectedSelection: []
    property string typeAhead: ""
    // Where each folder was scrolled to when it was left, so history lands back on the same screenful.
    property var scrollMemory: ({})
    property real restoreY: -1

    readonly property string viewMode: Settings.viewMode
    readonly property int zoom: Settings.zoomLevel
    readonly property real tileWidth: Theme.rem * [4.4, 5.8, 7.4, 9.6][zoom]
    readonly property real previewSize: tileWidth * 0.6
    readonly property int columns: Math.max(1, Math.floor(viewWidth / tileWidth))
    readonly property real cellWidth: viewWidth / columns
    // Room for the preview, two lines of name and (above the smallest zoom) the size line, so a wrapped name never runs into the next tile.
    readonly property real tileLabelSize: zoom === 0 ? Theme.smallSize * 1.05 : Theme.bodySize
    readonly property real cellHeight: Math.ceil(previewSize + Theme.rem * 1.6 + tileLabelSize * 1.1 * 1.3 * 2 + (zoom === 0 ? 0 : Theme.smallSize * 0.9 * 1.4 + Theme.rem * 0.12))
    readonly property real rowHeight: Theme.rem * [1.55, 1.85, 2.3, 2.9][zoom]
    readonly property real sizeColumnWidth: Theme.rem * 5.5
    readonly property real modifiedColumnWidth: Theme.rem * 7.5
    readonly property real kindColumnWidth: Theme.rem * 7
    readonly property real viewWidth: viewHost.width
    readonly property real viewHeight: viewHost.height
    readonly property real contentY: viewLoader.item ? viewLoader.item.contentY : 0
    readonly property var view: viewLoader.item
    readonly property alias frame: frame
    // Delegates carry a `pane` property, so inside them `pane` is their own; they are handed this instead.
    readonly property var paneItem: pane

    signal leaveRequested
    signal enterRequested
    signal cut(string path)

    // #region ── navigation ────────────────────────────────────────────────────────────────────
    function navigate(target: string, options: var) {
        options = options || {}
        target = System.expandPath(target)
        if (!System.exists(target)) {
            workspace.showError("path: " + target + " does not exist")
            return
        }
        if (target === path && folderModel.mode === "folder" && !options.isForced)
            return
        renamingPath = ""
        if (view && path.length > 0 && folderModel.mode === "folder")
            scrollMemory[path] = view.contentY - view.originY
        restoreY = options.isHistory && scrollMemory[target] !== undefined ? scrollMemory[target] : -1
        if (!options.isHistory && path.length > 0 && target !== path) {
            backStack = backStack.concat([path])
            forwardStack = []
        }
        direction = options.direction || (path.length > 0 && target.startsWith(path + "/") ? "into" : path.startsWith(target + "/") ? "out" : "jump")
        expectedSelection = options.selectPaths || (direction === "out" ? [childOnTheWay(target)] : [])
        targetPath = target
        isLeaveDone = false
        folderModel.load(target)
        const leaveDuration = options.isInitial ? 0 : workspace.beginRoomChange(pane, target)
        if (!options.isInitial) {
            leaveRequested()
            title.leave()
        }
        leaveTimer.interval = Math.max(1, leaveDuration)
        leaveTimer.restart()
        slowTimer.restart()
    }

    // Going up selects the folder you came out of, so the eye lands where it left.
    function childOnTheWay(target: string): string {
        if (!path.startsWith(target + "/") && !(target === "/" && path.length > 1))
            return ""
        const rest = path.substring(target === "/" ? 1 : target.length + 1)
        return (target === "/" ? "" : target) + "/" + rest.split("/")[0]
    }

    function tryCommit() {
        if (!isLeaveDone || folderModel.isLoading || folderModel.pendingPath !== targetPath)
            return
        isLeaveDone = false
        slowTimer.stop()
        isSlow = false
        isEntering = !isHeld
        folderModel.commit()
        if (view)
            view.contentY = view.originY
        if (restoreY >= 0)
            restoreTimer.restart()
        cut(folderModel.path)
        title.text = workspace.titleFor(folderModel.path)
        if (!isHeld)
            title.reveal(40)
        applyExpectedSelection()
        enteringTimer.restart()
    }

    Timer {
        id: restoreTimer
        interval: 1
        onTriggered: {
            if (!pane.view || pane.restoreY < 0)
                return
            const limit = Math.max(0, pane.view.contentHeight - pane.view.height)
            pane.view.contentY = pane.view.originY + Math.min(pane.restoreY, limit)
            pane.restoreY = -1
        }
    }

    function release(delay: int) {
        isHeld = false
        title.reveal(delay + 120)
        releaseTimer.interval = Math.max(1, delay)
        releaseTimer.restart()
    }

    function replayEnter() {
        isEntering = true
        enterRequested()
        enteringTimer.restart()
    }

    function reflow(change) {
        leaveRequested()
        reflowTimer.change = change
        reflowTimer.restart()
    }

    function goBack() {
        if (backStack.length === 0)
            return
        const previous = backStack[backStack.length - 1]
        backStack = backStack.slice(0, -1)
        forwardStack = forwardStack.concat([path])
        navigate(previous, { isHistory: true })
    }

    function goForward() {
        if (forwardStack.length === 0)
            return
        const next = forwardStack[forwardStack.length - 1]
        forwardStack = forwardStack.slice(0, -1)
        backStack = backStack.concat([path])
        navigate(next, { isHistory: true })
    }

    function goUp() {
        if (folderModel.mode === "search") {
            closeSearch()
            return
        }
        const parent = System.parentOf(path)
        if (parent.length > 0)
            navigate(parent, { direction: "out" })
    }

    // Wheel steps glide rather than jump; a touchpad's pixel deltas are already continuous and are applied as they come.
    function scrollBy(delta: real, isAnimated: bool) {
        if (!view)
            return
        const limit = Math.max(view.originY, view.contentHeight + view.originY - view.height)
        const start = scrollAnimation.running ? scrollAnimation.to : view.contentY
        const target = Math.max(view.originY, Math.min(limit, start + delta))
        scrollAnimation.stop()
        if (!isAnimated || Motion.isReduced) {
            view.contentY = target
            return
        }
        scrollAnimation.target = view
        scrollAnimation.to = target
        scrollAnimation.start()
    }

    function refresh() {
        folderModel.refresh()
    }

    function search(query: string) {
        if (query.trim().length === 0)
            return
        leaveRequested()
        title.leave()
        searchTimer.query = query
        searchTimer.restart()
    }

    function closeSearch() {
        if (folderModel.mode !== "search")
            return
        folderModel.cancelSearch()
        navigate(path, { isHistory: true, isForced: true, direction: "jump" })
    }

    function expectSelection(paths: var) {
        expectedSelection = paths
        applyExpectedSelection()
        expectationTimer.restart()
    }

    function applyExpectedSelection() {
        if (expectedSelection.length === 0)
            return
        const found = expectedSelection.filter(candidate => folderModel.indexOfPath(candidate) !== -1)
        if (found.length === 0)
            return
        folderModel.selectPaths(found)
        anchorIndex = folderModel.currentIndex
        ensureVisible(folderModel.currentIndex)
        if (found.length === expectedSelection.length)
            expectedSelection = []
    }
    // #endregion ───────────────────────────────────────────────────────────────────────────────

    // #region ── activation and selection ──────────────────────────────────────────────────────
    function activate(index: int) {
        const entry = folderModel.get(index)
        if (!entry.path)
            return
        if (entry.isDirectory)
            navigate(entry.path, { direction: folderModel.mode === "search" ? "jump" : "into" })
        else if (Picker.isActive)
            workspace.pickFile(entry.path)
        else if (folderModel.mode !== "trash")
            System.open(entry.path)
    }

    function activateSelection() {
        const paths = folderModel.selectedPaths()
        if (paths.length === 1 || (paths.length === 0 && folderModel.currentIndex >= 0)) {
            activate(paths.length === 1 ? folderModel.indexOfPath(paths[0]) : folderModel.currentIndex)
            return
        }
        if (Picker.isActive) {
            workspace.pick()
            return
        }
        for (const target of paths)
            if (!System.isDirectory(target))
                System.open(target)
    }

    function ensureVisible(index: int) {
        if (view && index >= 0)
            view.positionViewAtIndex(index, viewMode === "grid" ? GridView.Contain : ListView.Contain)
    }

    function moveCurrent(step: int, isExtending: bool, isMovingOnly: bool) {
        const count = folderModel.count
        if (count === 0)
            return
        const current = folderModel.currentIndex
        const next = Math.max(0, Math.min(count - 1, current < 0 ? 0 : current + step))
        isKeyboardFocused = true
        if (isExtending) {
            if (anchorIndex < 0)
                anchorIndex = Math.max(0, current)
            folderModel.selectRange(anchorIndex, next, false)
        } else if (isMovingOnly) {
            folderModel.currentIndex = next
        } else {
            folderModel.select(next)
            anchorIndex = next
        }
        ensureVisible(next)
    }

    function indexAtPoint(x: real, y: real): int {
        if (!view)
            return -1
        const item = view.itemAt(x + view.contentX, y + view.contentY)
        if (!item || item.index === undefined)
            return -1
        const local = item.mapFromItem(viewHost, x, y)
        return item.hitTest(local.x, local.y) ? item.index : -1
    }

    function itemForIndex(index: int): var {
        return view ? view.itemAtIndex(index) : null
    }

    function rowsInBand(left: real, top: real, right: real, bottom: real): var {
        const rows = []
        const count = folderModel.count
        if (viewMode === "grid") {
            const firstRow = Math.max(0, Math.floor(top / cellHeight))
            const lastRow = Math.floor(bottom / cellHeight)
            const firstColumn = Math.max(0, Math.floor(left / cellWidth))
            const lastColumn = Math.min(columns - 1, Math.floor(right / cellWidth))
            for (let row = firstRow; row <= lastRow; ++row)
                for (let column = firstColumn; column <= lastColumn; ++column) {
                    const index = row * columns + column
                    if (index < count)
                        rows.push(index)
                }
        } else {
            const first = Math.max(0, Math.floor(top / rowHeight))
            const last = Math.min(count - 1, Math.floor(bottom / rowHeight))
            for (let index = first; index <= last; ++index)
                rows.push(index)
        }
        return rows
    }
    // #endregion ───────────────────────────────────────────────────────────────────────────────

    // #region ── drag out ──────────────────────────────────────────────────────────────────────
    function startDrag(isRight: bool) {
        const paths = folderModel.selectedPaths()
        if (paths.length === 0)
            return
        carriedPaths = paths
        workspace.beginCarry(pane, paths, isRight)
        let action = Qt.IgnoreAction
        // The carried state is handed back however the drag ends, or the tiles stay dimmed as if still in the air.
        try {
            action = System.startDrag(paths, dragStack.image, dragStack.hotSpot.x, dragStack.hotSpot.y)
        } finally {
            carriedPaths = []
            workspace.endCarry(pane, action)
        }
    }
    // #endregion ───────────────────────────────────────────────────────────────────────────────

    FolderModel {
        id: folderModel
        showHidden: Settings.showHidden
        foldersFirst: Settings.foldersFirst
        sortKey: Settings.sortKey
        sortDescending: Settings.sortDescending
        cutPaths: System.isClipboardCut ? System.clipboardPaths : []
        nameFilters: pane.workspace.pickerPatterns
        isFoldersOnly: Picker.mode === "folder" && Picker.isActive
        onLoaded: pane.tryCommit()
        onCountChanged: if (pane.expectedSelection.length > 0) pane.applyExpectedSelection()
        onPathLost: lostPath => {
            let parent = System.parentOf(lostPath)
            while (parent.length > 0 && !System.exists(parent))
                parent = System.parentOf(parent)
            pane.navigate(parent.length > 0 ? parent : System.homePath, { direction: "out" })
        }
    }

    NumberAnimation {
        id: scrollAnimation
        property: "contentY"
        duration: 220
        easing.type: Easing.OutCubic
    }

    Timer {
        id: leaveTimer
        onTriggered: {
            pane.isLeaveDone = true
            pane.tryCommit()
        }
    }

    Timer {
        id: enteringTimer
        interval: Motion.navigateEnter + Motion.navigateStaggerVertical + 120
        onTriggered: pane.isEntering = false
    }

    Timer {
        id: releaseTimer
        onTriggered: pane.replayEnter()
    }

    Timer {
        id: reflowTimer
        property var change
        interval: Motion.navigateLeave
        onTriggered: {
            pane.isEntering = true
            if (change)
                change()
            change = null
            pane.replayEnter()
        }
    }

    Timer {
        id: searchTimer
        property string query: ""
        interval: Motion.navigateLeave
        onTriggered: {
            pane.isEntering = true
            folderModel.search(query)
            title.text = "“" + query + "”"
            title.reveal(40)
            enteringTimer.restart()
        }
    }

    // A slow read gets a skeleton rather than a blank pane; a fast one never shows it.
    property bool isSlow: false
    Timer {
        id: slowTimer
        interval: 260
        onTriggered: pane.isSlow = folderModel.isLoading
    }

    Timer {
        id: expectationTimer
        interval: 1500
        onTriggered: pane.expectedSelection = []
    }

    Timer {
        id: typeAheadTimer
        interval: 900
        onTriggered: pane.typeAhead = ""
    }

    Module {
        id: frame
        anchors.fill: parent
        isLit: paneDrop.containsDrag && paneDrop.isAccepting
        isFocused: pane.isActive && Settings.isSplit
        accent: Theme.accent
        topPadding: Theme.rem * 0.7
        sidePadding: Theme.rem * 0.6
        bottomPadding: Theme.rem * 0.9
        caption: workspace.captionFor(pane)

        Item {
            id: header
            width: parent.width
            height: Theme.rem * 2.3

            Reveal {
                id: title
                x: Theme.rem * 0.4
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth + Theme.rem, sortRow.x - Theme.rem - x)
                height: Theme.rem * 2
                font.family: Theme.display
                font.pixelSize: Theme.rem * 1.35
                font.letterSpacing: Theme.rem * 0.04
                color: Theme.textBright
            }

            Row {
                id: sortRow
                anchors.right: parent.right
                anchors.rightMargin: Theme.rem * 0.4
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.rem * 0.2

                Repeater {
                    model: [{ key: "name", text: "Name" }, { key: "size", text: "Size" }, { key: "modified", text: "Date" }, { key: "kind", text: "Kind" }]

                    delegate: Item {
                        id: sortChip
                        required property var modelData
                        readonly property bool isCurrent: Settings.sortKey === modelData.key
                        width: chipText.implicitWidth + Theme.rem * 0.9
                        height: Theme.rem * 1.4

                        Squircle {
                            anchors.fill: parent
                            radius: Theme.squircleSmall
                            fillColor: chipMouse.containsMouse ? Theme.sunken : Theme.alpha(Theme.sunken, 0)
                            borderColor: Theme.alpha(Theme.border, chipMouse.containsMouse ? 1 : 0)
                            insetWidth: sortChip.isCurrent ? 1 : 0
                            insetColor: Theme.alpha(Theme.accent, 0.6)
                        }

                        Text {
                            id: chipText
                            anchors.centerIn: parent
                            text: sortChip.modelData.text.toUpperCase() + (sortChip.isCurrent ? (Settings.sortDescending ? " ↓" : " ↑") : "")
                            color: sortChip.isCurrent ? Theme.accentInk : chipMouse.containsMouse ? Theme.textBody : Theme.textLabel
                            font.family: Theme.mono
                            font.pixelSize: Theme.labelSize * 0.95
                            font.letterSpacing: Theme.labelSpacing * 0.5
                        }

                        MouseArea {
                            id: chipMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: workspace.command(sortChip.isCurrent ? "sortReverse" : "sort", sortChip.modelData.key)
                        }
                    }
                }
            }
        }

        Rectangle {
            id: divider
            anchors.top: header.bottom
            anchors.topMargin: Theme.rem * 0.2
            x: parent.width * 0.02
            width: parent.width * 0.45
            height: 1
            color: Theme.border
        }

        Item {
            id: viewHost
            anchors.top: divider.bottom
            anchors.topMargin: Theme.rem * 0.35
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            clip: true

            DropArea {
                id: paneDrop
                anchors.fill: parent
                property bool isAccepting: false
                onEntered: event => {
                    isAccepting = folderModel.mode === "folder" && pane.workspace.acceptDrag(event, pane.path, null, paneDrop)
                }
                onPositionChanged: event => {
                    if (isAccepting)
                        pane.workspace.updateDrag(event, pane.path, null, paneDrop)
                    edgeScroller.pointerY = event.y
                }
                onExited: {
                    isAccepting = false
                    edgeScroller.pointerY = -1
                    pane.workspace.leaveDrag(null)
                }
                onDropped: event => {
                    isAccepting = false
                    edgeScroller.pointerY = -1
                    pane.workspace.dropOnto(event, pane.path, null, paneDrop)
                }
            }

            Loader {
                id: viewLoader
                anchors.fill: parent
                sourceComponent: pane.viewMode === "list" ? listComponent : gridComponent
            }

            Rectangle {
                id: band
                visible: pointer.isBanding && width > 2 && height > 2
                color: Theme.alpha(Theme.accent, 0.07)
                border.color: Theme.alpha(Theme.accent, 0.6)
                border.width: 1
                radius: Theme.rem * 0.2
            }

            Column {
                anchors.centerIn: parent
                spacing: Theme.rem * 0.5
                visible: opacity > 0
                opacity: folderModel.count === 0 && !folderModel.isLoading && !pane.isLeaving && !folderModel.isSearching ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Motion.navigateEnter } }

                Glyph {
                    id: emptyGlyph
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Theme.rem * 3
                    height: width
                    name: folderModel.error.length > 0 ? "close" : folderModel.mode === "trash" ? "trash" : folderModel.mode === "search" ? "search" : "folder"
                    ink: Theme.textFaint
                    // Life: the empty state is waiting for something, so it breathes; paused whenever it is not on screen.
                    SequentialAnimation on y {
                        running: emptyGlyph.parent.visible && !Motion.isLite && pane.visible
                        loops: Animation.Infinite
                        NumberAnimation { from: 0; to: -Theme.rem * 0.35; duration: Motion.idleDrift / 2; easing.type: Motion.idle }
                        NumberAnimation { from: -Theme.rem * 0.35; to: 0; duration: Motion.idleDrift / 2; easing.type: Motion.idle }
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: folderModel.error.length > 0 ? "NO ACCESS" : folderModel.mode === "trash" ? "TRASH IS EMPTY" : folderModel.mode === "search" ? "NOTHING FOUND" : folderModel.filter.length > 0 ? "NO MATCH" : "EMPTY"
                    color: Theme.textLabel
                    font.family: Theme.mono
                    font.pixelSize: Theme.labelSize
                    font.letterSpacing: Theme.labelSpacing
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: folderModel.error.length > 0 ? folderModel.error : folderModel.mode === "search" ? "Nothing under this folder has that in its name." : folderModel.filter.length > 0 ? "Nothing here has that in its name." : "Drop files here, or paste."
                    color: Theme.textFaint
                    font.family: Theme.mono
                    font.pixelSize: Theme.captionSize
                }
            }

            Grid {
                id: skeleton
                visible: opacity > 0
                opacity: pane.isSlow && folderModel.isLoading ? 1 : 0
                columns: pane.columns
                Behavior on opacity { NumberAnimation { duration: 160 } }
                Repeater {
                    model: skeleton.visible ? Math.min(24, pane.columns * 3) : 0
                    delegate: Item {
                        required property int index
                        width: pane.cellWidth
                        height: pane.cellHeight
                        Squircle {
                            id: bone
                            anchors.centerIn: parent
                            width: pane.previewSize
                            height: pane.previewSize
                            fillColor: Theme.sunken
                            borderColor: Theme.border
                            SequentialAnimation on opacity {
                                running: skeleton.visible
                                loops: Animation.Infinite
                                PauseAnimation { duration: (index * 137) % 600 }
                                NumberAnimation { from: 0.35; to: 0.8; duration: 700; easing.type: Motion.idle }
                                NumberAnimation { from: 0.8; to: 0.35; duration: 700; easing.type: Motion.idle }
                            }
                        }
                    }
                }
            }

            MouseArea {
                id: pointer
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton | Qt.BackButton | Qt.ForwardButton
                property int pressIndex: -1
                property point pressPoint
                property point bandOrigin
                property bool isBanding: false
                property bool isDragArmed: false
                property bool isRightArmed: false
                property bool shouldSelectOnRelease: false
                property var bandBase: []
                property point lastPoint

                function contentPoint(x: real, y: real): point {
                    return Qt.point(x + (pane.view ? pane.view.contentX : 0), y + (pane.view ? pane.view.contentY - pane.view.originY : 0))
                }

                function updateBand() {
                    const current = contentPoint(lastPoint.x, lastPoint.y)
                    const left = Math.min(bandOrigin.x, current.x)
                    const top = Math.min(bandOrigin.y, current.y)
                    const right = Math.max(bandOrigin.x, current.x)
                    const bottom = Math.max(bandOrigin.y, current.y)
                    const offsetY = pane.view ? pane.view.contentY - pane.view.originY : 0
                    band.x = left - (pane.view ? pane.view.contentX : 0)
                    band.y = top - offsetY
                    band.width = right - left
                    band.height = bottom - top
                    folderModel.selectRows(pane.rowsInBand(left, top, right, bottom), bandBase)
                }

                onPressed: event => {
                    pane.forceActiveFocus()
                    pane.workspace.setActivePane(pane)
                    pane.isKeyboardFocused = false
                    pane.renamingPath = ""
                    if (event.button === Qt.BackButton) { pane.goBack(); return }
                    if (event.button === Qt.ForwardButton) { pane.goForward(); return }
                    const index = pane.indexAtPoint(event.x, event.y)
                    const isControl = event.modifiers & Qt.ControlModifier
                    const isShift = event.modifiers & Qt.ShiftModifier
                    pressIndex = index
                    pressPoint = Qt.point(event.x, event.y)
                    lastPoint = pressPoint
                    if (event.button === Qt.RightButton) {
                        if (index >= 0 && !folderModel.isSelected(index))
                            folderModel.select(index)
                        else if (index < 0)
                            folderModel.clearSelection()
                        // The menu opens on release, as on Windows, so the same press can become a right-button drag instead.
                        isRightArmed = true
                        isDragArmed = index >= 0
                        if (isDragArmed)
                            dragStack.prepare(folderModel.selectedPaths(), pane.itemForIndex(index))
                        return
                    }
                    if (event.button === Qt.MiddleButton) {
                        const entry = folderModel.get(index)
                        if (entry.isDirectory)
                            pane.workspace.openTab(entry.path)
                        return
                    }
                    if (index < 0) {
                        if (!isControl && !isShift)
                            folderModel.clearSelection()
                        bandBase = isControl || isShift ? folderModel.selectedPaths() : []
                        bandOrigin = contentPoint(event.x, event.y)
                        isBanding = true
                        updateBand()
                        return
                    }
                    pane.pressedIndex = index
                    if (isShift) {
                        folderModel.selectRange(pane.anchorIndex < 0 ? index : pane.anchorIndex, index, isControl)
                        return
                    }
                    if (isControl) {
                        folderModel.toggle(index)
                        pane.anchorIndex = index
                    } else if (folderModel.isSelected(index)) {
                        shouldSelectOnRelease = true
                    } else {
                        folderModel.select(index)
                        pane.anchorIndex = index
                    }
                    isDragArmed = folderModel.isSelected(index)
                    if (isDragArmed)
                        dragStack.prepare(folderModel.selectedPaths(), pane.itemForIndex(index))
                }

                onPositionChanged: event => {
                    lastPoint = Qt.point(event.x, event.y)
                    if (isBanding) {
                        updateBand()
                        edgeScroller.pointerY = event.y
                        return
                    }
                    const distance = Math.hypot(event.x - pressPoint.x, event.y - pressPoint.y)
                    if (isDragArmed && distance > Theme.rem * 0.35) {
                        isDragArmed = false
                        shouldSelectOnRelease = false
                        pane.pressedIndex = -1
                        const isRight = isRightArmed
                        isRightArmed = false
                        pane.startDrag(isRight)
                    }
                }

                onReleased: event => {
                    if (isRightArmed && event.button === Qt.RightButton) {
                        isRightArmed = false
                        isDragArmed = false
                        pane.workspace.openContextMenu(pane, mapToItem(pane.workspace, event.x, event.y), pressIndex >= 0)
                        return
                    }
                    if (shouldSelectOnRelease && pressIndex >= 0) {
                        folderModel.select(pressIndex)
                        pane.anchorIndex = pressIndex
                    }
                    isBanding = false
                    isDragArmed = false
                    shouldSelectOnRelease = false
                    pane.pressedIndex = -1
                    edgeScroller.pointerY = -1
                }

                onCanceled: {
                    isRightArmed = false
                    isBanding = false
                    isDragArmed = false
                    shouldSelectOnRelease = false
                    pane.pressedIndex = -1
                    edgeScroller.pointerY = -1
                }

                onDoubleClicked: event => {
                    if (event.button !== Qt.LeftButton || event.modifiers & (Qt.ControlModifier | Qt.ShiftModifier))
                        return
                    const index = pane.indexAtPoint(event.x, event.y)
                    if (index >= 0)
                        pane.activate(index)
                }

                onWheel: event => {
                    if (event.modifiers & Qt.ControlModifier) {
                        pane.workspace.command(event.angleDelta.y > 0 ? "zoomIn" : "zoomOut")
                        return
                    }
                    // A wheel notch (angleDelta in steps of 120) moves three list rows or one grid row, as on Windows. Wayland also hands a wheel a small
                    // pixelDelta, so only a delta that is not whole notches is read as a touchpad's own pixels.
                    const notch = pane.viewMode === "list" ? pane.rowHeight * 3 : pane.cellHeight
                    if (event.angleDelta.y !== 0 && event.angleDelta.y % 120 === 0)
                        pane.scrollBy(-event.angleDelta.y / 120 * notch, true)
                    else if (event.pixelDelta.y !== 0)
                        pane.scrollBy(-event.pixelDelta.y * 1.5, false)
                    else
                        pane.scrollBy(-event.angleDelta.y / 120 * notch, true)
                    if (isBanding)
                        updateBand()
                }
            }

            // Scrolls the view while a band or a drag sits near its top or bottom edge, faster the closer it gets.
            Timer {
                id: edgeScroller
                property real pointerY: -1
                readonly property real zone: Theme.rem * 2.2
                interval: 16
                repeat: true
                running: pointerY >= 0 && pane.view && (pointerY < zone || pointerY > viewHost.height - zone)
                onTriggered: {
                    const view = pane.view
                    const speed = pointerY < zone ? -(zone - pointerY) : (pointerY - (viewHost.height - zone))
                    const limit = Math.max(view.originY, view.contentHeight + view.originY - view.height)
                    view.contentY = Math.max(view.originY, Math.min(limit, view.contentY + speed * 0.5))
                    if (pointer.isBanding)
                        pointer.updateBand()
                }
            }
        }
    }

    readonly property bool isLeaving: !isLeaveDone

    DragStack {
        id: dragStack
        x: -100000
        y: 0
        pane: paneItem
    }

    Component {
        id: gridComponent

        GridView {
            id: grid
            model: folderModel
            cellWidth: pane.cellWidth
            cellHeight: pane.cellHeight
            boundsBehavior: Flickable.StopAtBounds
            cacheBuffer: pane.cellHeight * 2
            interactive: false
            reuseItems: false
            currentIndex: -1
            ScrollBar.vertical: ThinScrollBar {}
            delegate: FileTile { pane: paneItem }

            add: Transition {
                enabled: !pane.isEntering
                NumberAnimation { property: "scale"; from: 0.2; to: 1; duration: Motion.stateChange; easing.type: Motion.enterProminent }
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Motion.stateChange * 0.6 }
            }
            remove: Transition {
                NumberAnimation { property: "scale"; to: 0; duration: 200; easing.type: Motion.leaveLarge }
                NumberAnimation { property: "opacity"; to: 0; duration: 200; easing.type: Motion.leave }
            }
            displaced: Transition {
                NumberAnimation { properties: "x,y"; duration: Motion.stateChange + 40; easing.type: Motion.state }
                NumberAnimation { property: "scale"; to: 1; duration: Motion.stateChange }
                NumberAnimation { property: "opacity"; to: 1; duration: Motion.stateChange }
            }

        }
    }

    Component {
        id: listComponent

        ListView {
            id: list
            model: folderModel
            boundsBehavior: Flickable.StopAtBounds
            cacheBuffer: pane.rowHeight * 10
            interactive: false
            reuseItems: false
            currentIndex: -1
            ScrollBar.vertical: ThinScrollBar {}
            delegate: FileRow { pane: paneItem }

            add: Transition {
                enabled: !pane.isEntering
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Motion.stateChange }
                NumberAnimation { property: "scale"; from: 0.6; to: 1; duration: Motion.stateChange; easing.type: Motion.enterProminent }
            }
            remove: Transition {
                NumberAnimation { property: "opacity"; to: 0; duration: 160; easing.type: Motion.leave }
                NumberAnimation { property: "scale"; to: 0.6; duration: 160; easing.type: Motion.leave }
            }
            displaced: Transition {
                NumberAnimation { property: "y"; duration: Motion.stateChange; easing.type: Motion.state }
                NumberAnimation { property: "scale"; to: 1; duration: Motion.stateChange }
                NumberAnimation { property: "opacity"; to: 1; duration: Motion.stateChange }
            }

        }
    }

    // #region ── keys ──────────────────────────────────────────────────────────────────────────
    Keys.onPressed: event => {
        const isControl = event.modifiers & Qt.ControlModifier
        const isShift = event.modifiers & Qt.ShiftModifier
        const isAlt = event.modifiers & Qt.AltModifier
        const step = viewMode === "grid" ? columns : 1
        const pageRows = Math.max(1, Math.floor(viewHeight / (viewMode === "grid" ? cellHeight : rowHeight)))
        switch (event.key) {
        case Qt.Key_Left:
            if (isAlt) { goBack(); break }
            if (viewMode === "grid") moveCurrent(-1, isShift, isControl)
            break
        case Qt.Key_Right:
            if (isAlt) { goForward(); break }
            if (viewMode === "grid") moveCurrent(1, isShift, isControl)
            break
        case Qt.Key_Up:
            if (isAlt) { goUp(); break }
            moveCurrent(-step, isShift, isControl)
            break
        case Qt.Key_Down:
            if (isAlt) { activateSelection(); break }
            moveCurrent(step, isShift, isControl)
            break
        case Qt.Key_PageUp: moveCurrent(-step * pageRows, isShift, isControl); break
        case Qt.Key_PageDown: moveCurrent(step * pageRows, isShift, isControl); break
        case Qt.Key_Home: moveCurrent(-folderModel.count, isShift, isControl); break
        case Qt.Key_End: moveCurrent(folderModel.count, isShift, isControl); break
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (isAlt) workspace.command("details")
            else activateSelection()
            break
        case Qt.Key_Backspace: goUp(); break
        case Qt.Key_Space:
            if (isControl && folderModel.currentIndex >= 0) folderModel.toggle(folderModel.currentIndex)
            else workspace.command("quickLook")
            break
        case Qt.Key_F2: workspace.command("rename"); break
        case Qt.Key_F5: refresh(); break
        case Qt.Key_Delete: workspace.command(isShift ? "deletePermanently" : "trash"); break
        case Qt.Key_Menu: workspace.command("contextMenu"); break
        case Qt.Key_Escape:
            if (folderModel.mode === "search") closeSearch()
            else if (folderModel.filter.length > 0) folderModel.filter = ""
            else folderModel.clearSelection()
            break
        default:
            if (isControl) {
                const commands = { [Qt.Key_A]: "selectAll", [Qt.Key_C]: "copy", [Qt.Key_X]: "cut", [Qt.Key_V]: "paste", [Qt.Key_D]: "duplicate", [Qt.Key_Z]: "undo", [Qt.Key_I]: "invertSelection" }
                if (isShift && event.key === Qt.Key_N) { workspace.command("newFolder"); break }
                if (isShift && event.key === Qt.Key_C) { workspace.command("copyPath"); break }
                if (commands[event.key] !== undefined) { workspace.command(commands[event.key]); break }
                event.accepted = false
                return
            }
            // Type-ahead jumps to the first name starting with what was typed, the way Explorer does; Ctrl+F filters instead.
            if (event.text.length === 1 && event.text.trim().length === 1 && !isAlt) {
                typeAhead += event.text
                typeAheadTimer.restart()
                const index = folderModel.indexOfPrefix(typeAhead, typeAhead.length === 1 ? folderModel.currentIndex + 1 : folderModel.currentIndex)
                if (index >= 0) {
                    folderModel.select(index)
                    anchorIndex = index
                    isKeyboardFocused = true
                    ensureVisible(index)
                }
                break
            }
            event.accepted = false
            return
        }
        event.accepted = true
    }
    // #endregion ───────────────────────────────────────────────────────────────────────────────
}
