import QtQuick
import Vados

// The universal panel (VAS components 11): translucent fill, one hairline, the squircle, a micro-label pinned top-left that names the box, an optional caption half-overhanging the bottom edge that explains it, and the hue ring that follows the pointer around the border.
Item {
    id: root

    property string label: ""
    property string caption: ""
    property color accent: Theme.accent
    // Lit from outside: a drag hovering over the box, or the pane that has focus.
    property bool isLit: false
    // The pane the keys go to, when there is more than one: its edge takes a share of the accent and nothing else changes.
    property bool isFocused: false
    property bool isFullTempo: false
    property real topPadding: Theme.rem * 2.75
    property real sidePadding: Theme.rem
    property real bottomPadding: Theme.rem
    property alias fillColor: surface.fillColor
    default property alias content: well.data
    readonly property alias well: well
    readonly property bool isHovered: hover.hovered

    // A module ships hidden; whatever brings its screen on brings it in (VAS module §6).
    opacity: 0

    // #region ── enter and leave ───────────────────────────────────────────────────────────────
    function enter(delay: int) {
        leaveAnimation.stop()
        enterAnimation.stop()
        enterAnimation.delay = delay
        enterAnimation.start()
        if (label.length > 0)
            labelReveal.reveal(delay + 100)
    }

    function leave() {
        enterAnimation.stop()
        leaveAnimation.start()
        labelReveal.leave()
    }

    function showNow() {
        enterAnimation.stop()
        leaveAnimation.stop()
        opacity = 1
        scale = 1
        labelReveal.showNow()
    }

    function relabel(text: string) {
        if (labelReveal.text === text.toUpperCase())
            return
        labelReveal.text = text.toUpperCase()
        if (opacity > 0)
            labelReveal.reveal(0)
    }

    SequentialAnimation {
        id: enterAnimation
        property int delay: 0
        ScriptAction { script: { root.opacity = 0; root.scale = Motion.isLite ? 1 : 0.92 } }
        PauseAnimation { duration: enterAnimation.delay }
        ParallelAnimation {
            NumberAnimation { target: root; property: "opacity"; to: 1; duration: root.isFullTempo ? Motion.launchPanelEnter : Motion.navigateEnter; easing.type: Motion.enter }
            NumberAnimation { target: root; property: "scale"; to: 1; duration: root.isFullTempo ? Motion.launchPanelEnter : Motion.navigateEnter; easing.type: Motion.enterProminent }
        }
    }

    // Leaves at once, faster, to 0.97 and not back to 0.92: a quieter version of the arrival, never the arrival reversed.
    ParallelAnimation {
        id: leaveAnimation
        NumberAnimation { target: root; property: "opacity"; to: 0; duration: Motion.navigateLeave; easing.type: Motion.leave }
        NumberAnimation { target: root; property: "scale"; to: 0.97; duration: Motion.navigateLeave; easing.type: Motion.leave }
    }
    // #endregion ───────────────────────────────────────────────────────────────────────────────

    Squircle {
        id: surface
        anchors.fill: parent
        fillColor: Theme.panel
        borderColor: root.isLit ? Theme.mix(root.accent, Theme.border, 0.5) : root.isHovered || root.isFocused ? Theme.mix(root.accent, Theme.border, 0.3) : Theme.border
        glowColor: root.accent
        glowOpacity: (root.isHovered && !Motion.isLite) || root.isLit ? 1 : 0
        glowPosition: root.isLit && !root.isHovered ? Qt.point(width / 2, height / 2) : hover.point.position
        glowRadius: root.isLit ? Math.max(width, height) : Theme.rem * 11

        Behavior on borderColor { ColorAnimation { duration: Motion.hover; easing.type: Motion.state } }
        Behavior on glowOpacity { NumberAnimation { duration: Motion.hover; easing.type: Motion.state } }
    }

    Item {
        id: well
        anchors.fill: parent
        anchors.topMargin: root.topPadding
        anchors.leftMargin: root.sidePadding
        anchors.rightMargin: root.sidePadding
        anchors.bottomMargin: root.bottomPadding
    }

    // The label names the box; it is a machine label, so it is uppercase, wide-spaced Mono in the label grey (VAS typography: the micro-label).
    Reveal {
        id: labelReveal
        x: Theme.rem
        y: Theme.rem * 0.78
        width: Math.min(implicitWidth, root.width - Theme.rem * 2)
        height: Theme.labelSize * 1.4
        text: root.label.toUpperCase()
        accent: root.accent
        isFullTempo: root.isFullTempo
        color: Theme.textLabel
        font.family: Theme.mono
        font.pixelSize: Theme.labelSize
        font.letterSpacing: Theme.labelSpacing
        font.weight: Font.Medium
    }

    // The caption half-overhangs the bottom edge; the ground behind it opens a gap in the hairline so the line does not run through the words.
    Rectangle {
        visible: root.caption.length > 0
        anchors.horizontalCenter: captionText.horizontalCenter
        y: captionText.y + captionText.height * 0.3
        width: captionText.implicitWidth + Theme.rem * 0.8
        height: captionText.height * 0.4
        color: Theme.ground
    }

    Text {
        id: captionText
        visible: root.caption.length > 0
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height - height * 0.45
        text: root.caption
        color: Theme.textFaint
        font.family: Theme.mono
        font.pixelSize: Theme.captionSize
        textFormat: Text.PlainText
    }

    HoverHandler {
        id: hover
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    }
}
