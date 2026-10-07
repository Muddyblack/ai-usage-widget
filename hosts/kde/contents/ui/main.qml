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
        cliPath: root.contentsDir + "/backend/sh/ai-usage-cli"
    }

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
            onClicked: root.expanded = !root.expanded
        }
    }

    // ── Popup ────────────────────────────────────────────────────────────────
    fullRepresentation: Item {
        id: popupRoot

        readonly property int margin: 20
        implicitWidth: 460
        implicitHeight: Math.min(740, mainColumn.implicitHeight + margin * 2)
        Layout.minimumWidth: implicitWidth
        Layout.preferredWidth: implicitWidth
        Layout.minimumHeight: implicitHeight
        Layout.preferredHeight: implicitHeight
        Layout.maximumHeight: implicitHeight

        // The same glass every host draws; Plasma's popup blur shows through.
        Rectangle {
            anchors.fill: parent
            anchors.margins: -Kirigami.Units.smallSpacing
            radius: 12
            gradient: Gradient {
                GradientStop {
                    position: 0.0
                    color: Qt.rgba(0.09, 0.10, 0.13, 0.94)
                }
                GradientStop {
                    position: 0.5
                    color: Qt.rgba(0.06, 0.07, 0.09, 0.94)
                }
                GradientStop {
                    position: 1.0
                    color: Qt.rgba(0.04, 0.045, 0.06, 0.95)
                }
            }
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.12)
        }

        Flickable {
            id: contentFlick
            anchors.fill: parent
            anchors.margins: popupRoot.margin
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
