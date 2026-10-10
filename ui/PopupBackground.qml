import QtQuick
import "js/Tone.js" as Tone

// The popup's glass, drawn the same by every host: a translucent gradient,
// dark or (under the light theme) milky light, which the compositor's blur
// shows through where it has one; an optional tint, one decoration, and a
// crisp top highlight.
//
// Settings (Settings → Appearance):
//   popupBgColor     tint colour, "#rrggbb"           (default black)
//   popupBgOpacity   tint strength, 0–1               (default 0: no tint)
//   popupDecoration  0 accent glow, 1 provider logo watermark, 2 none
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
    // Settings → Appearance → Theme, as the host set it on the palette
    // (AppState.light; ui/js/Tone.js).
    readonly property bool light: Tone.isLight(palette)
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
    readonly property int decoration: settings.popupDecoration === undefined ? 0 : Number(settings.popupDecoration)
    readonly property real tintOpacity: Math.max(0, Math.min(1, Number(settings.popupBgOpacity || 0)))
    readonly property color tint: {
        var c = Qt.color(settings.popupBgColor || "#000000");
        return Qt.rgba(c.r, c.g, c.b, glass.tintOpacity);
    }
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
    border.color: Tone.c(palette, Qt.rgba(1, 1, 1, 0.12))
    clip: true

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
    // Not under a `translucent` host: Plasma clips the popup's content to the
    // inside of its frame padding, so a fill here stops short of the frame and
    // reads as a second, inner border. Plasma's frame is the background there;
    // turn Blur off (AppState.ownGlass) to tint.
    Rectangle {
        anchors.fill: parent
        radius: glass.radius
        color: glass.tint
        visible: !glass.translucent && glass.tintOpacity > 0
    }

    // Soft glow in the top-left in the active tab's accent — also the
    // fallback while a watermark logo is missing.
    Rectangle {
        id: glow
        width: parent.width * 0.7
        height: parent.height * 0.7
        anchors.top: parent.top
        anchors.left: parent.left
        radius: width / 2
        opacity: 0.12
        visible: glass.decoration === 0 || (glass.decoration === 1 && (watermarkImage.source.toString() === "" || watermarkImage.status === Image.Error))
        gradient: Gradient {
            GradientStop {
                position: 0
                color: glass.shell ? glass.shell.activeAccent : "#cc785c"
            }
            GradientStop {
                position: 1
                color: "transparent"
            }
        }
    }

    // The active provider's logo, large and faint.
    Image {
        id: watermarkImage
        anchors.top: parent.top
        anchors.left: parent.left
        width: parent.width * 0.7
        height: parent.height * 0.7
        sourceSize.width: 280
        sourceSize.height: 280
        fillMode: Image.PreserveAspectFit
        smooth: true
        opacity: 0.12
        visible: glass.decoration === 1 && source.toString() !== "" && status !== Image.Error
        source: glass.decoration === 1 ? glass.watermark : ""
    }

    Rectangle {
        visible: !glass.translucent
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 1
        height: 1
        color: Qt.rgba(1, 1, 1, 0.18)
    }
}
