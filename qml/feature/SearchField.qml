import QtQuick
import Vados

// Typing filters the folder as you type; Enter searches everything beneath it. Escape gives the folder back.
Item {
    id: root

    property var workspace
    readonly property var pane: workspace ? workspace.activePane : null
    readonly property bool isExpanded: input.activeFocus || input.text.length > 0 || holdTimer.running

    function focusField() {
        holdTimer.restart()
        input.forceActiveFocus()
        input.selectAll()
    }

    onPaneChanged: if (pane) input.text = pane.model.filter

    Connections {
        target: root.pane ? root.pane.model : null
        function onFilterChanged() {
            if (input.text !== root.pane.model.filter && root.pane.model.mode !== "search")
                input.text = root.pane.model.filter
        }
    }

    // Bridges the moment between the click and the field taking focus, so the field does not fold before it has opened.
    Timer {
        id: holdTimer
        interval: 200
    }

    Squircle {
        anchors.fill: parent
        radius: Theme.squircleSmall
        fillColor: Theme.sunkenDeep
        borderColor: input.activeFocus ? Theme.mix(Theme.accent, Theme.border, 0.55) : mouse.containsMouse ? Theme.borderHover : Theme.borderStrong
        Behavior on borderColor { ColorAnimation { duration: Motion.hover } }
    }

    Glyph {
        id: icon
        x: root.isExpanded ? Theme.rem * 0.55 : (root.width - width) / 2
        Behavior on x { NumberAnimation { duration: Motion.stateChange; easing.type: Motion.enterProminent } }
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.rem * 0.85
        height: width
        name: "search"
        ink: input.activeFocus || input.text.length > 0 ? Theme.accentInk : Theme.textIcon
    }

    Text {
        anchors.left: icon.right
        anchors.leftMargin: Theme.rem * 0.45
        anchors.verticalCenter: parent.verticalCenter
        visible: input.text.length === 0 && root.isExpanded
        width: parent.width - x - Theme.rem * 0.4
        clip: true
        text: "FILTER"
        color: Theme.textFaint
        font.family: Theme.mono
        font.pixelSize: Theme.labelSize
        font.letterSpacing: Theme.labelSpacing * 0.6
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.isExpanded ? Qt.IBeamCursor : Qt.PointingHandCursor
        onClicked: root.focusField()
    }

    TextInput {
        id: input
        anchors.left: icon.right
        anchors.leftMargin: Theme.rem * 0.45
        anchors.right: clearButton.left
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.textBright
        selectionColor: Theme.alpha(Theme.accent, 0.35)
        selectedTextColor: Theme.textBright
        font.family: Theme.mono
        font.pixelSize: Theme.bodySize
        clip: true
        selectByMouse: true
        onTextEdited: if (root.pane && root.pane.model.mode !== "search") root.pane.model.filter = text
        Keys.onReturnPressed: root.pane.search(text)
        Keys.onEnterPressed: root.pane.search(text)
        Keys.onEscapePressed: {
            text = ""
            if (root.pane) {
                root.pane.closeSearch()
                root.pane.model.filter = ""
                root.pane.forceActiveFocus()
            }
        }
        Keys.onDownPressed: if (root.pane) root.pane.forceActiveFocus()
    }

    IconButton {
        id: clearButton
        anchors.right: parent.right
        anchors.rightMargin: Theme.rem * 0.25
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.rem * 1.35
        height: width
        glyphSize: Theme.rem * 0.6
        glyph: "close"
        visible: input.text.length > 0
        onClicked: {
            input.text = ""
            if (root.pane) {
                root.pane.closeSearch()
                root.pane.model.filter = ""
                root.pane.forceActiveFocus()
            }
        }
    }
}
