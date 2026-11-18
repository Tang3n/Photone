pragma Singleton
import QtQuick

// The look in one place. The chrome is neutral gray on purpose: a tinted interface shifts how
// the eye judges the colors of the photo. Color belongs to the photo and to controls about color.
QtObject {
    // Qt draws interface colors as they are written (sRGB-encoded). Should a surface ever take
    // linear light instead (session.linearSurface), every color has to be linearized, so every
    // color goes through fix(). Off on every system measured so far.
    property bool linear: false

    readonly property color bg: fix("#0e0e0f")       // the window, and around the photo
    readonly property color panel: fix("#18181a")    // columns and bars
    readonly property color raised: fix("#232326")   // controls
    readonly property color selected: fix("#34343a")
    readonly property color line: fix("#2a2a2e")
    readonly property color text: fix("#e4e4e6")
    readonly property color dim: fix("#8d8d93")
    readonly property color faint: fix("#55555b")
    readonly property color mark: fix("#e2a55a")     // "this is adjusted": the only accent
    // Color only where a control is about color: the histogram's channels, the white-balance pad.
    readonly property color red: fix("#c94f4f")
    readonly property color green: fix("#4fae5c")
    readonly property color blue: fix("#4f7fd0")
    readonly property color warm: fix("#d99a45")
    readonly property color cool: fix("#4a78c8")
    readonly property color magenta: fix("#b85ab0")
    // The four sides of the white-balance pad, at full strength (the owner: "bigger and more
    // saturated"): it is the one place where the interface shows color for its own sake.
    readonly property color padWarm: fix("#ff9a1f")
    readonly property color padCool: fix("#2a78ff")
    readonly property color padGreen: fix("#22d04a")
    readonly property color padMagenta: fix("#ee3fd8")
    readonly property color yellow: fix("#cfb54a")   // with red, green, blue and purple: the labels
    readonly property color purple: fix("#9a6fd0")
    readonly property color black: fix("#000000")    // the ends of a lightness strip
    readonly property color white: fix("#ffffff")

    readonly property color card: fix("#1f1f23")     // the card a section of the right column stands on
    readonly property int railIcon: 25

    // What each card of the two side panels is told by: an icon (a path of 20 units a side)
    // and a color of its own for its icon and title (the owner: "each card to actually have
    // its own icon, maybe even its own unique color"; of a trial of both: "looks good, but
    // the color order should be based off of the Adjust tab card order so its like a
    // continuous rainbow"). So Adjust runs yellow, green, teal, blue, purple, magenta,
    // then red, orange and amber down to Film grain, back toward the yellow it started from
    // (he then: "should start from the yellow"). The one place the chrome has color: small, and on
    // names only, never round the photo.
    readonly property var cards: ({
        light: ["M7.2 12.6 a5 5 0 1 1 5.6 0 V14.6 H7.2 Z M8.2 17.4 H11.8", "#e0c25a"],
        balance: ["M10 2.5 a2 2 0 0 1 2 2 V11 a3.6 3.6 0 1 1 -4 0 V4.5 a2 2 0 0 1 2 -2 Z M10 8 V13", "#6fcc7c"],
        lut: ["M10 2.5 L16.5 6 V14 L10 17.5 L3.5 14 V6 Z M3.5 6 L10 9.5 L16.5 6 M10 9.5 V17.5", "#5fcd9e"],
        curve: ["M3.5 3 V16.5 H17 M6 14 C10 14 10.5 6 16 5.5", "#4fcfc0"],
        saturation: ["M10 3 C10 3 4.5 9 4.5 12.2 a5.5 5.5 0 0 0 11 0 C15.5 9 10 3 10 3 Z", "#62a8e8"],
        eq: ["M5 3 V17 M10 3 V17 M15 3 V17 M3.4 7 H6.6 M8.4 12.5 H11.6 M13.4 6 H16.6", "#a583e6"],
        chroma: ["M3.5 16.5 C10 16.5 7 4 16.5 3.5 M3.5 16.4 V16.6 M16.5 3.4 V3.6", "#d66ac1"],
        wheel: ["M10 3 a7 7 0 1 0 0.01 0 Z M10 7.6 a2.4 2.4 0 1 0 0.01 0 Z", "#e45b67"],
        detail: ["M10 3 L17 16.5 H3 Z M10 8.5 L13 14 H7 Z", "#f77647"],
        lens: ["M10 3 a7 7 0 1 0 0.01 0 Z M10 6.2 a3.8 3.8 0 1 0 0.01 0 Z M7.6 7.6 L4.9 4.9", "#f4993c"],
        grain: ["M5 4.5 a1 1 0 1 0 .01 0 Z M11 3.5 a1 1 0 1 0 .01 0 Z M15.5 7.5 a1 1 0 1 0 .01 0 Z M8 9 a1 1 0 1 0 .01 0 Z M4 13 a1 1 0 1 0 .01 0 Z M12.5 12 a1 1 0 1 0 .01 0 Z M9 15.5 a1 1 0 1 0 .01 0 Z M15.5 15 a1 1 0 1 0 .01 0 Z", "#f0b135"],
        presets: ["M5.5 3 H14.5 V17 L10 13.6 L5.5 17 Z", "#c9c9cf"],
        mono: ["M10 3 a7 7 0 1 0 0.01 0 Z M10 3 V17 M10 6.5 H15.9 M10 10 H17 M10 13.5 H15.9", "#c9c9cf"],
        crop: ["M6 2 V14 H18 M2 6 H14 V18", "#c9c9cf"],
        masks: ["M3 3 H17 V17 H3 Z M10 6 a4 4 0 1 0 0.01 0 Z", "#c9c9cf"],
        mask: ["M10 3 a7 7 0 1 0 0.01 0 Z M10 3 V17", "#c9c9cf"],
        folders: ["M2.5 5.5 H8 L10 7.5 H17.5 V15.5 H2.5 Z", "#d9b074"],
        photo: ["M3 7 H6.5 L8 5 H12 L13.5 7 H17 V15.5 H3 Z M10 9 a2.5 2.5 0 1 0 0.01 0 Z", "#8fb6e8"],
        checkpoints: ["M5 17.5 V3 M5 4 H15 L12.5 7.5 L15 11 H5", "#6fcc7c"]
    })
    readonly property int titleSize: 13   // a card's title,
    readonly property int cardSign: 19    // its icon,
    readonly property int cardMid: 15     // and where both have their middle: that of a folded card
    // A card's head (Ground.qml) and outline, a very little toward its color (the owner's
    // choice of a trial, 2026-11-18).
    function cardGround(name, part) {
        if (!cards[name]) return part === "line" ? line : card
        // (Toward a dark shade of the color, not the color itself: the ground keeps its
        // lightness, or the sliders' tracks, which are barely lighter than it, are lost.)
        const from = part === "line" ? line : card, hue = fix(cards[name][1]), dim = part === "line" ? 0.3 : 0.16
        const by = 0.5
        return Qt.rgba(from.r + (hue.r * dim - from.r) * by, from.g + (hue.g * dim - from.g) * by, from.b + (hue.b * dim - from.b) * by, 1)
    }
    readonly property string resetSign: "M4.9 6.2 A6.4 6.4 0 1 1 3.6 10.4 M4.9 2.2 V6.2 H8.9"   // an arrow turning back
    readonly property string pencilSign: "M4 16 L4.8 12.6 L13.6 3.8 L16.2 6.4 L7.4 15.2 Z M12 5.4 L14.6 8"
    readonly property string binSign: "M4 6 H16 M8 6 V4 H12 V6 M5.5 6 L6.3 16.5 H13.7 L14.5 6 M8.5 9 V13.5 M11.5 9 V13.5"
    function cardIcon(card) { return cards[card] ? cards[card][0] : "" }
    function cardInk(card, otherwise) { return cards[card] ? fix(cards[card][1]) : otherwise }

    readonly property int row: 28        // the rhythm of every control row
    readonly property int slider: 44     // a slider: its name and value, the track below
    readonly property int fontSize: 13
    readonly property int smallSize: 11
    readonly property string font: "Noto Sans"   // (ui/fonts: it comes with the program)

    function decode(v) { return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
    function fix(c) {
        const k = Qt.color(c)
        return linear ? Qt.rgba(decode(k.r), decode(k.g), decode(k.b), k.a) : k
    }
}
