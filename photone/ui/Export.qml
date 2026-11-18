import QtQuick
import "."

// Export: how photos are exported (as what kind of file, how large, where to; remembered
// between runs and used by every export), the open photo as it will be exported with one
// button for it, and the last files exported. Several photos are exported from where they
// are selected, the library or the filmstrip, by their menu (the owner: "only for configuring
// exports and optionally exporting a single currently opened photo with a preview").
Rectangle {
    id: root
    property var picture: null   // the open photo's picture and its painted masks (PhotoView's)
    property var painted: null
    property var lut: null   // the open photo's LUT as a picture (PhotoView.lut), or none
    property bool ready: false   // that picture is there
    signal folderAsked()
    signal markFileAsked()   // choose the picture that is the watermark
    // The watermark's scale and opacity while their sliders are dragged: this page's own
    // numbers, which the watermark on the photo here follows at once; Python is told when a
    // slider is let go.
    property real markScale: 4
    property real markStrength: 60
    function markTaken() { markScale = exporter.mark.size; markStrength = exporter.mark.strength }
    Component.onCompleted: markTaken()
    Connections { target: exporter; function onMarkChanged() { root.markTaken() } }
    signal editAsked(string photo)   // open that photo in Edit
    property string kind: "jpeg"
    property real quality: 90
    property bool resized: false
    property real longest: 3000
    property string folder: ""
    // Several photos selected where the page was come from (the library, the filmstrip): then
    // it shows them all and its button exports them (the owner: "the export page should show
    // them all and the rest should adjust accordingly"). Else: the open photo.
    property var photos: []
    readonly property bool many: photos.length > 1
    readonly property bool has: session.path !== "" && ready
    readonly property bool can: (many || has) && !exporter.running
    function options() { return { kind: kind, quality: Math.round(quality), longest: resized ? Math.round(longest) : 0, folder: folder } }
    function start() { if (folder === "") folderAsked(); else exporter.start(many ? photos : [session.path], options()) }
    // How large the file's picture will be, and what it will be called.
    readonly property real by: resized ? Math.min(1, longest / Math.max(1, session.fullWidth, session.fullHeight)) : 1
    readonly property string ending: ({ jpeg: ".jpg", png8: ".png", png16: ".png", tiff16: ".tif" })[kind]
    function size(bytes) { return bytes >= 1048576 ? (bytes / 1048576).toFixed(1) + " MB" : Math.max(1, Math.round(bytes / 1024)) + " kB" }
    color: Theme.bg

    component Heading: Label {
        topPadding: 22; bottomPadding: 8; color: Theme.text   // (bright, as the library's headings are: the owner's wish)
        font.pixelSize: Theme.smallSize; font.weight: Font.DemiBold; font.letterSpacing: 0.9
    }
    component Choice: Rectangle {
        property bool on: false
        property string words
        property string more: ""
        signal picked()
        width: parent ? parent.width : 0; height: 34; radius: 6
        color: on ? Theme.raised : over.containsMouse ? Qt.darker(Theme.raised, 1.25) : "transparent"
        activeFocusOnTab: true
        Accessible.role: Accessible.RadioButton; Accessible.name: words; Accessible.checked: on
        Keys.onSpacePressed: picked()
        border { width: activeFocus ? 1 : 0; color: Theme.text }
        Rectangle { x: 12; width: 10; height: 10; radius: 5; anchors.verticalCenter: parent.verticalCenter; color: parent.on ? Theme.text : "transparent"; border { width: 1; color: Theme.dim } }
        Label { x: 34; anchors.verticalCenter: parent.verticalCenter; text: parent.words; color: parent.on ? Theme.text : Theme.dim }
        Label { anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter } text: parent.more; font.pixelSize: 12; color: Theme.faint }
        MouseArea { id: over; anchors.fill: parent; hoverEnabled: true; onClicked: parent.picked() }
    }

    // ---- the open photo, as it will be exported -------------------------------------------
    Item {
        id: stand
        readonly property int cell: {
            for (let s = 260; s > 110; s -= 10) if (Math.floor(width / s) * Math.floor(height / s) >= root.photos.length) return s
            return 110
        }
        readonly property int across: Math.max(1, Math.min(root.photos.length, Math.floor(width / cell)))
        anchors { left: parent.left; right: side.left; top: parent.top; bottom: parent.bottom; margins: 24; bottomMargin: 56 }
        Pipeline {
            id: shot
            objectName: "export-preview"
            visible: root.has && !root.many
            readonly property real fit: Math.min(stand.width / Math.max(1, session.fullWidth), stand.height / Math.max(1, session.fullHeight))
            width: Math.round(session.fullWidth * fit); height: Math.round(session.fullHeight * fit)
            anchors.centerIn: parent
            source: root.picture; painted: root.painted || root.picture; lutPicture: root.lut
            Local { over: shot; layers: session.maskLayers }
            Mark { wide: session.fullWidth; high: session.fullHeight; scale: root.markScale; strength: root.markStrength }
        }
        GridView {
            id: sheet
            objectName: "export-sheet"
            visible: root.many
            // (Cells as large as lets them all be seen at once, between 110 and 260 px; in the
            // middle: as wide as its columns, and no higher than its rows.)
            readonly property int each: stand.cell   // (not `side`: that is the column's id here, and the id wins)
            width: stand.across * each; height: Math.min(stand.height, Math.ceil(root.photos.length / stand.across) * each)
            anchors.centerIn: parent
            clip: true; boundsBehavior: Flickable.StopAtBounds
            cellWidth: each; cellHeight: each
            model: root.many ? root.photos : []
            delegate: Item {
                required property var modelData
                required property int index
                objectName: "export-photo:" + index
                width: sheet.each; height: sheet.each
                Image {
                    anchors { fill: parent; margins: 5; bottomMargin: 22 }
                    source: (library.thumbs, library.thumbFor(modelData)); asynchronous: true; fillMode: Image.PreserveAspectFit
                    sourceSize: Qt.size(320, 320)
                }
                Label {
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 4 }
                    width: parent.width - 10; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideMiddle
                    font.pixelSize: 11; color: Theme.dim; text: String(modelData).split("/").pop()
                }
            }
        }
        Label {
            visible: !root.has && !root.many
            anchors.centerIn: parent; width: Math.min(parent.width, 420); wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter
            color: Theme.faint
            text: session.path !== "" ? "Loading the photo…" : "No photo is open.\nOpen one in Edit to export it here. To export several, select them in the library or the filmstrip (Ctrl or Shift and a click) and right click."
        }
    }
    Label {
        objectName: "export-file"
        visible: root.has || root.many
        anchors { horizontalCenter: stand.horizontalCenter; top: stand.bottom; topMargin: 14 }
        color: Theme.dim; font.features: { "tnum": 1 }
        text: root.many ? root.photos.length + " photos  ·  " + root.ending.slice(1).toUpperCase() + "  ·  " + (root.resized ? "longer side " + Math.round(root.longest) + " px at most" : "full size")
            : session.name.replace(/\.[^.]+$/, "") + root.ending + "  ·  " + Math.round(session.fullWidth * root.by) + " × " + Math.round(session.fullHeight * root.by) + " px"
    }

    // ---- how, where to, the button, and what was exported last ---------------------------
    Rectangle {
        id: side
        anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
        width: Math.min(420, parent.width * 0.45); color: Theme.panel
        Rectangle { width: 1; height: parent.height; color: Theme.line }
    }
    Column {
        id: form
        objectName: "export-form"
        anchors { top: side.top; left: side.left; right: side.right; leftMargin: 20; rightMargin: 20 }

        Heading { text: "AS"; topPadding: 16 }
        Rectangle {
            width: parent.width; height: 30; radius: 7; color: Theme.raised
            Row {
                id: kinds
                anchors.centerIn: parent
                Repeater {
                    model: [["jpeg", "JPEG"], ["png8", "PNG 8 bit"], ["png16", "PNG 16 bit"], ["tiff16", "TIFF 16 bit"]]
                    Segment {
                        required property var modelData
                        objectName: "export-kind:" + modelData[0]
                        width: (form.width - 4) / 4; label: modelData[1]; on: root.kind === modelData[0]; onChosen: root.kind = modelData[0]
                    }
                }
            }
        }
        Item { width: 1; height: 8 }
        ParamSlider {
            objectName: "export-quality"
            width: parent.width; visible: root.kind === "jpeg"
            name: "Quality"; from: 50; to: 100; neutral: 90; step: 1; digits: 0; signed: false
            value: root.quality; onMoved: (v) => root.quality = v; onReset: root.quality = 90
        }

        Heading { text: "HOW LARGE" }
        Rectangle {
            width: parent.width; height: 30; radius: 7; color: Theme.raised
            Row {
                anchors.centerIn: parent
                Segment { objectName: "export-full"; width: (form.width - 4) / 2; label: "Full size"; on: !root.resized; onChosen: root.resized = false }
                Segment { objectName: "export-resized"; width: (form.width - 4) / 2; label: "Smaller"; on: root.resized; onChosen: root.resized = true }
            }
        }
        Item { width: 1; height: 8 }
        ParamSlider {
            objectName: "export-longest"
            width: parent.width; visible: root.resized
            name: "Longer side"; unit: "px"; from: 400; to: 8000; neutral: 3000; step: 50; digits: 0; signed: false; logarithmic: true
            value: root.longest; onMoved: (v) => root.longest = v; onReset: root.longest = 3000
        }

        Heading { text: "WHERE TO" }
        Item {
            width: parent.width; height: 34
            // The path, in a darker field of its own so that it reads as a value and not as
            // a heading (the owner: "a darker rectangle underneath"); a click on it chooses too.
            Rectangle {
                anchors { left: parent.left; right: choose.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                height: 30; radius: 6; color: Theme.bg; border { width: 1; color: Theme.line }
                Label {
                    objectName: "export-folder"
                    anchors { left: parent.left; right: parent.right; leftMargin: 10; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    elide: Text.ElideMiddle; color: root.folder === "" ? Theme.faint : Theme.dim; font.pixelSize: 12
                    text: root.folder === "" ? "No folder chosen yet" : root.folder
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.folderAsked() }
            }
            PushButton { id: choose; objectName: "export-choose"; anchors { right: parent.right; verticalCenter: parent.verticalCenter } label: "Choose…"; onPressed: root.folderAsked() }
        }
        // The watermark every export gets: nothing, some text, or a picture; where on the
        // photo, how large, how strong. Shown here on the photo, and in Edit unless hidden there.
        Heading { text: "WATERMARK" }
        Rectangle {
            width: parent.width; height: 30; radius: 7; color: Theme.raised
            Row {
                anchors.centerIn: parent
                Repeater {
                    model: [["none", "None"], ["text", "Text"], ["picture", "Picture"]]
                    Segment {
                        required property var modelData
                        objectName: "mark-kind:" + modelData[0]
                        width: (form.width - 4) / 3; label: modelData[1]; on: exporter.mark.kind === modelData[0]; onChosen: exporter.setMark({ kind: modelData[0] })
                    }
                }
            }
        }
        Item { width: 1; height: 8; visible: exporter.mark.kind !== "none" }
        Rectangle {
            visible: exporter.mark.kind === "text"
            width: parent.width; height: 30; radius: 6; color: Theme.bg; border { width: 1; color: markText.activeFocus ? Theme.text : Theme.faint }
            TextInput {
                id: markText
                objectName: "mark-text"
                anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                verticalAlignment: TextInput.AlignVCenter; clip: true; maximumLength: 120
                color: Theme.text; selectionColor: Theme.faint; selectedTextColor: Theme.text
                font.family: Theme.font; font.pixelSize: Theme.fontSize
                Accessible.name: "The watermark's text"
                text: exporter.mark.text
                onTextEdited: exporter.setMark({ text: text })
                Keys.onReturnPressed: (event) => { root.forceActiveFocus(); event.accepted = true }
                Keys.onEscapePressed: (event) => { root.forceActiveFocus(); event.accepted = true }
                Label { visible: parent.text === "" && !parent.activeFocus; anchors.verticalCenter: parent.verticalCenter; text: "© Your name"; color: Theme.faint }
            }
        }
        Item {
            visible: exporter.mark.kind === "picture"
            width: parent.width; height: 34
            Rectangle {
                anchors { left: parent.left; right: markChoose.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                height: 30; radius: 6; color: Theme.bg; border { width: 1; color: Theme.line }
                Label {
                    objectName: "mark-file"
                    anchors { left: parent.left; right: parent.right; leftMargin: 10; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    elide: Text.ElideMiddle; font.pixelSize: 12
                    // (A file that is no picture any more: said here, and no watermark is drawn.)
                    readonly property bool lost: exporter.mark.file !== "" && (exporter.mark, exporter.markPlace(1000, 1000)).length === 0
                    color: lost ? Theme.red : exporter.mark.file === "" ? Theme.faint : Theme.dim
                    text: exporter.mark.file === "" ? "No picture chosen yet" : (lost ? "Cannot be read: " : "") + exporter.mark.file
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.markFileAsked() }
            }
            PushButton { id: markChoose; objectName: "mark-choose"; anchors { right: parent.right; verticalCenter: parent.verticalCenter } label: "Choose…"; onPressed: root.markFileAsked() }
        }
        Item {
            visible: exporter.mark.kind !== "none"
            width: parent.width; height: 118
            // Where on the photo: a rectangle with nine points, its corners, the middles of its
            // sides and its middle (the owner's wish). The point chosen is also what the
            // watermark is held by: its own corner, side or middle lies there.
            Item {
                id: places
                objectName: "mark-places"
                y: 8; width: 100; height: 70
                Accessible.role: Accessible.Grouping; Accessible.name: "Where on the photo"
                Rectangle { x: 8; y: 8; width: parent.width - 16; height: parent.height - 16; radius: 3; color: Theme.bg; border { width: 1; color: Theme.faint } }
                Repeater {
                    model: 9
                    Item {
                        required property int index
                        readonly property bool on: exporter.mark.place === index
                        objectName: "mark-place:" + index
                        x: index % 3 * (places.width - 16) / 2 - 3; y: Math.floor(index / 3) * (places.height - 16) / 2 - 3; width: 22; height: 22
                        Accessible.role: Accessible.RadioButton; Accessible.checked: on
                        Accessible.name: ["Top", "Middle", "Bottom"][Math.floor(index / 3)] + " " + ["left", "middle", "right"][index % 3]
                        Rectangle {
                            anchors.centerIn: parent; width: parent.on ? 12 : 8; height: width; radius: width / 2
                            color: parent.on ? Theme.mark : overPlace.containsMouse ? Theme.text : Theme.dim
                            border { width: parent.on ? 0 : 1; color: Theme.bg }
                        }
                        MouseArea { id: overPlace; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: exporter.setMark({ place: index }) }
                    }
                }
            }
            Column {
                anchors { left: places.right; leftMargin: 16; right: parent.right }
                // (In steps too fine to see: at half a percent a step the watermark jumped by
                // 23 px on a 33 MP photo; the owner: "still isnt very smooth".)
                ParamSlider {
                    objectName: "mark-size"
                    width: parent.width
                    name: "Scale"; unit: "%"; from: 1; to: 30; neutral: 4; step: 0.01; digits: 1; signed: false; logarithmic: true
                    value: root.markScale; onMoved: (v) => root.markScale = v
                    onReleased: exporter.setMark({ size: root.markScale }); onReset: exporter.setMark({ size: 4 })
                }
                ParamSlider {
                    objectName: "mark-strength"
                    width: parent.width
                    name: "Opacity"; unit: "%"; from: 5; to: 100; neutral: 0; step: 0.1; digits: 0; signed: false
                    value: root.markStrength; onMoved: (v) => root.markStrength = v
                    onReleased: exporter.setMark({ strength: root.markStrength }); onReset: exporter.setMark({ strength: 60 })
                }
            }
            Rectangle {   // (a switch as the Edit screen's are, drawn here: this file has no OnOff)
                objectName: "mark-shown"
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 28; color: "transparent"
                Accessible.role: Accessible.CheckBox; Accessible.name: "Show it on the photo in Edit"; Accessible.checked: exporter.markShown
                Label { anchors.verticalCenter: parent.verticalCenter; text: "Show it on the photo in Edit"; color: exporter.markShown ? Theme.text : Theme.dim }
                Rectangle {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    width: 36; height: 20; radius: 10
                    color: exporter.markShown ? Theme.mark : Theme.bg; border { width: 1; color: exporter.markShown ? Theme.mark : Theme.faint }
                    Rectangle {
                        x: exporter.markShown ? parent.width - width - 3 : 3; anchors.verticalCenter: parent.verticalCenter
                        width: 14; height: 14; radius: 7; color: exporter.markShown ? Theme.bg : Theme.dim
                    }
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: exporter.setMarkShown(!exporter.markShown) }
            }
        }
        // (A file that is there is never replaced: export.destination. It is not said here; the
        // owner found the sentence, and the one under the button, awkward. A finished export
        // shows as new rows in the list below; only a failure is spelled out.)
        Item { width: 1; height: 20 }
        Item {
            width: parent.width; height: 40
            PushButton {
                objectName: "export-go"
                visible: !exporter.running
                width: parent.width; height: 40; opacity: root.can ? 1 : 0.4
                label: root.many ? "Export " + root.photos.length + " photos" : "Export this photo"
                onPressed: if (root.can) root.start()
            }
            // While it runs: how far it is, and a way to stop after the photo under way.
            Rectangle {
                visible: exporter.running
                width: parent.width - stop.width - 12; height: 8; radius: 4; color: Theme.raised
                anchors.verticalCenter: parent.verticalCenter
                Rectangle {
                    objectName: "export-progress"
                    width: parent.width * (exporter.total ? exporter.finished / exporter.total : 0); height: parent.height; radius: 4; color: Theme.text
                }
            }
            PushButton { id: stop; objectName: "export-stop"; visible: exporter.running; anchors { right: parent.right; verticalCenter: parent.verticalCenter } label: "Stop"; onPressed: exporter.stop() }
        }
        Label {
            objectName: "export-said"
            visible: text !== ""
            width: parent.width; wrapMode: Text.WordWrap; font.pixelSize: 12; topPadding: 10
            color: exporter.failures.length ? Theme.mark : Theme.dim
            text: exporter.running ? "Exporting photo " + Math.min(exporter.total, exporter.finished + 1) + " of " + exporter.total + "…" : exporter.failures.join("\n")
        }
        Item {
            width: parent.width; height: 46
            Heading { text: "LAST EXPORTED"; anchors.bottom: parent.bottom }
            TextButton {
                objectName: "export-forget"
                visible: exporter.recent.length > 0
                anchors { right: parent.right; bottom: parent.bottom; bottomMargin: 7 }
                text: "Clear"; font.pixelSize: 12; onPressed: exporter.forget()
            }
        }
    }
    // The last files exported, the newest first (the owner: "a short log of last exported
    // files"). A click shows the file in the file manager (its folder, if the file is gone).
    ListView {
        id: log
        objectName: "export-log"
        anchors { top: form.bottom; left: form.left; right: form.right; bottom: parent.bottom; bottomMargin: 12 }
        clip: true; boundsBehavior: Flickable.StopAtBounds
        model: exporter.recent
        delegate: Rectangle {
            required property var modelData
            required property int index
            objectName: "export-row:" + index
            width: log.width; height: 48; radius: 6
            color: overRow.containsMouse ? Theme.raised : "transparent"
            Accessible.role: Accessible.Button; Accessible.name: modelData.name + ", show in file manager"
            Image { x: 6; y: 4; width: 40; height: 40; source: modelData.thumb || ""; fillMode: Image.PreserveAspectFit; asynchronous: true }
            Label { x: 56; y: 7; width: parent.width - 96; elide: Text.ElideMiddle; text: modelData.name; color: Theme.text }
            Label {
                x: 56; y: 25; width: parent.width - 96; elide: Text.ElideRight; font.pixelSize: 11; color: Theme.faint; font.features: { "tnum": 1 }
                text: modelData.wide + " × " + modelData.high + "  ·  " + root.size(modelData.bytes) + "  ·  " + Qt.formatDateTime(new Date(modelData.when * 1000), "d MMM, hh:mm")
            }
            MouseArea { id: overRow; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: library.reveal(modelData.path) }
            // Back to the photo it was made from (the owner: "open the file in the editor so
            // i can come back to it").
            TextButton {
                objectName: "export-edit:" + index
                visible: !!modelData.source
                anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                sign: Theme.pencilSign; says: "Edit this photo"; glow: Theme.green
                onPressed: root.editAsked(modelData.source)
            }
        }
        Label { visible: log.count === 0; x: 0; y: 6; color: Theme.faint; font.pixelSize: 12; text: "Nothing yet." }
    }
}
