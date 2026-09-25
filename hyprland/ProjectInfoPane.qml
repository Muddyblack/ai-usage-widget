import QtQuick
import QtQuick.Layouts
import "../package/contents/code/ProjectInfo.js" as Project
import "../package/contents/code/ProjectInfoRequests.js" as InfoRequests

Column {
    id: info

    property var shell
    property var counts: ({})
    property var contributorList: []
    property var client: null
    property bool canRefresh: false
    readonly property string currentVersion: Project.currentVersion
    property string latestVersion: ""
    property string releaseCheckState: "Not checked"
    readonly property string versionStatus: latestVersion ? Project.releaseStatus(currentVersion, latestVersion) : releaseCheckState
    readonly property bool onlineEnabled: true
    readonly property color accent: shell && shell.activeAccent ? shell.activeAccent : "#38bdf8"

    spacing: 14

    function applyNetworkState(state) {
        counts = state.counts;
        contributorList = state.contributors;
        latestVersion = state.latestVersion;
        releaseCheckState = state.releaseState;
        canRefresh = state.canRefresh;
    }

    onVisibleChanged: {
        if (client) {
            if (visible && onlineEnabled)
                client.tick();
            else
                client.pause();
        }
    }
    Component.onCompleted: {
        client = InfoRequests.create(Project, function () {
            return new XMLHttpRequest();
        }, function () {
            return Date.now();
        }, applyNetworkState);
        if (visible && onlineEnabled)
            client.tick();
    }
    Component.onDestruction: {
        if (client)
            client.dispose();
    }

    Timer {
        interval: 1000
        repeat: true
        running: info.visible && info.onlineEnabled && info.client !== null
        onTriggered: info.client.tick()
    }

    // ── Header (Icon, Title, Author) ─────────────────────────────────────────
    Row {
        width: parent.width
        spacing: 14

        Image {
            width: 56
            height: 56
            source: (info.shell && info.shell.iconSource) ? info.shell.iconSource : Qt.resolvedUrl("../package/icon.png")
            sourceSize.width: 112
            sourceSize.height: 112
            fillMode: Image.PreserveAspectFit
            Accessible.name: "AI Usage Monitor project icon"
        }

        Column {
            width: parent.width - 70
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Text {
                width: parent.width
                text: Project.name
                wrapMode: Text.WordWrap
                color: "#f8fafc"
                font.pixelSize: 17
                font.weight: Font.DemiBold
            }

            Row {
                spacing: 8

                Rectangle {
                    width: 24
                    height: 24
                    radius: 12
                    color: Qt.rgba(0, 0, 0, 0.3)

                    Text {
                        anchors.centerIn: parent
                        text: "M"
                        color: info.accent
                        font.pixelSize: 12
                        visible: !authorAvatar.ready
                    }

                    SoftwareCover {
                        id: authorAvatar
                        anchors.fill: parent
                        source: info.onlineEnabled ? Project.avatar : ""
                        imageSize: Qt.size(128, 128)
                        radius: 12
                        Accessible.name: Project.author + " GitHub avatar"
                    }
                }

                SettingsButton {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "By " + Project.author + " ↗"
                    onClicked: Qt.openUrlExternally(Project.profile)
                }
            }
        }
    }

    Text {
        width: parent.width
        text: "An open-source AI quota & usage monitor for Plasma, Hyprland, macOS and Windows. Explore the project, get updates, or help improve it."
        wrapMode: Text.WordWrap
        color: Qt.rgba(1, 1, 1, 0.55)
        font.pixelSize: 11
        lineHeight: 1.25
    }

    // ── Version Card ─────────────────────────────────────────────────────────
    Rectangle {
        objectName: "projectVersion"
        width: parent.width
        height: versionContent.implicitHeight + 24
        radius: 8
        color: Qt.rgba(1, 1, 1, 0.04)
        border.color: Qt.rgba(1, 1, 1, 0.12)
        border.width: 1

        Column {
            id: versionContent
            x: 12
            y: 12
            width: parent.width - 24
            spacing: 6

            Text {
                text: "Installed version · " + info.currentVersion
                color: "#f8fafc"
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }

            Text {
                objectName: "latestVersionLabel"
                text: "Latest stable release · " + (info.latestVersion || "—")
                color: Qt.rgba(1, 1, 1, 0.5)
                font.pixelSize: 11
            }

            Text {
                objectName: "versionStatusLabel"
                width: parent.width
                text: info.versionStatus
                wrapMode: Text.WordWrap
                color: text === "Update available" ? info.accent : Qt.rgba(1, 1, 1, 0.5)
                font.pixelSize: 11
            }

            Flow {
                width: parent.width
                spacing: 8

                SettingsButton {
                    text: info.versionStatus === "Update available" ? "Get update ↗" : "View latest release ↗"
                    onClicked: Qt.openUrlExternally(Project.releasesPage)
                }

                SettingsButton {
                    text: "Check again"
                    enabled: info.onlineEnabled && info.canRefresh
                    onClicked: info.client.refresh()
                }
            }
        }
    }

    // ── Statistics Cards ─────────────────────────────────────────────────────
    Flow {
        width: parent.width
        spacing: 8

        Repeater {
            model: Project.statistics

            Rectangle {
                required property var modelData
                objectName: "stat_" + modelData.id
                width: info.width >= 570 ? (info.width - 16) / 3 : info.width >= 360 ? (info.width - 8) / 2 : info.width
                height: 72
                radius: 8
                color: statArea.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.04)
                border.width: 1
                border.color: statArea.containsMouse ? info.accent : Qt.rgba(1, 1, 1, 0.12)

                Image {
                    objectName: "statIcon_" + parent.modelData.id
                    x: 12
                    y: 12
                    width: 20
                    height: 20
                    source: (info.shell && info.shell.iconDir ? info.shell.iconDir : Qt.resolvedUrl("../package/contents/icons/")) + parent.modelData.icon
                    sourceSize: Qt.size(40, 40)
                    fillMode: Image.PreserveAspectFit
                }

                Text {
                    x: 40
                    y: 8
                    text: info.counts[parent.modelData.id] || "—"
                    color: "#f8fafc"
                    font.pixelSize: 18
                    font.weight: Font.DemiBold
                }

                Text {
                    x: 12
                    y: 42
                    width: parent.width - 24
                    text: parent.modelData.label + " ↗"
                    color: Qt.rgba(1, 1, 1, 0.5)
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }

                MouseArea {
                    id: statArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    Accessible.name: parent.modelData.label + ", open " + parent.modelData.href
                    onClicked: Qt.openUrlExternally(parent.modelData.href)
                }
            }
        }
    }

    // ── License Card ─────────────────────────────────────────────────────────
    Rectangle {
        objectName: "projectLicense"
        width: parent.width
        height: 56
        radius: 8
        color: Qt.rgba(1, 1, 1, 0.04)
        border.color: Qt.rgba(1, 1, 1, 0.12)
        border.width: 1

        Column {
            x: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
                text: "License · " + Project.license
                color: "#f8fafc"
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }

            Text {
                text: Project.licenseId + " · From the bundled LICENSE file"
                color: Qt.rgba(1, 1, 1, 0.45)
                font.pixelSize: 9
            }
        }
    }

    // ── Contributors Section ─────────────────────────────────────────────────
    Column {
        objectName: "contributorsSection"
        width: parent.width
        visible: info.contributorList.length > 0
        spacing: 8

        Row {
            width: parent.width
            spacing: 10

            Text {
                text: "Contributors"
                color: "#f8fafc"
                font.pixelSize: 13
                font.weight: Font.DemiBold
                anchors.verticalCenter: parent.verticalCenter
            }

            SettingsButton {
                anchors.verticalCenter: parent.verticalCenter
                text: "See all on GitHub ↗"
                onClicked: Qt.openUrlExternally(Project.contributorsPage)
            }
        }

        Flow {
            width: parent.width
            spacing: 8

            Repeater {
                model: info.contributorList

                Rectangle {
                    id: contributorCard
                    required property var modelData
                    objectName: "contributor_" + modelData.login
                    width: info.width >= 570 ? (info.width - 16) / 3 : info.width >= 360 ? (info.width - 8) / 2 : info.width
                    height: 52
                    radius: 8
                    color: contributorArea.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.04)
                    border.color: contributorArea.containsMouse ? info.accent : Qt.rgba(1, 1, 1, 0.12)
                    border.width: 1

                    Rectangle {
                        x: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: 32
                        height: 32
                        radius: 16
                        color: Qt.rgba(0, 0, 0, 0.3)

                        Text {
                            anchors.centerIn: parent
                            text: contributorCard.modelData.login[0].toUpperCase()
                            color: info.accent
                            font.pixelSize: 12
                            visible: !contributorAvatar.ready
                        }

                        SoftwareCover {
                            id: contributorAvatar
                            anchors.fill: parent
                            source: info.onlineEnabled ? contributorCard.modelData.avatar : ""
                            imageSize: Qt.size(96, 96)
                            radius: 16
                            Accessible.name: contributorCard.modelData.login + " avatar"
                        }
                    }

                    Column {
                        x: 48
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 56
                        spacing: 1

                        Text {
                            width: parent.width
                            text: contributorCard.modelData.login
                            elide: Text.ElideRight
                            color: "#f8fafc"
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }

                        Text {
                            text: contributorCard.modelData.commits + (contributorCard.modelData.commits === 1 ? " commit" : " commits")
                            color: Qt.rgba(1, 1, 1, 0.5)
                            font.pixelSize: 9
                        }
                    }

                    MouseArea {
                        id: contributorArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        Accessible.name: "Open " + contributorCard.modelData.login + " on GitHub"
                        onClicked: Qt.openUrlExternally(contributorCard.modelData.profile)
                    }
                }
            }
        }
    }

    // ── Support the project ──────────────────────────────────────────────────
    Column {
        width: parent.width
        spacing: 8

        Text {
            text: "Support the project"
            color: "#f8fafc"
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }

        Flow {
            width: parent.width
            spacing: 8

            Repeater {
                model: Project.funding

                Rectangle {
                    required property var modelData
                    objectName: "funding_" + modelData.id
                    width: info.width >= 570 ? (info.width - 16) / 3 : info.width >= 360 ? (info.width - 8) / 2 : info.width
                    height: 56
                    radius: 8
                    color: linkArea.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.04)
                    border.width: 1
                    border.color: linkArea.containsMouse ? info.accent : Qt.rgba(1, 1, 1, 0.12)

                    Image {
                        objectName: "fundingIcon_" + parent.modelData.id
                        x: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: 22
                        height: 22
                        source: (info.shell && info.shell.iconDir ? info.shell.iconDir : Qt.resolvedUrl("../package/contents/icons/")) + parent.modelData.icon
                        fillMode: Image.PreserveAspectFit
                        sourceSize: Qt.size(44, 44)
                    }

                    Text {
                        x: 40
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 48
                        text: parent.modelData.label
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        color: "#f8fafc"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: linkArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        Accessible.name: "Support on " + parent.modelData.label
                        onClicked: Qt.openUrlExternally(parent.modelData.url)
                    }
                }
            }
        }
    }

    // ── Footer Actions ───────────────────────────────────────────────────────
    Flow {
        width: parent.width
        spacing: 8

        SettingsButton {
            text: "View source on GitHub ↗"
            onClicked: Qt.openUrlExternally(Project.repository)
        }

        SettingsButton {
            text: "Report an issue ↗"
            onClicked: Qt.openUrlExternally(Project.repository + "/issues")
        }
    }
}
