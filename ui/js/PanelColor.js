// The compact panel readout's usage-level colour rule.
//
// The panel is the always-visible surface, so its thresholds are a contract:
// amber at 70%, red at 90%, on both ends inclusive. Kept here rather than
// inline in PanelSlot.qml so the boundary values can be tested exactly and a
// later "optimization" cannot quietly shift them.

var DANGER = "#ff4d4d";
var WARNING = "#ffa64d";

function level(pct) {
    var value = Number(pct);
    if (!isFinite(value) || value < 0)
        return "normal";
    if (value >= 90)
        return "danger";
    if (value >= 70)
        return "warning";
    return "normal";
}

function colorFor(pct, normalColor) {
    var name = level(pct);
    if (name === "danger")
        return DANGER;
    if (name === "warning")
        return WARNING;
    return normalColor;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        DANGER: DANGER,
        WARNING: WARNING,
        level: level,
        colorFor: colorFor
    };
}
