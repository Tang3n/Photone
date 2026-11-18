import QtQuick
import "."

// The watermark, laid over a picture of the photo (its parent, which it fills): the very
// image an export scales and paints on the file (export.mark_base), where an export puts it
// and as strong. `wide`, `high`: the photo's size in pixels, which the watermark's size goes
// by. Its scale, opacity and place are plain numbers of this item, and where it lies is
// worked out here (as export.mark_size and mark_at do; the audit "(mark)" holds the two
// together): a slider that moves them reaches nothing but this, no Python and no picture.
// (Each step went to Python and back several times; the owner: "inefficiently handled".)
Item {
    id: mark
    property real wide: 0
    property real high: 0
    property real scale: exporter.mark.size          // percent of the photo's shorter side
    property real strength: exporter.mark.strength   // percent
    property int place: exporter.mark.place          // 0 top left … 8 bottom right
    readonly property bool there: picture.status === Image.Ready && picture.implicitWidth > 1 && wide > 0 && high > 0
    readonly property real edge: Math.round(0.03 * Math.min(wide, high))
    readonly property var size: {
        const tall = Math.max(4, scale / 100 * Math.min(wide, high))
        const across = picture.implicitWidth * tall / Math.max(1, picture.implicitHeight)
        const fit = Math.min(1, Math.max(8, wide - 2 * edge) / Math.max(1, across))
        return Qt.size(Math.max(1, Math.round(across * fit)), Math.max(1, Math.round(tall * fit)))
    }
    readonly property real by: wide > 0 ? width / wide : 0   // the photo on screen, to the photo in pixels
    anchors.fill: parent
    Image {
        id: picture
        objectName: "watermark"
        visible: mark.there
        x: [mark.edge, Math.floor((mark.wide - mark.size.width) / 2), mark.wide - mark.size.width - mark.edge][mark.place % 3] * mark.by
        y: [mark.edge, Math.floor((mark.high - mark.size.height) / 2), mark.high - mark.size.height - mark.edge][Math.floor(mark.place / 3)] * mark.by
        width: mark.size.width * mark.by; height: mark.size.height * mark.by
        source: exporter.mark.kind !== "none" ? "image://photo/mark/" + exporter.markSerial + "/base" : ""
        opacity: mark.strength / 100
        // (Fetched beside the interface, never while it waits: fetched in line, the interface
        // waited for Qt's loader thread, which waited for Python, which the interface held.)
        asynchronous: true
        cache: false; smooth: true; mipmap: true
    }
}
