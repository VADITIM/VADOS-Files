import QtQuick
import Vados

// The pills at the bottom of the window (VAS confirm and undo). A permanent delete waits on CONFIRM; every change that can be reversed offers its reversal for a few seconds; a name clash asks once, in place.
Item {
    id: root

    property var workspace
    property var pendingAction: null
    property string description: ""
    property bool isExtreme: false
    property string offerMessage: ""
    property var offerAction: null
    property bool isOfferError: false
    property int conflictJobId: 0
    property string conflictName: ""
    property string conflictDestination: ""

    // #region ── confirm ───────────────────────────────────────────────────────────────────────
    function confirm(text: string, action: var, isIrreversible: bool) {
        description = text
        pendingAction = action
        isExtreme = isIrreversible
        confirmShrink.stop()
        confirmGrow.restart()
    }

    function clearConfirm() {
        if (pendingAction === null)
            return
        pendingAction = null
        confirmGrow.stop()
        confirmShrink.restart()
    }

    function runConfirm() {
        const action = pendingAction
        clearConfirm()
        if (action)
            action()
    }

    Shortcut {
        sequences: ["Return", "Enter"]
        enabled: root.pendingAction !== null
        onActivated: root.runConfirm()
    }

    Shortcut {
        sequence: "Escape"
        enabled: root.pendingAction !== null
        onActivated: root.clearConfirm()
    }
    // #endregion ───────────────────────────────────────────────────────────────────────────────

    // #region ── offers ────────────────────────────────────────────────────────────────────────
    function offer(message: string, action: var, duration: int, isError: bool) {
        offerMessage = message
        offerAction = action
        isOfferError = isError === true
        offerTimer.interval = duration
        offerTimer.restart()
        offerDrop.stop()
        if (undoBox.opacity < 1 || offerRise.running) {
            offerRise.restart()
        } else {
            offerBump.restart()
        }
    }

    function dismissOffer() {
        offerTimer.stop()
        offerRise.stop()
        offerDrop.restart()
    }

    function askConflict(jobId: int, name: string, destination: string) {
        conflictJobId = jobId
        conflictName = name
        conflictDestination = destination
        conflictShrink.stop()
        conflictGrow.restart()
    }

    function answerConflict(answer: string) {
        FileOperations.resolveConflict(conflictJobId, answer, allPill.isOn)
        allPill.isOn = false
        conflictGrow.stop()
        conflictShrink.restart()
    }

    Timer {
        id: offerTimer
        // A pointer resting on the pill is someone about to press it.
        running: false
        onTriggered: if (!undoMouse.containsMouse) root.dismissOffer(); else restart()
    }
    // #endregion ───────────────────────────────────────────────────────────────────────────────

    // #region ── conflict ──────────────────────────────────────────────────────────────────────
    Item {
        id: conflictBox
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: confirmBox.top
        anchors.bottomMargin: Theme.rem * 0.6
        width: conflictRow.implicitWidth + Theme.rem * 1.2
        height: Theme.rem * 2.5
        scale: 0
        visible: scale > 0

        NumberAnimation { id: conflictGrow; target: conflictBox; property: "scale"; to: 1; duration: Motion.stateChange; easing.type: Motion.enterProminent }
        NumberAnimation { id: conflictShrink; target: conflictBox; property: "scale"; to: 0; duration: Motion.stateChange; easing.type: Motion.leaveLarge }

        Squircle {
            anchors.fill: parent
            radius: height / 2
            exponent: 3
            fillColor: Theme.panelSolid
            borderColor: Theme.mix(Theme.accent, Theme.border, 0.5)
        }

        Row {
            id: conflictRow
            anchors.centerIn: parent
            spacing: Theme.rem * 0.35

            Text {
                anchors.verticalCenter: parent.verticalCenter
                rightPadding: Theme.rem * 0.4
                text: root.conflictName + " is already in " + root.conflictDestination
                color: Theme.textBright
                font.family: Theme.mono
                font.pixelSize: Theme.smallSize
            }
            Pill { anchors.verticalCenter: parent.verticalCenter; text: "replace"; onClicked: root.answerConflict("replace") }
            Pill { anchors.verticalCenter: parent.verticalCenter; text: "keep both"; onClicked: root.answerConflict("keep") }
            Pill { anchors.verticalCenter: parent.verticalCenter; text: "skip"; onClicked: root.answerConflict("skip") }
            Pill { id: allPill; anchors.verticalCenter: parent.verticalCenter; text: "for all"; onClicked: isOn = !isOn }
        }
    }
    // #endregion ───────────────────────────────────────────────────────────────────────────────

    // #region ── confirm pill ──────────────────────────────────────────────────────────────────
    Item {
        id: confirmBox
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: undoBox.top
        anchors.bottomMargin: Theme.rem * 0.6
        width: Math.max(confirmPill.width, confirmText.implicitWidth)
        height: confirmText.implicitHeight + Theme.rem * 0.45 + confirmPill.height
        scale: 0
        visible: scale > 0

        // It pops in place: a new thing standing there, not something sliding up.
        NumberAnimation { id: confirmGrow; target: confirmBox; property: "scale"; to: 1; duration: Motion.stateChange; easing.type: Motion.enterProminent }
        NumberAnimation { id: confirmShrink; target: confirmBox; property: "scale"; to: 0; duration: Motion.stateChange; easing.type: Motion.leaveLarge }

        Text {
            id: confirmText
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.description
            color: root.isExtreme ? Theme.danger : Theme.textBody
            font.family: Theme.mono
            font.pixelSize: Theme.smallSize
            style: Text.Outline
            styleColor: Theme.ground
        }

        Pill {
            id: confirmPill
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            implicitHeight: Theme.rem * 2.3
            implicitWidth: Theme.rem * 9
            text: "confirm"
            isDanger: true
            fillColor: root.isExtreme ? Theme.dangerExtreme : Theme.danger
            // A fifth larger than the other labels, so the one irreversible tap is the easiest to find.
            textScale: 1.2
            onClicked: root.runConfirm()
        }
    }
    // #endregion ───────────────────────────────────────────────────────────────────────────────

    // #region ── undo pill ─────────────────────────────────────────────────────────────────────
    Item {
        id: undoBox
        property real rise: height + Theme.gap
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height - height - Theme.gap * 1.6 + rise
        width: undoRow.implicitWidth + (root.offerAction ? Theme.rem * 0.5 : Theme.rem * 1.4)
        height: Theme.rem * 2.4
        opacity: 0
        visible: opacity > 0

        ParallelAnimation {
            id: offerRise
            NumberAnimation { target: undoBox; property: "rise"; to: 0; duration: Motion.pillEnter; easing.type: Motion.enterProminent }
            NumberAnimation { target: undoBox; property: "opacity"; to: 1; duration: Motion.pillEnter * 0.6; easing.type: Motion.enter }
        }

        ParallelAnimation {
            id: offerDrop
            NumberAnimation { target: undoBox; property: "rise"; to: undoBox.height + Theme.gap; duration: Motion.pillLeave; easing.type: Motion.leave }
            NumberAnimation { target: undoBox; property: "opacity"; to: 0; duration: Motion.pillLeave; easing.type: Motion.leave }
        }

        // A second offer while one is showing replaces the words and nudges the pill, rather than dropping and raising it again.
        SequentialAnimation {
            id: offerBump
            NumberAnimation { target: undoBox; property: "scale"; to: 1.05; duration: 90; easing.type: Easing.OutQuad }
            NumberAnimation { target: undoBox; property: "scale"; to: 1; duration: 200; easing.type: Motion.enterProminent }
        }

        Squircle {
            anchors.fill: parent
            radius: height / 2
            exponent: 3
            fillColor: Theme.panelSolid
            borderColor: root.isOfferError ? Theme.dangerHard : Theme.borderStrong
        }

        Row {
            id: undoRow
            x: Theme.rem * 0.7
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.rem * 0.5

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.offerMessage
                color: root.isOfferError ? Theme.danger : Theme.textBright
                font.family: Theme.mono
                font.pixelSize: Theme.smallSize
            }

            Item {
                visible: root.offerAction !== null
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.rem * 1.9
                height: width

                Squircle {
                    anchors.fill: parent
                    radius: width / 2
                    exponent: 2
                    fillColor: undoMouse.pressed ? Theme.raisedHigh : undoMouse.containsMouse ? Theme.raised : Theme.alpha(Theme.raised, 0)
                    borderWidth: 0
                }

                Glyph {
                    anchors.centerIn: parent
                    width: Theme.rem * 0.95
                    height: width
                    name: "restore"
                    ink: Theme.accentInk
                }
            }
        }

        MouseArea {
            id: undoMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: root.offerAction ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                const action = root.offerAction
                root.dismissOffer()
                if (action)
                    action()
            }
        }
    }
    // #endregion ───────────────────────────────────────────────────────────────────────────────
}
