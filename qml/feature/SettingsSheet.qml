import QtQuick
import Vados

// The few choices that change how the app behaves, in one floating sheet hung from the top so it never moves under the pointer as it grows (VAS glass sheet §4).
Item {
    id: root

    property var workspace
    readonly property bool isOpen: sheet.isOpen

    visible: sheet.opacity > 0 || scrim.opacity > 0

    function toggle() {
        if (sheet.isOpen)
            close()
        else
            open()
    }

    function open() {
        sheet.open()
        scrimAnimation.to = 0.3
        scrimAnimation.duration = Motion.overlayEnter
        scrimAnimation.restart()
        keyCatcher.forceActiveFocus()
    }

    function close() {
        sheet.close()
        scrimAnimation.to = 0
        scrimAnimation.duration = Motion.overlayLeave
        scrimAnimation.restart()
        if (workspace.activePane)
            workspace.activePane.forceActiveFocus()
    }

    Rectangle {
        id: scrim
        anchors.fill: parent
        color: "#000000"
        opacity: 0

        NumberAnimation { id: scrimAnimation; target: scrim; property: "opacity" }

        MouseArea {
            anchors.fill: parent
            enabled: sheet.isOpen
            acceptedButtons: Qt.AllButtons
            onPressed: root.close()
        }
    }

    Item {
        id: keyCatcher
        focus: sheet.isOpen
        Keys.onEscapePressed: root.close()
    }

    MenuSheet {
        id: sheet
        label: "settings"
        width: Theme.rem * 21
        x: (root.width - width) / 2
        y: Theme.rem * 4.5

        Item { width: 1; height: Theme.rem * 0.3 }

        Toggle {
            width: sheet.column.width - Theme.rem * 0.6
            x: Theme.rem * 0.3
            text: "Show hidden files"
            detail: "Names starting with a dot. Ctrl+H."
            isOn: Settings.showHidden
            onToggled: Settings.showHidden = !Settings.showHidden
        }

        Toggle {
            width: sheet.column.width - Theme.rem * 0.6
            x: Theme.rem * 0.3
            text: "Folders first"
            detail: "Folders sort above files, whatever the order."
            isOn: Settings.foldersFirst
            onToggled: Settings.foldersFirst = !Settings.foldersFirst
        }

        Toggle {
            width: sheet.column.width - Theme.rem * 0.6
            x: Theme.rem * 0.3
            text: "Details column"
            detail: "The facts about the selection, on the right. Alt+P."
            isOn: Settings.showDetails
            onToggled: Settings.showDetails = !Settings.showDetails
        }

        Toggle {
            width: sheet.column.width - Theme.rem * 0.6
            x: Theme.rem * 0.3
            text: "Lite motion"
            detail: System.prefersReducedMotion ? "On, because the desktop asks for reduced motion." : "Drops the bars, the overshoot and the pointer glow; keeps every enter and leave."
            isOn: Motion.isLite
            onToggled: Settings.isLiteMode = !Settings.isLiteMode
        }

        Item {
            width: sheet.column.width
            height: Theme.rem * 2.4

            Text {
                x: Theme.rem * 0.3
                anchors.verticalCenter: parent.verticalCenter
                text: "TILE SIZE"
                color: Theme.textBody
                font.family: Theme.mono
                font.pixelSize: Theme.labelSize * 1.05
                font.letterSpacing: Theme.labelSpacing * 0.45
            }

            GooStepSlider {
                anchors.right: parent.right
                anchors.rightMargin: Theme.rem * 0.1
                anchors.verticalCenter: parent.verticalCenter
                count: 4
                value: Settings.zoomLevel
                onCommitted: step => Settings.zoomLevel = step
            }
        }

        Item {
            width: sheet.column.width
            height: Theme.rem * 2.6

            Text {
                x: Theme.rem * 0.3
                anchors.verticalCenter: parent.verticalCenter
                text: "TERMINAL"
                color: Theme.textBody
                font.family: Theme.mono
                font.pixelSize: Theme.labelSize * 1.05
                font.letterSpacing: Theme.labelSpacing * 0.45
            }

            Item {
                anchors.right: parent.right
                anchors.rightMargin: Theme.rem * 0.3
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.rem * 11
                height: Theme.rem * 1.7

                Squircle {
                    anchors.fill: parent
                    radius: Theme.squircleSmall
                    fillColor: Theme.sunkenDeep
                    borderColor: terminalInput.activeFocus ? Theme.mix(Theme.accent, Theme.border, 0.55) : Theme.borderStrong
                }

                TextInput {
                    id: terminalInput
                    anchors.fill: parent
                    anchors.leftMargin: Theme.rem * 0.5
                    anchors.rightMargin: Theme.rem * 0.5
                    verticalAlignment: TextInput.AlignVCenter
                    text: Settings.terminalCommand
                    color: Theme.textBright
                    font.family: Theme.mono
                    font.pixelSize: Theme.smallSize
                    clip: true
                    selectByMouse: true
                    onEditingFinished: Settings.terminalCommand = text.trim()
                }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.rem * 0.5
                    anchors.verticalCenter: parent.verticalCenter
                    visible: terminalInput.text.length === 0 && !terminalInput.activeFocus
                    text: "$TERMINAL, or foot"
                    color: Theme.textFaint
                    font.family: Theme.mono
                    font.pixelSize: Theme.smallSize
                }
            }
        }

        Text {
            x: Theme.rem * 0.3
            width: sheet.column.width - Theme.rem * 0.6
            topPadding: Theme.rem * 0.4
            bottomPadding: Theme.rem * 0.3
            text: "VAD/OS FILES · built on VAS"
            color: Theme.textFaint
            font.family: Theme.mono
            font.pixelSize: Theme.labelSize * 0.9
            font.letterSpacing: Theme.labelSpacing * 0.6
        }
    }
}
