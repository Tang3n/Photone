import QtQuick
import "."

// The library: where to look on the left (all photos, the edited ones, a folder, a month, a
// camera), the photos there as a grid of thumbnails, and over the grid the filter. Photos are
// marked here (picked or rejected, stars, a color) with the keys or the mouse; Enter opens one.
Rectangle {
    id: root
    signal opened(int row)      // show the photo at that row in Edit
    signal folderAsked()        // "Add folder…" was pressed
    signal menuAsked(var rows, real x, real y)   // a right click on a photo: for those selected, there in the window
    signal folderMenuAsked(string folder, real x, real y)   // a right click on a folder of the list
    signal folderRemoveAsked(string folder)      // "Remove" on a folder: the window asks first
    property int current: -1    // the photo the keys work on
    property var chosen: []     // the rows that are selected, in order
    property int from: -1       // where a Shift+click reaches from
    readonly property var places: library.places
    readonly property var filter: library.filter
    readonly property var labels: [Theme.red, Theme.yellow, Theme.green, Theme.blue, Theme.purple]
    color: Theme.bg

    function title() {
        if (library.where === "all") return "All photos"
        if (library.where === "edited") return "Edited"
        for (const list of [places.folders, places.months, places.cameras])
            for (const place of list) if (place.id === library.where) return place.name
        return ""
    }
    // A click on a photo: alone, with Ctrl (this one too, or no longer), with Shift (all from
    // the last one clicked to here).
    function pick(row, ctrl, shift) {
        if (shift && from >= 0) {
            const reach = []
            for (let i = Math.min(from, row); i <= Math.max(from, row); i++) reach.push(i)
            chosen = reach
        } else if (ctrl) {
            chosen = chosen.includes(row) ? chosen.filter(r => r !== row) : chosen.concat([row]).sort((a, b) => a - b)
            from = row
        } else {
            chosen = [row]
            from = row
        }
        current = row
    }
    function go(row) {
        if (library.count === 0) return
        pick(Math.max(0, Math.min(library.count - 1, row)), false, false)
        grid.positionViewAtIndex(current, GridView.Contain)
    }
    function choose(row) {   // that photo alone, and in view
        chosen = row >= 0 ? [row] : []
        current = from = row
        if (row >= 0) grid.positionViewAtIndex(row, GridView.Center)
    }
    function settle(row) {   // back from Edit: at that photo, the list read again
        library.refresh()
        choose(row)
    }
    onCurrentChanged: library.lookAt(current)   // (where the program starts next time)
    function mark(what, value) { library.mark(chosen.length ? chosen : (current >= 0 ? [current] : []), what, value) }
    // The keys, as on a camera and in every culling program. True if the key was one of them.
    function key(event) {
        const across = Math.max(1, Math.floor(grid.width / grid.cellWidth)), k = event.key
        if (k === Qt.Key_Left) go(current - 1)
        else if (k === Qt.Key_Right) go(current + 1)
        else if (k === Qt.Key_Up) go(current - across)
        else if (k === Qt.Key_Down) go(current < 0 ? 0 : current + across)
        else if ((k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) && current >= 0) opened(current)
        else if (k === Qt.Key_A && (event.modifiers & Qt.ControlModifier)) chosen = Array.from({ length: library.count }, (_, i) => i)
        else if (k === Qt.Key_P) mark("flag", 1)
        else if (k === Qt.Key_X) mark("flag", -1)
        else if (k === Qt.Key_U) mark("flag", 0)
        else if (k >= Qt.Key_0 && k <= Qt.Key_5) mark("stars", k - Qt.Key_0)
        else if (k >= Qt.Key_6 && k <= Qt.Key_9) mark("label", k - Qt.Key_5)
        else return false
        return true
    }
    Connections {
        target: library
        function onChanged() { if (root.current >= library.count) { root.current = -1; root.chosen = [] } }
    }

    // ---- Where to look ------------------------------------------------------------------
    // A section of the list: a line across, and its name in the color of text (dim, it read
    // as one more entry; the owner: "too dim to imply they mark a section").
    component Heading: Item {
        property alias text: words.text
        default property alias extra: beside.data
        width: parent ? parent.width : 0; height: 44
        Rectangle { y: 10; width: parent.width; height: 1; color: Theme.line }
        Label {
            id: words
            x: 10; y: 22; color: Theme.text
            font.pixelSize: Theme.smallSize; font.weight: Font.DemiBold; font.letterSpacing: 0.9
        }
        Item { id: beside; anchors { right: parent.right; rightMargin: 10 } y: 20; height: 18 }
    }
    component Place: Rectangle {
        id: place
        property string where
        property string name
        property int count: 0
        property bool there: true          // (a folder on a drive that is not connected is not)
        property bool removable: false
        signal removed()
        objectName: "place:" + where
        width: parent ? parent.width : 0; height: Theme.row; radius: 6
        color: library.where === where ? Theme.raised : over.containsMouse ? Qt.darker(Theme.raised, 1.25) : "transparent"
        Accessible.role: Accessible.ListItem; Accessible.name: name + ", " + count + " photos"
        Label {
            x: 10; anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 20 - tally.width - (leave.visible ? leave.width + 10 : 0) - 8; elide: Text.ElideMiddle
            text: place.name; color: !place.there ? Theme.faint : library.where === place.where ? Theme.text : Theme.dim
        }
        signal menuAsked(real x, real y)
        MouseArea {
            id: over
            anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: (mouse) => {
                if (mouse.button === Qt.RightButton) { const at = mapToItem(null, mouse.x, mouse.y); return place.menuAsked(at.x, at.y) }
                library.show(place.where); root.choose(library.rowLast())
            }
        }
        TextButton {
            id: leave
            objectName: "leave:" + place.where
            visible: place.removable && (over.containsMouse || containsPointer)
            anchors { right: tally.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
            text: "Remove"; onPressed: place.removed()
        }
        Label {
            id: tally
            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
            text: place.there ? place.count : "not there"; font.pixelSize: 12; font.features: { "tnum": 1 }; color: Theme.faint
        }
    }
    Rectangle {
        id: side
        objectName: "library-places"
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        width: 250; color: Theme.panel
        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.line }
        Scrollbar { id: placesBar; objectName: "places-bar"; of: placesList; step: 84; anchors { right: parent.right; rightMargin: 1; top: placesList.top; bottom: placesList.bottom } }
        Flickable {
            id: placesList
            anchors { fill: parent; margins: 8; rightMargin: 15 }
            contentHeight: list.height; clip: true
            boundsBehavior: Flickable.StopAtBounds; acceptedButtons: Qt.NoButton
            MouseArea { anchors.fill: parent; z: -1; acceptedButtons: Qt.NoButton; onWheel: (wheel) => placesBar.turned(wheel) }
            Column {
                id: list
                width: parent.width
                Place { where: "all"; name: "All photos"; count: root.places.all }
                Place { where: "edited"; name: "Edited"; count: root.places.edited }
                // (Adding one is the section's own action, at its head: as a line of text under
                // the last folder it read as one more folder; the owner: "looks awkward".)
                Heading {
                    text: "FOLDERS"
                    TextButton { objectName: "add-folder"; anchors.right: parent.right; text: "+ Add folder"; onPressed: root.folderAsked() }
                }
                Repeater {
                    model: root.places.folders
                    Place {
                        required property var modelData
                        where: modelData.id; name: modelData.name; count: modelData.count; there: modelData.there
                        removable: true; onRemoved: root.folderRemoveAsked(modelData.path)
                        onMenuAsked: (x, y) => root.folderMenuAsked(modelData.path, x, y)
                    }
                }
                Label {
                    visible: root.places.folders.length === 0
                    x: 10; height: Theme.row; verticalAlignment: Text.AlignVCenter; text: "None yet"; color: Theme.faint; font.pixelSize: 12
                }
                Heading { text: "MONTHS"; visible: root.places.months.length > 0 }
                Repeater {
                    model: root.places.months
                    Place { required property var modelData; where: modelData.id; name: modelData.name; count: modelData.count }
                }
                Heading { text: "CAMERAS"; visible: root.places.cameras.length > 0 }
                Repeater {
                    model: root.places.cameras
                    Place { required property var modelData; where: modelData.id; name: modelData.name; count: modelData.count }
                }
            }
        }
    }

    // ---- Which of them: the filter ---------------------------------------------------------
    component Chip: Rectangle {
        property bool on: false
        property alias text: words.text
        signal pressed()
        width: Math.max(30, words.implicitWidth + 16); height: 26; radius: 5
        color: on ? Theme.selected : press.containsMouse ? Theme.raised : "transparent"
        border { width: 1; color: on ? Theme.faint : Theme.line }
        Accessible.role: Accessible.CheckBox; Accessible.checked: on
        Label { id: words; anchors.centerIn: parent; font.pixelSize: 12; color: parent.on ? Theme.text : Theme.dim }
        MouseArea { id: press; anchors.fill: parent; hoverEnabled: true; onClicked: parent.pressed() }
    }
    Item {
        id: bar
        objectName: "library-filter"
        anchors { left: side.right; right: parent.right; top: parent.top; leftMargin: 16; rightMargin: 16 }
        height: 50
        Row {
            anchors.verticalCenter: parent.verticalCenter; spacing: 10
            Label { objectName: "text:place"; text: root.title(); color: Theme.text; font.pixelSize: 15; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
            Label { objectName: "text:count"; text: library.count; font.features: { "tnum": 1 }; anchors.verticalCenter: parent.verticalCenter }
        }
        Row {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 6
            Chip {   // on unless turned off: finished pictures (JPEG, PNG, TIFF) are not shown
                objectName: "filter:raw"; text: "Raw only"; on: root.filter.raw
                Accessible.name: on ? "Only raw files are shown" : "Raw files and finished pictures are shown"
                onPressed: library.setFilter("raw", !on)
            }
            Item { width: 8; height: 1 }
            Chip {
                objectName: "filter:pick"; text: "Picked"; on: root.filter.pick; Accessible.name: "Only picked photos"
                onPressed: library.setFilter("pick", !on)
            }
            Chip {   // each press asks for one star more; after five, none again
                objectName: "filter:stars"; on: root.filter.stars > 0; Accessible.name: "At least " + root.filter.stars + " stars"
                text: root.filter.stars > 0 ? "★ " + root.filter.stars + (root.filter.stars < 5 ? "+" : "") : "★ any"
                onPressed: library.setFilter("stars", (root.filter.stars + 1) % 6)
            }
            Repeater {
                model: 5
                Chip {
                    required property int index
                    objectName: "filter:label" + (index + 1); width: 26; on: root.filter.label === index + 1
                    Accessible.name: "Only photos with color " + (index + 1)
                    onPressed: library.setFilter("label", on ? 0 : index + 1)
                    Rectangle { anchors.centerIn: parent; width: 10; height: 10; radius: 5; color: root.labels[parent.index] }
                }
            }
            Chip {
                objectName: "filter:rejected"; text: "Rejected"; on: root.filter.rejected; Accessible.name: "Only rejected photos"
                onPressed: library.setFilter("rejected", !on)
            }
            Item { width: 8; height: 1 }
            Label { text: "Size"; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
            Chip { objectName: "smaller"; text: "−"; Accessible.name: "Smaller thumbnails"; onPressed: grid.cell = Math.max(120, grid.cell - 40) }
            Chip { objectName: "larger"; text: "+"; Accessible.name: "Larger thumbnails"; onPressed: grid.cell = Math.min(440, grid.cell + 40) }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
    }

    // ---- The photos ------------------------------------------------------------------------
    Scrollbar { id: gridBar; objectName: "library-bar"; of: grid; step: grid.cellHeight; anchors { right: parent.right; rightMargin: 1; top: grid.top; bottom: grid.bottom } }
    GridView {
        id: grid
        objectName: "library-grid"
        property real cell: 240
        anchors { left: side.right; right: parent.right; top: bar.bottom; bottom: parent.bottom; leftMargin: 12; topMargin: 8; rightMargin: 16 }
        // As many across as fit, each as wide as that leaves.
        readonly property int across: Math.max(1, Math.floor(width / cell))
        cellWidth: Math.floor(width / across); cellHeight: Math.round(cellWidth * 0.82)
        clip: true; boundsBehavior: Flickable.StopAtBounds; acceptedButtons: Qt.NoButton
        cacheBuffer: 600
        // The wheel: a row a notch (Qt's own step, three lines of text, is a third of a row
        // here: "pretty slow", the owner). Under the photos, which do not want the wheel.
        // (Put into what scrolls, behind the photos: there it comes before the view's own
        // handling. A grid's children are not put there by themselves, a Flickable's are.)
        // With Ctrl the wheel makes the thumbnails larger or smaller, a step of the − and +
        // buttons a notch (the owner's wish); parts of a notch (a touchpad) add up to one.
        MouseArea { parent: grid.contentItem; width: grid.width; height: Math.max(grid.height, grid.contentHeight); z: -1; acceptedButtons: Qt.NoButton; onWheel: (wheel) => grid.turned(wheel) }
        property real sizing: 0   // of the wheel with Ctrl, not yet a whole notch
        function turned(wheel) {
            if (!(wheel.modifiers & Qt.ControlModifier)) return gridBar.turned(wheel)
            sizing += wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.pixelDelta.y * 2
            const notches = Math.trunc(sizing / 120)
            sizing -= notches * 120
            if (notches) cell = Math.max(120, Math.min(440, cell + 40 * notches))
        }
        model: library.photos
        delegate: Item {
            id: cell
            required property int index
            required property string name
            required property string thumb
            required property string kind
            required property bool pair
            required property int flag
            required property int stars
            required property int label
            required property bool edited
            readonly property bool taken: root.chosen.includes(index)
            objectName: "photo:" + index
            width: grid.cellWidth; height: grid.cellHeight
            Accessible.role: Accessible.ListItem; Accessible.name: name
            Rectangle {
                anchors { fill: parent; margins: 3 }
                radius: 6; color: cell.taken ? Theme.selected : Theme.panel
                border { width: cell.index === root.current ? 1 : 0; color: Theme.text }
                Image {
                    id: shownThumb
                    anchors { fill: parent; margins: 8; topMargin: 26; bottomMargin: 26 }
                    // (Empty until the thumbnail has been made: asking for it puts it next in line.)
                    source: cell.thumb; asynchronous: true; fillMode: Image.PreserveAspectFit; retainWhileLoading: true
                    sourceSize: Qt.size(512, 512); opacity: cell.flag < 0 ? 0.3 : 1
                    Component.onCompleted: if (cell.thumb === "") library.want(cell.index)
                }
                EditedMark {   // on the picture's own corner, wherever that is in its slot
                    visible: cell.edited && shownThumb.paintedWidth > 1
                    x: shownThumb.x + (shownThumb.width + shownThumb.paintedWidth) / 2 - width - 5
                    y: shownThumb.y + (shownThumb.height + shownThumb.paintedHeight) / 2 - height - 5
                }
                Row {
                    x: 8; y: 6; spacing: 5
                    Label { text: cell.kind === "raw" ? (cell.pair ? "RAW + JPG" : "RAW") : ""; font.pixelSize: 10; font.letterSpacing: 0.6; color: Theme.faint }
                }
                Row {
                    anchors { right: parent.right; rightMargin: 8 } y: 5; spacing: 6
                    Label { objectName: "stars"; text: "★".repeat(cell.stars); font.pixelSize: 12; color: Theme.mark }
                    Label {
                        objectName: "flag"; visible: cell.flag !== 0; font.pixelSize: 10; font.weight: Font.DemiBold
                        text: cell.flag > 0 ? "PICK" : "REJECT"; color: cell.flag > 0 ? Theme.green : Theme.red
                    }
                }
                Rectangle {
                    visible: cell.label > 0
                    x: 8; anchors { bottom: parent.bottom; bottomMargin: 10 }
                    width: 10; height: 10; radius: 5; color: root.labels[Math.max(0, cell.label - 1)]
                }
                Label {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: cell.label > 0 ? 24 : 8; rightMargin: 8; bottomMargin: 6 }
                    text: cell.name; elide: Text.ElideMiddle; font.pixelSize: 12
                    color: cell.taken ? Theme.text : Theme.dim
                }
                MouseArea {
                    anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton
                    // (A right click is for all that is selected if this one is among them,
                    // and else selects this one alone, as file managers have it.)
                    onPressed: (mouse) => {
                        if (mouse.button === Qt.LeftButton) return root.pick(cell.index, mouse.modifiers & Qt.ControlModifier, mouse.modifiers & Qt.ShiftModifier)
                        if (!cell.taken) root.pick(cell.index, false, false)
                        const at = mapToItem(null, mouse.x, mouse.y)
                        root.menuAsked(root.chosen, at.x, at.y)
                    }
                    onDoubleClicked: (mouse) => { if (mouse.button === Qt.LeftButton) root.opened(cell.index) }
                }
            }
        }
    }
    Column {
        objectName: "library-empty"
        visible: library.count === 0
        anchors.centerIn: grid; spacing: 10
        Label {
            anchors.horizontalCenter: parent.horizontalCenter; color: Theme.text; font.pixelSize: 15
            text: library.busy ? "Looking through the folders…" : library.total === 0 ? "No photos in the library yet" : "No photo here passes the filter"
        }
        Label {
            objectName: "text:raw-only"
            anchors.horizontalCenter: parent.horizontalCenter; visible: library.total > 0 && !library.busy && root.filter.raw
            text: "“Raw only” is on: JPEG, PNG and TIFF pictures are not shown."
        }
        Label {
            anchors.horizontalCenter: parent.horizontalCenter; visible: library.total === 0 && !library.busy
            text: "Add a folder of photos. Nothing is copied or moved: Photone only reads them."
        }
        PushButton {
            objectName: "add-first"
            anchors.horizontalCenter: parent.horizontalCenter; visible: library.total === 0 && !library.busy
            label: "Add folder…"; onPressed: root.folderAsked()
        }
    }
}
