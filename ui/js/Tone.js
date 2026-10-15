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
// Components pass theme/Palette.qml, a shared QtObject updated by AppState.
// Reading its ordinary colour property keeps bindings reactive without
// changing Qt's inherited item palettes (which can crash during live updates).

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

// Foreground accents need a darker shade on a light surface. Keep raw brand
// colours for fills and charts; use this for text and small symbols.
function ink(palette, value) {
    var k = Qt.color(value);
    if (!isLight(palette))
        return k;
    return Qt.hsla(Math.max(0, k.hslHue), k.hslSaturation, Math.min(k.hslLightness, 0.30), k.a);
}

// A panel can use either a host-provided surface or our own pill background.
function onSurface(value, surface) {
    var k = Qt.color(value);
    var bg = Qt.color(surface);
    function luminance(v) {
        function linear(n) { return n <= 0.04045 ? n / 12.92 : Math.pow((n + 0.055) / 1.055, 2.4); }
        return 0.2126 * linear(v.r) + 0.7152 * linear(v.g) + 0.0722 * linear(v.b);
    }
    var b = luminance(bg);
    for (var i = 0; i < 32; i++) {
        var f = luminance(k);
        if ((Math.max(f, b) + 0.05) / (Math.min(f, b) + 0.05) >= 4.5)
            break;
        var target = b > 0.179 ? 0 : 1;
        k = Qt.rgba(k.r * 0.85 + target * 0.15, k.g * 0.85 + target * 0.15, k.b * 0.85 + target * 0.15, k.a);
    }
    return k;
}

function paleLogo(source) {
    return /\/(cursor|cline|zed)\.svg$/.test(String(source));
}

// The same for a Canvas, whose fillStyle and strokeStyle take CSS strings:
// c() as "rgba(r, g, b, a)".
function css(palette, value) {
    var k = c(palette, value);
    return "rgba(" + Math.round(k.r * 255) + ", " + Math.round(k.g * 255) + ", " + Math.round(k.b * 255) + ", " + k.a + ")";
}
