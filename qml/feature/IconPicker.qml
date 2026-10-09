import QtQuick
import Vados

// The icons a pin can wear, as a grid in a sheet that grows from where its menu was. A click sets the icon and closes; Escape or a click outside closes.
Item {
    id: root

    property int row: -1
    property string current: ""
    property string tint: ""

    visible: sheet.opacity > 0

    function open(pinRow: int, icon: string, point: point) {
        row = pinRow
        current = icon
        tint = PlacesModel.tintAt(pinRow)
        const margin = Theme.rem * 0.5
        sheet.x = Math.max(margin, Math.min(point.x, width - sheet.width - margin))
        sheet.y = Math.max(margin, Math.min(point.y, height - sheet.implicitHeight - margin))
        sheet.transformOrigin = Item.TopLeft
        sheet.open()
        focusCatcher.forceActiveFocus()
    }

    function close() {
        sheet.close()
    }

    MouseArea {
        anchors.fill: parent
        enabled: sheet.isOpen
        acceptedButtons: Qt.AllButtons
        onPressed: root.close()
    }

    Item {
        id: focusCatcher
        focus: true
        Keys.onEscapePressed: root.close()
    }

    MenuSheet {
        id: sheet
        label: "icon and colour"
        isAnchored: true
        width: grid.width + Theme.rem * 1.2

        Grid {
            id: grid
            x: Theme.rem * 0.1
            columns: 6
            spacing: Theme.rem * 0.2

            Repeater {
                model: PlacesModel.iconChoices

                delegate: Item {
                    id: cell
                    required property string modelData
                    readonly property bool isCurrent: modelData === root.current
                    width: Theme.rem * 2
                    height: width

                    Squircle {
                        anchors.fill: parent
                        radius: Theme.squircleSmall
                        fillColor: cellMouse.containsMouse || cell.isCurrent ? Theme.sunken : Theme.alpha(Theme.sunken, 0)
                        borderColor: cell.isCurrent ? Theme.accent : cellMouse.containsMouse ? Theme.border : Theme.alpha(Theme.border, 0)
                        Behavior on fillColor { ColorAnimation { duration: Motion.hover } }
                    }

                    Glyph {
                        anchors.centerIn: parent
                        width: Theme.rem * 0.95
                        height: width
                        name: cell.modelData
                        ink: cell.isCurrent || cellMouse.containsMouse ? Theme.accentInk : Theme.textBody
                    }

                    MouseArea {
                        id: cellMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            PlacesModel.setPinIcon(root.row, cell.modelData)
                            root.close()
                        }
                    }
                }
            }
        }

        // The colour: the first swatch follows the pin's room, the rest are the room colours.
        Row {
            x: Theme.rem * 0.1
            topPadding: Theme.rem * 0.35
            spacing: Theme.rem * 0.2

            Repeater {
                model: ["", "home", "desktop", "documents", "downloads", "system", "trash", "pictures", "music", "videos"]

                delegate: Item {
                    id: swatch
                    required property string modelData
                    readonly property bool isCurrent: modelData === root.tint
                    width: Theme.rem * 1.1
                    height: width

                    Squircle {
                        anchors.fill: parent
                        radius: Theme.squircleSmall
                        fillColor: swatch.modelData === "" ? Theme.sunken : Theme.accentFor(swatch.modelData)
                        borderColor: swatch.isCurrent ? Theme.textBright : swatchMouse.containsMouse ? Theme.borderStrong : Theme.border
                        borderWidth: swatch.isCurrent ? 2 : 1
                    }

                    Text {
                        visible: swatch.modelData === ""
                        anchors.centerIn: parent
                        text: "A"
                        color: Theme.textMuted
                        font.family: Theme.mono
                        font.pixelSize: Theme.labelSize
                    }

                    MouseArea {
                        id: swatchMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            PlacesModel.setPinTint(root.row, swatch.modelData)
                            root.tint = swatch.modelData
                        }
                    }
                }
            }
        }

        Item {
            width: 1
            height: Theme.rem * 0.3
        }
    }
}
