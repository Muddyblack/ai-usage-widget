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

    gradient: Gradient {
        GradientStop {
            position: 0.0
            color: Qt.rgba(0.09, 0.10, 0.13, 0.96)
        }
        GradientStop {
            position: 0.5
            color: Qt.rgba(0.06, 0.07, 0.09, 0.96)
        }
        GradientStop {
            position: 1.0
            color: Qt.rgba(0.04, 0.045, 0.06, 0.97)
        }
    }
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.12)
    clip: true

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
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 1
        height: 1
        color: Qt.rgba(1, 1, 1, 0.18)
    }
}
