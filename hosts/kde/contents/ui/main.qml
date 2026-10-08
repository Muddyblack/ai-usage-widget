import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtCore
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import "shared"
import "KdeMigration.js" as KdeMigration

// The KDE Plasma host: the panel item, the popup Plasma opens from it, and the
// process runner. Everything inside the popup — and all state behind it — is
// the shared ui/ (copied to contents/ui/shared by `make pack`), the same files
// every other host shows. The backend tools ship in contents/backend.
PlasmoidItem {
    id: root

    // contents/, wherever Plasma installed the package.
    readonly property string contentsDir: Qt.resolvedUrl("..").toString().replace("file://", "").replace(/\/$/, "")
    readonly property string configPath: StandardPaths.writableLocation(StandardPaths.ConfigLocation).toString().replace("file://", "") + "/ai-usage-widget/hyprland-settings.json"

    PlasmaRunner {
        id: runner
    }

    CommandBackend {
        id: commandBackend
        runner: runner
        toolsDir: root.contentsDir + "/backend/sh"
        translateDir: root.contentsDir + "/translate"
        assetsDir: root.contentsDir + "/assets"
        configPath: root.configPath
        pythonPath: app.settings.pythonPath || ""
        systemLanguages: Qt.locale().uiLanguages.map(function (l) {
            return l.replace("-", "_");
        }).concat(Qt.locale().uiLanguages.map(function (l) {
            return l.split(/[-_]/)[0];
        }))
        migrateSettings: function (text) {
            return KdeMigration.migrate(text, Plasmoid.configuration);
        }
    }

    AppState {
        id: app
        backend: commandBackend
        popupVisible: root.expanded
        interpreterControls: true
        themeAccentAvailable: true
        backgroundStyleAvailable: true
        themeAccentColor: Kirigami.Theme.highlightColor
        cliPath: root.contentsDir + "/backend/sh/ai-usage-cli"
        // Each widget keeps its own pins and rotation (one per panel or
        // screen), in its own KConfig rather than the shared file.
        hostSettingsKeys: ["pinnedTabs", "panelRotationSec", "backgroundHints"]
        hostSettings: ({
                pinnedTabs: (Plasmoid.configuration.pinnedTab || "").split(",").filter(function (id) {
                    return id !== "";
                }),
                panelRotationSec: Plasmoid.configuration.panelRotationIntervalSec || 0,
                backgroundHints: Plasmoid.configuration.backgroundHints
            })
        onHostSettingChanged: function (key, value) {
            if (key === "pinnedTabs")
                Plasmoid.configuration.pinnedTab = value.join(",");
            else if (key === "panelRotationSec")
                Plasmoid.configuration.panelRotationIntervalSec = value;
            else if (key === "backgroundHints")
                Plasmoid.configuration.backgroundHints = value;
        }
    }

    Plasmoid.backgroundHints: Plasmoid.configuration.backgroundHints
    Plasmoid.icon: "org.muddyblack.aiUsageWidget"
    toolTipMainText: app.i18n("AI Usage")
    toolTipSubText: {
        var lines = [];
        for (var i = 0; i < app.providers.length; i++) {
            var p = app.providers[i];
            if (p.label && p.summary && p.summary.text)
                lines.push(p.label + ": " + p.summary.text);
        }
        return lines.join("\n");
    }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: app.i18n("Refresh")
            icon.name: "view-refresh"
            onTriggered: app.refresh()
        },
        PlasmaCore.Action {
            text: app.i18n("Settings")
            icon.name: "configure"
            onTriggered: {
                app.showSettings = true;
                root.expanded = true;
            }
        }
    ]

    // ── Panel item ───────────────────────────────────────────────────────────
    compactRepresentation: Item {
        implicitWidth: pill.implicitWidth
        implicitHeight: Kirigami.Units.iconSizes.medium
        Layout.preferredWidth: implicitWidth
        Layout.minimumWidth: implicitWidth
        Layout.maximumWidth: implicitWidth
        Layout.minimumHeight: implicitHeight

        PanelPill {
            id: pill
            anchors.centerIn: parent
            // Plasma draws the panel; the pill keeps only its hover tint and
            // takes the panel theme's text colour.
            framed: false
            textColor: Kirigami.Theme.textColor
            iconSource: app.pillIcon
            active: root.expanded
            slots: app.pillSlots
            stale: app.pillStale
            hasError: app.pillHasError
            groups: app.panelGroups
            onClicked: root.expanded = !root.expanded
        }
    }

    // ── Popup ────────────────────────────────────────────────────────────────
    fullRepresentation: Item {
        id: popupRoot

        // Plasma's own dialog frame already pads this item, so only a little more.
        readonly property int margin: 6
        // Wider while the settings studio is open: it has a sidebar.
        implicitWidth: app.popupWidth
        implicitHeight: Math.min(740, popupHeader.implicitHeight + 12 + mainColumn.implicitHeight + margin * 2)
        Layout.minimumWidth: implicitWidth
        Layout.preferredWidth: implicitWidth
        Layout.minimumHeight: implicitHeight
        Layout.preferredHeight: implicitHeight
        Layout.maximumHeight: implicitHeight

        // The shared glass (ui/PopupBackground.qml), with its tint and decoration.
        PopupBackground {
            anchors.fill: parent
            // Over the whole dialog, edge to edge.
            anchors.margins: -popupRoot.margin
            // Plasma already draws the popup's blurred card; this adds only
            // the tint and decoration so it stays one layer, not a card in a card.
            translucent: true
            radius: 0
            shell: app
        }

        // Title bar and tabs stay put while the body below scrolls.
        PopupHeader {
            id: popupHeader
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: popupRoot.margin
            // Over the body, which the status chip's hover card overlaps.
            z: 2
            shell: app
            snapshotTarget: popupRoot
        }

        Flickable {
            id: contentFlick
            anchors.top: popupHeader.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: popupRoot.margin
            anchors.topMargin: 12
            clip: true
            contentWidth: width
            contentHeight: mainColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            interactive: Math.round(contentHeight) > Math.round(height) + 1

            QQC2.ScrollBar.vertical: QQC2.ScrollBar {
                policy: contentFlick.interactive ? QQC2.ScrollBar.AsNeeded : QQC2.ScrollBar.AlwaysOff
            }

            PopupContent {
                id: mainColumn
                width: contentFlick.width
                shell: app
            }
        }
    }
}
