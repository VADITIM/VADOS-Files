import QtQuick
import QtQuick.Controls.Basic
import Vados

// A thumb and no track (VAS surface: chrome removal): a grey gutter draws a hard line down the inside of a box whether or not there is anything to scroll.
ScrollBar {
    id: root

    policy: ScrollBar.AsNeeded
    minimumSize: 0.06
    padding: 2
    interactive: true

    contentItem: Rectangle {
        implicitWidth: 5
        radius: width / 2
        color: root.pressed || root.hovered ? Theme.borderHover : Theme.borderControl
        opacity: root.active || root.hovered ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.hover } }
        Behavior on color { ColorAnimation { duration: Motion.hover } }
    }

    background: Item {}
}
