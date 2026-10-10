import QtQuick
import "studio"
import "studio/Theme.js" as Theme
import "js/Tone.js" as Tone
import "js/ProviderSources.js" as ProviderSources

// Authentication: every way the provider can be read, with whether each one
// works on this machine, and — where they are alternatives — which to use.
// It knows no provider and no kind of source: the backend lists what exists
// (aiusage/sources.py), so a new source appears here without a change.
Item {
    id: choice

    property var shell
    // The provider's snapshot (shell.providerById), whose `sources` block this draws.
    property var snapshot: null
    property string providerId: ""

    readonly property var sources: ProviderSources.block(choice.snapshot)
    readonly property bool choosable: choice.sources !== null && choice.sources.choice !== false
    readonly property string selected: choice.choosable ? choice.shell.sourceChoice(choice.providerId) : ""

    visible: choice.sources !== null
    width: parent ? parent.width : implicitWidth
    height: visible ? card.height : 0

    function kindLabel(kind) {
        switch (kind) {
        case "cli":
            return choice.shell.i18n("CLI");
        case "ide":
            return choice.shell.i18n("IDE");
        case "server":
            return choice.shell.i18n("Server");
        case "api":
            return choice.shell.i18n("API key");
        case "browser":
            return choice.shell.i18n("Browser");
        }
        return choice.shell.i18n("Local files");
    }

    function stateLabel(state) {
        switch (state) {
        case "working":
            return choice.shell.i18n("Working");
        case "failing":
            return choice.shell.i18n("Not working");
        case "ready":
            return choice.shell.i18n("Ready");
        }
        return choice.shell.i18n("Not found");
    }

    StudioCard {
        id: card
        title: choice.shell.i18n("Authentication")
        caption: choice.choosable ? choice.shell.i18n("Choose where this provider is read from. Auto uses the first source that works.") : choice.shell.i18n("Everything this provider is read from. All of it is used.")

        // Auto: the default, and the only choice that falls back.
        Item {
            id: autoRow
            visible: choice.choosable
            width: parent.width
            height: visible ? 48 : 0

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: choice.shell.chooseSource(choice.providerId, ProviderSources.AUTO)
            }
            Radio {
                id: autoRadio
                on: choice.selected === ProviderSources.AUTO
            }
            Column {
                anchors.left: autoRadio.right
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Text {
                    text: choice.shell.i18n("Auto")
                    color: Tone.c(palette, Theme.text)
                    font.pixelSize: 12
                    font.weight: Font.Medium
                }
                Text {
                    width: parent.width
                    text: choice.shell.i18n("The first source below that works")
                    color: Tone.c(palette, Theme.muted)
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }
            }
        }

        Repeater {
            model: choice.sources ? choice.sources.options : []

            Item {
                id: row

                required property var modelData
                required property int index
                readonly property bool picked: choice.choosable && choice.selected === row.modelData.id

                width: parent.width
                height: 54

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Tone.c(palette, Theme.line)
                    visible: row.index > 0 || choice.choosable
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: choice.choosable
                    cursorShape: choice.choosable ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: choice.shell.chooseSource(choice.providerId, row.modelData.id)
                }
                Radio {
                    id: radio
                    visible: choice.choosable
                    on: row.picked
                }
                Column {
                    anchors.left: choice.choosable ? radio.right : parent.left
                    anchors.leftMargin: choice.choosable ? 12 : 0
                    anchors.right: status.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Row {
                        spacing: 8
                        Text {
                            text: row.modelData.label
                            color: Tone.c(palette, Theme.text)
                            font.pixelSize: 12
                            font.weight: Font.Medium
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: choice.kindLabel(row.modelData.kind)
                            color: Tone.c(palette, Theme.dim)
                            font.pixelSize: 10
                        }
                    }
                    Text {
                        width: parent.width
                        text: row.modelData.detail
                        color: Tone.c(palette, Theme.muted)
                        font.pixelSize: 10
                        elide: Text.ElideRight
                    }
                }
                Row {
                    id: status
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: choice.stateLabel(row.modelData.state)
                        color: Tone.c(palette, Theme.tone(ProviderSources.stateTone(row.modelData.state)))
                        font.pixelSize: 11
                    }
                    StudioIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: row.modelData.state === "working"
                        name: "check"
                        tint: Theme.ok
                        width: 14
                        height: 14
                    }
                }
            }
        }
    }

    // A round radio mark, filled when chosen.
    component Radio: Rectangle {
        property bool on: false
        x: 0
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        width: 16
        height: 16
        radius: 8
        color: "transparent"
        border.width: 1.5
        border.color: on ? Theme.brand : Tone.c(palette, Theme.line2)
        Rectangle {
            anchors.centerIn: parent
            width: 8
            height: 8
            radius: 4
            color: Theme.brand
            visible: parent.on
        }
    }
}
