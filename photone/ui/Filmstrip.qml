import QtQuick
import "."

// The photos at hand, as a row of thumbnails under the photo: a click shows one, the wheel
// and the scrollbar go along the row, the open one is outlined. Scrolled out of sight, the
// open photo is still marked on the scrollbar, and a button at that end of the row brings it
// back. Each cell shows the photo's marks: a check when it is picked, dimmed when rejected,
// its stars. Its thumbnails are the library's (library.thumbFor), made one at a time while a
// photo is edited so that the editing loses nothing by it. Nothing here listens to the edit:
// a slider being dragged does not reach it.
Rectangle {
    id: strip
    property int current: 0            // the open photo's place in the row
    signal opened(int index)
    signal menuAsked(var files, real x, real y)   // a right click on a photo: for it, or for all selected if it is one of them
    // The photos selected, by their place in the row: Ctrl and a click takes one in or out,
    // Shift all from the last one clicked to here; a plain click opens a photo and selects
    // nothing (the owner: "CTRL+Click or Shift+Click to de/select photos in the library or
    // film strip"). The open photo is the first of a selection that is begun.
    property var chosen: []
    property int from: -1
    function pick(index, shift) {
        const start = from >= 0 ? from : current
        if (shift) {
            const reach = []
            for (let i = Math.min(start, index); i <= Math.max(start, index); i++) reach.push(i)
            chosen = reach
        } else {
            const had = chosen.length ? chosen : [current]
            chosen = had.includes(index) ? had.filter(i => i !== index) : had.concat([index]).sort((a, b) => a - b)
            from = index
        }
    }
    Connections { target: session; function onListingChanged() { strip.chosen = []; strip.from = -1 } }
    color: Theme.panel
    clip: true
    function bringBack() { row.positionViewAtIndex(current, ListView.Center) }
    onCurrentChanged: row.positionViewAtIndex(current, ListView.Contain)
    Rectangle { width: parent.width; height: 1; color: Theme.line }
    ListView {
        id: row
        objectName: "strip-row"
        // (Fewer photos than fill the strip stand in its middle, not at its left end.)
        readonly property real spare: Math.max(0, strip.width - 16 - (count * pace - spacing)) / 2
        anchors { fill: parent; topMargin: 10; bottomMargin: 16; leftMargin: 8 + spare; rightMargin: 8 + spare }
        visible: strip.height > 40   // (put away: only the strip's edge is left)
        orientation: ListView.Horizontal; spacing: 4
        boundsBehavior: Flickable.StopAtBounds; acceptedButtons: Qt.NoButton
        cacheBuffer: 600
        model: session.count
        // How wide a cell is. Never nothing: with the row put away (no height) every photo of
        // the folder would fit in it at once, and a cell was made for each of thousands (the
        // owner: "the entire program lags and is unusable").
        readonly property real wide: Math.max(40, Math.round(height * 1.4))
        readonly property real pace: wide + spacing   // from one cell to the next
        // Made taller or lower, the row keeps its place: the open photo stays where it is if
        // it is in sight, and else the photo in the middle of the row. (Asked of the cell
        // itself: where the view puts its cells is not their number times their width.)
        property real paceWas: pace
        onPaceChanged: {
            const middle = cell => cell.x + (paceWas - spacing) / 2 - contentX
            const open = itemAtIndex(strip.current)
            const kept = open && middle(open) > 0 && middle(open) < width ? open : itemAt(contentX + width / 2, height / 2)
            const stood = kept ? middle(kept) : 0
            paceWas = pace
            // (Once the view has taken its new height and put its cells in their places.)
            if (kept) Qt.callLater(() => {
                forceLayout()
                contentX = kept.x + kept.width / 2 - stood
                returnToBounds()
            })
        }
        // Where the open photo is, if not in sight: -1 to the left, 1 to the right. (Asked of
        // its cell while there is one: made taller or lower, the view does not count from 0.)
        readonly property real along: contentX - originX
        readonly property int away: {
            if (spare > 0) return 0   // (every photo is in sight)
            const cell = (count, pace, width, contentWidth, itemAtIndex(strip.current)), from = contentX
            if (cell) return cell.x + cell.width < from + 8 ? -1 : cell.x > from + width - 8 ? 1 : 0
            return strip.current < indexAt(from + width / 2, height / 2) ? -1 : 1
        }
        Component.onCompleted: positionViewAtIndex(strip.current, ListView.Contain)
        delegate: Item {
            id: cell
            required property int index
            // (Asked anew only when the list of photos is another, a thumbnail has been made,
            // or a mark was set.)
            readonly property string file: (session.listing, session.fileAt(index))
            readonly property string thumb: (library.thumbs, library.thumbFor(file))
            readonly property var marks: (library.busy, library.marksOf(file))
            readonly property bool open: index === strip.current   // the photo on show
            readonly property int flag: marks.flag || 0
            readonly property int stars: marks.stars || 0
            // (The open photo by what it is now; the others by what the library last read.)
            readonly property bool edited: open ? session.edited : marks.edited === true
            readonly property bool taken: strip.chosen.includes(index)
            objectName: "strip:" + index
            width: row.wide; height: row.height
            Image {
                id: thumbImage
                objectName: "strip-thumb"
                anchors.fill: parent
                source: cell.thumb; asynchronous: true; fillMode: Image.PreserveAspectFit
                sourceSize: Qt.size(320, 320)
                retainWhileLoading: true   // (made anew as the photo is edited: no empty cell meanwhile)
                opacity: (cell.flag < 0 ? 0.3 : 1) * (strip.chosen.length > 0 && !cell.taken ? 0.4 : 1)   // rejected; not of the selection
            }
            Item {
                id: pic
                readonly property bool shown: thumbImage.paintedWidth > 1
                anchors.centerIn: parent
                width: shown ? Math.round(thumbImage.paintedWidth) : parent.width
                height: shown ? Math.round(thumbImage.paintedHeight) : parent.height
                Rectangle { anchors.fill: parent; z: -1; visible: !pic.shown; radius: 3; color: Theme.raised }
                // Selected: a blue outline just inside the picture's own edge (the owner: "use
                // the photo bounds"; round the slot it stood apart from the open photo's white
                // one), and while there is a selection the photos outside it are dimmed.
                Rectangle {
                    objectName: "strip-taken"
                    visible: cell.taken
                    anchors.fill: parent; color: "transparent"; border { width: 3; color: Qt.lighter(Theme.blue, 1.25) }
                }
                Rectangle {   // the open photo: outlined
                    anchors { fill: parent; margins: -2 }
                    visible: cell.open; radius: 3; color: "transparent"; border { width: 2.5; color: Theme.white }
                }
            }
            MouseArea {
                anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: (mouse) => {
                    const ctrl = mouse.modifiers & Qt.ControlModifier, shift = mouse.modifiers & Qt.ShiftModifier
                    if (mouse.button === Qt.LeftButton) {
                        if (ctrl || shift) return strip.pick(cell.index, shift)
                        strip.chosen = []; strip.from = -1
                        return strip.opened(cell.index)
                    }
                    const at = mapToItem(null, mouse.x, mouse.y)
                    strip.menuAsked(cell.taken ? strip.chosen.map(i => session.fileAt(i)) : [cell.file], at.x, at.y)
                }
            }
            // Its marks, to see and to set on the spot: a check (picked), a cross (rejected),
            // its stars. What it has is always there; what it could have shows while the
            // pointer is on the cell (the owner: "if ungraded, they should show on hover"),
            // and a click sets it, the same click again takes it away.
            HoverHandler { id: pointed }
            readonly property bool known: marks.stars !== undefined   // (the library has this photo)
            readonly property bool offered: pointed.hovered && known
            // (One look for the three things that sit on a thumbnail: a dark, half-clear disc
            // with a drawn sign in it. Set, the disc is the sign's color and the sign white;
            // under the pointer it has a light ring. They were letters in circles of three
            // different makes; the owner: "look a bit nicer".)
            component Sign: Rectangle {
                id: sign
                property string path
                property bool on: false
                property color lit: Theme.mark
                signal pressed()
                visible: on || cell.offered
                width: 22; height: 22; radius: 11
                color: on ? lit : Qt.rgba(0.05, 0.05, 0.06, 0.66)
                // (A white outline, the owner's wish: fainter until the pointer is on it.)
                border { width: 1.5; color: overSign.containsMouse ? Theme.white : Qt.rgba(1, 1, 1, 0.78) }
                Icon { anchors.centerIn: parent; width: 14; height: 14; stroke: 2.4; path: sign.path; color: sign.on || overSign.containsMouse ? Theme.white : Qt.rgba(1, 1, 1, 0.8) }
                MouseArea { id: overSign; anchors.fill: parent; hoverEnabled: true; onClicked: sign.pressed() }
            }
            Sign {
                objectName: "strip-pick"
                anchors { right: pic.right; top: pic.top; margins: 4 }
                path: "M4.5 10.5 L8.5 14.5 L15.5 6"; lit: Theme.green; on: cell.flag > 0
                Accessible.role: Accessible.Button; Accessible.name: "Pick"
                onPressed: library.markPhoto(cell.file, "flag", 1)
            }
            Sign {
                objectName: "strip-reject"
                anchors { left: pic.left; top: pic.top; margins: 4 }
                path: "M5.5 5.5 L14.5 14.5 M14.5 5.5 L5.5 14.5"; lit: Theme.red; on: cell.flag < 0
                Accessible.role: Accessible.Button; Accessible.name: "Reject"
                onPressed: library.markPhoto(cell.file, "flag", -1)
            }
            EditedMark {
                visible: cell.edited && pic.shown
                // (Top middle: the corners are Pick and Reject's, the foot the stars'.)
                anchors { horizontalCenter: pic.horizontalCenter; top: pic.top; topMargin: 4 }
            }
            Rectangle {   // its stars: five to click, as large as the cell lets them be
                objectName: "strip-stars"
                visible: cell.stars > 0 || cell.offered
                readonly property real each: Math.max(9, Math.min(19, (pic.width - 18) / 5))
                anchors { horizontalCenter: pic.horizontalCenter; bottom: pic.bottom; bottomMargin: 4 }
                width: each * 5 + 12; height: each + 3; radius: height / 2; color: Qt.rgba(0, 0, 0, 0.62)
                Row {
                    x: 6
                    Repeater {
                        model: 5
                        Item {
                            required property int index
                            objectName: "strip-star" + (index + 1)
                            width: parent.parent.each; height: parent.parent.each + 3
                            Accessible.role: Accessible.Button; Accessible.name: (index + 1) + " stars"
                            Label {
                                anchors.centerIn: parent; text: "★"; font.pixelSize: Math.round(parent.width * 0.86)
                                color: index < cell.stars ? Theme.mark : Qt.rgba(1, 1, 1, 0.38)
                                // (The star under the pointer: outlined in white, the owner's wish.)
                                style: overStar.containsMouse ? Text.Outline : Text.Normal; styleColor: Theme.white
                            }
                            MouseArea { id: overStar; anchors.fill: parent; hoverEnabled: true; onClicked: library.markPhoto(cell.file, "stars", index + 1) }
                        }
                    }
                }
            }
        }
        // The wheel goes along the row, some two cells a notch.
        MouseArea {
            // (From where the row's cells begin, which is not 0 once the strip has been made
            // taller or lower: lying from 0 it was then beside the cells, and the wheel did
            // nothing; the owner: "after making the filmstrip smaller, i cant scroll it".)
            parent: row.contentItem; x: row.originX; width: Math.max(row.width, row.contentWidth); height: row.height; z: -1
            acceptedButtons: Qt.NoButton
            onWheel: (wheel) => along.turned(wheel)
        }
    }
    Scrollbar {
        id: along
        objectName: "strip-bar"
        of: row; across: true; step: row.pace * 2
        visible: row.visible && reach > 0.5
        anchors { left: row.left; right: row.right; bottom: parent.bottom; bottomMargin: 1 }
        // (Where the open photo is among them all.)
        mark: session.count > 1 ? (strip.current + 0.5) / session.count : -1
    }
    // The open photo is out of sight: at that end of the row, the way back to it.
    Rectangle {
        objectName: "strip-back"
        visible: row.away !== 0 && strip.height > 40
        x: row.away < 0 ? 10 : parent.width - width - 10
        anchors.verticalCenter: row.verticalCenter
        width: back.implicitWidth + 20; height: 26; radius: 13
        color: over.containsMouse ? Theme.selected : Qt.rgba(0.07, 0.07, 0.08, 0.86); border { width: 1; color: Theme.mark }
        Accessible.role: Accessible.Button; Accessible.name: "Back to the open photo"
        Label { id: back; anchors.centerIn: parent; font.pixelSize: 12; color: Theme.text; text: row.away < 0 ? "◀  open photo" : "open photo  ▶" }
        MouseArea { id: over; anchors.fill: parent; hoverEnabled: true; onClicked: strip.bringBack() }
    }
}
