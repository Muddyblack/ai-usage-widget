.pragma library

// Light and dark popups from one set of colours.
//
// The shared UI is drawn in dark-theme colours. Under a light popup, Tone.c()
// turns each neutral one (text, hairlines, hover tints, dark fills; low
// chroma) into its twin with the lightness flipped: white text becomes
// near-black, a 6% white hover becomes a 6% black one, a near-black menu
// becomes near-white. Colours with a hue of their own (provider accents,
// warning red, brand blue) stay as they are. Under a dark popup every colour
// comes back unchanged, so the dark look is exactly what it was.
//
// Which one a component is under comes from Qt's inherited `palette`: the
// host sets palette.window on the popup's root item (AppState.windowColor),
// and every item below it inherits that, reactively. So a binding written
//     color: Tone.c(palette, "#f8fafc")
// re-evaluates when the appearance changes, with no `shell` to pass around.
// A QtQuick.Controls Popup starts a palette of its own: set its
// palette.window from its parent's (see PopupHeader's save menu).

// Above this chroma (the spread between its largest and smallest channel) a
// colour is an accent and is left alone. Not HSL saturation: that rates a
// near-white like #f8fafc 40% saturated.
var NEUTRAL_CHROMA = 0.18;

function isLight(palette) {
    return !!palette && palette.window.hslLightness > 0.5;
}

function c(palette, value) {
    var k = Qt.color(value);
    if (!isLight(palette) || Math.max(k.r, k.g, k.b) - Math.min(k.r, k.g, k.b) > NEUTRAL_CHROMA)
        return k;
    return Qt.hsla(Math.max(0, k.hslHue), k.hslSaturation, 1 - k.hslLightness, k.a);
}

// The same for a Canvas, whose fillStyle and strokeStyle take CSS strings:
// c() as "rgba(r, g, b, a)".
function css(palette, value) {
    var k = c(palette, value);
    return "rgba(" + Math.round(k.r * 255) + ", " + Math.round(k.g * 255) + ", " + Math.round(k.b * 255) + ", " + k.a + ")";
}
