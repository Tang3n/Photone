import QtQuick
import QtQuick.Shapes
import QtQuick.Dialogs
import QtQuick.Effects
import "."

// The window. `session` (app.py) says what is open; everything drawn here follows from it.
Rectangle {
    id: root
    color: Theme.bg

    readonly property var edit: session.edit   // read once per change; the sliders share it
    // Which of the two places is on show: the library (the photos there are) or Edit (one of
    // them). Without a photo to edit, the program starts in the library.
    property string place: "edit"
    readonly property bool editing: place === "edit"
    Component.onCompleted: {
        place = session.source === "" ? "library" : "edit"
        library.rest(away)
        if (session.source === "") Qt.callLater(root.resume)
    }
    // Started without a photo named: where it was left. The library is at the place it was
    // at already (library.py); here the photo last looked at is selected, and opened in Edit
    // if that is where the window was.
    function resume() {
        const row = library.rowOf(library.lastPhoto)
        if (row < 0) return
        shelf.choose(row)
        if (session.panels.place === "edit") { session.openAt(library.paths(), row); root.show("edit") }
    }
    function show(where) {
        if (where === "library" && place !== "library") {
            session.flush()   // so that the library knows of the edit just made
            shelf.settle(library.paths().indexOf(session.path))
        }
        if (where === "export" && place !== "export") {
            // (What is selected where the page is come from, if that is more than one photo.)
            const all = library.paths()
            const taken = place === "library" ? shelf.chosen.map(row => all[row]) : filmstrip.chosen.map(i => session.fileAt(i))
            desk.photos = taken.length > 1 ? taken.filter(path => !!path) : []
        }
        place = where
        if (where !== "export") session.setPanel("place", where)   // (remembered for the next start)
        root.forceActiveFocus()
    }
    // The open photo's marks (the library keeps them), asked again whenever either changes.
    readonly property string openPath: session.path   // (asked at every change; another only with another photo)
    // While a photo is being edited the library rests: no scans, no thumbnails made.
    readonly property bool away: place !== "library"
    onAwayChanged: library.rest(away)
    readonly property bool photoReady: stage.ready
    readonly property bool photoFailed: session.failed

    // Keys reach here from wherever the focus is, unless a control used them itself.
    focus: true
    Keys.onPressed: (event) => {
        const ctrl = event.modifiers & Qt.ControlModifier, shift = event.modifiers & Qt.ShiftModifier
        if (ctrl && event.key === Qt.Key_1) return root.show("library")
        if (ctrl && event.key === Qt.Key_2) return root.show("edit")
        if (ctrl && event.key === Qt.Key_3) return root.show("export")
        if (root.place === "library") { shelf.key(event); return }
        if (root.place !== "edit") return
        // The arrows, held, go on through the photos (the owner: "hold left/right arrows to
        // quickly list through the filmstrip"); every other key acts once however long held.
        if (!ctrl && event.key === Qt.Key_Left) return session.step(-1)
        if (!ctrl && event.key === Qt.Key_Right) return session.step(1)
        if (event.isAutoRepeat) return
        // Marking the photo on show, as in the library: Edit is where a photo is looked at closely.
        if (!ctrl && event.key === Qt.Key_P) return library.markPhoto(session.path, "flag", 1)
        if (!ctrl && event.key === Qt.Key_X) return library.markPhoto(session.path, "flag", -1)
        if (!ctrl && event.key === Qt.Key_U) return library.markPhoto(session.path, "flag", 0)
        if (event.key >= Qt.Key_1 && event.key <= Qt.Key_5) return library.markPhoto(session.path, "stars", event.key - Qt.Key_0)
        if (event.key >= Qt.Key_6 && event.key <= Qt.Key_9) return library.markPhoto(session.path, "label", event.key - Qt.Key_5)
        if (event.key === Qt.Key_B) session.setOriginal(true)
        else if (event.key === Qt.Key_H) { if (wheel.selected >= 0) stage.reach = wheel.selected + 1; else stage.showMask = wheel.mask }
        else if (ctrl && event.key === Qt.Key_Z) shift ? session.redo() : session.undo()
        else if (ctrl && event.key === Qt.Key_Y) session.redo()
        else if (ctrl && event.key === Qt.Key_O) opener.open()
        else if (event.key === Qt.Key_T) root.toggle("tone")
        else if (event.key === Qt.Key_W) root.toggle("balance")
        else if (event.key === Qt.Key_S && !ctrl) root.toggle("saturation")
        else if (event.key === Qt.Key_C && !ctrl) root.toggle("crop")
        else if (event.key === Qt.Key_BracketLeft) session.turn(-1)
        else if (event.key === Qt.Key_BracketRight) session.turn(1)
        else if (event.key === Qt.Key_Backslash) stage.split = stage.split < 0 ? 0.5 : -1
        else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && session.panels.tool === "crop") session.setPanel("tool", "")
        else if (event.key === Qt.Key_F) wheel.glideFit()
        else if (event.key === Qt.Key_0) wheel.glideAll()
        else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) wheel.remove(wheel.selected)
        else if (event.key === Qt.Key_Escape && session.panels.tool === "crop") { session.undoTo(root.cropFrom); session.setPanel("tool", "") }
        else if (event.key === Qt.Key_Escape) { stage.picking = ""; wheel.deselect() }
    }
    // M16's trial, for renders the owner chooses from: every section in one scrolling column,
    // each folded to its header or open, the rail's buttons going to them. Off: as it was, the
    // rail opens one panel at a time over the wheel. (Whichever is chosen becomes the only way.)
    property bool sections: !trial.split(",").includes("old")
    // (Open at start: Light and White balance, where a photo is begun; the owner's choice.)
    property var unfolded: ({ tone: true, balance: true, about: true, histogram: true, folders: true })
    property bool masking: false       // the trial's Masks tab is the one on show
    readonly property string mode: !sections ? "" : session.panels.tool === "crop" ? "crop" : masking ? "masks" : "edit"
    function shows(tool) { return sections ? (tool === "crop" ? mode === "crop" : mode === "edit") : session.panels.tool === tool }
    function go(to) { masking = to === "masks"; session.setPanel("tool", to === "crop" ? "crop" : ""); if (to !== "masks") wheel.mask = 0 }
    function isOpen(tool) { return !sections || tool === "crop" ? session.panels.tool === tool || (tool === "wheel" && !sections) : unfolded[tool] === true }
    function fold(tool) {   // a section's header was pressed
        if (!sections || tool === "crop") return session.setPanel("tool", session.panels.tool === tool ? "" : tool)
        unfolded = Object.assign({}, unfolded, { [tool]: !unfolded[tool] })
        if (unfolded[tool]) { laidOut.tool = tool; laidOut.restart() }
    }
    // A card of the right column just opened is brought to the middle of the column, quickly
    // and smoothly; one higher than the column, to its top; never past the column's ends.
    // (A trial of the owner's: "i want to just test this".)
    function bringIn(tool) {
        const card = ({ tone: tonePanel, curve: curvePanel, balance: balancePanel, saturation: saturationPanel,
                        eq: eqPanel, chroma: chromaPanel, wheel: wheelBlock })[tool]
        if (!card || !card.visible) return
        const top = card.mapToItem(develop, 0, 0).y, high = card.height - 24, room = scroller.height
        const to = high > room - 20 ? top - 10 : top + high / 2 - room / 2
        bringing.to = Math.max(0, Math.min(Math.max(0, scroller.contentHeight - room), to))
        bringing.restart()
    }
    // (A moment later: the column has its new height only once the card is laid out.)
    Timer { id: laidOut; property string tool; interval: 30; onTriggered: root.bringIn(tool) }
    NumberAnimation { id: bringing; target: scroller; property: "contentY"; duration: 170; easing.type: Easing.OutCubic }
    function toggle(tool) {   // a tool was asked for, from the rail or by its key
        if (!sections) return fold(tool)
        if (!isOpen(tool)) fold(tool)
        const at = ({ tone: tonePanel, curve: curvePanel, balance: balancePanel, pins: pinPanel, crop: cropPanel,
                      saturation: saturationPanel, eq: eqPanel, chroma: chromaPanel })[tool]
        Qt.callLater(() => scroller.contentY = Math.max(0, Math.min(scroller.contentHeight - scroller.height, at.mapToItem(develop, 0, 0).y - 10)))
    }
    // Where undo stood when the Crop tool was opened: Esc goes back there.
    property int cropFrom: 0
    readonly property bool cropping: session.panels.tool === "crop"
    onCroppingChanged: if (cropping) cropFrom = session.steps
    Keys.onReleased: (event) => {
        if (event.isAutoRepeat) return
        if (event.key === Qt.Key_B) session.setOriginal(false)
        if (event.key === Qt.Key_H) { stage.reach = 0; stage.showMask = 0 }
    }
    // A key that is held when the window loses the keyboard is never let go here: let go for it.
    Window.onActiveChanged: if (!Window.active) { session.setOriginal(false); stage.reach = 0; stage.showMask = 0 }
    Connections {
        target: session
        // (The zoom, and where in the photo it is, stay as they are from one photo to the
        // next: two shots of the same thing are compared at the same place.)
        function onPhotoChanged() { stage.picking = ""; wheel.deselect(); wheel.mask = 0; library.lookingAt(session.path) }
        function onMasksChanged() { if (wheel.mask > session.masks.length) wheel.mask = 0 }
    }

    // Nothing is drawn until the surface is known (one frame): colors may depend on it. By
    // opacity, not visibility: an invisible item cannot hold the keyboard focus.
    opacity: session.ready ? 1 : 0
    Binding { target: Theme; property: "linear"; value: session.linearSurface }

    component NavButton: Rectangle {
        property string label
        property bool current: false
        property bool built: true
        signal pressed()
        objectName: "nav:" + label
        width: caption.implicitWidth + 24; height: 30; radius: 6
        color: current ? Theme.raised : "transparent"
        Accessible.role: Accessible.PageTab; Accessible.name: label
        Label {
            id: caption
            anchors.centerIn: parent; text: parent.label
            color: parent.current ? Theme.text : parent.built ? Theme.dim : Theme.faint
        }
        MouseArea { anchors.fill: parent; enabled: parent.built; onClicked: parent.pressed() }
    }
    // ---- Top bar -------------------------------------------------------------------------
    Rectangle {
        id: topBar
        objectName: "box:top"
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 44; color: Theme.panel

        Row {
            anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
            spacing: 20
            Row {
                spacing: 8; anchors.verticalCenter: parent.verticalCenter
                Image { source: "icon.svg"; sourceSize: Qt.size(20, 20); anchors.verticalCenter: parent.verticalCenter }
                Label { text: "Photone"; color: Theme.text; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
            }
            Row {
                spacing: 2; anchors.verticalCenter: parent.verticalCenter
                NavButton { label: "Library"; current: root.place === "library"; onPressed: root.show("library") }
                NavButton { label: "Edit"; current: root.editing; onPressed: root.show("edit") }
                NavButton { label: "Export"; current: root.place === "export"; onPressed: root.show("export") }
            }
        }
        Row {
            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
            spacing: 14
            // The photo, or a test chart in its place with the photo's edit on it: to see what
            // an edit does to every hue and to a row of grays. Said loudly while it is on
            // (the bar over the picture), and never on by itself.
            Rectangle {
                objectName: "chartSwitch"
                visible: session.source !== "" && root.editing
                width: chartSides.width + 4; height: 30; radius: 7; color: Theme.raised
                anchors.verticalCenter: parent.verticalCenter
                Row {
                    id: chartSides
                    anchors.centerIn: parent
                    Segment { objectName: "show-photo"; width: 60; label: "Photo"; on: !session.panels.chart; onChosen: session.setPanel("chart", false) }
                    Segment { objectName: "show-chart"; width: 84; label: "Test chart"; on: session.panels.chart; onChosen: session.setPanel("chart", true) }
                }
            }
            // SDR or HDR: how the photo is drawn. HDR lets highlights go above the white of the
            // interface. Instant: only the photo changes. Dimmed where the window has no HDR
            // surface; choosing it there says why.
            Rectangle {
                objectName: "hdrSwitch"
                width: 2 * 52 + 4; height: 30; radius: 7; color: Theme.raised
                anchors.verticalCenter: parent.verticalCenter
                Row {
                    anchors.centerIn: parent
                    Segment { label: "SDR"; on: !session.hdr; onChosen: session.setHdr(false) }
                    Segment { label: "HDR"; on: session.hdr; available: session.hdrSurface; onChosen: session.setHdr(true) }
                }
            }
        }
        Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: Theme.line }
    }

    // ---- The foot: what the program is and who made it -----------------------------------
    // (The owner: "add back the footer at the very bottom of the window to offset everything
    // up a little", with the version, "Made by Morphox", "View on GitHub". Nothing about the
    // photo is said here: that is the left panel's and the tip's.)
    Rectangle {
        id: foot
        objectName: "box:foot"
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 26; color: Theme.panel
        Rectangle { width: parent.width; height: 1; color: Theme.line }
        Label {
            objectName: "text:version"
            anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
            text: "Version " + session.version; font.pixelSize: 12; color: Theme.dim
        }
        TextButton {   // an export, wherever it was started: how far it is, then what came of it
            objectName: "foot-export"
            visible: exporter.running || exporter.total > 0 || exporter.failures.length > 0
            anchors { left: parent.left; leftMargin: 130; verticalCenter: parent.verticalCenter }
            font.pixelSize: 12; says: "Export"
            readonly property int done: exporter.finished - exporter.failures.length
            text: exporter.running ? "Exporting " + Math.min(exporter.total, exporter.finished + 1) + " of " + exporter.total + "…"
                : done + " exported" + (exporter.failures.length ? ", " + exporter.failures.length + " failed" : "")
            onPressed: root.show("export")
        }
        Label {   // what the program is using (the owner's wish), read every two seconds
            objectName: "text:usage"
            anchors.centerIn: parent
            text: usage.text; font.pixelSize: 12; font.features: { "tnum": 1 }; color: Theme.faint
        }
        Row {
            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
            spacing: 14
            // (Links: the author's page on GitHub, and the project's, with GitHub's mark.)
            TextButton {
                objectName: "foot-author"
                anchors.verticalCenter: parent.verticalCenter
                text: "Made by Morphox"; font.pixelSize: 12
                Accessible.role: Accessible.Link
                onPressed: Qt.openUrlExternally(session.homepage.replace(/\/[^\/]+\/?$/, ""))   // (the account the project is under)
            }
            Rectangle { width: 1; height: 12; color: Theme.line; anchors.verticalCenter: parent.verticalCenter }
            TextButton {
                objectName: "foot-github"
                anchors.verticalCenter: parent.verticalCenter
                text: "View on GitHub"; font.pixelSize: 12; rightPadding: 20
                Accessible.role: Accessible.Link
                onPressed: Qt.openUrlExternally(session.homepage)
                Icon {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    width: 14; height: 14; units: 24; filled: true; color: parent.color
                    // GitHub's mark (its own drawing, for a link to GitHub).
                    path: "M12 .297c-6.63 0-12 5.373-12 12 0 5.303 3.438 9.8 8.205 11.385.6.113.82-.258.82-.577 0-.285-.01-1.04-.015-2.04-3.338.724-4.042-1.61-4.042-1.61C4.422 18.07 3.633 17.7 3.633 17.7c-1.087-.744.084-.729.084-.729 1.205.084 1.838 1.236 1.838 1.236 1.07 1.835 2.809 1.305 3.495.998.108-.776.417-1.305.76-1.605-2.665-.3-5.466-1.332-5.466-5.93 0-1.31.465-2.38 1.235-3.22-.135-.303-.54-1.523.105-3.176 0 0 1.005-.322 3.3 1.23.96-.267 1.98-.399 3-.405 1.02.006 2.04.138 3 .405 2.28-1.552 3.285-1.23 3.285-1.23.645 1.653.24 2.873.12 3.176.765.84 1.23 1.91 1.23 3.22 0 4.61-2.805 5.625-5.475 5.92.42.36.81 1.096.81 2.22 0 1.606-.015 2.896-.015 3.286 0 .315.21.69.825.57C20.565 22.092 24 17.592 24 12.297c0-6.627-5.373-12-12-12"
                }
            }
        }
    }

    // A list in a dark box has no scrollbar: the bar took a strip off every row (the owner: "i
    // hate how ... the content is offset by the scrollbar size"). That there is more below
    // is said by the last rows fading out at the box's foot, until the list is at its end.
    // (`above`: the same at the box's head, for what lies over the first row in sight; the
    // checkpoints' list stands at its end, the newest, so what it hides is above.)
    component MoreBelow: Rectangle {
        property Flickable of
        property bool above: false
        property color ground: Theme.bg   // what the rows stand on, and fade into
        readonly property real gone: of ? of.contentY - of.originY : 0
        // How strong it is goes by how far there is still to scroll that way: full with its
        // own height or more to go, less and less over the last of the way, nothing at the
        // end (the owner: "they should fade with scroll distance"). `wanted`: whether at all.
        property bool wanted: true
        readonly property real togo: !of ? 0 : above ? gone : of.contentHeight - of.height - gone
        opacity: wanted ? Math.max(0, Math.min(1, togo / height)) : 0; visible: opacity > 0
        height: 30
        gradient: Gradient {
            GradientStop { position: above ? 1 : 0; color: Qt.rgba(ground.r, ground.g, ground.b, 0) }
            GradientStop { position: above ? 0 : 1; color: ground }
        }
    }

    // The profile (what only a raw file has: how the sensor's data becomes a picture), and
    // under it what it is. On the new screen it stands over all the cards of Adjust (the
    // owner's choice of two renders: there, or in the Exposure card over the histogram); on
    // the old one, in the Tone panel.
    component ProfileRow: Column {
        width: parent ? parent.width : 0
        Item {  // what only a raw file has: how the sensor's data becomes a picture
            objectName: "profile"
            width: parent.width; height: 34; visible: session.develops
            Label {
                // (Bold, in the color of text; yellow while it is changed and in no checkpoint, as
                // the sliders are: the owner's wish.)
                anchors.verticalCenter: parent.verticalCenter; text: "Profile"; font.weight: Font.DemiBold
                color: session.unsavedKeys.includes("profile") ? Theme.yellow : Theme.text
            }
            Rectangle {
                width: profiles.width + 4; height: 24; radius: 6; color: Theme.raised
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                Row {
                    id: profiles
                    anchors.centerIn: parent
                    Segment { width: 76; height: 20; label: "Standard"; on: root.edit.profile === "standard"; onChosen: { session.setEdit("profile", "standard"); session.commitEdit() } }
                    Segment { width: 76; height: 20; label: "Flat"; on: root.edit.profile === "flat"; onChosen: { session.setEdit("profile", "flat"); session.commitEdit() } }
                }
            }
        }
        // (The owner: "i dont understand what the profiles ... actually change and
        // where they come from". Said under them, in the fewest words.)
        Label {
            objectName: "profile-words"
            visible: session.develops
            width: parent.width; height: implicitHeight + 8; wrapMode: Text.WordWrap; font.pixelSize: 12; color: Theme.faint
            // (What a profile is, and on a line of its own what this one is, its name in bold:
            // the owner's wish.)
            textFormat: Text.StyledText
            readonly property string name: root.edit.profile === "flat" ? "Flat" : "Standard"
            readonly property string what: root.edit.profile === "flat" ? "softer and darker in the midtones, room for a grade of your own."
                                                                        : "fitted to look like the camera's own JPEG."
            text: "The base contrast before any slider.<br><b>" + name + "</b>: " + what
        }
    }

    // ---- Adjustments ---------------------------------------------------------------------
    component EditSlider: ParamSlider {
        property string key   // the setting in the photo's edit (photone/edit.py)
        objectName: "slider:" + key
        width: parent.width
        value: root.edit[key]
        unsaved: session.unsavedKeys.includes(key)
        onMoved: (v) => session.setEdit(key, v)
        onReleased: session.commitEdit()
        // Where a double click puts it: the edit's own rest, or `rest` where that is not
        // what the slider's zero is (Exposure: see there).
        property var rest
        onReset: {
            if (rest === undefined) return session.resetEdit(key)
            session.commitEdit(); session.setEdit(key, rest); session.commitEdit()
        }
        onTyped: root.forceActiveFocus()
    }
    // The side panels' widths: dragged by their inner edges (the owner: "both the left and
    // right panels resizable (with some minimal width and max until 1/3 of the window for
    // safety)"), remembered; a double click on an edge puts it back. Asked 0: the usual width.
    property real leftAsked: Number(session.remembered("view/left", "0")) || 0
    property real rightAsked: Number(session.remembered("view/right", "0")) || 0
    readonly property real leftWide: Math.round(Math.max(220, Math.min(width / 3, leftAsked > 0 ? leftAsked : 276)))
    readonly property real rightWide: Math.round(Math.max(340, Math.min(width / 3, rightAsked > 0 ? rightAsked
                                                                         : Math.max(360, Math.min(520, width * 0.3)))))
    component PaneEdge: MouseArea {
        property int way: 1   // 1: the left panel's right edge; -1: the right column's left edge
        property real from
        property real start
        width: 6; hoverEnabled: true; cursorShape: Qt.SizeHorCursor
        Rectangle { anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; bottom: parent.bottom } width: 2; color: Theme.dim; visible: parent.containsMouse || parent.pressed }
        onPressed: (mouse) => { from = mapToItem(root, mouse.x, 0).x; start = way > 0 ? root.leftWide : root.rightWide }
        onPositionChanged: (mouse) => {
            if (!pressed) return
            const wide = start + way * (mapToItem(root, mouse.x, 0).x - from)
            if (way > 0) root.leftAsked = wide; else root.rightAsked = wide
        }
        function keep() {
            session.remember(way > 0 ? "view/left" : "view/right", String(Math.round(way > 0 ? root.leftAsked : root.rightAsked)))
        }
        onReleased: { if (way > 0) root.leftAsked = root.leftWide; else root.rightAsked = root.rightWide; keep() }
        onDoubleClicked: { if (way > 0) root.leftAsked = 0; else root.rightAsked = 0; keep() }
    }
    // A switch on a row of its own: its name, and on the right a track with a knob. The whole
    // row takes the click; `flipped` asks for the other state, which the owner of `on` sets.
    component OnOff: Item {
        id: onOff
        property string label
        property bool on: false
        signal flipped()
        width: parent ? parent.width : 0; height: 34
        Accessible.role: Accessible.CheckBox; Accessible.name: label; Accessible.checked: on
        Label { anchors.verticalCenter: parent.verticalCenter; text: onOff.label; color: onOff.on ? Theme.text : Theme.dim }
        Rectangle {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            width: 36; height: 20; radius: 10
            color: onOff.on ? Theme.mark : Theme.bg; border { width: 1; color: onOff.on ? Theme.mark : Theme.faint }
            Rectangle {
                x: onOff.on ? parent.width - width - 3 : 3; anchors.verticalCenter: parent.verticalCenter
                width: 14; height: 14; radius: 7; color: onOff.on ? Theme.bg : Theme.dim
                Behavior on x { NumberAnimation { duration: 90 } }
            }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: onOff.flipped() }
    }
    // A setting of what the chosen mask changes inside it (edit.LOCAL): an amount added to the
    // whole image's, nothing at rest.
    readonly property var localEdit: wheel.mask > 0 && wheel.mask <= session.masks.length ? (session.masks[wheel.mask - 1].edit || {}) : ({})
    // (Which of these settings the chosen mask has of its own, and taking them away again.)
    function leaveMask() { wheel.mask = 0 }
    // What a mask is called: the name it was given, or its kind and its place in the list.
    function maskName(number) {
        const mask = session.masks[number - 1]
        return !mask ? "Mask" : mask.name || ({ radial: "Radial ", linear: "Linear ", brush: "Brush " })[mask.kind] + number
    }
    // A name being typed in a list's row, in the name's place: Enter or leaving the field
    // takes it (docs/PLAN.md §5), Escape does not. (The owner: "rename masks and checkpoints".)
    component NameEntry: Rectangle {
        id: nameEntry
        signal taken(string name)
        function begin(name) { field.text = name; visible = true; field.forceActiveFocus(); field.selectAll() }
        function end(keep) {
            if (!visible) return
            visible = false
            if (keep && field.text.trim() !== "") taken(field.text.trim())
            root.forceActiveFocus()
        }
        visible: false
        height: 22; radius: 4; color: Theme.bg; border { width: 1; color: Theme.text }
        TextInput {
            id: field
            objectName: "name-entry"
            anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
            verticalAlignment: TextInput.AlignVCenter; clip: true; maximumLength: 40
            color: Theme.text; selectionColor: Theme.faint; selectedTextColor: Theme.text
            font.family: Theme.font; font.pixelSize: Theme.fontSize
            Accessible.name: "Name"
            // (Its keys are its own: Enter is not the window's, the arrows not the photos'.)
            Keys.onReturnPressed: (event) => { nameEntry.end(true); event.accepted = true }
            Keys.onEnterPressed: (event) => { nameEntry.end(true); event.accepted = true }
            Keys.onEscapePressed: (event) => { nameEntry.end(false); event.accepted = true }
            onActiveFocusChanged: if (!activeFocus) nameEntry.end(true)
        }
    }
    function localHas(keys) { return keys.some(key => root.localEdit[key] !== undefined) }
    component LocalCard: Panel {
        property var keys: []
        local: true; closes: false; changed: root.localHas(keys)
        visible: root.mode === "masks" && maskRow.mask !== null
        onReset: session.resetMaskEdit(wheel.mask, keys)
    }
    component LocalSlider: ParamSlider {
        property string key
        objectName: "local:" + key
        width: parent.width
        neutral: 0; signed: true
        value: root.localEdit[key] || 0
        onMoved: (v) => session.setMaskEdit(wheel.mask, key, v)
        onReleased: session.commitEdit()
        onReset: { session.setMaskEdit(wheel.mask, key, 0); session.commitEdit() }
        onTyped: root.forceActiveFocus()
    }
    component PinSlider: ParamSlider {
        property string key   // a setting of the pin being worked on (edit.PIN)
        objectName: "pin:" + key
        width: parent.width
        // (There with no pin too, dimmed: the section keeps its height, see panel:pins.)
        enabled: pinPanel.has; opacity: enabled ? 1 : 0.35
        value: pinPanel.has ? pinPanel.shown[key] : neutral
        onMoved: (v) => wheel.change(wheel.place(), { [key]: v })
        onReleased: session.commitEdit()
        onReset: { wheel.change(wheel.place(), { [key]: neutral }); session.commitEdit() }
        onTyped: root.forceActiveFocus()
    }
    // Going to a checkpoint puts its edit in place of the present one. Where the present one is
    // in no checkpoint, that would lose it: ask first.
    function goTo(point) {
        if (point.state === "here") return
        if (!session.unsaved) return session.goToCheckpoint(point.id)
        confirm.ask("Discard the changes?",
                    "This photo has changes that are in no checkpoint. Going to “" + point.name + "” discards them.",
                    "Discard changes", () => session.goToCheckpoint(point.id))
    }
    // The trial: a column left of the photo, which then stands between the two (the owner:
    // "maybe we should also have a left-side panel so that the image we're editing is in the
    // middle and we can put checkpoints at the bottom there", "maybe folder selection could be
    // the main purpose of that left panel"). Where the photos come from and what tells about
    // the open one are here; what changes it is on the right.
    Rectangle {
        id: leftPane
        objectName: "box:left"
        visible: root.editing && root.sections && session.source !== ""
        anchors { left: parent.left; top: topBar.bottom; bottom: foot.top }
        width: root.leftWide; color: Theme.panel
        PaneEdge { objectName: "left-edge"; anchors { right: parent.right; top: parent.top; bottom: parent.bottom } way: 1 }
        Rectangle { anchors { right: parent.right; top: parent.top; bottom: parent.bottom } width: 1; color: Theme.line }
        readonly property var places: library.places
        // A window too low for all of it: the cards over Checkpoints are folded for as long
        // as it is, the Photo card first and Folders last, only when
        // even its two rows have no room (the owner's rule). What the user had open is not
        // forgotten: with room again, it is open again.
        property real aboutHigh: 250   // the Photo card open, as last measured
        readonly property var fits: {
            const room = points.y - 16, folded = 46
            const need = (p, f) => (p ? aboutHigh : folded) + (f ? 138 : folded)
            let p = root.unfolded.about === true, f = root.unfolded.folders === true
            if (need(p, f) > room) p = false
            if (need(p, f) > room) f = false
            return { about: p, folders: f }
        }
        // Where the photos come from: the library's folders, as a list in a dark box like the
        // masks' and the checkpoints' (more by the wheel), right over Checkpoints
        // (the owner: "a scrollable list just like the others ... right above checkpoints").
        Panel {
            id: foldersCard
            objectName: "panel:folders"
            title: "Folders"; card: "folders"
            visible: points.visible
            // From under the cards above down to Checkpoints, whatever room that is (the
            // owner: "resize dynamically to fill the space above"); never under two rows.
            // (It folds too. It stands under the cards above it like any card, and open it
            // reaches down to Checkpoints; the owner: "anchored to the top like the other
            // cards and size toward the bottom".)
            folds: true; open: leftPane.fits.folders; onFold: root.fold("folders")
            x: 16; width: parent.width - 32; y: leftTop.y + leftTop.height
            readonly property real boxHigh: Math.max(2 * Theme.row + 8, points.y + 16 - 74 - (leftTop.y + leftTop.height))
            Rectangle {
                objectName: "folder-list"
                width: parent.width; height: foldersCard.boxHigh; radius: 6; color: Theme.bg; border { width: 1; color: Theme.line }
                ListView {
                    id: folderList
                    anchors { fill: parent; margins: 4 }
                    clip: true; boundsBehavior: Flickable.StopAtBounds; acceptedButtons: Qt.NoButton
                    model: [{ id: "all", name: "All photos", count: leftPane.places.all || 0 }].concat(leftPane.places.folders || [])
                    MouseArea { parent: folderList.contentItem; width: folderList.width; height: Math.max(folderList.height, folderList.contentHeight); z: -1; acceptedButtons: Qt.NoButton; onWheel: (wheel) => folderBar.turned(wheel) }
                    delegate: Rectangle {
                        required property var modelData
                        width: folderList.width; height: Theme.row; radius: 5
                        color: library.where === modelData.id ? Theme.selected : overPlace.containsMouse ? Theme.raised : "transparent"
                        Accessible.role: Accessible.ListItem; Accessible.name: modelData.name + ", " + modelData.count + " photos"
                        Label {
                            x: 10; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 60; elide: Text.ElideMiddle
                            text: modelData.name; color: library.where === modelData.id ? Theme.text : Theme.dim
                        }
                        Label {
                            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            text: modelData.count; font.pixelSize: 12; font.features: { "tnum": 1 }; color: Theme.faint
                        }
                        MouseArea {
                            id: overPlace
                            anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.LeftButton | Qt.RightButton
                            // (The folder's photos become the filmstrip; the open photo is the one last looked at there.)
                            onClicked: (mouse) => {
                                if (mouse.button === Qt.RightButton) {
                                    const at = mapToItem(null, mouse.x, mouse.y)
                                    if (modelData.path) menu.openFolder(modelData.path, at.x, at.y)
                                    return
                                }
                                library.show(modelData.id); if (library.count > 0) session.openAt(library.paths(), Math.max(0, library.rowLast()))
                            }
                        }
                    }
                }
                Scrollbar { id: folderBar; of: folderList; step: Theme.row; visible: false }   // (what the wheel scrolls it by)
                MoreBelow { of: folderList; x: 1; width: parent.width - 2; anchors { bottom: parent.bottom; bottomMargin: 1 } radius: 5 }
                MoreBelow { above: true; of: folderList; x: 1; y: 1; width: parent.width - 2; radius: 5 }
            }
        }
        Column {
            id: leftTop
            // (The first card as far from the bar above as from the panel's sides: 6 px.)
            x: 16; y: 14; width: parent.width - 32; spacing: 0
            // What the photo is (the owner: "information about the photo.. metadata and file
            // information in a neat way"): its name and when it was taken; how it was exposed,
            // the four numbers side by side as a camera shows them; with what; how large; where.
            // Only what the file says; nothing is labelled that reads plainly by itself.
            Panel {
                id: aboutCard
                objectName: "panel:about"
                title: "Photo"; card: "photo"
                // (It folds, as the right column's cards do: the owner's wish.
                // Folded, Folders under them has their room.)
                folds: true; open: leftPane.fits.about; onFold: root.fold("about")
                onHeightChanged: if (open && height > 60) leftPane.aboutHigh = height
                readonly property var facts: session.about
                readonly property var exposed: [facts.shutter, facts.aperture, facts.iso, facts.focal].filter(w => w)
                readonly property string picture: session.fullWidth > 0
                    ? session.fullWidth + " × " + session.fullHeight + "  ·  " + (session.fullWidth * session.fullHeight / 1e6).toFixed(1) + " MP" : ""
                Label {
                    objectName: "about:file"
                    width: parent.width; elide: Text.ElideMiddle
                    text: aboutCard.facts.file || ""; color: Theme.text; font.pixelSize: 14; font.weight: Font.DemiBold
                }
                Label {
                    width: parent.width; topPadding: 2; elide: Text.ElideRight
                    text: aboutCard.facts.taken || ""; font.pixelSize: 12; color: Theme.dim
                }
                Item { width: 1; height: 12 }
                Rectangle {   // the exposure: shutter, aperture, ISO, focal length
                    objectName: "about:exposure"
                    visible: aboutCard.exposed.length > 0
                    width: parent.width; height: 44; radius: 7; color: Theme.bg; border { width: 1; color: Theme.line }
                    Row {
                        anchors.fill: parent
                        Repeater {
                            model: aboutCard.exposed
                            Item {
                                required property string modelData
                                required property int index
                                width: parent.width / aboutCard.exposed.length; height: parent.height
                                Rectangle { visible: index > 0; width: 1; height: parent.height - 16; anchors.verticalCenter: parent.verticalCenter; color: Theme.line }
                                Label {
                                    anchors.centerIn: parent; text: modelData; color: Theme.text
                                    font.pixelSize: 13; font.features: { "tnum": 1 }
                                }
                            }
                        }
                    }
                }
                Label {
                    visible: text !== ""
                    width: parent.width; topPadding: 6; horizontalAlignment: Text.AlignRight
                    text: aboutCard.facts.bias ? "Exposure compensation " + aboutCard.facts.bias : ""; font.pixelSize: 11; color: Theme.dim
                }
                Item { width: 1; height: 12; visible: aboutCard.exposed.length > 0 }
                Label {
                    visible: text !== ""
                    width: parent.width; elide: Text.ElideRight
                    text: aboutCard.facts.camera || ""; font.pixelSize: 13; color: Theme.text
                }
                Label {
                    visible: text !== ""
                    width: parent.width; topPadding: 2; elide: Text.ElideRight
                    text: aboutCard.facts.lens || ""; font.pixelSize: 12; color: Theme.dim
                }
                Item { width: 1; height: 12 }
                Label {
                    width: parent.width; elide: Text.ElideRight
                    text: [aboutCard.picture, aboutCard.facts.size].filter(w => w).join("  ·  "); font.pixelSize: 12; color: Theme.dim
                }
                Label {
                    width: parent.width; topPadding: 2; elide: Text.ElideMiddle
                    text: aboutCard.facts.folder || ""; font.pixelSize: 11; color: Theme.faint
                }
            }
        }
    }
    Rectangle {
        id: tools
        objectName: "box:tools"
        anchors { right: parent.right; top: topBar.bottom; bottom: foot.top }
        visible: root.editing
        // Wide enough for the wheel, which is the main thing in it, without taking the photo's place.
        width: root.rightWide; color: Theme.panel
        PaneEdge { objectName: "right-edge"; anchors { left: parent.left; top: parent.top; bottom: parent.bottom } way: -1; z: 3 }
        Rectangle { anchors { left: parent.left; top: parent.top; bottom: parent.bottom } width: 1; color: Theme.line }
        // Everything but the checkpoints: it scrolls (by the wheel) when the window is too low
        // for it. A drag never scrolls: it belongs to the slider, curve or pad under it.
        // (Over the cards: a card's ground reaches a little past the column, onto the bar.)
        Scrollbar { id: toolsBar; objectName: "tools-bar"; of: scroller; step: 150; visible: !root.sections && reach > 0.5; x: scroller.x + scroller.width + 1; y: scrollArea.y; height: scroller.height; z: 2 }
        // (No scrollbar on the new screen: that there is more below, or above, is said as in
        // the lists, by the cards fading out at that edge; the owner's wish.)
        MoreBelow { objectName: "tools-more"; wanted: root.sections; of: scroller; ground: Theme.bg; z: 2; height: 120; x: 1; width: parent.width - 1; anchors.bottom: parent.bottom }   // (long and into the dark of the window, to be plain: the owner's wish)
        MoreBelow { above: true; wanted: root.sections; of: scroller; ground: Theme.panel; z: 2; height: 28; x: 1; width: parent.width - 1; y: scrollArea.y }
        Item {   // (what scrolls is cut off above and below, but a section's ground reaches to the column's sides)
        id: scrollArea
        anchors { left: parent.left; right: parent.right; top: parent.top; bottom: root.sections ? parent.bottom : points.top; topMargin: 12 }
        clip: true
        Flickable {
            id: scroller
            objectName: "tools-scroll"
            anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
            // (The last card ends as far above the panel's foot as the cards are from its
            // sides, 6 px: a card's own foot leaves 18 below it open, 10 folded.)
            readonly property real tail: (root.mode === "edit" || (root.mode === "masks" && wheel.mask > 0)) && !wheelBlock.open ? 10 : 18
            contentHeight: develop.height - (root.sections ? tail - 6 : 0)
            // (Never left scrolled past its end when what it holds gets shorter, and at its top
            // when another tab is chosen: it showed nothing, and nothing there took a click.)
            onContentHeightChanged: contentY = Math.max(0, Math.min(contentY, contentHeight - height))
            Connections { target: root; function onModeChanged() { scroller.contentY = 0 } }
            boundsBehavior: Flickable.StopAtBounds; acceptedButtons: Qt.NoButton
            // (Under everything that scrolls here: the wheel, where nothing else wants it.)
            MouseArea { anchors.fill: parent; z: -1; acceptedButtons: Qt.NoButton; onWheel: (wheel) => { scrolling.restart(); toolsBar.turned(wheel) } }
            Timer { id: scrolling; interval: 400 }   // the column was scrolled a moment ago
        Column {
            id: develop
            width: parent.width
            spacing: 0
            Item {
                width: parent.width; height: 32
                Row {
                    spacing: 14
                    // (Signs on the new screen, white when they can be pressed: the owner's wish.)
                    TextButton {
                        objectName: "undo"; says: "Undo"; available: session.canUndo; onPressed: session.undo()
                        text: root.sections ? "" : "Undo"; sign: root.sections ? "M7.5 4.5 L3.5 8.5 L7.5 12.5 M3.5 8.5 H12 A4.25 4.25 0 0 1 12 17 H9" : ""
                        strong: root.sections; width: root.sections ? 20 : implicitWidth; height: root.sections ? 20 : implicitHeight
                    }
                    TextButton {
                        objectName: "redo"; says: "Redo"; available: session.canRedo; onPressed: session.redo()
                        text: root.sections ? "" : "Redo"; sign: root.sections ? "M12.5 4.5 L16.5 8.5 L12.5 12.5 M16.5 8.5 H8 A4.25 4.25 0 0 0 8 17 H11" : ""
                        strong: root.sections; width: root.sections ? 20 : implicitWidth; height: root.sections ? 20 : implicitHeight
                    }
                }
                TextButton {
                    objectName: "reset-all"
                    anchors.right: parent.right
                    // (Red while there is something to reset, as Delete is: the owner's wish.)
                    text: "Reset all"; danger: root.sections; available: session.edited; onPressed: session.resetAll()
                }
                Rectangle { y: 25; width: parent.width; height: 1; color: Theme.line }
                Item { width: 1; height: 8 }
            }
            Item { width: 1; height: 8 }
            // The trial: what the column is showing. Adjust is the photo's sections, in the order
            // a photo is worked on; Masks is a part of the picture with settings of its own;
            // Crop is the frame. (The owner: "we need a Mask tab", "the Lightroom approach".)
            Rectangle {
                objectName: "modes"
                visible: root.sections && session.source !== ""
                // (As high as the Tone Wheel's row of tones: the owner's wish.)
                width: parent.width; height: 38; radius: 7; color: Theme.raised
                Row {
                    x: 2; y: 2
                    Repeater {
                        model: [["edit", "Adjust"], ["masks", "Masks"], ["crop", "Crop"]]
                        Segment {
                            required property var modelData
                            objectName: "mode:" + modelData[0]
                            width: (develop.width - 4) / 3; height: 34; label: modelData[1]
                            on: root.mode === modelData[0]; onChosen: root.go(modelData[0])
                        }
                    }
                }
            }
            // (Less under the tabs where the profile's row follows, which has room of its own
            // round its words: the two gaps, over it and under it, then look alike.)
            Item { width: 1; height: root.mode === "edit" && session.develops ? 8 : 16; visible: root.sections }
            ProfileRow { visible: root.sections && root.mode === "edit" && session.source !== "" }
            Item { width: 1; height: 14; visible: root.sections && root.mode === "edit" && session.develops }
            // The masks, as a list and nothing else; whatever can be set of the one chosen is
            // in the cards under it (the owner: "it just needs to be a list of masks and ANY
            // settings (including feather) should be in the other cards below").
            Panel {
                objectName: "panel:masks"
                title: "Masks"; card: "masks"; visible: root.mode === "masks" && session.source !== ""
                // (A box darker than the card, to read as a list; five rows high, more by
                // scrolling: the owner's wish.)
                Rectangle {
                    objectName: "mask-list"
                    width: parent.width; height: 5 * Theme.row + 8; radius: 6; color: Theme.bg; border { width: 1; color: Theme.line }
                    ListView {
                        id: maskList
                        anchors { fill: parent; margins: 4 }
                        clip: true; boundsBehavior: Flickable.StopAtBounds; acceptedButtons: Qt.NoButton
                        model: session.masks.length
                        // (Under the rows: the wheel scrolls the list, and a click on its empty
                        // part lets go of the mask. `wheel` in here is this area's own signal.)
                        MouseArea { parent: maskList.contentItem; width: maskList.width; height: Math.max(maskList.height, maskList.contentHeight); z: -1; onWheel: (wheel) => maskBar.turned(wheel); onClicked: root.leaveMask() }
                        delegate: Rectangle {
                            required property int index
                            readonly property bool chosen: wheel.mask === index + 1
                            objectName: "mask-item:" + (index + 1)
                            width: maskList.width; height: Theme.row; radius: 5
                            color: chosen ? Theme.selected : overMask.containsMouse ? Theme.raised : "transparent"
                            id: maskItem
                            readonly property bool off: (session.masks[index] || {}).off === true
                            Accessible.role: Accessible.ListItem; Accessible.name: maskName.text; Accessible.selected: chosen
                            Label {
                                id: maskName
                                x: 34; anchors.verticalCenter: parent.verticalCenter; color: maskItem.off ? Theme.faint : parent.chosen ? Theme.text : Theme.dim
                                width: parent.width - x - (renameMask.visible ? renameMask.width + 16 : 8); elide: Text.ElideRight
                                visible: !maskEntry.visible
                                text: (session.masks, root.maskName(index + 1))
                            }
                            // (Not set from inside the MouseArea: there `wheel` is its own signal.)
                            function choose() { wheel.mask = index + 1 }
                            // A click chooses it, a second one names it.
                            MouseArea { id: overMask; anchors.fill: parent; hoverEnabled: true; onClicked: parent.choose(); onDoubleClicked: maskEntry.begin(maskName.text) }
                            // The eye: the mask on or off, without losing anything of it (the
                            // owner: "an eye button for each mask in the list").
                            Item {
                                objectName: "mask-eye:" + (index + 1)
                                x: 4; width: 26; height: parent.height
                                Accessible.role: Accessible.CheckBox; Accessible.name: "Mask is on"; Accessible.checked: !maskItem.off
                                Icon {
                                    anchors.centerIn: parent; width: 16; height: 16
                                    color: maskItem.off ? Theme.faint : overEye.containsMouse ? Theme.text : Theme.dim
                                    path: maskItem.off ? "M2 10 C5 5 15 5 18 10 C15 15 5 15 2 10 Z M3.5 3.5 L16.5 16.5"
                                                       : "M2 10 C5 5 15 5 18 10 C15 15 5 15 2 10 Z M10 7.6 a2.4 2.4 0 1 0 0.01 0 Z"
                                }
                                MouseArea {
                                    id: overEye
                                    anchors.fill: parent; hoverEnabled: true
                                    onClicked: { session.setMask(index + 1, { off: !maskItem.off }); session.commitEdit() }
                                }
                            }
                            // A row's two buttons, as a checkpoint's has them (the owner: "a pencil
                            // and trash can icon", the bin red and the pencil green under the
                            // pointer). Delete takes the mask and its pins, in one step of undo.
                            Row {
                                id: renameMask
                                anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                spacing: 12
                                visible: (overMask.containsMouse || maskPencil.containsPointer || maskBin.containsPointer) && !maskEntry.visible
                                TextButton { id: maskPencil; objectName: "mask-rename:" + (index + 1); sign: Theme.pencilSign; says: "Rename"; glow: Theme.green; onPressed: maskEntry.begin(maskName.text) }
                                TextButton { id: maskBin; objectName: "mask-delete:" + (index + 1); sign: Theme.binSign; says: "Delete"; glow: Theme.red; onPressed: session.deleteMask(index + 1) }
                            }
                            NameEntry {
                                id: maskEntry
                                x: 30; width: parent.width - x - 6; anchors.verticalCenter: parent.verticalCenter
                                onTaken: (name) => { session.setMask(index + 1, { name: name }); session.commitEdit() }
                            }
                        }
                        // (The one chosen is in sight, also one just added below the fifth.)
                        Connections { target: wheel; function onMaskChanged() { if (wheel.mask > 0) maskList.positionViewAtIndex(wheel.mask - 1, ListView.Contain) } }
                    }
                    // (Not on show: it is what the wheel scrolls the list by.)
                    Scrollbar { id: maskBar; of: maskList; step: Theme.row; visible: false; anchors { right: parent.right; rightMargin: 1; top: maskList.top; bottom: maskList.bottom } }
                    MoreBelow { objectName: "masks-more"; of: maskList; x: 1; width: parent.width - 2; anchors { bottom: parent.bottom; bottomMargin: 1 } radius: 5 }
                    MoreBelow { above: true; of: maskList; x: 1; y: 1; width: parent.width - 2; radius: 5 }
                    Label {
                        visible: session.masks.length === 0
                        anchors.centerIn: parent; text: "No masks yet"; color: Theme.faint; font.pixelSize: 12
                    }
                }
                // Adding one, and what is done to the one chosen as a whole (the owner: "the
                // Invert/Delete buttons should be in the MASKS card"; their buttons are
                // mask-row's, given this place in the new screen).
                Item {
                    id: maskActions
                    width: parent.width; height: 32
                    Row {
                        visible: session.masks.length < 8
                        anchors.verticalCenter: parent.verticalCenter; spacing: 16
                        TextButton { objectName: "add-mask:radial"; text: "+ Radial"; onPressed: { wheel.mask = session.addMask("radial"); root.forceActiveFocus() } }
                        TextButton { objectName: "add-mask:linear"; text: "+ Linear"; onPressed: { wheel.mask = session.addMask("linear"); root.forceActiveFocus() } }
                        TextButton { objectName: "add-mask:brush"; text: "+ Brush"; onPressed: { wheel.mask = session.addMask("brush"); root.forceActiveFocus() } }
                    }
                }
            }
            Panel {
                id: maskCard
                objectName: "panel:mask-settings"
                readonly property var mask: wheel.mask > 0 && wheel.mask <= session.masks.length ? session.masks[wheel.mask - 1] : null
                readonly property bool brush: mask !== null && mask.kind === "brush"
                title: (session.masks, root.maskName(wheel.mask)); card: "mask"
                visible: root.mode === "masks" && mask !== null
                Item { id: maskSettingsSlot; width: parent.width; height: Theme.slider; visible: !maskCard.brush }
                // A painted mask: what the left button does on the photo, and with what
                // brush (the owner: "a paintable mask with a brush and eraser", both with
                // "Feathering and Size"). The brush is the same for every painted mask and
                // kept from one day to the next.
                Item {
                    objectName: "brush-tool"
                    width: parent.width; height: 34; visible: maskCard.brush
                    Label { anchors.verticalCenter: parent.verticalCenter; text: "Paint with" }
                    Rectangle {
                        width: brushTools.width + 4; height: 24; radius: 6; color: Theme.raised
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        Row {
                            id: brushTools
                            anchors.centerIn: parent
                            Segment { objectName: "brush:paint"; width: 76; height: 20; label: "Brush"; on: !stage.erasing; onChosen: stage.erasing = false }
                            Segment { objectName: "brush:erase"; width: 76; height: 20; label: "Eraser"; on: stage.erasing; onChosen: stage.erasing = true }
                        }
                    }
                }
                ParamSlider {
                    objectName: "brush:size"
                    visible: maskCard.brush; width: parent.width
                    name: "Size"; unit: "%"; from: 0.3; to: 30; neutral: 5; step: 0.1; digits: 1; logarithmic: true; signed: false
                    value: stage.brushSize * 100
                    onMoved: (v) => stage.brushSize = v / 100
                    onReleased: session.remember("brush/size", String(stage.brushSize))
                    onReset: { stage.brushSize = 0.05; session.remember("brush/size", "0.05") }
                    onTyped: root.forceActiveFocus()
                }
                ParamSlider {
                    objectName: "brush:feather"
                    visible: maskCard.brush; width: parent.width
                    name: "Feather"; unit: "%"; from: 0; to: 100; neutral: 50; step: 1; digits: 0; signed: false
                    value: stage.brushFeather * 100
                    onMoved: (v) => stage.brushFeather = v / 100
                    onReleased: session.remember("brush/feather", String(stage.brushFeather))
                    onReset: { stage.brushFeather = 0.5; session.remember("brush/feather", "0.5") }
                    onTyped: root.forceActiveFocus()
                }
                // Inside out: the mask works everywhere but where it is drawn (the owner: "maybe
                // Inverted should be a toggle button on the card of the mask").
                OnOff {
                    objectName: "mask:inverted"
                    label: "Inverted"
                    on: maskRow.mask !== null && maskRow.mask.invert
                    onFlipped: { session.setMask(wheel.mask, { invert: !maskRow.mask.invert }); session.commitEdit() }
                }
                Label {
                    width: parent.width; height: implicitHeight + 12; verticalAlignment: Text.AlignBottom; wrapMode: Text.WordWrap; color: Theme.faint; font.pixelSize: 12
                    text: maskCard.brush ? "Paint on the photo; the mask shows in red while the pointer is there. Ctrl and the wheel size the brush. What is set below changes the picture inside it only."
                                              : "Hold H to see the mask. What is set below changes the picture inside it only."
                }
            }
            // What the chosen mask changes inside it: the cards of Adjust, each setting an
            // amount added to the whole image's (the owner: "a mask should have ALL the cards
            // available as long as it makes sense for them"). The sliders add to the whole
            // image's; a curve or the color EQ, once changed here, holds inside the mask in
            // place of the whole image's. The Tone Wheel under these works inside it too.
            LocalCard {
                objectName: "panel:local-light"
                title: "Exposure"; card: "light"; keys: ["exposure", "contrast", "brightness", "highlights", "midtones", "shadows", "whites", "blacks"]
                LocalSlider { key: "exposure"; name: "Exposure"; unit: "EV"; from: -5; to: 5; step: 0.01; digits: 2 }
                LocalSlider { key: "contrast"; name: "Contrast"; from: -100; to: 100; step: 1; digits: 0 }
                LocalSlider { key: "brightness"; name: "Brightness"; from: -100; to: 100; step: 1; digits: 0 }
                Item { width: 1; height: 16 }   // between two groups: room, no line (a line reads as a slider's track)
                LocalSlider { key: "highlights"; name: "Highlights"; from: -100; to: 100; step: 1; digits: 0 }
                LocalSlider { key: "midtones"; name: "Midtones"; from: -100; to: 100; step: 1; digits: 0 }
                LocalSlider { key: "shadows"; name: "Shadows"; from: -100; to: 100; step: 1; digits: 0 }
                Item { width: 1; height: 16 }   // between two groups: room, no line (a line reads as a slider's track)
                LocalSlider { key: "whites"; name: "Whites"; from: -100; to: 100; step: 1; digits: 0 }
                LocalSlider { key: "blacks"; name: "Blacks"; from: -100; to: 100; step: 1; digits: 0 }
            }
            LocalCard {
                objectName: "panel:local-curve"
                title: "Tone curve"; card: "curve"; keys: ["curve"]
                CurveEditor {
                    width: parent.width; height: 220; onDone: root.forceActiveFocus()
                    key: "curve"; local: true; mask: wheel.mask; line: (session.masks, session.localLine(wheel.mask, "curve")); bars: (session.bars.light || [])
                }
            }
            LocalCard {
                objectName: "panel:local-balance"
                title: "White balance"; card: "balance"; keys: ["temperature", "tint"]
                LocalSlider { key: "temperature"; name: "Temperature"; unit: "K"; from: -4000; to: 4000; step: 10; digits: 0 }
                LocalSlider { key: "tint"; name: "Tint"; from: -150; to: 150; step: 1; digits: 0 }
            }
            LocalCard {
                objectName: "panel:local-saturation"
                title: "Saturation & Vibrance"; card: "saturation"; keys: ["saturation", "vibrance"]
                LocalSlider { key: "saturation"; name: "Saturation"; from: -100; to: 100; step: 1; digits: 0 }
                LocalSlider { key: "vibrance"; name: "Vibrance"; from: -100; to: 100; step: 1; digits: 0 }
            }
            LocalCard {
                objectName: "panel:local-eq"
                title: "Color EQ"; card: "eq"; keys: ["eq"]
                HueEditor { width: parent.width; height: 200; onDone: root.forceActiveFocus(); local: true; mask: wheel.mask }
            }
            LocalCard {
                objectName: "panel:local-chroma"
                title: "Chroma curve"; card: "chroma"; keys: ["chroma"]
                CurveEditor {
                    width: parent.width; height: 220; onDone: root.forceActiveFocus()
                    key: "chroma"; local: true; mask: wheel.mask; line: (session.masks, session.localLine(wheel.mask, "chroma")); bars: (session.bars.chroma || [])
                    low: "muted"; high: "vivid"
                }
            }
            // The panel of the rail's open tool, one at a time, above everything else.
            Panel {
                objectName: "panel:tone"
                id: tonePanel
                title: root.sections ? "Exposure" : "Tone"; tool: "tone"; card: root.sections ? "light" : ""; visible: session.source !== "" && root.shows("tone")
                folds: root.sections; open: root.isOpen("tone"); onFold: root.fold("tone")
                ProfileRow { visible: !root.sections }
                // The histogram is here, over what moves it (the owner: "the histogram should
                // probably be a part of the LIGHT card"); it was a card of the left panel.
                Histogram { visible: root.sections; width: parent.width; height: 110; color: "transparent"; border.width: 0 }
                OnOff {
                    objectName: "clipping-switch"
                    visible: root.sections
                    label: "Show clipping"
                    on: session.panels.clipping
                    onFlipped: session.setPanel("clipping", !session.panels.clipping)
                }
                Item { width: 1; height: 8; visible: root.sections }
                // Its zero is the photo as shot, and a double click puts it there. Where a
                // photo starts (lighter than shot if it has room: session.shot) is only the
                // value it has when first opened, which Reset all and the card's Reset bring
                // back. (The start was the slider's rest and its tick; the owner: it "should
                // NOT set the actual zero point of the slider, nor should it make the bar
                // reset to it. It simply needs to be the initial value".)
                EditSlider { key: "exposure"; name: "Exposure"; unit: "EV"; from: -5; to: 5; step: 0.01; digits: 2; rest: 0 }
                EditSlider { key: "contrast"; name: "Contrast"; from: -100; to: 100; step: 1; digits: 0 }
                EditSlider { key: "brightness"; name: "Brightness"; from: -100; to: 100; step: 1; digits: 0 }
                Item { width: 1; height: 16 }   // between two groups: room, no line (a line reads as a slider's track)
                EditSlider { key: "highlights"; name: "Highlights"; from: -100; to: 100; step: 1; digits: 0 }
                EditSlider { key: "midtones"; name: "Midtones"; from: -100; to: 100; step: 1; digits: 0 }
                EditSlider { key: "shadows"; name: "Shadows"; from: -100; to: 100; step: 1; digits: 0 }
                Item { width: 1; height: 16 }   // between two groups: room, no line (a line reads as a slider's track)
                EditSlider { key: "whites"; name: "Whites"; from: -100; to: 100; step: 1; digits: 0 }
                EditSlider { key: "blacks"; name: "Blacks"; from: -100; to: 100; step: 1; digits: 0 }
            }
            Panel {
                objectName: "panel:balance"
                id: balancePanel
                title: "White balance"; tool: "balance"; card: root.sections ? "balance" : ""; visible: session.source !== "" && root.shows("balance")
                folds: root.sections; open: root.isOpen("balance"); onFold: root.fold("balance")
                onVisibleChanged: if (!visible && stage.picking === "neutral") stage.picking = ""
                BalancePad {
                    width: parent.width; picking: stage.picking === "neutral"
                    onDone: root.forceActiveFocus()
                    onPick: { stage.picking = picking ? "" : "neutral"; root.forceActiveFocus() }
                }
                // The same two numbers as the pad, in kelvin, where a camera gave them a meaning.
                EditSlider {
                    key: "temperature"; visible: session.develops
                    name: "Temperature"; unit: "K"; from: 2000; to: 15000; logarithmic: true; step: 10; digits: 0
                    neutral: session.shot.temperature
                }
                EditSlider {
                    key: "tint"; visible: session.develops
                    name: "Tint"; from: -150; to: 150; step: 1; digits: 0
                    neutral: session.shot.tint
                }
            }
            Panel {
                objectName: "panel:curve"
                id: curvePanel
                title: "Tone curve"; tool: "curve"; card: root.sections ? "curve" : ""; visible: session.source !== "" && root.shows("curve")
                folds: root.sections; open: root.isOpen("curve"); onFold: root.fold("curve")
                CurveEditor {
                    width: parent.width; height: 250; onDone: root.forceActiveFocus()
                    key: "curve"; line: session.curveLine; bars: (session.bars.light || [])
                }
            }
            // The photo's frame: its shape, its straightening, its turns. The frame itself is
            // dragged on the photo, which shows whole while this is open.
            Panel {
                objectName: "panel:crop"
                id: cropPanel
                title: root.sections ? "Crop and straighten" : "Crop"; tool: "crop"; card: root.sections ? "crop" : ""; visible: session.source !== "" && root.shows("crop")
                open: root.isOpen("crop"); closes: !root.sections   // (the tabs leave it)
                // The frame's shape: the usual ones, or Custom, typed (the owner: "writing a
                // custom ratio doesnt indicate it is being used in any way and there is no way to
                // make it use it other than to press Enter"). A typed shape is used a moment after
                // the typing stops; the Custom chip stays lit while it is. Portrait stands every
                // shape on end.
                property bool custom: false
                function shaped(wide) { return wide > 0 && portrait.on ? 1 / wide : wide }
                Flow {
                    width: parent.width; spacing: 4; bottomPadding: 6
                    // (Two lines: the three that are no fixed shape, then the shapes; the owner's wish.)
                    Component {
                        id: shapeChipMade
                        Rectangle {
                            id: shapeChip
                            required property var modelData
                            readonly property bool mine: modelData[1] === -2
                            // (As shot: the picture's own shape, which stands as it was shot.)
                            readonly property real asked: modelData[1] === -1 ? session.framing.picture : cropPanel.shaped(modelData[1])
                            readonly property bool on: mine ? cropPanel.custom : !cropPanel.custom && Math.abs(stage.cropRatio - Math.max(0, asked)) < 1e-6
                            objectName: "crop-shape:" + modelData[0]
                            width: 58; height: 26; radius: 5
                            color: on ? Theme.selected : Theme.raised
                            border { width: on ? 1 : 0; color: Theme.dim }
                            Accessible.role: Accessible.RadioButton; Accessible.name: modelData[0]; Accessible.checked: on
                            Label { anchors.centerIn: parent; text: shapeChip.modelData[0]; font.pixelSize: 12; color: shapeChip.on ? Theme.text : Theme.dim }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    cropPanel.custom = shapeChip.mine
                                    if (!shapeChip.mine) return stage.reshape(shapeChip.asked)
                                    shapeEntry.forceActiveFocus()
                                    shapeEntry.selectAll()
                                    shapeEntry.use()
                                }
                            }
                        }
                    }
                    Repeater { model: [["Free", 0], ["As shot", -1], ["Custom", -2]]; delegate: shapeChipMade }
                    Item { width: parent.width; height: 1 }   // (ends the line: a thing of no height is not laid out)
                    Repeater { model: [["1 : 1", 1], ["5 : 4", 1.25], ["4 : 3", 4 / 3], ["3 : 2", 1.5], ["16 : 9", 16 / 9]]; delegate: shapeChipMade }
                }
                Item {
                    objectName: "crop-custom"
                    visible: cropPanel.custom
                    width: parent.width; height: 36
                    Label { anchors.verticalCenter: parent.verticalCenter; text: "Width : height" }
                    Rectangle {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        width: 120; height: 26; radius: 5; color: Theme.bg
                        border { width: 1; color: !shapeEntry.fine ? Theme.red : shapeEntry.activeFocus ? Theme.text : Theme.faint }
                        TextInput {
                            id: shapeEntry
                            objectName: "crop-custom-entry"
                            anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                            verticalAlignment: TextInput.AlignVCenter; horizontalAlignment: TextInput.AlignRight; clip: true
                            color: Theme.text; selectionColor: Theme.faint; selectedTextColor: Theme.text
                            font.family: Theme.font; font.pixelSize: Theme.fontSize; font.features: { "tnum": 1 }
                            Accessible.name: "Custom shape, width to height"
                            text: "7 : 5"
                            // Width over height of what is typed ("7:5", "2.35"); 0 if it is not a shape.
                            readonly property real asked: {
                                const parts = text.replace(/,/g, ".").split(/[:x×\/ ]+/).filter(part => part !== "").map(Number)
                                const shape = parts.length === 2 ? parts[0] / parts[1] : parts.length === 1 ? parts[0] : 0
                                return isFinite(shape) && shape >= 0.1 && shape <= 10 ? shape : 0
                            }
                            readonly property bool fine: text.trim() === "" || asked > 0
                            function use() {
                                const wanted = cropPanel.shaped(asked)
                                if (asked > 0 && Math.abs(stage.cropRatio - wanted) > 1e-6) stage.reshape(wanted)
                            }
                            onTextChanged: typing.restart()
                            Timer { id: typing; interval: 350; onTriggered: shapeEntry.use() }
                            // (Enter is taken here: let through, it is the window's "done cropping".)
                            Keys.onReturnPressed: (event) => { typing.stop(); use(); root.forceActiveFocus(); event.accepted = true }
                            Keys.onEnterPressed: (event) => { typing.stop(); use(); root.forceActiveFocus(); event.accepted = true }
                            Keys.onEscapePressed: (event) => { root.forceActiveFocus(); event.accepted = true }
                            onActiveFocusChanged: if (!activeFocus) { typing.stop(); use() }   // (left: what is typed is used)
                        }
                    }
                }
                OnOff {
                    id: portrait
                    objectName: "crop-portrait"
                    label: "Portrait"
                    onFlipped: { on = !on; stage.flipCrop() }
                }
                EditSlider { key: "angle"; name: "Straighten"; unit: "°"; from: -15; to: 15; step: 0.1; digits: 1 }
                Item {
                    width: parent.width; height: 28
                    Row {
                        anchors.verticalCenter: parent.verticalCenter; spacing: 14
                        // (Signs on the new screen: an arrow going up and round to that side; and no
                        // line about the keys there, which the tip over the photo says: the owner's wishes.)
                        TextButton {
                            objectName: "turn-left"; says: "Turn left"; onPressed: session.turn(-1)
                            text: root.sections ? "" : "Turn left"; strong: root.sections; width: root.sections ? 22 : implicitWidth; height: root.sections ? 22 : implicitHeight
                            sign: root.sections ? "M15 17 V10 A5 5 0 0 0 10 5 H4 M7 2 L4 5 L7 8" : ""
                        }
                        TextButton {
                            objectName: "turn-right"; says: "Turn right"; onPressed: session.turn(1)
                            text: root.sections ? "" : "Turn right"; strong: root.sections; width: root.sections ? 22 : implicitWidth; height: root.sections ? 22 : implicitHeight
                            sign: root.sections ? "M5 17 V10 A5 5 0 0 1 10 5 H16 M13 2 L16 5 L13 8" : ""
                        }
                    }
                    Label { visible: !root.sections; anchors { right: parent.right; verticalCenter: parent.verticalCenter } text: "Enter is done  ·  Esc undoes it"; font.pixelSize: 12; color: Theme.faint }
                }
            }
            // The three that work on every color of the picture, after the pins.
            Panel {
                objectName: "panel:saturation"
                id: saturationPanel
                title: root.sections ? "Saturation & Vibrance" : "Saturation"; tool: "saturation"; card: root.sections ? "saturation" : ""; visible: session.source !== "" && root.shows("saturation")
                folds: root.sections; open: root.isOpen("saturation"); onFold: root.fold("saturation")
                EditSlider { key: "saturation"; name: "Saturation"; unit: "%"; from: 0; to: 200; neutral: 100; step: 1; digits: 0 }
                // The muted colors more than the vivid ones, and skin least.
                EditSlider { key: "vibrance"; name: "Vibrance"; from: -100; to: 100; step: 1; digits: 0 }
            }
            Panel {
                objectName: "panel:eq"
                id: eqPanel
                title: "Color EQ"; tool: "eq"; card: root.sections ? "eq" : ""; visible: session.source !== "" && root.shows("eq")
                folds: root.sections; open: root.isOpen("eq"); onFold: root.fold("eq")
                HueEditor { width: parent.width; height: 220; onDone: root.forceActiveFocus() }
            }
            Panel {
                objectName: "panel:chroma"
                id: chromaPanel
                title: "Chroma curve"; tool: "chroma"; card: root.sections ? "chroma" : ""; visible: session.source !== "" && root.shows("chroma")
                folds: root.sections; open: root.isOpen("chroma"); onFold: root.fold("chroma")
                CurveEditor {
                    width: parent.width; height: 250; onDone: root.forceActiveFocus()
                    key: "chroma"; line: session.chromaLine; bars: (session.bars.chroma || [])
                    low: "muted"; high: "vivid"
                }
            }
            // The pin being worked on, as numbers: everything the wheel does by gesture, and
            // what has no gesture (its kind, its span of lightness).
            Panel {
                id: pinPanel
                objectName: "panel:pins"
                // (In the wheel's own card, under the wheel; the owner: "cannot be a separate
                // card, it needs to be inside the color wheel card below the tonewheel".)
                title: "Pin"; tool: "pins"; visible: session.source !== "" && (root.sections || root.shows("pins"))
                plain: root.sections; parent: root.sections ? pinSlot : develop
                // What it shows: the pin being worked on, or the color just marked as the pin
                // it would be (it becomes one the moment anything here is moved). With neither
                // the section stays as it is, dimmed: the wheel under it must not move when a
                // color is marked (the owner: "the entire wheel gets shifted down").
                readonly property var shown: wheel.selected >= 0 ? wheel.pins[wheel.selected]
                    : wheel.fresh ? { mode: "offset", range: 0.08, feather: 70, variance: 0, light: 0, low: session.range.low, high: session.range.high } : null
                readonly property bool has: shown !== null
                Label {
                    objectName: "pin-hint"
                    width: parent.width; height: 40; wrapMode: Text.WordWrap; color: Theme.faint; font.pixelSize: 12
                    text: wheel.selected >= 0 ? "Pin " + (wheel.selected + 1) + " of " + wheel.pins.length + ", works on " + wheel.tonesOf(wheel.pins[wheel.selected]) + (wheel.tonesOf(wheel.pins[wheel.selected]) === "all tones" ? "" : " only") + ". A right click or Delete takes it away."
                        : wheel.fresh ? "A new pin. Drag it on the wheel to shift that color and those near it, or set it here."
                        : wheel.pins.length ? "No pin chosen. Click a pin on the wheel to work on it, or a color to make another."
                                            : "No pins yet. A pin shifts one color and those near it, as far as its range. Click a color in the photo or on the wheel to place one."
                }
                Item {
                    width: parent.width; height: 34; enabled: pinPanel.has; opacity: enabled ? 1 : 0.35
                    Label { anchors.verticalCenter: parent.verticalCenter; text: "Kind" }
                    Rectangle {
                        width: kinds.width + 4; height: 24; radius: 6; color: Theme.raised
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        Row {
                            id: kinds
                            anchors.centerIn: parent
                            Repeater {
                                model: [["offset", "Offset"], ["rotate", "Rotate"], ["protect", "Protect"]]
                                Segment {
                                    required property var modelData
                                    objectName: "pin-kind:" + modelData[0]
                                    width: 68; height: 20; label: modelData[1]
                                    on: pinPanel.has && pinPanel.shown.mode === modelData[0]
                                    onChosen: { wheel.change(wheel.place(), { mode: modelData[0] }); session.commitEdit() }
                                }
                            }
                        }
                    }
                }
                PinSlider { key: "range"; name: "Range"; from: 0.01; to: 0.5; neutral: 0.08; step: 0.005; digits: 3; logarithmic: true }
                PinSlider { key: "feather"; name: "Feather"; from: 0; to: 100; neutral: 70; step: 1; digits: 0 }
                PinSlider { key: "variance"; name: "Variance"; from: -100; to: 100; step: 1; digits: 0 }
                PinSlider { key: "light"; name: "Lightness"; from: -0.5; to: 0.5; step: 0.01; digits: 2 }
                PinSlider { key: "low"; name: "Only tones lighter than"; from: 0; to: 1; neutral: 0; step: 0.01; digits: 2; signed: false }
                PinSlider { key: "high"; name: "Only tones darker than"; from: 0; to: 1; neutral: 1; step: 0.01; digits: 2 }
            }
            // The wheel: the photo's colors. It takes the room that is left, as a square, and
            // is never smaller than it can be read at: below that the column scrolls instead.
            Item {
                id: wheelBlock
                objectName: "wheel-block"
                visible: session.source !== "" && (!root.sections || root.mode === "edit" || (root.mode === "masks" && wheel.mask > 0))
                readonly property real lead: 30   // its title
                readonly property bool open: !root.sections || root.unfolded.wheel === true
                readonly property real head: root.sections ? lead + 16 : lead + masksBar.height + 8 + (maskRow.visible ? maskRow.height + 8 : 0)
                readonly property real side: root.sections ? Math.min(parent.width, 400) : Math.max(220, Math.min(parent.width, scroller.height - y - head - tabs - 8 - 46 - 10))
                readonly property real tabs: 34   // the tone tabs' height (taller than they were: the owner's wish)
                width: parent.width; height: open ? head + tabs + 8 + side + 46 + 22 + (root.sections ? pinPanel.height + 14 : 0) : lead + 16
                onOpenChanged: if (open && root.sections) wheelGround.flash()
                Ground { id: wheelGround; card: root.sections ? "wheel" : ""; wide: wheelBlock.width; high: wheelBlock.height - (wheelBlock.open ? 24 : 16) }
                MouseArea {
                    enabled: root.sections; x: -10; y: -8; width: parent.width + 20; height: 44   // (the card's head)
                    cursorShape: root.sections ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.fold("wheel")
                }
                Icon {
                    visible: root.sections
                    x: -2; y: Theme.cardMid - height / 2; width: 14; height: 14; stroke: 2
                    path: "M7.5 4.5 L13 10 L7.5 15.5"; color: Theme.cardInk("wheel", Theme.dim)
                    rotation: wheelBlock.open ? 90 : 0
                    Behavior on rotation { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                }
                Icon {
                    visible: root.sections
                    x: 17; y: Theme.cardMid - height / 2; width: Theme.cardSign; height: Theme.cardSign; stroke: 1.8
                    path: Theme.cardIcon("wheel"); color: Theme.cardInk("wheel", wheelBlock.open ? Theme.text : Theme.dim)
                }
                Label {
                    x: root.sections ? 18 + Theme.cardSign + 8 : 0; y: root.sections ? Theme.cardMid - height / 2 : 4; text: root.sections ? "TONE WHEEL" : "COLORS"
                    color: Theme.cardInk(root.sections ? "wheel" : "", root.sections && wheelBlock.open ? Theme.text : Theme.dim)
                    font.pixelSize: root.sections ? Theme.titleSize : Theme.smallSize; font.weight: Font.DemiBold; font.letterSpacing: 0.9
                }
                Label {   // which pins the wheel is showing and making (the Masks section chooses)
                    visible: root.sections && wheelBlock.open && root.mode === "masks"
                    anchors { right: wheelReset.left; rightMargin: 14 } y: Theme.cardMid - height / 2; font.pixelSize: Theme.smallSize; color: wheel.mask > 0 ? Theme.mark : Theme.dim
                    text: wheel.mask > 0 ? "inside " + (session.masks, root.maskName(wheel.mask)) : "whole image"
                }
                // Reset, as every card has: the pins the wheel is showing go (the whole image's,
                // or the chosen mask's), in one step of undo. Not the masks themselves, which
                // the old screen's Pin tool took along.
                TextButton {
                    id: wheelReset
                    objectName: "reset:wheel"
                    visible: root.sections && wheelBlock.open
                    anchors { right: parent.right; rightMargin: -2 } y: Theme.cardMid - height / 2
                    readonly property var kept: wheel.pins.filter(pin => (pin.mask || 0) !== wheel.mask)
                    sign: Theme.resetSign; says: "Reset"; strong: true; available: kept.length < wheel.pins.length
                    onPressed: { wheel.deselect(); session.commitEdit(); session.setEdit("pins", kept); session.commitEdit() }
                }
                // What the pins are for: the whole image, or one of the photo's masks (a part
                // of the picture, drawn on the photo to be dragged). A pin made while a mask
                // is chosen works only there.
                Rectangle {
                    id: masksBar
                    objectName: "masks"
                    visible: !root.sections
                    y: wheelBlock.lead; width: parent.width; height: chips.height; radius: 6; color: Theme.raised
                    Flow {
                        id: chips
                        width: parent.width
                        Segment { objectName: "mask:0"; width: 96; label: "Whole image"; on: wheel.mask === 0; onChosen: wheel.mask = 0; visible: !root.sections }
                        Repeater {
                            model: session.masks.length
                            Segment {
                                required property int index
                                objectName: "mask:" + (index + 1)
                                width: 70; label: (session.masks, root.maskName(index + 1))
                                on: wheel.mask === index + 1; onChosen: wheel.mask = index + 1
                            }
                        }
                        Segment { objectName: "mask:radial"; width: 70; label: "+ Radial"; visible: session.masks.length < 8; onChosen: { wheel.mask = session.addMask("radial"); root.forceActiveFocus() } }
                        Segment { objectName: "mask:linear"; width: 70; label: "+ Linear"; visible: session.masks.length < 8; onChosen: { wheel.mask = session.addMask("linear"); root.forceActiveFocus() } }
                    }
                }
                Item {
                    id: maskRow
                    objectName: "mask-row"
                    readonly property var mask: wheel.mask > 0 && wheel.mask <= session.masks.length ? session.masks[wheel.mask - 1] : null
                    // There once the photo has a mask, whichever chip is chosen: the wheel
                    // must not jump when one goes from a mask's pins to the whole image's.
                    visible: session.masks.length > 0
                    parent: root.sections ? maskSettingsSlot : wheelBlock
                    y: root.sections ? 0 : wheelBlock.lead + masksBar.height + 8; width: parent.width; height: Theme.slider
                    ParamSlider {
                        objectName: "slider:mask-feather"
                        visible: maskRow.mask !== null && maskRow.mask.kind === "radial"
                        width: parent.width - (root.sections ? 0 : 130)
                        name: "Feather"; unit: " %"; from: 0; to: 100; neutral: 50; step: 1; digits: 0; signed: false
                        value: maskRow.mask ? maskRow.mask.feather * 100 : neutral
                        onMoved: (v) => session.setMask(wheel.mask, { feather: v / 100 })
                        onReleased: session.commitEdit()
                        onReset: { session.setMask(wheel.mask, { feather: 0.5 }); session.commitEdit() }
                        onTyped: root.forceActiveFocus()
                    }
                    Label {
                        visible: maskRow.mask === null || maskRow.mask.kind === "linear"
                        anchors.verticalCenter: parent.verticalCenter; width: parent.width - (maskRow.mask ? 130 : 0)
                        text: maskRow.mask ? "Fades toward the far line" : "Pins work on the whole image"
                        color: Theme.dim; font.pixelSize: 12; elide: Text.ElideRight
                    }
                    Row {
                        visible: maskRow.mask !== null
                        anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                        spacing: 18
                        TextButton {
                            objectName: "mask:invert"; text: "Invert"; visible: !root.sections   // (the new screen: a switch, mask:inverted)
                            color: maskRow.mask && maskRow.mask.invert ? Theme.mark : containsPointer ? Theme.text : Theme.dim
                            Accessible.checkable: true; Accessible.checked: maskRow.mask !== null && maskRow.mask.invert
                            onPressed: { session.setMask(wheel.mask, { invert: !maskRow.mask.invert }); session.commitEdit() }
                        }
                        TextButton {
                            objectName: "mask:delete"; text: "Delete"; danger: true; onPressed: session.deleteMask(wheel.mask)
                            visible: !root.sections   // (the new screen: the bin on the mask's own row)
                            parent: root.sections ? maskActions : parent
                            anchors { right: root.sections ? parent.right : undefined; rightMargin: 4; verticalCenter: root.sections ? parent.verticalCenter : undefined }
                        }
                    }
                }
                // The working range: the wheel shows only colors that light. "Pick" takes the
                // lightness from a click on the photo.
                Rectangle {
                    objectName: "range"
                    visible: wheelBlock.open
                    id: rangeRow
                    y: wheelBlock.head; width: parent.width; height: wheelBlock.tabs; radius: 7; color: Theme.raised
                    Row {
                        Repeater {
                            model: [["full", "All tones"], ["highlights", "Highlights"], ["midtones", "Midtones"], ["shadows", "Shadows"]]
                            Segment {
                                required property var modelData
                                objectName: "range:" + modelData[0]
                                width: wheelBlock.width / 4; height: wheelBlock.tabs; label: modelData[1]
                                on: session.range.name === modelData[0]
                                onChosen: session.setRange(modelData[0])
                            }
                        }
                        // (There was a fifth, Pick: tones as light as a spot clicked in the
                        // photo. The owner: "really not obvious what it does and ... not needed".)
                    }
                }
                Wheel {
                    id: wheel
                    objectName: "wheel"
                    visible: wheelBlock.open
                    // (As wide as its card, as the lightness strip under it is; the owner's wish.)
                    y: wheelBlock.head + wheelBlock.tabs + 8; width: root.sections ? parent.width : wheelBlock.side; height: wheelBlock.side
                    anchors.horizontalCenter: parent.horizontalCenter
                    hover: stage.hover
                    picture: stage.picture; painted: stage.painted
                    onDone: root.forceActiveFocus()
                    // (The column was being scrolled when the wheel came under the pointer:
                    // the scroll goes on; the owner: "it will get swallowed by the tonewheel".)
                    yields: root.sections && scrolling.running
                }
                Item {   // the pin's settings, in the trial's layout
                    id: pinSlot
                    visible: root.sections && wheelBlock.open
                    y: wheelBlock.head + wheelBlock.tabs + 8 + wheelBlock.side + 46 + 14; width: parent.width; height: pinPanel.height
                }
                LightnessStrip {
                    y: wheel.y + wheel.height + 8; width: parent.width
                    objectName: "lightness"
                    visible: wheelBlock.open
                    bars: (wheel.cloud.light || [])
                    // The pin being worked on: lighter or darker.
                    held: wheel.selected >= 0
                    shift: held ? wheel.pins[wheel.selected].light : 0
                    onMoved: (v) => wheel.change(wheel.selected, { light: v })
                    onReleased: { session.commitEdit(); root.forceActiveFocus() }
                    onReset: { wheel.change(wheel.selected, { light: 0 }); session.commitEdit() }
                    probe: wheel.probe.length === 3 ? wheel.probe[2] : -1
                }
            }
        }

        }
        }

        // Checkpoints: the edit as it was when "Save" was pressed, to come back to. The one the
        // edit stands at is lit; changed since, it keeps a hollow mark and says so. A low
        // section of its own at the foot of the column, under everything (the owner's choice):
        // four rows at most, more by scrolling.
        Scrollbar { id: pointsBar; parent: points.parent; objectName: "checkpoints-bar"; of: pointsList; step: Theme.row; visible: !root.sections && reach > 0.5; x: points.x + points.width + (root.sections ? -13 : 1); y: points.y + pointsList.y; height: pointsList.height }
        Item {
            id: points
            objectName: "checkpoints"
            visible: session.source !== ""
            parent: root.sections ? leftPane : tools
            readonly property int rows: Math.min(root.sections ? 6 : 4, session.checkpoints.length)
            // (Its card reaches 6 px below it: with this, the card ends as far above the status
            // line as it begins below the card over it. It stood right on the line.)
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 16; rightMargin: 16; bottomMargin: root.sections ? 12 : 16 }
            // The new screen (the owner: "like the masks list... dark rectangle for the scrollable
            // area", Save "at the very bottom under that list", "latest at the bottom"): a dark
            // box five rows high that scrolls, the newest checkpoint last, Save across its foot.
            readonly property real boxHigh: 5 * Theme.row + 8
            // How long ago, in a word or two (the owner: "how long ago, not when"); kept true by
            // a look at the clock twice a minute.
            property real now: Date.now() / 1000
            Timer { interval: 30000; running: points.visible; repeat: true; onTriggered: points.now = Date.now() / 1000 }
            function ago(made) {
                const s = Math.max(0, now - made), m = Math.floor(s / 60), h = Math.floor(m / 60), d = Math.floor(h / 24)
                return m < 1 ? "just now" : m < 60 ? m + " min ago" : h < 24 ? h + " h ago" : d < 30 ? d + (d === 1 ? " day ago" : " days ago") : Math.floor(d / 30) + " mo ago"
            }
            Connections { target: session; function onChanged() { points.now = Date.now() / 1000 } }
            height: root.sections ? 12 + 54 + boxHigh + 8 + 30 + 12 : 12 + 26 + (rows ? rows * Theme.row : 24) + 10
            Item {
                id: pointsHeader
                y: 12; width: parent.width; height: root.sections ? 54 : 26
                Ground { y: -4; head: 48; card: root.sections ? "checkpoints" : ""; wide: points.width; high: points.height - 16 }
                Icon {
                    visible: root.sections
                    y: 21 - height / 2; width: Theme.cardSign; height: Theme.cardSign; stroke: 1.8
                    path: Theme.cardIcon("checkpoints"); color: Theme.cardInk("checkpoints", Theme.dim)
                }
                Label {
                    x: root.sections ? Theme.cardSign + 8 : 0; y: root.sections ? 21 - height / 2 : 0; color: Theme.cardInk(root.sections ? "checkpoints" : "", Theme.dim)
                    text: "CHECKPOINTS"
                    font.pixelSize: root.sections ? Theme.titleSize : Theme.smallSize; font.weight: Font.DemiBold; font.letterSpacing: 0.9
                }
                TextButton {
                    objectName: "checkpoint-save"
                    visible: !root.sections
                    anchors.right: parent.right
                    text: "Save"; onPressed: session.saveCheckpoint()
                }
            }
            Label {
                anchors { top: pointsHeader.bottom; left: parent.left; right: parent.right }
                visible: session.checkpoints.length === 0 && !root.sections
                elide: Text.ElideRight; color: Theme.faint; font.pixelSize: 12
                text: "Save keeps the edit as it is now, to come back to."
            }
            Rectangle {
                id: pointsBox
                visible: root.sections
                anchors { top: pointsHeader.bottom; left: parent.left; right: parent.right }
                height: points.boxHigh; radius: 6; color: Theme.bg; border { width: 1; color: Theme.line }
                Label {
                    visible: session.checkpoints.length === 0
                    anchors.centerIn: parent; text: "No checkpoints yet"; color: Theme.faint; font.pixelSize: 12
                }
            }
            MoreBelow { objectName: "checkpoints-more"; z: 1; of: root.sections ? pointsList : null; x: 1; width: parent.width - 2; anchors { bottom: pointsBox.bottom; bottomMargin: 1 } radius: 5 }
            MoreBelow { above: true; z: 1; of: root.sections ? pointsList : null; x: 1; width: parent.width - 2; anchors { top: pointsBox.top; topMargin: 1 } radius: 5 }
            PushButton {
                objectName: "checkpoint-save-wide"
                visible: root.sections
                anchors { top: pointsBox.bottom; topMargin: 8; left: parent.left; right: parent.right }
                label: "Save checkpoint"; onPressed: session.saveCheckpoint()
            }
            ListView {
                id: pointsList
                objectName: "checkpoint-list"
                x: root.sections ? 4 : -8; y: pointsHeader.y + pointsHeader.height + (root.sections ? 4 : 0)
                width: parent.width + (root.sections ? -8 : 16)
                height: root.sections ? points.boxHigh - 8 : points.rows * Theme.row
                clip: true; boundsBehavior: Flickable.StopAtBounds; acceptedButtons: Qt.NoButton
                onCountChanged: if (root.sections) positionViewAtEnd()   // (the newest is the last, and in sight)
                MouseArea { parent: pointsList.contentItem; width: pointsList.width; height: Math.max(pointsList.height, pointsList.contentHeight); z: -1; acceptedButtons: Qt.NoButton; onWheel: (wheel) => pointsBar.turned(wheel) }
                model: root.sections ? session.checkpoints.slice().reverse() : session.checkpoints
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    objectName: "checkpoint:" + modelData.id
                    width: pointsList.width; height: Theme.row; radius: 6
                    // (The new screen: the checkpoint the edit stands at has its whole row in the accent
                    // color, faintly, with an outline of it; it was a thin strip at the row's
                    // edge, which the owner wanted easier to see.)
                    border { width: root.sections && modelData.state === "here" ? 1 : 0; color: Qt.rgba(Theme.mark.r, Theme.mark.g, Theme.mark.b, 0.6) }
                    color: modelData.state === "here" ? (root.sections ? Qt.rgba(Theme.mark.r, Theme.mark.g, Theme.mark.b, 0.2) : Theme.raised) : over.containsMouse ? (root.sections ? Theme.raised : Qt.darker(Theme.raised, 1.25)) : "transparent"
                    Accessible.role: Accessible.ListItem
                    Accessible.name: modelData.name + (modelData.state === "here" ? ", current" : modelData.state === "changed" ? ", changed since" : "")
                    Rectangle {  // the mark: filled where the edit stands, hollow where it stood
                        x: 10; width: 8; height: 8; radius: 4; anchors.verticalCenter: parent.verticalCenter
                        visible: row.modelData.state !== "" && !root.sections
                        color: row.modelData.state === "here" ? Theme.mark : "transparent"
                        border { width: 1; color: Theme.mark }
                    }
                    Label {
                        // (No column kept free for a mark: the names of all stand on one edge.)
                        x: root.sections ? 12 : 28; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - x - trailing.width - 16; elide: Text.ElideRight
                        text: row.modelData.name
                        color: row.modelData.state === "" ? Theme.dim : Theme.text
                        visible: !pointEntry.visible
                    }
                    MouseArea {
                        id: over
                        anchors.fill: parent; hoverEnabled: true
                        onClicked: root.goTo(row.modelData)
                    }
                    Row {
                        id: trailing
                        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        spacing: 10
                        visible: !pointEntry.visible
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            font.pixelSize: 12; font.features: { "tnum": 1 }
                            // (While the pointer is on the row its two buttons have this place.)
                            visible: !(root.sections && renamePoint.visible)
                            color: row.modelData.state === "changed" ? Theme.mark : Theme.faint
                            text: row.modelData.state === "changed" ? "changed" : root.sections ? points.ago(row.modelData.made) : row.modelData.when
                        }
                        TextButton {
                            id: renamePoint
                            objectName: "checkpoint-rename:" + row.modelData.id
                            anchors.verticalCenter: parent.verticalCenter
                            visible: root.sections && (over.containsMouse || containsPointer || deletePoint.containsPointer)
                            sign: Theme.pencilSign; says: "Rename"; glow: Theme.green; onPressed: pointEntry.begin(row.modelData.name)
                        }
                        TextButton {
                            id: deletePoint
                            objectName: "checkpoint-delete:" + row.modelData.id
                            anchors.verticalCenter: parent.verticalCenter
                            visible: over.containsMouse || containsPointer || renamePoint.containsPointer
                            text: root.sections ? "" : "Delete"; sign: root.sections ? Theme.binSign : ""; says: "Delete"; glow: root.sections ? Theme.red : "transparent"
                            onPressed: confirm.ask("Delete “" + row.modelData.name + "”?",
                                                   "The checkpoint cannot be brought back. The photo's edit stays as it is.",
                                                   "Delete", () => session.deleteCheckpoint(row.modelData.id))
                        }
                    }
                    NameEntry {
                        id: pointEntry
                        x: 8; width: parent.width - 16; anchors.verticalCenter: parent.verticalCenter
                        onTaken: (name) => session.renameCheckpoint(row.modelData.id, name)
                    }
                }
            }
        }
    }

    // ---- The photo -----------------------------------------------------------------------
    PhotoView {
        id: stage
        objectName: "box:stage"
        visible: root.editing
        anchors { left: leftPane.visible ? leftPane.right : parent.left; right: tools.left; top: chartBar.visible ? chartBar.bottom : topBar.bottom; bottom: filmstrip.visible ? filmstrip.top : foot.top }
        onPicked: (u, v) => { session.pickRange(u, v); picking = "" }
        // Pick neutral: while the button is held and slid, the spot under the pointer is made
        // gray, as one step of undo; it stays on for another try, until Esc or its button.
        onSampled: (u, v, first) => { if (first) session.commitEdit(); session.pickNeutral(u, v) }
        onSampleDone: session.commitEdit()
        // A plain click on the photo marks its color on the wheel, to be pinned.
        onTapped: (u, v) => wheel.mark(session.colorAt(u, v))
        onMaskLeft: wheel.mask = 0
        asking: confirm.visible   // (files dropped while a question is open are not opened)
        brushSize: Math.max(0.003, Math.min(0.3, Number(session.remembered("brush/size", "0.05")) || 0.05))
        brushFeather: Math.max(0, Math.min(1, Number(session.remembered("brush/feather", "0.5"))))
        mask: wheel.mask
        clear: rail.visible ? rail.width + 12 : 0
        standIn: (library.thumbs, library.thumbFor(root.openPath))
        // Pressing the photo takes the keys back from whatever control had them, so that the
        // arrows step through photos again and not through a slider.
        onClicked: root.forceActiveFocus()
    }
    // The photos at hand, in a row under the photo (there once there is more than one). Its
    // top edge is dragged to make it taller or lower, down to nothing; a double click on that
    // edge puts it away and brings it back. How tall it is, is remembered.
    readonly property int openAt: session.index   // (asked at every change; another only with another photo)
    property real stripHigh: Math.max(0, Math.min(240, Number(session.remembered("view/strip", "104")) || 0))
    Filmstrip {
        id: filmstrip
        objectName: "box:strip"
        visible: root.editing && session.count > 1
        anchors { left: leftPane.visible ? leftPane.right : parent.left; right: tools.left; bottom: foot.top }
        height: root.stripHigh < 40 ? 7 : root.stripHigh   // (put away, its edge stays to take hold of)
        current: root.openAt
        onOpened: (index) => { session.goTo(index); root.forceActiveFocus() }
        onMenuAsked: (files, x, y) => menu.open(files, x, y)
        MouseArea {
            objectName: "strip-edge"
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: 7; cursorShape: Qt.SizeVerCursor
            property real from
            property real start
            property real before: 104   // how tall it was when it was put away
            onPressed: (mouse) => { from = mapToItem(root, 0, mouse.y).y; start = root.stripHigh < 40 ? 0 : root.stripHigh }
            onPositionChanged: (mouse) => {
                if (!pressed) return   // (the pointer merely passing over it)
                const high = start + from - mapToItem(root, 0, mouse.y).y
                root.stripHigh = high < 40 ? 0 : Math.min(240, Math.max(64, high))
            }
            onReleased: session.remember("view/strip", String(Math.round(root.stripHigh)))
            onDoubleClicked: {
                if (root.stripHigh >= 40) { before = root.stripHigh; root.stripHigh = 0 } else root.stripHigh = before
                session.remember("view/strip", String(Math.round(root.stripHigh)))
            }
            Rectangle { anchors.horizontalCenter: parent.horizontalCenter; y: 2; width: 36; height: 3; radius: 1.5; color: parent.containsMouse || parent.pressed ? Theme.dim : Theme.faint }
            hoverEnabled: true
        }
    }
    // The open photo's thumbnail is the photo as it is edited: when the edit has come to rest
    // (and a moment after an edited photo is opened), a small render of it through the same
    // shader is read back and handed to the library, which keeps it in place of the one made
    // from the file. It takes its numbers only then, so a slider being dragged does not reach it.
    Pipeline {
        id: keeper
        objectName: "keeper"
        visible: false; z: 5
        readonly property real share: 512 / Math.max(1, session.fullWidth, session.fullHeight)
        width: Math.max(1, Math.round(session.fullWidth * share)); height: Math.max(1, Math.round(session.fullHeight * share))
        source: stage.picture; sharp: stage.picture; useSharp: 0; painted: stage.painted
        property var numbers: session.inFrame
        property var layers: []
        edit: numbers
        peak: 1; hdrLift: 0; linearOut: 0; clipping: 0
        Local { over: keeper; layers: keeper.layers }
        Component.onCompleted: take()   // (assignments: from here on only `keep` sets them)
        function fit() { return stage.ready && !session.original && !session.panels.chart }
        function take() { numbers = session.inFrame; layers = session.maskLayersInFrame }   // the edit as it is now
        function keep() {
            if (!fit() || !Window.window || !Window.window.visible) return
            const path = session.path, steps = session.steps
            take()
            // (Taken by the library, not by a function here: app.Session.grabScope says why.)
            wanted = { path: path, steps: steps }
            if (!library.grabThumb(keeper, path)) wanted = null
        }
        property var wanted: null   // the photo and the edit the render under way is of
        Connections {
            target: library
            function onThumbTaken() {
                const of = keeper.wanted
                keeper.wanted = null
                library.keepTaken(of !== null && session.path === of.path && session.steps === of.steps && keeper.fit())
            }
        }
    }
    Timer { id: keeping; interval: 250; onTriggered: keeper.keep() }
    Connections {
        target: session
        function onSaved() { keeping.restart(); library.setEdited(session.path, session.edited) }
    }
    // (A photo that was edited before thumbnails were kept this way gets its own when opened.)
    Connections {
        target: stage
        function onReadyChanged() { if (stage.ready && session.edited) keeping.restart() }
    }
    // While the test chart is on show, a bar over it says so in the one accent color.
    Rectangle {
        id: chartBar
        objectName: "box:chart"
        visible: session.panels.chart && root.editing
        // (Over the photo only: it lay over the top of the left panel; the owner: "overflows".)
        anchors { left: leftPane.visible ? leftPane.right : parent.left; right: tools.left; top: topBar.bottom }
        height: chartWords.height + 16; color: Theme.mark
        Accessible.role: Accessible.AlertMessage; Accessible.name: chartWords.text
        Label {
            id: chartWords
            objectName: "text:chart"
            anchors { left: parent.left; right: chartBack.left; margins: 14; verticalCenter: parent.verticalCenter }
            wrapMode: Text.WordWrap; color: Theme.bg; font.weight: Font.DemiBold
            text: "TEST CHART  ·  This is not your photo. It shows what the edit of " + session.name + " does to a set of test colors. Anything you change here still changes that photo's edit."
        }
        Rectangle {
            id: chartBack
            objectName: "chart-back"
            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
            width: backWords.implicitWidth + 24; height: 28; radius: 6; color: Theme.bg
            activeFocusOnTab: true
            Accessible.role: Accessible.Button; Accessible.name: backWords.text
            Keys.onSpacePressed: session.setPanel("chart", false)
            Label { id: backWords; anchors.centerIn: parent; text: "Back to my photo"; color: Theme.text }
            MouseArea { anchors.fill: parent; onClicked: session.setPanel("chart", false) }
        }
    }
    Scopes { objectName: "scopes"; z: 5; source: stage.picture; painted: stage.painted; ready: stage.ready }   // (shots show it for a moment)
    Histogram {
        objectName: "screen:histogram"
        visible: stage.ready && session.panels.histogram && root.editing && !root.sections
        anchors { right: stage.right; top: stage.top; margins: 12; rightMargin: rail.width + 24 }   // (left of the rail)
    }

    // ---- The rail: the tools, between the photo and their panels -------------------------
    component RailButton: Rectangle {
        id: button
        property string tool: ""     // the panel it opens (edit.TOOLS), or none: a switch
        property string label
        property string keys: ""
        property alias path: glyph.path
        property bool on: tool !== "" && (root.sections ? tool === "crop" && root.cropping : session.panels.tool === tool)
        signal pressed()
        objectName: "rail:" + label
        width: Theme.railButton; height: Theme.railButton; radius: 6
        color: on ? Theme.selected : over.containsMouse ? Theme.raised : "transparent"
        activeFocusOnTab: true
        Accessible.role: Accessible.Button; Accessible.name: label; Accessible.checkable: true; Accessible.checked: on
        Keys.onSpacePressed: pressed()
        border { width: activeFocus ? 1 : 0; color: Theme.text }
        onPressed: if (tool !== "") root.toggle(tool)
        Icon { id: glyph; anchors.centerIn: parent; color: Theme.text; opacity: button.on || over.containsMouse ? 1 : 0.82 }
        Rectangle {  // the dot: this tool has changed the photo
            visible: button.tool !== "" && session.adjusted[button.tool] === true
            x: parent.width - 8; y: 3; width: 5; height: 5; radius: 2.5; color: Theme.mark
        }
        MouseArea {
            id: over
            anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.LeftButton | Qt.RightButton
            // A right click puts the tool back to rest.
            onClicked: (mouse) => mouse.button === Qt.RightButton ? session.resetTool(button.tool) : button.pressed()
        }
        Rectangle {  // its name, while the pointer is on it
            visible: over.containsMouse
            anchors { right: parent.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
            width: tip.width + 16; height: 26; radius: 6; color: Theme.raised; border { width: 1; color: Theme.line }
            Row {
                id: tip
                anchors.centerIn: parent; spacing: 8
                Label { text: button.label; color: Theme.text; font.pixelSize: 12 }
                Label { text: button.keys; visible: text !== ""; font.pixelSize: 12 }
            }
        }
    }
    // The rail of tools: no column of its own, the icons float over the photo's right edge on
    // a rounded, half-clear ground that blurs what of the photo lies behind it (the owner's
    // choice, 2026-11-17).
    Rectangle {
        id: rail
        objectName: "screen:rail"
        visible: root.editing && session.source !== "" && !root.sections   // (the trial has the column's tabs instead)
        z: 1   // a button's name reaches out over the photo
        anchors { right: tools.left; top: chartBar.visible ? chartBar.bottom : topBar.bottom; rightMargin: 12; topMargin: 12 }
        // The same 6 px between the ground's edge and a button on every side, and the ground's
        // corners rounder than a button's by just that: the two curves run side by side.
        height: railTools.height + 12; width: Theme.railButton + 12; radius: 12
        color: "transparent"
        ShaderEffectSource {
            id: behind
            visible: false
            sourceItem: stage
            sourceRect: Qt.rect(rail.x - stage.x, rail.y - stage.y, rail.width, rail.height)
        }
        Rectangle { id: railShape; anchors.fill: parent; radius: rail.radius; visible: false; layer.enabled: true }
        MultiEffect {
            anchors.fill: parent
            source: behind
            blurEnabled: true; blur: 1.0; blurMax: 48; autoPaddingEnabled: false
            maskEnabled: true; maskSource: railShape
        }
        Rectangle {
            anchors.fill: parent; radius: rail.radius
            color: Qt.rgba(0.07, 0.07, 0.08, 0.62); border { width: 1; color: Qt.rgba(1, 1, 1, 0.1) }
        }
        Column {
            id: railTools
            x: 6; y: 6; spacing: 4
            RailButton { tool: "tone"; label: "Tone"; keys: "T"; path: "M3 6 H8.5 M12.5 6 H17 M3 14 H6.5 M10.5 14 H17 M8.5 6 a2 2 0 1 0 4 0 a2 2 0 1 0 -4 0 M6.5 14 a2 2 0 1 0 4 0 a2 2 0 1 0 -4 0" }
            RailButton { tool: "curve"; label: "Tone curve"; path: "M3.5 3 V16.5 H17 M6 14 C10 14 10.5 6 16 5.5" }
            RailButton { tool: "crop"; label: "Crop"; keys: "C"; path: "M6 2 V14 H18 M2 6 H14 V18" }
            RailButton { tool: "balance"; label: "White balance"; keys: "W"; path: "M10 2.5 a2 2 0 0 1 2 2 V11 a3.6 3.6 0 1 1 -4 0 V4.5 a2 2 0 0 1 2 -2 Z M10 8 V13" }
            Item { width: Theme.railButton; height: 13; Rectangle { x: 4; y: 6; width: parent.width - 8; height: 1; color: Qt.rgba(1, 1, 1, 0.16) } }
            RailButton { tool: "pins"; label: "Pin"; path: "M10 3 a7 7 0 1 0 0.01 0 Z M10 7.6 a2.4 2.4 0 1 0 0.01 0 Z" }
            RailButton { tool: "saturation"; label: "Saturation"; keys: "S"; path: "M10 3 C10 3 4.5 9 4.5 12.2 a5.5 5.5 0 0 0 11 0 C15.5 9 10 3 10 3 Z" }
            RailButton { tool: "eq"; label: "Color EQ"; path: "M5 3 V17 M10 3 V17 M15 3 V17 M3.4 7 H6.6 M8.4 12.5 H11.6 M13.4 6 H16.6" }
            RailButton { tool: "chroma"; label: "Chroma curve"; path: "M3.5 16.5 C10 16.5 7 4 16.5 3.5 M3.5 16.4 V16.6 M16.5 3.4 V3.6" }
            Item { width: Theme.railButton; height: 13; Rectangle { x: 4; y: 6; width: parent.width - 8; height: 1; color: Qt.rgba(1, 1, 1, 0.16) } }
            RailButton {
                label: "Histogram"; path: "M4 16.5 V11 M8 16.5 V5 M12 16.5 V8.5 M16 16.5 V12.5"
                on: session.panels.histogram; onPressed: session.setPanel("histogram", !on)
            }
            RailButton {
                label: "Clipping"; path: "M10 3.5 L17.5 16.5 H2.5 Z M10 8.5 V12 M10 14.3 V14.4"
                on: session.panels.clipping; onPressed: session.setPanel("clipping", !on)
            }
        }
    }
    Column {
        anchors.centerIn: stage; spacing: 10
        visible: (session.source === "" || root.photoFailed) && root.editing
        Label { text: root.photoFailed ? "This photo could not be opened" : "No photo open"; color: Theme.text; font.pixelSize: 15; anchors.horizontalCenter: parent.horizontalCenter }
        Label { text: "Drop a photo here, or"; anchors.horizontalCenter: parent.horizontalCenter }
        PushButton { label: "Open…"; anchors.horizontalCenter: parent.horizontalCenter; onPressed: opener.open() }
    }
    // Fit, 100 %, and what the zoom is now.
    Rectangle {
        objectName: "screen:zoom"
        visible: stage.ready && root.editing
        anchors { horizontalCenter: stage.horizontalCenter; bottom: stage.bottom; bottomMargin: 12 }
        id: zoomBox
        width: zoomRow.width + 6; height: 30; radius: 8; color: "transparent"
        // Glass: the photo behind it blurred and darkened, and an outline (the owner: "a blur
        // glass transparent background and an outline", "make sure the text is readable").
        ShaderEffectSource {
            id: behindZoom
            visible: false
            sourceItem: stage
            sourceRect: Qt.rect(zoomBox.x - stage.x, zoomBox.y - stage.y, zoomBox.width, zoomBox.height)
        }
        Rectangle { id: zoomShape; anchors.fill: parent; radius: zoomBox.radius; visible: false; layer.enabled: true }
        MultiEffect {
            anchors.fill: parent
            source: behindZoom
            blurEnabled: true; blur: 1.0; blurMax: 48; autoPaddingEnabled: false
            maskEnabled: true; maskSource: zoomShape
        }
        Rectangle {
            anchors.fill: parent; radius: zoomBox.radius
            color: Qt.rgba(0.05, 0.05, 0.06, 0.58); border { width: 1; color: Qt.rgba(1, 1, 1, 0.28) }
        }
        Row {
            id: zoomRow
            anchors.centerIn: parent
            // Two buttons, then the zoom in effect as plain dim text behind a divider, so that
            // it reads as a reading and not as a third button.
            Segment { bright: true; label: "Fit"; on: stage.fitted; onChosen: stage.glideFit() }
            Segment { bright: true; label: "1:1"; on: !stage.fitted && Math.abs(stage.zoom - 1) < 0.0005; onChosen: stage.actual() }
            Item {
                width: 60; height: 26
                Rectangle { x: 5; y: 5; width: 1; height: 16; color: Qt.rgba(1, 1, 1, 0.25) }
                Label {
                    objectName: "text:zoom"
                    anchors { fill: parent; leftMargin: 6 }
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    color: Qt.rgba(1, 1, 1, 0.82); font.pixelSize: 12; font.features: { "tnum": 1 }
                    text: Math.round(stage.shown * 100) + " %"
                }
            }
        }
    }
    // ---- The library, in Edit's place while it is on show ---------------------------------
    Library {
        id: shelf
        objectName: "box:library"
        visible: root.place === "library"
        anchors { left: parent.left; right: parent.right; top: topBar.bottom; bottom: foot.top }
        onOpened: (row) => { session.openAt(library.paths(), row); root.show("edit") }
        onFolderAsked: root.pickFolder()
        onFolderMenuAsked: (folder, x, y) => menu.openFolder(folder, x, y)
        onFolderRemoveAsked: (folder) => root.removeFolder(folder)
        onMenuAsked: (rows, x, y) => { const all = library.paths(); menu.open(rows.map(row => all[row]).filter(path => path !== undefined), x, y) }
    }
    // ---- Export, likewise --------------------------------------------------------------------
    Export {
        id: desk
        objectName: "box:export"
        visible: root.place === "export"
        anchors { left: parent.left; right: parent.right; top: topBar.bottom; bottom: foot.top }
        picture: stage.picture; painted: stage.painted; ready: stage.ready
        // How and where to is remembered between runs.
        Component.onCompleted: {
            kind = session.remembered("export/kind", "jpeg"); quality = Number(session.remembered("export/quality", "90"))
            longest = Number(session.remembered("export/longest", "3000")); resized = session.remembered("export/resized", "no") === "yes"
            folder = session.remembered("export/folder", "")
        }
        onKindChanged: session.remember("export/kind", kind)
        onQualityChanged: session.remember("export/quality", String(Math.round(quality)))
        onLongestChanged: session.remember("export/longest", String(Math.round(longest)))
        onResizedChanged: session.remember("export/resized", resized ? "yes" : "no")
        onFolderChanged: session.remember("export/folder", folder)
        onFolderAsked: exportFolder.open()
        onEditAsked: (photo) => root.editPhoto(photo)
    }
    FolderDialog {
        id: exportFolder
        title: "Export to this folder"
        onAccepted: {
            desk.folder = exporter.folder_of(selectedFolder); root.forceActiveFocus()
            if (root.waiting.length) exporter.start(root.waiting, desk.options())
            root.waiting = []
        }
        onRejected: { root.waiting = []; root.forceActiveFocus() }
    }
    Bench { objectName: "bench"; z: 6 }   // (shots show it for a moment)
    // Adding a folder begins where the last one was added from (the owner: the dialog
    // "doesn't remember the last picked path, which is annoying"): in the folder that one is in.
    function pickFolder() {
        const last = session.remembered("library/added", "")
        if (last !== "") folderPicker.currentFolder = last
        folderPicker.open()
    }
    // Taking a folder out of the library asks first (the owner: it "needs a confirmation").
    function removeFolder(folder) {
        confirm.ask("Remove “" + folder.split("/").pop() + "” from the library?",
                    "Its photos stay where they are on the disk. Their edits and marks are kept, and are there again if the folder is added back.",
                    "Remove", () => library.removeFolder(folder))
    }
    FolderDialog {
        id: folderPicker
        title: "Add a folder of photos"
        onAccepted: {
            library.addFolder(selectedFolder)
            session.remember("library/added", String(selectedFolder).replace(/\/[^\/]+\/?$/, ""))
            root.forceActiveFocus()
        }
        onRejected: root.forceActiveFocus()
    }
    FileDialog {
        id: opener
        title: "Open photos"
        fileMode: FileDialog.OpenFiles
        nameFilters: ["Photos (*.arw *.cr2 *.cr3 *.dng *.nef *.orf *.pef *.raf *.rw2 *.jpg *.jpeg *.png *.tif *.tiff)", "All files (*)"]
        onAccepted: { session.open(selectedFiles); root.show("edit") }
        onRejected: root.forceActiveFocus()
    }

    // ---- Leaving a text field ------------------------------------------------------------
    // Every press anywhere comes here first and goes on to what is under it. Pressed outside
    // the text field that has the keys, the field loses them, and so takes its value (a click
    // on a card or on the empty ground would not take them by itself). (docs/PLAN.md §5.)
    // (A handler that only looks on, on an item of its own over everything. As a MouseArea
    // it also took the pointer's shape from all under it: no hand on a card's head, no
    // arrows on a panel's edge, no text cursor on a number; the owner: "i still dont see a
    // cursor change".)
    Item {
        id: leaving
        anchors.fill: parent; z: 1000
        PointHandler {
            acceptedButtons: Qt.AllButtons
            onActiveChanged: {
                if (!active) return
                const field = root.Window.activeFocusItem, at = point.pressPosition
                if (field && field.cursorPosition !== undefined && !field.contains(field.mapFromItem(leaving, at.x, at.y)))
                    root.forceActiveFocus()
            }
        }
    }

    // ---- A tip, at the top of the photo, while a gesture on it needs saying ---------------
    // (The owner: "nobody looks at the bottom of the window", and asked for "a toast-like GUI
    // ... middle-top of the photo view ... short, concise and easy to understand". So the
    // status line is gone; this comes when the thing it is about begins, and fades.)
    Rectangle {
        id: tip
        objectName: "screen:tip"
        readonly property string says: !root.editing || !stage.ready ? ""
            : stage.picking === "neutral" ? "Click something that should be gray  ·  Esc stops"
            : root.cropping ? "Drag the edges  ·  Drag outside to straighten  ·  Enter when done"
            : wheel.mask > 0 && (session.masks[wheel.mask - 1] || {}).kind === "brush" ? "Paint the mask on the photo  ·  Ctrl + wheel sizes the brush  ·  Hold H to see it"
            : wheel.mask > 0 ? "Drag the handles to shape it  ·  Drag outside to turn it  ·  Hold H to see it"
            : ""
        property bool fresh: false
        onSaysChanged: { fresh = says !== ""; if (fresh) fading.restart() }
        Timer { id: fading; interval: 5000; onTriggered: tip.fresh = false }
        opacity: fresh ? 1 : 0; visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 250 } }
        anchors { horizontalCenter: stage.horizontalCenter; top: stage.top; topMargin: 14 }
        width: tipText.implicitWidth + 32; height: 32; radius: 16
        color: Qt.rgba(0.07, 0.07, 0.08, 0.86); border { width: 1; color: Qt.rgba(1, 1, 1, 0.12) }
        Accessible.role: Accessible.StaticText; Accessible.name: says
        Label { id: tipText; anchors.centerIn: parent; text: tip.says; color: Theme.text; font.pixelSize: 13 }
    }

    // ---- What went wrong, in one sentence; click to dismiss -------------------------------
    Rectangle {
        objectName: "screen:notice"
        visible: session.error !== ""
        // Above the zoom control when that is there: two floating things never share a place.
        anchors { horizontalCenter: stage.horizontalCenter; bottom: stage.bottom; bottomMargin: stage.ready ? 54 : 16 }
        width: Math.min(message.implicitWidth + 28, stage.width * 0.8); height: message.height + 20
        radius: 8; color: Theme.raised; border { width: 1; color: Theme.faint }
        Accessible.role: Accessible.AlertMessage; Accessible.name: session.error
        Label {
            id: message
            anchors.centerIn: parent; width: parent.width - 28
            text: session.error; color: Theme.text; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter
        }
        MouseArea { anchors.fill: parent; onClicked: session.say("") }
    }

    // ---- What can be done with a photo: a right click on it, in the filmstrip or the library -
    // (the owner: "a right-click context menu on images on the film strip AND in the library").
    // Copy and Paste edits come here with M21.
    // Export these at once, as the Export page has it set up (the owner: "a context menu with
    // options that make sense, mainly Export All (number)"); the footer says how far it is.
    // With no folder chosen yet, that is asked first.
    // Open a photo in Edit by its path (from the log of exports): among the photos the
    // library is showing if it is one of them, else among all of them, else alone.
    function editPhoto(path) {
        let row = library.rowOf(path)
        if (row < 0) { library.show("all"); row = library.rowOf(path) }
        if (row >= 0) session.openAt(library.paths(), row)
        else session.open([path])
        if (session.path === path) show("edit")
    }
    property var waiting: []
    function exportNow(paths) {
        if (exporter.running) return
        if (desk.folder === "") { waiting = paths; return exportFolder.open() }
        exporter.start(paths, desk.options())
    }
    // The open photo is reset as any edit is made (one step of undo, its thumbnail made from
    // what is on screen); the others in the catalog, where the reset becomes a step of theirs.
    function resetThese(paths) {
        const open = paths.includes(session.path)
        if (open) { session.resetAll(); session.flush() }
        library.resetEdits(open && editing ? paths.filter(path => path !== session.path) : paths)
    }
    Item {
        id: menu
        anchors.fill: parent
        z: 9
        visible: false
        property var photos: []
        property string folder: ""   // set: the menu is a folder's, not photos'
        function openFolder(path, x, y) { folder = path; photos = []; place(x, y) }
        function open(paths, x, y) {
            if (!paths.length) return
            photos = paths; folder = ""
            place(x, y)
        }
        function place(x, y) {
            card.x = Math.min(x, width - card.width - 6); card.y = Math.min(y, height - card.height - 6)
            visible = true
            card.forceActiveFocus()
        }
        function close() { visible = false; root.forceActiveFocus() }
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onPressed: menu.close(); onWheel: (wheel) => menu.close() }
        Rectangle {
            id: card
            objectName: "modal:menu"
            width: 210; height: entries.height + 8; radius: 8
            color: Theme.panel; border { width: 1; color: Theme.faint }
            Accessible.role: Accessible.PopupMenu; Accessible.name: menu.folder !== "" ? "Folder" : "Photo"
            Keys.onPressed: (event) => { if (event.key === Qt.Key_Escape) menu.close(); event.accepted = true }   // (its own while it is open)
            MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }   // (a press on the card itself is not one beside it)
            Column {
                id: entries
                x: 4; y: 4; width: parent.width - 8
                component Entry: Rectangle {
                    property string label
                    signal pressed()
                    width: parent.width; height: 30; radius: 5
                    color: entryArea.containsMouse ? Theme.selected : "transparent"
                    Accessible.role: Accessible.MenuItem; Accessible.name: label
                    Label { x: 10; anchors.verticalCenter: parent.verticalCenter; text: parent.label; color: Theme.text }
                    MouseArea { id: entryArea; anchors.fill: parent; hoverEnabled: true; onClicked: { menu.close(); parent.pressed() } }
                }
                Label {
                    x: 10; height: 24; verticalAlignment: Text.AlignVCenter; font.pixelSize: 11; color: Theme.faint
                    width: parent.width - 20; elide: Text.ElideMiddle
                    text: menu.folder !== "" ? menu.folder.split("/").pop() : menu.photos.length === 1 ? String(menu.photos[0]).split("/").pop() : menu.photos.length + " photos"
                }
                // (The owner: "right-click a folder entry in both the Library AND the card on
                // the Edit page ... a `Show in explorer` option". Offered for a photo too.)
                Entry {
                    objectName: "menu-reveal"; label: "Show in file manager"
                    onPressed: library.reveal(menu.folder !== "" ? menu.folder : String(menu.photos[0]))
                }
                Entry { objectName: "menu-remove-folder"; visible: menu.folder !== ""; label: "Remove from library…"; onPressed: root.removeFolder(menu.folder) }
                Entry {
                    objectName: "menu-export"; visible: menu.folder === ""; opacity: exporter.running ? 0.4 : 1
                    label: exporter.running ? "An export is running" : menu.photos.length > 1 ? "Export all (" + menu.photos.length + ")" : "Export"
                    onPressed: root.exportNow(menu.photos)
                }
                Entry {
                    objectName: "menu-reset"; label: "Reset edits…"; visible: menu.folder === ""
                    onPressed: {
                        const these = menu.photos, one = these.length === 1
                        confirm.ask(one ? "Reset the edits of “" + these[0].split("/").pop() + "”?" : "Reset the edits of " + these.length + " photos?",
                                    (one ? "The photo goes" : "They go") + " back to how " + (one ? "it was" : "they were") + " shot. Checkpoints stay, and with "
                                    + (one ? "the" : "a") + " photo open, Undo brings its edit back.",
                                    "Reset edits", () => root.resetThese(these))
                    }
                }
            }
        }
    }

    // ---- A question that must be answered before anything else ---------------------------
    Item {
        id: confirm
        anchors.fill: parent
        z: 10
        visible: false
        property var then: null
        function ask(title, text, action, then) {
            question.text = title; detail.text = text; yes.label = action; confirm.then = then
            visible = true
            no.forceActiveFocus()   // the safe answer is the one under the keys
        }
        function answer(agreed) {
            visible = false
            root.forceActiveFocus()
            if (agreed && then) then()
            then = null
        }
        // While it is up, the keys are its own: the arrows (and Tab) go from one button to the
        // other, Enter or Space presses the one that has them, Escape is Cancel; nothing reaches
        // what lies under it (the arrows stepped through the photos behind the question).
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape) answer(false)
            else if ([Qt.Key_Left, Qt.Key_Right, Qt.Key_Up, Qt.Key_Down, Qt.Key_Tab, Qt.Key_Backtab].includes(event.key))
                (yes.activeFocus ? no : yes).forceActiveFocus()
            event.accepted = true
        }
        Keys.onReleased: (event) => event.accepted = true
        Rectangle { anchors.fill: parent; color: Theme.bg; opacity: 0.6 }
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; hoverEnabled: true; onWheel: (wheel) => wheel.accepted = true }
        Rectangle {
            objectName: "modal:confirm"
            anchors.centerIn: parent
            width: 400; height: words.height + 40; radius: 10
            color: Theme.panel; border { width: 1; color: Theme.faint }
            Accessible.role: Accessible.Dialog; Accessible.name: question.text
            Column {
                id: words
                x: 20; y: 20; width: parent.width - 40; spacing: 10
                Label { id: question; width: parent.width; color: Theme.text; font.pixelSize: 15; wrapMode: Text.WordWrap }
                Label { id: detail; width: parent.width; wrapMode: Text.WordWrap }
                Row {
                    anchors.right: parent.right; spacing: 8; topPadding: 6
                    PushButton { id: no; objectName: "confirm-no"; label: "Cancel"; onPressed: confirm.answer(false) }
                    PushButton { id: yes; objectName: "confirm-yes"; onPressed: confirm.answer(true) }
                }
            }
        }
    }
}
