import QtQuick
import "Theme.js" as Theme
import "../js/Tone.js" as Tone

// A line icon from an SVG path on a 24 x 24 grid, drawn the way StudioNavEntry
// draws its tabs. The few every page needs are in `paths`, so a page names one
// instead of carrying the path.
Canvas {
    id: icon

    readonly property var paths: ({
            back: "M19 12H5M11 6l-6 6 6 6",
            plus: "M12 5v14M5 12h14",
            edit: "M4 20h4L19 9l-4-4L4 16zM13.5 6.5l4 4",
            trash: "M5 7h14M10 7V4h4v3M7 7l1 13h8l1-13M10 11v6M14 11v6",
            search: "M11 4a7 7 0 1 0 0 14 7 7 0 0 0 0-14zM16 16l4 4",
            chevron: "M9 6l6 6-6 6",
            check: "M5 12.5l4.5 4.5L19 7.5",
            close: "M6 6l12 12M18 6L6 18",
            refresh: "M20 11a8 8 0 0 0-14.5-4M4 4v4h4M4 13a8 8 0 0 0 14.5 4M20 20v-4h-4"
        })
    // A name from `paths`, or a path of its own.
    property string name: ""
    property color tint: Tone.c(palette, Theme.muted)
    property real stroke: 1.8

    readonly property string path: paths[name] !== undefined ? paths[name] : name

    width: 16
    height: 16
    onTintChanged: requestPaint()
    onPathChanged: requestPaint()
    onWidthChanged: requestPaint()
    onPaint: {
        var ctx = getContext("2d");
        ctx.reset();
        ctx.scale(width / 24, height / 24);
        ctx.strokeStyle = tint;
        ctx.lineWidth = stroke;
        ctx.lineCap = "round";
        ctx.lineJoin = "round";
        ctx.path = path;
        ctx.stroke();
    }
}
