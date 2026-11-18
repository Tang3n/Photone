import QtQuick
import "."

// The card a section of the right column stands on: each section is one thing, with a gap to
// the next (the owner's choice of three ways, 2026-11-17: "it's hard to tell at a glance where
// sections are separated"). Put inside the section's first item; it draws behind.
// Its head, as high as the card is when folded, is the title's alone: what the card holds
// begins under it (the owner: "the content of the cards should start after the size of the
// collapsed card"). Only that head is
// tinted toward the card's color, with a plain edge (a fade under it was tried: the owner, "lets try no fade").
Rectangle {
    id: ground
    property real wide     // the section's width
    property real high     // and its height, title and all
    property string card: ""   // which of Theme.cards stands on it
    property real head: 44     // how high its head is: a folded card
    z: -1
    x: -10; y: -8; width: wide + 20; height: high + 14; radius: 8
    // (`flash`: its outline white for a moment and back, to show which card was just opened:
    // the scroll that brings it in is quick; the owner's wish.)
    property real lit: 0
    function flash() { fading.restart() }
    NumberAnimation { id: fading; target: ground; property: "lit"; from: 1; to: 0; duration: 1500; easing.type: Easing.OutQuad }
    readonly property color edge: Theme.cardGround(card, "line")
    color: Theme.card
    border { width: 1; color: Qt.rgba(edge.r + (1 - edge.r) * lit, edge.g + (1 - edge.g) * lit, edge.b + (1 - edge.b) * lit, 1) }
    readonly property bool tinted: card !== ""
    readonly property bool more: height > head + 1   // open: there is something under the head
    Rectangle {
        visible: ground.tinted
        // (Inside the outline on every side: folded, it ends a pixel above the card's foot.)
        x: 1; y: 1; width: parent.width - 2; height: Math.min(ground.head, ground.height - 1) - 1
        topLeftRadius: 7; topRightRadius: 7; bottomLeftRadius: ground.more ? 0 : 7; bottomRightRadius: ground.more ? 0 : 7
        color: Theme.cardGround(ground.card, "ground")
    }
    // Open: a line in the title's color between the head and what the card holds (the owner's wish).
    Rectangle {
        visible: ground.tinted && ground.more
        x: 1; y: ground.head - 1; width: parent.width - 2; height: 1
        color: Theme.cardInk(ground.card, Theme.line)
    }
}
