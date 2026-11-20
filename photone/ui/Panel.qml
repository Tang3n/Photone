import QtQuick
import "."

// A section of a side column, on a card of its own: a title, what belongs to it below. With
// `tool` set it is the card of one of the edit's tools (edit.TOOLS) and its head offers
// A/B (held: the photo without this tool) and Reset.
Column {
    id: panel
    property string title
    property string tool: ""
    property string card: ""     // which of Theme.cards it is: its icon and its color
    default property alias content: body.data
    // As one of a column of cards that are all there: a
    // press on its header folds it to that header, or opens it.
    property bool folds: false
    property bool open: true
    property bool plain: false   // a part of another section's card: no card of its own
    // A card of a mask's own settings: its Reset and its A/B ask its owner.
    property bool local: false
    property bool changed: false
    signal reset()
    signal compare(bool held)
    signal fold()
    // The card of a tool, or of a mask's own settings: A/B (held: the photo without what
    // this card does) stays on its head when it is folded, and Reset stands after the title
    // and its dot, there only when the card has changed the photo (the owner: "all cards
    // could have an A/B button even collapsed", Reset "right after the title and the unsaved
    // status dot"; his choice of two renders; and "same for cards under Masks").
    readonly property bool headed: tool !== "" || local
    readonly property bool altered: local ? changed : session.adjusted[tool] === true
    property bool made: false
    Component.onCompleted: made = true
    onOpenChanged: if (made && open && folds) under.flash()
    function flash() { under.flash() }
    width: parent.width
    Item {
        width: parent.width; height: 30
        Ground { id: under; visible: !panel.plain; card: panel.card; wide: panel.width; high: panel.height - foot.height }
        MouseArea {
            // (All of the card's head, to its edges: Ground.qml. There the pointer is a hand.)
            enabled: panel.folds; x: -10; y: -8; width: parent.width + 20; height: 44
            cursorShape: panel.folds ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: panel.fold()
        }
        Icon {   // folded or open: a chevron that turns (it was a small text triangle)
            visible: panel.folds
            x: -2; y: Theme.cardMid - height / 2; width: 14; height: 14; stroke: 2
            path: "M7.5 4.5 L13 10 L7.5 15.5"; color: heading.color
            rotation: panel.open ? 90 : 0
            Behavior on rotation { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
        }
        Icon {
            id: sign
            visible: path !== ""
            x: panel.folds ? 17 : 0; y: Theme.cardMid - height / 2; width: Theme.cardSign; height: Theme.cardSign; stroke: 1.8
            path: Theme.cardIcon(panel.card); color: heading.color
        }
        Label {
            id: heading
            x: (panel.folds ? 18 : 0) + (sign.visible ? Theme.cardSign + 8 : 0); y: Theme.cardMid - height / 2; text: panel.title.toUpperCase()
            color: Theme.cardInk(panel.card, panel.folds && panel.open ? Theme.text : Theme.dim)
            font.pixelSize: panel.card !== "" ? Theme.titleSize : Theme.smallSize; font.weight: Font.DemiBold; font.letterSpacing: 0.9
            Accessible.role: panel.folds ? Accessible.Button : Accessible.Heading
            Accessible.name: panel.title + (panel.folds ? (panel.open ? ", open" : ", folded") : "")
        }
        Rectangle {   // it has changed the photo: said on its head, folded or open
            id: dot
            visible: panel.local ? panel.changed : panel.folds && panel.tool !== "" && panel.altered
            // (8 px on the new screen's cards, where titles and icons are larger; the owner:
            // "a bigger dot for consistency with the rest of the UI".)
            readonly property real size: panel.card !== "" ? 8 : 5
            x: heading.x + heading.width + 10; y: heading.y + heading.height / 2 - size / 2; width: size; height: size; radius: size / 2; color: Theme.mark
        }
        TextButton {
            objectName: "reset:" + panel.tool
            visible: panel.headed && panel.altered
            x: (dot.visible ? dot.x + dot.width : heading.x + heading.width) + 12; y: Theme.cardMid - height / 2
            sign: Theme.resetSign; says: "Reset"; strong: true
            onPressed: panel.local ? panel.reset() : session.resetTool(panel.tool)
        }
        TextButton {
            objectName: "compare:" + panel.tool
            // (On the head's middle line, as the title and its icon are. Not on the Crop
            // card: the owner's wish.)
            visible: panel.headed && panel.card !== "crop"
            y: Theme.cardMid - height / 2; anchors { right: parent.right; rightMargin: 6 }
            text: "A/B"; says: "Compare"; strong: true; font.weight: Font.DemiBold
            font.pixelSize: Theme.titleSize; font.letterSpacing: 0.6
            available: panel.local ? panel.altered : session.comparable[panel.tool] === true
            onHeldChanged: panel.local ? panel.compare(held) : session.setBypass(held ? panel.tool : "")
        }
    }
    // (What it holds begins under the head: Ground.qml. Not on the old screen, whose cards have no icon.)
    // (10 px under the head and 10 over the card's foot, as much as there is at its sides.)
    Item { width: 1; height: 16; visible: body.visible && !panel.plain && panel.card !== "" }
    Column { id: body; width: parent.width; visible: !panel.folds || panel.open }
    Item { width: 1; height: 4; visible: body.visible && !panel.plain && panel.card !== "" }
    Item { id: foot; width: 1; height: panel.plain ? 0 : panel.folds && !panel.open ? 16 : 24 }   // the card's own foot, and the gap to the next
}
