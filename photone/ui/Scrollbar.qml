import QtQuick
import "."

// A scrollbar for something that scrolls (`of`), upright or lying flat (`across`): where the
// view is, to take hold of and drag; a press beside the thumb brings the view there. It also
// answers the mouse wheel for that view (`turned`, called by a MouseArea that lies under what
// scrolls): a notch goes `step` pixels, gliding; a touchpad goes by its own pixels. And it can
// mark one place on its way (`mark`): where the open photo is in the filmstrip.
Item {
    id: bar
    property Flickable of
    property bool across: false            // it lies flat and scrolls sideways
    property real step: 80                 // what one notch of a mouse wheel scrolls, in pixels
    property real mark: -1                 // a place to mark, 0..1 of all there is; none below zero
    readonly property real all: of ? (across ? of.contentWidth : of.contentHeight) : 0
    readonly property real seen: of ? (across ? of.width : of.height) : 0
    readonly property real reach: Math.max(0, all - seen)
    readonly property real at: of ? (across ? of.contentX - of.originX : of.contentY - of.originY) : 0
    readonly property real run: across ? width : height
    readonly property real grip: Math.max(36, Math.min(run, all > 0 ? seen / all * run : 0))
    readonly property real room: run - grip
    readonly property bool lit: grab.containsMouse || grab.pressed
    visible: reach > 0.5
    implicitWidth: 14; implicitHeight: 14
    function go(to) {
        to = Math.max(0, Math.min(reach, to))
        if (across) of.contentX = of.originX + to; else of.contentY = of.originY + to
    }
    function turned(wheel) {
        if (reach <= 0.5) return
        const pixels = across && wheel.pixelDelta.x !== 0 ? wheel.pixelDelta.x : wheel.pixelDelta.y
        const notches = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x
        // (Asked before the glide is stopped: a notch during one goes on from where that one
        // was going, so a wheel turned fast goes as far as its notches say, and so faster.)
        const from = gliding ? aim : at
        glide.stop()
        if (pixels !== 0 && notches % 120 !== 0) return go(at - pixels)   // a touchpad: as far as it says
        glide.from = at
        glide.to = Math.max(0, Math.min(reach, from - notches / 120 * step))
        aim = glide.to
        glide.start()
    }
    property real aim: 0
    readonly property bool gliding: glide.running
    // (It glides by a number of its own, so that it works the same upright and flat.)
    NumberAnimation { id: glide; target: slide; property: "at"; duration: 110; easing.type: Easing.OutCubic }
    QtObject { id: slide; property real at: 0; onAtChanged: if (glide.running) bar.go(at) }
    Rectangle {   // the place marked
        visible: bar.mark >= 0
        x: bar.across ? Math.round(bar.mark * (bar.width - 3)) : 2
        y: bar.across ? 2 : Math.round(bar.mark * (bar.height - 3))
        width: bar.across ? 3 : bar.width - 4; height: bar.across ? bar.height - 4 : 3; radius: 1.5
        color: Theme.mark
    }
    Rectangle {
        id: thumb
        objectName: "thumb"
        readonly property real along: bar.reach > 0 ? bar.at / bar.reach * bar.room : 0
        readonly property real thick: bar.lit ? 8 : 5
        x: bar.across ? along : (bar.lit ? 3 : 5); y: bar.across ? (bar.lit ? 3 : 5) : along
        width: bar.across ? bar.grip : thick; height: bar.across ? thick : bar.grip; radius: thick / 2
        color: grab.pressed ? Theme.text : bar.lit ? Theme.dim : Theme.faint
        opacity: 0.9
    }
    MouseArea {
        id: grab
        anchors.fill: parent
        hoverEnabled: true
        property real from
        property real start
        function place(mouse) { return bar.across ? mouse.x : mouse.y }
        function to(along) { bar.go(along / Math.max(1, bar.room) * bar.reach) }
        onPressed: (mouse) => {
            glide.stop()
            if (place(mouse) < thumb.along || place(mouse) > thumb.along + bar.grip) to(place(mouse) - bar.grip / 2)
            from = place(mouse); start = thumb.along
        }
        onPositionChanged: (mouse) => { if (pressed) to(start + place(mouse) - from) }
        onWheel: (wheel) => bar.turned(wheel)
    }
    Accessible.role: Accessible.ScrollBar; Accessible.name: "Scroll"
}
