import QtQuick
import "."

// What is counted as numbers (photone/scopes.py: what Fit frames, the histogram's corners,
// the colors a pin is picked from, and what the checks look at): six small renders of the pipeline,
// three by two (the mipmaps average the photo down): the picture as displayed in SDR, its
// lightness before the tone curve, its OKLab colors after the curve in two tiles, and the same
// after the pins. Never on show; rendered and read back a moment after anything changes.
Grid {
    id: scopes
    property var source            // the photo's first picture (an Image)
    property var painted           // its painted masks' picture (PhotoView.painted)
    property var lut: null         // its LUT's picture (PhotoView.lut), or none
    property bool ready: false     // there is a photo to count
    property int mask: 0           // the mask being worked on: the wheel and the histograms count only what it reaches
    onMaskChanged: count.start()
    // The edit as numbers, as it was when the renders were last asked for: they are only
    // needed at a count, not at every change of a slider being dragged.
    property var numbers: session.inFrame
    function refresh() { numbers = session.inFrame }
    Component.onCompleted: refresh()   // (an assignment: from here on it only follows `refresh`)
    visible: false
    columns: 3
    Repeater {
        model: 6
        Pipeline { width: 256; height: 256; source: scopes.source; painted: scopes.painted || scopes.source; lutPicture: scopes.lut; follows: true; edit: scopes.numbers; scope: index; showMask: index > 1 ? scopes.mask : 0; peak: 1; hdrLift: 0; linearOut: 0 }
    }
    Timer {
        id: count
        interval: 40
        onTriggered: {
            if (!(scopes.ready && scopes.Window.window && scopes.Window.window.visible)) return
            // One render under way at a time: asked for again before the last had come
            // back (every 40 ms, whatever the frames were doing), they piled up whenever a
            // frame took longer than that, each one more render for the frames to come.
            if (scopes.asked) { scopes.again = true; return }
            scopes.asked = true
            scopes.refresh()
            // (Taken by the session, not by a function here: app.Session.grabScope says why.)
            if (!session.grabScope(scopes)) scopes.asked = false
        }
    }
    Connections {
        target: session
        function onScopeTaken() {
            scopes.asked = false
            if (scopes.again) { scopes.again = false; count.start() }
        }
    }
    property bool asked: false   // a render has been asked for and is not back yet
    property bool again: false   // and something changed meanwhile
    // Once changes pause, not while something is dragged: a count is a render read back and
    // some milliseconds on a thread that shares the interpreter with the interface. (25 times
    // a second through a drag, with every graph drawn anew after each, a mask dragged ran at
    // 50 frames a second.) Nothing that is drawn waits for it: the graphs are Counts.qml's.
    Timer { id: paused; interval: 120; onTriggered: count.start() }
    Connections { target: session; function onChanged() { paused.restart() } }
    onReadyChanged: count.start()
}
