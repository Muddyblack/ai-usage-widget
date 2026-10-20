import QtQuick
import "theme" as Appearance
import "js/Tone.js" as Tone

// The popup's glass, drawn the same by every host: a translucent gradient,
// dark or (under the light theme) milky light, which the compositor's blur
// shows through where it has one; an optional tint, one decoration, and a
// crisp top highlight.
//
// Settings (Settings → Appearance):
//   popupBgColor     tint colour, "#rrggbb"           (default black)
//   popupBgOpacity   tint strength, 0–1               (default 0: no tint)
//   popupDecoration  0 accent glow, 1 provider logo glow (default), 2 none
Rectangle {
    id: glass

    property var shell
    // A host whose window already has a blurred, translucent backdrop of its
    // own (the KDE popup) sets this: only a faint lightening and shading is
    // drawn, so that backdrop shows through. Otherwise the gradient is a
    // milky, blue-tinged glass (blurred too if the compositor blurs the layer).
    property bool translucent: false
    // The compositor blurs behind this window (Hyprland with glass.conf): the
    // gradient thins out so the blur reads through, edge and highlight stay.
    property bool blurred: false
    // Settings → Appearance → Glass opacity (popupGlassOpacity, 0.2–1): how
    // much of the popup's own glass is drawn; lower lets more of the desktop
    // (and the blur, where there is one) show through. Unused under a
    // `translucent` host, whose frame is the background (see the tint below).
    readonly property real glassOpacity: Math.max(0.2, Math.min(1, settings.popupGlassOpacity === undefined ? 1 : Number(settings.popupGlassOpacity)))
    readonly property real fillScale: (blurred ? 0.62 : 1) * glassOpacity
    // Settings → Appearance → Theme (AppState.light; ui/js/Tone.js).
    readonly property bool light: Tone.isLight(Appearance.Palette)
    // The glass colour at gradient stop 0, 1 or 2, for opacity scale `s`:
    // blue-tinged and dark, or milky and light.
    function glassStop(i, s) {
        if (glass.light)
            return [Qt.rgba(0.99, 0.995, 1.0, 0.78 * s), Qt.rgba(0.95, 0.96, 0.98, 0.82 * s), Qt.rgba(0.91, 0.93, 0.96, 0.86 * s)][i];
        return [Qt.rgba(0.24, 0.31, 0.45, 0.66 * s), Qt.rgba(0.12, 0.17, 0.29, 0.70 * s), Qt.rgba(0.06, 0.09, 0.19, 0.76 * s)][i];
    }
    // A host whose window frame already rounds the corners (KDE's popup
    // dialog) can turn the radius down.
    radius: 12

    readonly property var settings: shell ? shell.settings : ({})
    readonly property int decoration: settings.popupDecoration === undefined ? 1 : Number(settings.popupDecoration)
    readonly property real tintOpacity: Math.max(0, Math.min(1, Number(settings.popupBgOpacity || 0)))
    readonly property color tint: {
        var c = Qt.color(settings.popupBgColor || "#000000");
        // Keep the selected hue, but keep the background in the theme's
        // luminance range so strong tints cannot hide the foreground text.
        if (glass.light)
            c = Qt.hsla(Math.max(0, c.hslHue), c.hslSaturation, Math.max(0.88, c.hslLightness), 1);
        return Qt.rgba(c.r, c.g, c.b, glass.tintOpacity);
    }
    // Settings and feature tabs blur the widget's own multicolour icon in its own colours; only
    // a provider's logo is turned into a one-colour glow.
    readonly property bool providerLogo: !!shell && !shell.showSettings && !shell.activeIsFeature
    readonly property string watermark: {
        if (!shell)
            return "";
        if (shell.showSettings || shell.activeIsFeature)
            return shell.iconSource;
        return shell.providerIcon(shell.activeProvider()) || shell.iconSource;
    }

    // Under a host that already draws the glass, nothing is filled here: a
    // second translucent layer inside the frame reads as a card in a card.
    color: "transparent"
    gradient: glass.translucent ? null : glassGradient
    Gradient {
        id: glassGradient
        GradientStop {
            position: 0.0
            color: glass.glassStop(0, glass.fillScale)
        }
        GradientStop {
            position: 0.5
            color: glass.glassStop(1, glass.fillScale)
        }
        GradientStop {
            position: 1.0
            color: glass.glassStop(2, glass.fillScale)
        }
    }
    // The KDE dialog frame already draws an edge; a second one reads as a
    // double layer.
    border.width: glass.translucent ? 0 : 1
    border.color: Tone.c(Appearance.Palette, Qt.rgba(1, 1, 1, 0.12))
    clip: true

    // Item.clip is rectangular even on a rounded Rectangle. Clip canvas
    // decorations to the actual glass outline so they cannot fill its corners.
    function clipDecoration(ctx) {
        var w = glass.width;
        var h = glass.height;
        var r = Math.min(glass.radius, w / 2, h / 2);
        ctx.beginPath();
        ctx.moveTo(r, 0);
        ctx.lineTo(w - r, 0);
        ctx.quadraticCurveTo(w, 0, w, r);
        ctx.lineTo(w, h - r);
        ctx.quadraticCurveTo(w, h, w - r, h);
        ctx.lineTo(r, h);
        ctx.quadraticCurveTo(0, h, 0, h - r);
        ctx.lineTo(0, r);
        ctx.quadraticCurveTo(0, 0, r, 0);
        ctx.closePath();
        ctx.clip();
    }

    // Frost (Settings → Appearance → Frost, popupFrost 0–1): a milky wash,
    // brighter at the top, and fine grain — the frosted-glass look of the
    // Glassy System Monitor's cards. It is drawn, not sampled: no window can
    // read what is behind it, so it reads as frosted with or without the
    // compositor's blur, and keeps text legible over a busy desktop. Not
    // under a `translucent` host, for the reason the tint below gives.
    readonly property real frost: glass.translucent ? 0 : Math.max(0, Math.min(1, Number(settings.popupFrost || 0)))
    Rectangle {
        anchors.fill: parent
        radius: glass.radius
        visible: glass.frost > 0
        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: Qt.rgba(0.92, 0.95, 1.0, 0.52 * glass.frost)
            }
            GradientStop {
                position: 0.45
                color: Qt.rgba(0.85, 0.89, 0.97, 0.42 * glass.frost)
            }
            GradientStop {
                position: 1.0
                color: Qt.rgba(0.78, 0.83, 0.94, 0.36 * glass.frost)
            }
        }
    }
    // Grain: specks batched into two paths (light and dark), painted once per
    // size from a fixed seed, so it never shimmers or costs a frame.
    Canvas {
        anchors.fill: parent
        visible: glass.frost > 0
        opacity: Math.min(1, 0.35 + glass.frost)
        renderStrategy: Canvas.Cooperative
        readonly property var signature: [width, height, visible]
        onSignatureChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            if (!visible || width <= 0 || height <= 0)
                return;
            glass.clipDecoration(ctx);
            var seed = 1234567;
            function rnd() {
                seed = (seed * 1103515245 + 12345) % 2147483648;
                return seed / 2147483648;
            }
            var count = Math.floor(width * height / 26);
            for (var pass = 0; pass < 2; pass++) {
                ctx.beginPath();
                for (var i = 0; i < count / 2; i++)
                    ctx.rect(Math.floor(rnd() * width), Math.floor(rnd() * height), 1, 1);
                ctx.fillStyle = pass === 0 ? "rgba(255,255,255,0.10)" : "rgba(0,0,0,0.10)";
                ctx.fill();
            }
        }
    }

    // Tint: under the decoration, so a stronger tint does not blot it out.
    // Under a `translucent` host the host oversizes this item past Plasma's
    // frame padding, so the tint reaches the frame's edge.
    Rectangle {
        anchors.fill: parent
        radius: glass.radius
        color: glass.tint
        visible: glass.tintOpacity > 0
    }

    // Soft glow in the top-left in the active tab's accent — also the
    // fallback while a watermark logo is missing.
    Canvas {
        id: glow
        width: parent.width * 0.7
        height: parent.height * 0.7
        anchors.top: parent.top
        anchors.left: parent.left
        opacity: 0.22
        visible: glass.decoration === 0 || (glass.decoration === 1 && (watermarkImage.loadedSource.toString() === ""))
        readonly property color accent: glass.shell ? glass.shell.activeAccent : "#cc785c"
        readonly property var signature: [width, height, visible, accent]
        onSignatureChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            if (!visible || width <= 0 || height <= 0)
                return;
            // Paint in normalized coordinates for an elliptical glow that
            // reaches full transparency before any of its bounds.
            ctx.scale(width, height);
            var fade = ctx.createRadialGradient(0.35, 0.3, 0, 0.35, 0.3, 0.65);
            fade.addColorStop(0, accent.toString());
            fade.addColorStop(1, "transparent");
            ctx.fillStyle = fade;
            ctx.fillRect(0, 0, 1, 1);
        }
    }

    // The active provider's logo as a soft one-colour glow in the accent: the
    // shape stays recognisable but never competes with the content. Drawn on
    // a Canvas (with a faked blur) because MultiEffect
    // cannot render hidden source images under the software renderer.
    Canvas {
        id: watermarkImage
        anchors.top: parent.top
        anchors.left: parent.left
        width: Math.min(parent.width, parent.height) * 0.7
        height: width
        // Painted at its on-screen size: the software renderer doesn't rescale
        // a Canvas whose canvasSize differs from the item size.
        canvasSize: Qt.size(Math.max(1, width), Math.max(1, height))
        onCanvasSizeChanged: requestPaint()
        smooth: true
        // A host that draws its own glass (not `translucent`) has no blurred
        // desktop behind the logo to lift it, so it gets a little more weight.
        opacity: glass.providerLogo ? (glass.light ? (glass.translucent ? 0.22 : 0.38) : (glass.translucent ? 0.25 : 0.5)) : (glass.translucent ? 0.18 : 0.26)
        visible: glass.decoration === 1 && loadedSource.toString() !== ""
        property url loadedSource
        readonly property url wanted: glass.decoration === 1 ? glass.watermark : ""
        readonly property color accent: glass.shell ? glass.shell.activeAccent : "#cc785c"
        readonly property bool tint: glass.providerLogo
        onWantedChanged: loadSource()
        onAccentChanged: requestPaint()
        onTintChanged: requestPaint()
        onImageLoaded: requestPaint()
        Component.onCompleted: loadSource()

        function loadSource() {
            if (loadedSource.toString() !== "")
                unloadImage(loadedSource);
            loadedSource = wanted;
            if (loadedSource.toString() !== "")
                loadImage(loadedSource);
            requestPaint();
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            if (loadedSource.toString() === "" || !isImageLoaded(loadedSource))
                return;
            glass.clipDecoration(ctx);
            ctx.imageSmoothingEnabled = true;
            // No blur filter in Canvas: stack a few offset, low-alpha copies
            // on two rings to get a soft halo around the logo.
            const side = Math.min(width, height) * 0.8;
            const o = (Math.min(width, height) - side) / 2;
            const spread = side * 0.06;
            // ~0.7 combined peak; a real blur would spread it thinner.
            ctx.globalAlpha = 0.05;
            for (let ring = 1; ring <= 2; ring++) {
                for (let i = 0; i < 12; i++) {
                    const ang = i * Math.PI / 6;
                    ctx.drawImage(loadedSource, o + Math.cos(ang) * spread * ring, o + Math.sin(ang) * spread * ring, side, side);
                }
            }
            ctx.globalAlpha = 1;
            if (tint) {
                ctx.globalCompositeOperation = "source-in";
                ctx.fillStyle = accent.toString();
                ctx.fillRect(0, 0, width, height);
            }
        }
    }

    Rectangle {
        visible: !glass.translucent
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 1
        anchors.leftMargin: glass.radius
        anchors.rightMargin: glass.radius
        height: 1
        color: Qt.rgba(1, 1, 1, 0.18)
    }
}
