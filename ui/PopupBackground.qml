import QtQuick

// The popup's glass, drawn the same by every host: a dark translucent
// gradient (the compositor's blur shows through where it has one), an
// optional tint, one decoration, and a crisp top highlight.
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
    // (and the blur, where there is one) show through.
    // Under a host whose frame is Plasma's (`translucent`) the same setting runs
    // the other way: 0 leaves Plasma's backdrop as it is, and raising it lays
    // this popup's own solid glass over it.
    readonly property real glassOpacity: translucent ? Math.max(0, Math.min(1, Number(settings.popupGlassOpacity || 0))) : Math.max(0.2, Math.min(1, settings.popupGlassOpacity === undefined ? 1 : Number(settings.popupGlassOpacity)))
    readonly property real fillScale: (blurred ? 0.62 : 1) * glassOpacity
    // Settings → Appearance → Glass look (popupGlassStyle): "dark" is the deep
    // blue glass, "milky" a frosted white one that reads best over a blur.
    readonly property bool milky: settings.popupGlassStyle === "milky"
    // The glass colour at gradient stop 0, 1 or 2, for opacity scale `s`.
    function glassStop(i, s) {
        if (milky)
            return [Qt.rgba(0.93, 0.95, 1.0, 0.34 * s), Qt.rgba(0.86, 0.9, 0.98, 0.26 * s), Qt.rgba(0.8, 0.85, 0.95, 0.22 * s)][i];
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
    border.color: Qt.rgba(1, 1, 1, 0.12)
    clip: true

    // Plasma host: the popup's own glass over Plasma's backdrop, as strong as
    // the setting says.
    Rectangle {
        anchors.fill: parent
        radius: glass.radius
        visible: glass.translucent && glass.glassOpacity > 0
        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: glass.glassStop(0, glass.glassOpacity * 1.2)
            }
            GradientStop {
                position: 0.5
                color: glass.glassStop(1, glass.glassOpacity * 1.2)
            }
            GradientStop {
                position: 1.0
                color: glass.glassStop(2, glass.glassOpacity * 1.2)
            }
        }
    }

    // Tint: under the decoration, so a stronger tint does not blot it out.
    Rectangle {
        anchors.fill: parent
        radius: glass.radius
        color: glass.tint
        visible: glass.tintOpacity > 0
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
