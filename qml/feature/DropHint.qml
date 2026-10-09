import QtQuick
import Vados

// Says what a drop will do before it happens — MOVE TO DOCUMENTS, COPY TO HOME — next to the pointer, in the app's own voice.
Item {
    id: root

    property string verb: ""
    property string target: ""
    property bool isShown: false

    width: row.implicitWidth + Theme.rem * 1.1
    height: Theme.rem * 1.6
    visible: opacity > 0
    opacity: 0
    scale: 0.6
    z: 1000

    function show(verbText: string, targetText: string, point: point) {
        verb = verbText
        target = targetText
        x = point.x + Theme.rem * 1.2
        y = point.y + Theme.rem * 0.9
        if (isShown)
            return
        isShown = true
        leaveAnimation.stop()
        enterAnimation.restart()
    }

    function hide() {
        if (!isShown)
            return
        isShown = false
        enterAnimation.stop()
        leaveAnimation.restart()
    }

    ParallelAnimation {
        id: enterAnimation
        NumberAnimation { target: root; property: "opacity"; to: 1; duration: 140; easing.type: Motion.enter }
        NumberAnimation { target: root; property: "scale"; to: 1; duration: 200; easing.type: Motion.enterProminent }
    }

    ParallelAnimation {
        id: leaveAnimation
        NumberAnimation { target: root; property: "opacity"; to: 0; duration: 110; easing.type: Motion.leave }
        NumberAnimation { target: root; property: "scale"; to: 0.6; duration: 110; easing.type: Motion.leaveLarge }
    }

    Squircle {
        anchors.fill: parent
        radius: height / 2
        exponent: 3
        fillColor: Theme.panelSolid
        borderColor: Theme.mix(Theme.accent, Theme.border, 0.5)
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Theme.rem * 0.35

        Text {
            text: root.verb.toUpperCase()
            color: Theme.accentInk
            font.family: Theme.mono
            font.pixelSize: Theme.labelSize
            font.letterSpacing: Theme.labelSpacing * 0.6
            font.weight: Font.Medium
        }

        Text {
            text: root.target
            color: Theme.textBright
            font.family: Theme.mono
            font.pixelSize: Theme.labelSize * 1.05
        }
    }
}
