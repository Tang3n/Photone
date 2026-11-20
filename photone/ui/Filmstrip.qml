import QtQuick
import QtQuick.Shapes
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
    // A photo and its denoised copy stand as a pair: further apart than photos otherwise
    // (`pairGap`), one outline round both that dips a little between them (`pairDip`, as a
    // share of its height at top and foot; 0: a plain rounded outline), a link in the gap.
    // (The owner's choice of six rounds of renders, 2026-11-20: "lets go with D1 for now";
    // the one he may come back to is a plain outline, 26 apart: pairGap 26, pairDip 0.)
    property real pairGap: 44
    property real pairDip: 0.08
    readonly property real pairPad: 5   // from the outline to the pictures
    color: Theme.panel
    clip: true
    function bringBack() { row.positionViewAtIndex(current, ListView.Center) }
    onCurrentChanged: row.positionViewAtIndex(current, ListView.Contain)
    Rectangle { width: parent.width; height: 1; color: Theme.line }
    ListView {
        id: row
        objectName: "strip-row"
        // (Fewer photos than fill the strip stand in its middle, not at its left end.)
        readonly property real spare: Math.max(0, strip.width - 16 - Math.max(count * pace - spacing, contentWidth)) / 2
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
            // (Asked anew with the list of photos; the library keeps what each file says.)
            readonly property bool denoised: file !== "" && library.denoised(file)
            readonly property bool second: denoised && index > 0 && library.copyOf(file, (session.listing, session.fileAt(index - 1)))   // the copy, its original before it
            readonly property bool first: (session.listing, library.copyOf(session.fileAt(index + 1), file))                              // an original, its copy after it
            // Room for the pair's outline on its outer sides, and for the gap before the copy.
            // (A picture wider than its slot stands lower than the row: the outline is as far
            // from its sides as that puts it from its top and foot.)
            readonly property real side: strip.pairPad + (pic.shown ? Math.max(0, (height - pic.height) / 2) : 0)
            readonly property real lead: second ? strip.pairGap - row.spacing : first ? side + 2 : 0
            readonly property real trail: second ? side + 2 : 0
            objectName: "strip:" + index
            width: row.wide + lead + trail; height: row.height
            Loader {
                objectName: "strip-pair"
                active: cell.second
                x: cell.lead - strip.pairGap - row.wide - cell.side; y: -strip.pairPad
                width: 2 * row.wide + strip.pairGap + 2 * cell.side; height: cell.height + 2 * strip.pairPad
                sourceComponent: Item {
                    id: pair
                    readonly property real r: 7
                    readonly property string outline: {
                        const W = width, H = height, a = cell.side + row.wide + strip.pairPad, c = W - a, m = W / 2
                        const from = a - r, to = c + r, half = (to - from) / 2, d = H * strip.pairDip
                        return "M" + r + " 0 H" + from
                            + " C" + (from + half * 0.6) + " 0 " + (m - half * 0.5) + " " + d + " " + m + " " + d
                            + " C" + (m + half * 0.5) + " " + d + " " + (to - half * 0.6) + " 0 " + to + " 0"
                            + " H" + (W - r) + " A" + r + " " + r + " 0 0 1 " + W + " " + r + " V" + (H - r) + " A" + r + " " + r + " 0 0 1 " + (W - r) + " " + H
                            + " H" + to
                            + " C" + (to - half * 0.6) + " " + H + " " + (m + half * 0.5) + " " + (H - d) + " " + m + " " + (H - d)
                            + " C" + (m - half * 0.5) + " " + (H - d) + " " + (from + half * 0.6) + " " + H + " " + from + " " + H
                            + " H" + r + " A" + r + " " + r + " 0 0 1 0 " + (H - r) + " V" + r + " A" + r + " " + r + " 0 0 1 " + r + " 0 Z"
                    }
                    // (The layer is a little larger than the outline: its straight sides run along
                    // the very edge, and a layer of that size cut the outer half of the line off
                    // them, so the curves looked thicker.)
                    Item {
                        anchors { fill: parent; margins: -2 }
                        layer.enabled: true; layer.samples: 8
                        Shape {
                            x: 2; y: 2; width: pair.width; height: pair.height
                            ShapePath {
                                strokeColor: Qt.rgba(Theme.mark.r, Theme.mark.g, Theme.mark.b, 0.75); strokeWidth: 1.5; fillColor: "transparent"; joinStyle: ShapePath.RoundJoin
                                PathSvg { path: pair.outline }
                            }
                        }
                    }
                    Icon { anchors.centerIn: parent; width: 18; height: 18; stroke: 2.2; path: Theme.linkSign; color: Theme.mark }
                    Accessible.role: Accessible.StaticText; Accessible.name: "A photo and its denoised copy"
                }
            }
            Image {
                id: thumbImage
                objectName: "strip-thumb"
                x: cell.lead; width: row.wide; height: parent.height
                source: cell.thumb; asynchronous: true; fillMode: Image.PreserveAspectFit
                sourceSize: Qt.size(320, 320)
                retainWhileLoading: true   // (made anew as the photo is edited: no empty cell meanwhile)
                opacity: (cell.flag < 0 ? 0.3 : 1) * (strip.chosen.length > 0 && !cell.taken ? 0.4 : 1)   // rejected; not of the selection
            }
            Item {
                id: pic
                readonly property bool shown: thumbImage.paintedWidth > 1
                anchors.centerIn: thumbImage
                width: shown ? Math.round(thumbImage.paintedWidth) : thumbImage.width
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
            // (Top middle: the corners are Pick and Reject's, the foot the stars'.) Beside it,
            // on a file the neural denoiser wrote, a spark.
            Row {
                anchors { horizontalCenter: pic.horizontalCenter; top: pic.top; topMargin: 4 }
                spacing: 4
                EditedMark { visible: cell.edited && pic.shown }
                Rectangle {
                    objectName: "strip-spark"
                    visible: cell.denoised && pic.shown
                    width: 22; height: 22; radius: 11
                    color: Qt.rgba(0.05, 0.05, 0.06, 0.66); border { width: 1.5; color: Qt.rgba(1, 1, 1, 0.78) }
                    Accessible.role: Accessible.StaticText; Accessible.name: "Denoised"
                    Icon { anchors.centerIn: parent; width: 14; height: 14; path: Theme.sparkSign; color: Theme.mark; filled: true }
                }
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
    // The open photo is out of sight: at that end of the row, the way back to it: an arrow
    // and the photo itself, small, outlined as it is in the row (the owner, of the words
    // "open photo" in a pill: "should be bigger", "shorter and self explanatory"; of four
    // renders, the card, and "we can drop the text"). The row fades into the panel under it.
    Rectangle {
        visible: back.visible
        x: row.away < 0 ? 0 : parent.width - width; y: 1; width: 110; height: parent.height - 1
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: row.away < 0 ? 0 : 1; color: Qt.alpha(Theme.panel, 0.96) }
            GradientStop { position: row.away < 0 ? 0.45 : 0.55; color: Qt.alpha(Theme.panel, 0.8) }
            GradientStop { position: row.away < 0 ? 1 : 0; color: Qt.alpha(Theme.panel, 0) }
        }
    }
    Rectangle {
        id: back
        objectName: "strip-back"
        visible: row.away !== 0 && strip.height > 40
        x: row.away < 0 ? 10 : parent.width - width - 10
        anchors.verticalCenter: row.verticalCenter
        width: both.width + 20; height: Math.min(row.height, 56); radius: 8
        color: over.containsMouse ? Theme.selected : Qt.rgba(0.07, 0.07, 0.08, 0.92)
        border { width: 1; color: over.containsMouse ? Theme.mark : Theme.faint }
        Accessible.role: Accessible.Button; Accessible.name: "Back to the open photo"
        Row {
            id: both
            anchors.centerIn: parent; spacing: 9; layoutDirection: row.away < 0 ? Qt.LeftToRight : Qt.RightToLeft
            Icon {
                anchors.verticalCenter: parent.verticalCenter; width: 18; height: 18; stroke: 2.2; color: Theme.mark
                path: row.away < 0 ? "M12.5 4 L6.5 10 L12.5 16" : "M7.5 4 L13.5 10 L7.5 16"
            }
            Image {
                id: small
                anchors.verticalCenter: parent.verticalCenter
                height: back.height - 20; width: Math.round(height * (implicitHeight > 0 ? implicitWidth / implicitHeight : 1.5))
                source: (session.listing, library.thumbs, library.thumbFor(session.fileAt(strip.current)))
                sourceSize: Qt.size(320, 320); retainWhileLoading: true
                Rectangle { anchors { fill: parent; margins: -2 } radius: 3; color: "transparent"; border { width: 2; color: Theme.white } }
            }
        }
        MouseArea { id: over; anchors.fill: parent; hoverEnabled: true; onClicked: strip.bringBack() }
    }
}
