import QtQuick
import "studio"
import "studio/Theme.js" as Theme
import "js/Tone.js" as Tone
import "js/ProviderSources.js" as ProviderSources

// "Add provider": a search over every provider that is not on yet. Picking one
// switches it on and opens its page, where its source and key are set.
Column {
    id: picker

    property var shell
    property string query: ""

    signal back
    signal chosen(string id)

    readonly property var matches: ProviderSources.pickable((picker.shell.allProviders || []).filter(function (p) {
        return p.id !== "selfhosted";
    }), picker.query, picker.shell.providerEnabled)

    width: parent ? parent.width : implicitWidth
    spacing: 12

    Item {
        width: parent.width
        height: 30
        StudioIconButton {
            icon: "back"
            onClicked: picker.back()
        }
        Text {
            anchors.centerIn: parent
            text: picker.shell.i18n("Add provider")
            color: Tone.c(palette, Theme.text)
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }
    }

    StudioField {
        width: parent.width
        live: true
        value: picker.query
        placeholder: picker.shell.i18n("Search providers")
        onCommitted: v => picker.query = v
    }

    StudioCard {
        StudioNote {
            visible: picker.matches.length === 0
            text: picker.query === "" ? picker.shell.i18n("Every provider is already on.") : picker.shell.i18n("No provider matches “%1”.", picker.query)
        }
        Item {
            width: 1
            height: picker.matches.length === 0 ? 12 : 0
        }

        Repeater {
            model: picker.matches

            Item {
                id: row

                required property var modelData
                required property int index

                width: parent.width
                height: 54

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Tone.c(palette, Theme.line)
                    visible: row.index > 0
                }
                Rectangle {
                    anchors.fill: parent
                    anchors.topMargin: 1
                    radius: 8
                    color: Tone.c(palette, Theme.hover)
                    visible: area.containsMouse
                }
                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: picker.chosen(row.modelData.id)
                }

                ProviderBadge {
                    id: badge
                    anchors.verticalCenter: parent.verticalCenter
                    provider: row.modelData
                    shell: picker.shell
                    size: 32
                }
                Column {
                    anchors.left: badge.right
                    anchors.leftMargin: 12
                    anchors.right: chevron.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text {
                        width: parent.width
                        text: row.modelData.label
                        color: Tone.c(palette, Theme.text)
                        font.pixelSize: 12
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: row.modelData.id
                        color: Tone.c(palette, Theme.dim)
                        font.pixelSize: 10
                        elide: Text.ElideRight
                    }
                }
                StudioIcon {
                    id: chevron
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    name: "chevron"
                }
            }
        }
    }
}
