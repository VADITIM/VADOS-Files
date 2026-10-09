import QtQuick
import QtQuick.Effects
import Vados

// The bar-sweep reveal, the default arrival for text (VAS components 08): an accent bar grows across the text, the text is unclipped underneath the opaque bar, and the bar retracts off the far edge. The text is never seen fading in.
Item {
    id: root

    property alias text: label.text
    property alias font: label.font
    property alias color: label.color
    property alias horizontalAlignment: label.horizontalAlignment
    property color accent: Theme.accent
    // A tool runs the sweep at the navigation tempo; the launch runs it at the portfolio's.
    property bool isFullTempo: false
    property bool isRevealed: false
    readonly property alias contentWidth: label.contentWidth
    readonly property int growDuration: isFullTempo ? Motion.revealGrow : Motion.navigateRevealGrow
    readonly property int retractDuration: isFullTempo ? Motion.revealRetract : Motion.navigateRevealRetract

    implicitWidth: label.implicitWidth
    implicitHeight: label.implicitHeight

    // #region ── enter and leave ───────────────────────────────────────────────────────────────
    function reveal(delay: int) {
        leaveAnimation.stop()
        sweep.stop()
        liteEnter.stop()
        if (Motion.isLite) {
            clipper.width = Qt.binding(() => root.width)
            liteEnter.delay = delay
            liteEnter.start()
            return
        }
        sweep.delay = delay
        sweep.start()
    }

    function leave() {
        sweep.stop()
        liteEnter.stop()
        bar.opacity = 0
        isRevealed = false
        leaveAnimation.start()
    }

    function hideNow() {
        sweep.stop()
        liteEnter.stop()
        leaveAnimation.stop()
        bar.opacity = 0
        clipper.width = 0
        isRevealed = false
    }

    function showNow() {
        sweep.stop()
        liteEnter.stop()
        leaveAnimation.stop()
        bar.opacity = 0
        label.opacity = 1
        label.y = 0
        clipper.width = Qt.binding(() => root.width)
        isRevealed = true
    }
    // #endregion ───────────────────────────────────────────────────────────────────────────────

    Item {
        id: clipper
        width: 0
        height: parent.height
        clip: true

        Text {
            id: label
            width: root.width
            height: root.height
            verticalAlignment: Text.AlignVCenter
            font.family: Theme.mono
            color: Theme.textBody
            textFormat: Text.PlainText
            elide: Text.ElideNone
        }
    }

    Rectangle {
        id: bar
        y: -root.height * 0.06
        height: root.height * 1.12
        width: Math.min(label.contentWidth, root.width)
        x: label.horizontalAlignment === Text.AlignRight ? root.width - width : 0
        color: root.accent
        opacity: 0
        transform: Scale {
            id: barScale
            xScale: 0
        }
        // The bloom past the bar's edges is what makes the sweep read as light rather than as a rectangle; it only exists while the bar is moving.
        layer.enabled: sweep.running && !Motion.isLite
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: root.accent
            shadowBlur: 0.8
            shadowHorizontalOffset: 0
            shadowVerticalOffset: 0
            shadowOpacity: 0.9
        }
    }

    SequentialAnimation {
        id: sweep
        property int delay: 0
        ScriptAction {
            script: {
                clipper.width = 0
                label.opacity = 1
                label.y = 0
                barScale.origin.x = 0
                barScale.xScale = 0
                bar.opacity = 1
            }
        }
        PauseAnimation { duration: sweep.delay }
        NumberAnimation { target: barScale; property: "xScale"; from: 0; to: 1; duration: root.growDuration; easing.type: Motion.sweep }
        // The clip and the origin flip land in the frame the bar is full, under it, so the text can never be caught mid-reveal.
        ScriptAction {
            script: {
                clipper.width = Qt.binding(() => root.width)
                barScale.origin.x = bar.width
                root.isRevealed = true
            }
        }
        NumberAnimation { target: barScale; property: "xScale"; to: 0; duration: root.retractDuration; easing.type: Motion.sweep }
        ScriptAction { script: bar.opacity = 0 }
    }

    SequentialAnimation {
        id: liteEnter
        property int delay: 0
        ScriptAction { script: { label.opacity = 0; label.y = 18; root.isRevealed = true } }
        PauseAnimation { duration: liteEnter.delay }
        ParallelAnimation {
            NumberAnimation { target: label; property: "opacity"; to: 1; duration: Motion.navigateEnter; easing.type: Motion.enter }
            NumberAnimation { target: label; property: "y"; to: 0; duration: Motion.navigateEnter; easing.type: Motion.enter }
        }
    }

    // The exit is a cut, not the sweep run backwards: the clip closes, no bar, no delay.
    NumberAnimation {
        id: leaveAnimation
        target: clipper
        property: "width"
        to: 0
        duration: root.isFullTempo ? Motion.revealLeave : Motion.navigateLeave
        easing.type: Motion.leave
    }
}
