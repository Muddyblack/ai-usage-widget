import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import "../code/ProjectInfo.js" as Project
import "../code/ProjectInfoRequests.js" as InfoRequests

ColumnLayout {
    id: info

    property var rootItem
    property var counts: ({})
    property var contributorList: []
    property var client: null
    property bool canRefresh: false
    readonly property string currentVersion: Project.currentVersion
    property string latestVersion: ""
    property string releaseCheckState: "Not checked"
    readonly property string versionStatus: latestVersion ? Project.releaseStatus(currentVersion, latestVersion) : releaseCheckState
    readonly property bool onlineEnabled: true
    readonly property color accent: rootItem ? rootItem.activeAccent : Kirigami.Theme.highlightColor

    spacing: 12

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
    RowLayout {
        Layout.fillWidth: true
        spacing: 14

        Image {
            Layout.preferredWidth: 56
            Layout.preferredHeight: 56
            source: Qt.resolvedUrl("../../icon.png")
            sourceSize.width: 112
            sourceSize.height: 112
            fillMode: Image.PreserveAspectFit
            Accessible.name: "AI Usage Monitor project icon"
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: Project.name
                wrapMode: Text.WordWrap
                color: Kirigami.Theme.textColor
                font.pixelSize: 16
                font.bold: true
            }

            RowLayout {
                spacing: 8

                Rectangle {
                    width: 24
                    height: 24
                    radius: 12
                    color: Qt.rgba(0, 0, 0, 0.2)

                    PlasmaComponents.Label {
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

                PlasmaComponents.Button {
                    text: "By " + Project.author + " ↗"
                    implicitHeight: 24
                    font.pixelSize: 10
                    onClicked: Qt.openUrlExternally(Project.profile)
                }
            }
        }
    }

    PlasmaComponents.Label {
        Layout.fillWidth: true
        text: i18n("An open-source AI quota & usage monitor for Plasma, Hyprland, macOS and Windows. Explore the project, get updates, or help improve it.")
        wrapMode: Text.WordWrap
        color: Kirigami.Theme.textColor
        opacity: 0.6
        font.pixelSize: 10
    }

    // ── Version Card ─────────────────────────────────────────────────────────
    Rectangle {
        objectName: "projectVersion"
        Layout.fillWidth: true
        implicitHeight: versionContent.implicitHeight + 20
        radius: 8
        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.04)
        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
        border.width: 1

        ColumnLayout {
            id: versionContent
            anchors.fill: parent
            anchors.margins: 10
            spacing: 4

            PlasmaComponents.Label {
                text: i18n("Installed version · %1", info.currentVersion)
                color: Kirigami.Theme.textColor
                font.pixelSize: 11
                font.bold: true
            }

            PlasmaComponents.Label {
                objectName: "latestVersionLabel"
                text: i18n("Latest stable release · %1", (info.latestVersion || "—"))
                color: Kirigami.Theme.textColor
                opacity: 0.6
                font.pixelSize: 10
            }

            PlasmaComponents.Label {
                objectName: "versionStatusLabel"
                Layout.fillWidth: true
                text: info.versionStatus
                wrapMode: Text.WordWrap
                color: text === "Update available" ? info.accent : Kirigami.Theme.textColor
                opacity: text === "Update available" ? 1.0 : 0.6
                font.pixelSize: 10
            }

            RowLayout {
                spacing: 8

                PlasmaComponents.Button {
                    text: info.versionStatus === "Update available" ? i18n("Get update ↗") : i18n("View latest release ↗")
                    implicitHeight: 24
                    font.pixelSize: 10
                    onClicked: Qt.openUrlExternally(Project.releasesPage)
                }

                PlasmaComponents.Button {
                    text: i18n("Check again")
                    implicitHeight: 24
                    font.pixelSize: 10
                    enabled: info.onlineEnabled && info.canRefresh
                    onClicked: info.client.refresh()
                }
            }
        }
    }

    // ── Statistics Cards ─────────────────────────────────────────────────────
    Flow {
        Layout.fillWidth: true
        spacing: 8

        Repeater {
            model: Project.statistics

            Rectangle {
                required property var modelData
                objectName: "stat_" + modelData.id
                width: info.width >= 570 ? (info.width - 16) / 3 : info.width >= 360 ? (info.width - 8) / 2 : info.width
                height: 68
                radius: 8
                color: statArea.containsMouse ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08) : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.04)
                border.width: 1
                border.color: statArea.containsMouse ? info.accent : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)

                Image {
                    objectName: "statIcon_" + parent.modelData.id
                    x: 10
                    y: 10
                    width: 20
                    height: 20
                    source: Qt.resolvedUrl("../icons/" + parent.modelData.icon)
                    sourceSize: Qt.size(40, 40)
                    fillMode: Image.PreserveAspectFit
                }

                PlasmaComponents.Label {
                    x: 38
                    y: 8
                    text: info.counts[parent.modelData.id] || "—"
                    color: Kirigami.Theme.textColor
                    font.pixelSize: 17
                    font.bold: true
                }

                PlasmaComponents.Label {
                    x: 10
                    y: 38
                    width: parent.width - 20
                    text: parent.modelData.label + " ↗"
                    color: Kirigami.Theme.textColor
                    opacity: 0.6
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
        Layout.fillWidth: true
        height: 52
        radius: 8
        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.04)
        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
        border.width: 1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 2

            PlasmaComponents.Label {
                text: i18n("License · %1", Project.license)
                color: Kirigami.Theme.textColor
                font.pixelSize: 11
                font.bold: true
            }

            PlasmaComponents.Label {
                text: Project.licenseId + " · " + i18n("From the bundled LICENSE file")
                color: Kirigami.Theme.textColor
                opacity: 0.5
                font.pixelSize: 9
            }
        }
    }

    // ── Contributors Section ─────────────────────────────────────────────────
    ColumnLayout {
        objectName: "contributorsSection"
        Layout.fillWidth: true
        visible: info.contributorList.length > 0
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            PlasmaComponents.Label {
                text: i18n("Contributors")
                color: Kirigami.Theme.textColor
                font.pixelSize: 13
                font.bold: true
            }

            Item {
                Layout.fillWidth: true
            }

            PlasmaComponents.Button {
                text: i18n("See all on GitHub ↗")
                implicitHeight: 22
                font.pixelSize: 9
                onClicked: Qt.openUrlExternally(Project.contributorsPage)
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: 8

            Repeater {
                model: info.contributorList

                Rectangle {
                    id: contributorCard
                    required property var modelData
                    objectName: "contributor_" + modelData.login
                    width: info.width >= 570 ? (info.width - 16) / 3 : info.width >= 360 ? (info.width - 8) / 2 : info.width
                    height: 50
                    radius: 8
                    color: contributorArea.containsMouse ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08) : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.04)
                    border.color: contributorArea.containsMouse ? info.accent : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
                    border.width: 1

                    Rectangle {
                        x: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: 30
                        height: 30
                        radius: 15
                        color: Qt.rgba(0, 0, 0, 0.2)

                        PlasmaComponents.Label {
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
                            radius: 15
                            Accessible.name: contributorCard.modelData.login + " avatar"
                        }
                    }

                    ColumnLayout {
                        x: 46
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 54
                        spacing: 1

                        PlasmaComponents.Label {
                            Layout.fillWidth: true
                            text: contributorCard.modelData.login
                            elide: Text.ElideRight
                            color: Kirigami.Theme.textColor
                            font.pixelSize: 10
                            font.bold: true
                        }

                        PlasmaComponents.Label {
                            text: contributorCard.modelData.commits + (contributorCard.modelData.commits === 1 ? " commit" : " commits")
                            color: Kirigami.Theme.textColor
                            opacity: 0.5
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
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 6

        PlasmaComponents.Label {
            text: i18n("Support the project")
            color: Kirigami.Theme.textColor
            font.pixelSize: 13
            font.bold: true
        }

        Flow {
            Layout.fillWidth: true
            spacing: 8

            Repeater {
                model: Project.funding

                Rectangle {
                    required property var modelData
                    objectName: "funding_" + modelData.id
                    width: info.width >= 570 ? (info.width - 16) / 3 : info.width >= 360 ? (info.width - 8) / 2 : info.width
                    height: 52
                    radius: 8
                    color: linkArea.containsMouse ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08) : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.04)
                    border.width: 1
                    border.color: linkArea.containsMouse ? info.accent : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)

                    Image {
                        objectName: "fundingIcon_" + parent.modelData.id
                        x: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: 22
                        height: 22
                        source: Qt.resolvedUrl("../icons/" + parent.modelData.icon)
                        fillMode: Image.PreserveAspectFit
                        sourceSize: Qt.size(44, 44)
                    }

                    PlasmaComponents.Label {
                        x: 36
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 44
                        text: parent.modelData.label
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        color: Kirigami.Theme.textColor
                        font.pixelSize: 10
                        font.bold: true
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
    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        PlasmaComponents.Button {
            text: i18n("View source on GitHub ↗")
            implicitHeight: 24
            font.pixelSize: 10
            onClicked: Qt.openUrlExternally(Project.repository)
        }

        PlasmaComponents.Button {
            text: i18n("Report an issue ↗")
            implicitHeight: 24
            font.pixelSize: 10
            onClicked: Qt.openUrlExternally(Project.repository + "/issues")
        }

        Item {
            Layout.fillWidth: true
        }
    }
}
