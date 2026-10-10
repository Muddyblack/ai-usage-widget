import QtQuick
import "studio/Theme.js" as Theme

// A provider's mark: its logo on a tinted tile, or its colour as a dot where
// it ships no artwork. The one place that draws it, so the list, the picker
// and a provider's own page cannot drift apart.
Rectangle {
    id: badge

    // An entry from shell.allProviders: { id, label, accent, icon? }.
    property var provider: null
    property var shell
    property real size: 34
    // A provider that is off is drawn quieter.
    property bool dim: false

    readonly property color accent: provider ? provider.accent : Theme.brand

    width: size
    height: size
    radius: size * 0.28
    color: Qt.rgba(accent.r, accent.g, accent.b, dim ? 0.08 : 0.2)

    Image {
        id: logo
        anchors.centerIn: parent
        width: badge.size * 0.58
        height: width
        source: badge.shell ? badge.shell.providerIcon(badge.provider) : ""
        sourceSize.width: 64
        sourceSize.height: 64
        fillMode: Image.PreserveAspectFit
        opacity: badge.dim ? 0.45 : 1
        visible: source.toString() !== "" && status !== Image.Error
    }
    Rectangle {
        anchors.centerIn: parent
        width: badge.size * 0.3
        height: width
        radius: width / 2
        color: badge.accent
        opacity: badge.dim ? 0.4 : 1
        visible: !logo.visible
    }
}
