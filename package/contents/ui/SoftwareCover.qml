import QtQuick

// Paint once at display resolution, then fit the backing canvas to the cover.
// Playback frames never rasterize artwork.
Item {
    id: cover
    property url source
    property size imageSize: Qt.size(1, 1)
    property real radius: 10
    property bool grayed: false
    property bool ready: false
    property real rasterScale: Math.max(1, Screen.devicePixelRatio)

    Canvas {
        id: painter
        objectName: "softwareCoverCanvas"
        property url loadedSource
        width: Math.max(1, Math.min(2048, Math.ceil(cover.width * cover.rasterScale)))
        height: Math.max(1, Math.min(2048, Math.ceil(cover.height * cover.rasterScale)))
        transform: Scale {
            xScale: cover.width / painter.width
            yScale: cover.height / painter.height
        }
        renderStrategy: Canvas.Cooperative
        smooth: true
        antialiasing: true
        function loadSource() {
            cover.ready = false;
            if (loadedSource.toString() !== "")
                unloadImage(loadedSource);
            loadedSource = cover.source;
            if (cover.source.toString() !== "") {
                loadImage(cover.source);
                cover.ready = isImageLoaded(cover.source);
            }
            requestPaint();
        }
        Component.onCompleted: loadSource()
        onImageLoaded: {
            cover.ready = isImageLoaded(cover.source);
            requestPaint();
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Connections {
            target: cover
            function onSourceChanged() {
                painter.loadSource();
            }
            function onImageSizeChanged() {
                painter.requestPaint();
            }
            function onRadiusChanged() {
                painter.requestPaint();
            }
            function onGrayedChanged() {
                painter.requestPaint();
            }
        }
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            if (cover.source.toString() === "" || !isImageLoaded(cover.source) || cover.width <= 0 || cover.height <= 0)
                return;
            ctx.scale(width / cover.width, height / cover.height);
            const w = cover.width, h = cover.height;
            const r = Math.max(0, Math.min(cover.radius, w / 2, h / 2));
            ctx.beginPath();
            ctx.roundedRect(0, 0, w, h, r, r);
            ctx.closePath();
            ctx.clip();
            const iw = Math.max(1, cover.imageSize.width), ih = Math.max(1, cover.imageSize.height);
            const fit = Math.max(w / iw, h / ih);
            ctx.drawImage(cover.source, (w - iw * fit) / 2, (h - ih * fit) / 2, iw * fit, ih * fit);
            if (cover.grayed) {
                ctx.globalCompositeOperation = "source-atop";
                ctx.fillStyle = "rgba(0,0,0,0.25)";
                ctx.fillRect(0, 0, w, h);
            }
        }
    }
}
