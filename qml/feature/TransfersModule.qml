import QtQuick
import Vados

// Running copies, moves and trashes. It exists only while something is running: it grows out of a fifth of its size when the first job starts and goes back down to a fifth when the last one ends — one state change, one shape, both ways (VAS motion §12).
Item {
    id: root

    property real maximumHeight: Theme.rem * 20
    readonly property bool hasJobs: FileOperations.jobs.count > 0
    readonly property real rowHeight: Theme.rem * 2.9

    height: Math.min(maximumHeight, Theme.rem * 2.3 + list.contentHeight + Theme.rem * 0.6)
    visible: frame.opacity > 0

    onHasJobsChanged: {
        if (hasJobs) {
            lingerTimer.stop()
            leaveAnimation.stop()
            enterAnimation.restart()
        } else {
            lingerTimer.restart()
        }
    }

    Timer {
        id: lingerTimer
        interval: 250
        onTriggered: {
            enterAnimation.stop()
            leaveAnimation.restart()
        }
    }

    ParallelAnimation {
        id: enterAnimation
        NumberAnimation { target: frame; property: "opacity"; from: 0; to: 1; duration: Motion.overlayEnter * 0.7; easing.type: Motion.enter }
        NumberAnimation { target: frame; property: "scale"; from: 0.2; to: 1; duration: Motion.overlayEnter + 80; easing.type: Motion.enterProminent }
    }

    ParallelAnimation {
        id: leaveAnimation
        NumberAnimation { target: frame; property: "opacity"; to: 0; duration: Motion.overlayLeave + 40; easing.type: Motion.leave }
        NumberAnimation { target: frame; property: "scale"; to: 0.2; duration: Motion.overlayLeave + 40; easing.type: Motion.leave }
    }

    Behavior on height { enabled: root.visible; NumberAnimation { duration: Motion.stateChange; easing.type: Motion.state } }

    Module {
        id: frame
        anchors.fill: parent
        label: "transfers"
        topPadding: Theme.rem * 2.3
        sidePadding: Theme.rem * 0.5
        bottomPadding: Theme.rem * 0.5
        // The label is part of the box here, not an arrival of its own: it is set once and the whole module grows in around it.
        Component.onCompleted: {
            showNow()
            opacity = 0
        }
        transformOrigin: Item.Bottom

        ListView {
            id: list
            anchors.fill: parent
            model: FileOperations.jobs
            interactive: contentHeight > height
            clip: true
            spacing: Theme.rem * 0.2

            add: Transition {
                NumberAnimation { property: "scale"; from: 0.2; to: 1; duration: Motion.stateChange; easing.type: Motion.enterProminent }
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Motion.stateChange * 0.6 }
            }
            remove: Transition {
                NumberAnimation { property: "scale"; to: 0.2; duration: Motion.overlayLeave; easing.type: Motion.leave }
                NumberAnimation { property: "opacity"; to: 0; duration: Motion.overlayLeave; easing.type: Motion.leave }
            }
            displaced: Transition {
                NumberAnimation { property: "y"; duration: Motion.stateChange; easing.type: Motion.state }
            }

            delegate: Item {
                id: job
                required property int jobId
                required property string verb
                required property string title
                required property string detail
                required property real progress
                required property string state
                required property string conflictName
                width: list.width
                height: root.rowHeight

                Squircle {
                    anchors.fill: parent
                    radius: Theme.squircleSmall
                    fillColor: Theme.sunken
                    borderColor: job.state === "failed" ? Theme.dangerHard : job.state === "conflict" ? Theme.mix(Theme.accent, Theme.border, 0.5) : Theme.border
                }

                Text {
                    id: verbText
                    x: Theme.rem * 0.6
                    y: Theme.rem * 0.45
                    text: (job.state === "conflict" ? "waiting" : job.state === "done" ? "done" : job.state === "failed" ? "failed" : job.verb).toUpperCase()
                    color: job.state === "failed" ? Theme.danger : job.state === "done" ? Theme.accentInk : Theme.textLabel
                    font.family: Theme.mono
                    font.pixelSize: Theme.labelSize * 0.9
                    font.letterSpacing: Theme.labelSpacing * 0.8
                }

                FadeText {
                    anchors.left: verbText.right
                    anchors.leftMargin: Theme.rem * 0.4
                    anchors.right: cancel.left
                    anchors.rightMargin: Theme.rem * 0.3
                    anchors.verticalCenter: verbText.verticalCenter
                    text: job.state === "conflict" ? job.conflictName + " already exists" : job.detail.length > 0 ? job.detail : job.title
                    color: Theme.textBody
                    font.pixelSize: Theme.smallSize
                }

                IconButton {
                    id: cancel
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.rem * 0.3
                    y: Theme.rem * 0.22
                    width: Theme.rem * 1.2
                    height: width
                    glyphSize: Theme.rem * 0.6
                    glyph: "close"
                    hint: "cancel"
                    visible: job.state === "running" || job.state === "conflict"
                    onClicked: FileOperations.cancel(job.jobId)
                }

                // The level: a fill clipped inside its own hairline; indeterminate work shows a travelling segment instead, which is the job being alive.
                Rectangle {
                    id: track
                    x: Theme.rem * 0.6
                    y: Theme.rem * 1.75
                    width: parent.width - Theme.rem * 1.2
                    height: 5
                    radius: 2.5
                    color: "transparent"
                    border.color: Theme.borderControl
                    border.width: 1
                    clip: true

                    Rectangle {
                        visible: job.progress >= 0
                        x: 1
                        y: 1
                        height: parent.height - 2
                        radius: 1.5
                        width: Math.max(0, (parent.width - 2) * Math.min(1, job.progress))
                        color: job.state === "failed" ? Theme.danger : Theme.accentInk
                        Behavior on width { NumberAnimation { duration: 160; easing.type: Motion.state } }
                    }

                    Rectangle {
                        id: runner
                        visible: job.progress < 0
                        y: 1
                        height: parent.height - 2
                        width: parent.width * 0.28
                        radius: 1.5
                        color: Theme.accentInk
                        SequentialAnimation on x {
                            running: runner.visible
                            loops: Animation.Infinite
                            NumberAnimation { from: -runner.width; to: track.width; duration: 1100; easing.type: Motion.idle }
                        }
                    }
                }

            }
        }
    }
}
