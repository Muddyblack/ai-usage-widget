var VALID_INTERVALS = [0, 30, 60, 120, 300, 600];

function normalizeIntervalSec(intervalSec) {
    return VALID_INTERVALS.indexOf(intervalSec) >= 0 ? intervalSec : 0;
}

function normalizeSelection(pinnedTabs, selectedId) {
    var pins = pinnedTabs || [];
    if (pins.length === 0)
        return "";
    if (pins.indexOf(selectedId) >= 0)
        return selectedId;
    return pins[0];
}

function nextSelection(pinnedTabs, selectedId) {
    var pins = pinnedTabs || [];
    var selected = normalizeSelection(pins, selectedId);
    if (pins.length < 2)
        return selected;
    return pins[(pins.indexOf(selected) + 1) % pins.length];
}

function isEnabled(intervalSec, pinnedTabs) {
    return normalizeIntervalSec(intervalSec) > 0 && (pinnedTabs || []).length > 1;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        normalizeIntervalSec: normalizeIntervalSec,
        normalizeSelection: normalizeSelection,
        nextSelection: nextSelection,
        isEnabled: isEnabled
    };
}
