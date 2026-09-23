import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: mistralTabRoot
    property Item rootItem

    visible: rootItem.enabledTabs[rootItem.activeTab] === "mistral" && !rootItem.showSettings
    Layout.fillWidth: true
    spacing: 12

    readonly property bool hasVibe: rootItem.mistralVibeSessionCount > 0

    function fmtTokens(n) {
        if (n >= 1000000)
            return (n / 1000000).toFixed(2) + "M";
        if (n >= 1000)
            return (n / 1000).toFixed(1) + "k";
        return "" + n;
    }

    function relTime(iso) {
        if (!iso)
            return "";
        var then = new Date(iso).getTime();
        if (isNaN(then))
            return "";
        var s = Math.max(0, (new Date().getTime() - then) / 1000);
        if (s < 60)
            return i18n("just now");
        if (s < 3600)
            return i18n("%1m ago", Math.floor(s / 60));
        if (s < 86400)
            return i18n("%1h ago", Math.floor(s / 3600));
        if (s < 604800)
            // xgettext:no-javascript-format
            return i18n("%1d ago", Math.floor(s / 86400));
        return i18n("%1w ago", Math.floor(s / 604800));
    }

    // ── Header: model pill + status ───────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        PlasmaComponents.Label {
            text: "vibe"
            font.pixelSize: 13
            font.bold: true
            color: rootItem.mistralOrange
        }
        PlasmaComponents.Label {
            text: rootItem.mistralVibeActiveModel !== "" ? rootItem.mistralVibeActiveModel : "Mistral AI"
            font.pixelSize: 10
            opacity: 0.55
            color: Kirigami.Theme.textColor
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            implicitHeight: 18
            implicitWidth: mistralBadgeLabel.implicitWidth + 16
            radius: 4
            color: rootItem.mistralKeyValid ? Qt.rgba(1.0, 0.44, 0.0, 0.18) : Qt.rgba(1, 1, 1, 0.06)
            border.width: 1
            border.color: rootItem.mistralKeyValid ? Qt.rgba(1.0, 0.44, 0.0, 0.40) : Qt.rgba(1, 1, 1, 0.12)
            PlasmaComponents.Label {
                id: mistralBadgeLabel
                anchors.centerIn: parent
                text: rootItem.mistralKeyValid ? i18n("CONNECTED") : (rootItem.mistralHasKey ? i18n("INVALID KEY") : i18n("NO KEY"))
                font.pixelSize: 9
                font.bold: true
                color: rootItem.mistralKeyValid ? rootItem.mistralOrange : Kirigami.Theme.textColor
            }
        }
        StatusChip {
            Layout.alignment: Qt.AlignVCenter
            status: rootItem.providerStatus.mistral
        }
    }

    // ── No data at all ────────────────────────────────────────────────────────
    ColumnLayout {
        visible: !mistralTabRoot.hasVibe && !rootItem.mistralKeyValid && !rootItem.mistralHasKey
        Layout.fillWidth: true
        spacing: 6
        PlasmaComponents.Label {
            text: i18n("Not connected")
            font.pixelSize: 12
            font.bold: true
            color: Kirigami.Theme.textColor
            opacity: 0.7
        }
        PlasmaComponents.Label {
            text: i18n("Run the vibe CLI, or set a Mistral API key via\n$MISTRAL_API_KEY · ~/.vibe/.env · ⚙ settings")
            font.pixelSize: 10
            opacity: 0.5
            color: Kirigami.Theme.textColor
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
    }

    // ── Hero cost card ────────────────────────────────────────────────────────
    Rectangle {
        visible: mistralTabRoot.hasVibe
        Layout.fillWidth: true
        Layout.preferredHeight: heroCol.implicitHeight + 24
        radius: 10
        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: Qt.rgba(1.0, 0.44, 0.0, 0.16)
            }
            GradientStop {
                position: 1.0
                color: Qt.rgba(1.0, 0.44, 0.0, 0.05)
            }
        }
        border.width: 1
        border.color: Qt.rgba(1.0, 0.44, 0.0, 0.28)

        ColumnLayout {
            id: heroCol
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: 14
                rightMargin: 14
            }
            spacing: 2

            PlasmaComponents.Label {
                text: i18n("TOTAL SPEND · VIBE CLI")
                font.pixelSize: 9
                font.bold: true
                opacity: 0.55
                color: Kirigami.Theme.textColor
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                PlasmaComponents.Label {
                    text: "$" + rootItem.mistralVibeTotalCost.toFixed(4)
                    font.pixelSize: 28
                    font.bold: true
                    color: rootItem.mistralOrange
                }
                Item {
                    Layout.fillWidth: true
                }
                ColumnLayout {
                    spacing: 0
                    Layout.alignment: Qt.AlignBottom
                    PlasmaComponents.Label {
                        text: i18np("1 session", "%1 sessions", rootItem.mistralVibeSessionCount)
                        font.pixelSize: 11
                        opacity: 0.7
                        color: Kirigami.Theme.textColor
                        Layout.alignment: Qt.AlignRight
                    }
                    PlasmaComponents.Label {
                        text: i18n("%1 tokens", mistralTabRoot.fmtTokens(rootItem.mistralVibeTotalTokens))
                        font.pixelSize: 11
                        opacity: 0.7
                        color: Kirigami.Theme.textColor
                        Layout.alignment: Qt.AlignRight
                    }
                }
            }
        }
    }

    // ── Stat grid: in/out tokens · steps · tool calls ─────────────────────────
    GridLayout {
        visible: mistralTabRoot.hasVibe
        Layout.fillWidth: true
        columns: 2
        rowSpacing: 8
        columnSpacing: 8

        // Input tokens
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 44
            radius: 8
            color: Qt.rgba(1, 1, 1, 0.04)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 8
                ColumnLayout {
                    spacing: 0
                    PlasmaComponents.Label {
                        text: i18nc("stat label", "Input")
                        font.pixelSize: 9
                        opacity: 0.5
                        color: Kirigami.Theme.textColor
                    }
                    PlasmaComponents.Label {
                        text: mistralTabRoot.fmtTokens(rootItem.mistralVibePromptTokens)
                        font.pixelSize: 15
                        font.bold: true
                        color: Kirigami.Theme.textColor
                    }
                }
                Item {
                    Layout.fillWidth: true
                }
                PlasmaComponents.Label {
                    text: "↓"
                    font.pixelSize: 16
                    opacity: 0.4
                    color: rootItem.mistralOrange
                }
            }
        }

        // Output tokens
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 44
            radius: 8
            color: Qt.rgba(1, 1, 1, 0.04)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 8
                ColumnLayout {
                    spacing: 0
                    PlasmaComponents.Label {
                        text: i18nc("stat label", "Output")
                        font.pixelSize: 9
                        opacity: 0.5
                        color: Kirigami.Theme.textColor
                    }
                    PlasmaComponents.Label {
                        text: mistralTabRoot.fmtTokens(rootItem.mistralVibeCompletionTokens)
                        font.pixelSize: 15
                        font.bold: true
                        color: Kirigami.Theme.textColor
                    }
                }
                Item {
                    Layout.fillWidth: true
                }
                PlasmaComponents.Label {
                    text: "↑"
                    font.pixelSize: 16
                    opacity: 0.4
                    color: rootItem.mistralOrange
                }
            }
        }

        // Steps
        Rectangle {
            visible: rootItem.mistralVibeTotalSteps > 0
            Layout.fillWidth: true
            Layout.preferredHeight: 44
            radius: 8
            color: Qt.rgba(1, 1, 1, 0.04)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)
            ColumnLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 0
                Layout.alignment: Qt.AlignVCenter
                PlasmaComponents.Label {
                    text: i18nc("stat label", "Steps")
                    font.pixelSize: 9
                    opacity: 0.5
                    color: Kirigami.Theme.textColor
                }
                PlasmaComponents.Label {
                    text: "" + rootItem.mistralVibeTotalSteps
                    font.pixelSize: 15
                    font.bold: true
                    color: Kirigami.Theme.textColor
                }
            }
        }

        // Tool calls
        Rectangle {
            visible: (rootItem.mistralVibeToolOk + rootItem.mistralVibeToolFail) > 0
            Layout.fillWidth: true
            Layout.preferredHeight: 44
            radius: 8
            color: Qt.rgba(1, 1, 1, 0.04)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)
            ColumnLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 0
                Layout.alignment: Qt.AlignVCenter
                PlasmaComponents.Label {
                    text: i18n("Tool calls")
                    font.pixelSize: 9
                    opacity: 0.5
                    color: Kirigami.Theme.textColor
                }
                RowLayout {
                    spacing: 4
                    PlasmaComponents.Label {
                        text: "" + rootItem.mistralVibeToolOk
                        font.pixelSize: 15
                        font.bold: true
                        color: Kirigami.Theme.textColor
                    }
                    PlasmaComponents.Label {
                        visible: rootItem.mistralVibeToolFail > 0
                        text: "· " + i18n("%1 failed", rootItem.mistralVibeToolFail)
                        font.pixelSize: 10
                        color: "#ff6b6b"
                        opacity: 0.8
                        Layout.alignment: Qt.AlignVCenter
                    }
                }
            }
        }
    }

    // ── Recent sessions (compact, scrollable) ─────────────────────────────────
    ColumnLayout {
        visible: mistralTabRoot.hasVibe && rootItem.mistralVibeRecent.length > 0
        Layout.fillWidth: true
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Rectangle {
                width: 6
                height: 6
                radius: 3
                color: rootItem.mistralOrange
                Layout.alignment: Qt.AlignVCenter
            }
            PlasmaComponents.Label {
                text: i18n("RECENT SESSIONS")
                font.pixelSize: 9
                font.bold: true
                opacity: 0.5
                color: Kirigami.Theme.textColor
                Layout.fillWidth: true
            }
            PlasmaComponents.Label {
                text: i18n("%1 of %2", rootItem.mistralVibeRecent.length, rootItem.mistralVibeSessionCount)
                font.pixelSize: 9
                opacity: 0.4
                color: Kirigami.Theme.textColor
            }
        }

        Rectangle {
            Layout.fillWidth: true
            // ~3.5 rows tall, then scroll; each row is 38px + 6 spacing
            Layout.preferredHeight: Math.min(rootItem.mistralVibeRecent.length, 4) * 44 + 4
            radius: 8
            color: Qt.rgba(1, 1, 1, 0.03)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.07)
            clip: true

            QQC2.ScrollView {
                anchors.fill: parent
                anchors.margins: 2
                contentWidth: availableWidth

                ColumnLayout {
                    width: parent.width
                    spacing: 0

                    Repeater {
                        model: rootItem.mistralVibeRecent
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 44
                            color: rowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.04) : "transparent"

                            // subtle divider between rows (not on the first)
                            Rectangle {
                                visible: index > 0
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                height: 1
                                color: Qt.rgba(1, 1, 1, 0.05)
                            }

                            MouseArea {
                                id: rowMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                QQC2.ToolTip.visible: containsMouse
                                QQC2.ToolTip.delay: 400
                                QQC2.ToolTip.text: (modelData.title || i18n("untitled")) + "\n" + i18n("%1 tokens", mistralTabRoot.fmtTokens(modelData.tokens || 0)) + "  ·  $" + (modelData.cost || 0).toFixed(4) + (modelData.project ? "\n" + modelData.project : "") + (modelData.branch ? " ⎇ " + modelData.branch : "") + (modelData.start ? "\n" + Qt.formatDateTime(new Date(modelData.start), "MMM d, hh:mm") : "")
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 8

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    PlasmaComponents.Label {
                                        text: modelData.title || i18n("untitled")
                                        font.pixelSize: 11
                                        color: Kirigami.Theme.textColor
                                        opacity: 0.9
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 5
                                        PlasmaComponents.Label {
                                            visible: !!modelData.project
                                            text: modelData.project
                                            font.pixelSize: 9
                                            opacity: 0.5
                                            color: Kirigami.Theme.textColor
                                        }
                                        PlasmaComponents.Label {
                                            visible: !!modelData.branch
                                            text: "⎇ " + modelData.branch
                                            font.pixelSize: 9
                                            opacity: 0.4
                                            color: Kirigami.Theme.textColor
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                    }
                                }

                                ColumnLayout {
                                    spacing: 1
                                    Layout.alignment: Qt.AlignVCenter
                                    PlasmaComponents.Label {
                                        text: "$" + (modelData.cost || 0).toFixed(4)
                                        font.pixelSize: 11
                                        font.bold: true
                                        color: rootItem.mistralOrange
                                        Layout.alignment: Qt.AlignRight
                                    }
                                    PlasmaComponents.Label {
                                        text: mistralTabRoot.relTime(modelData.start)
                                        font.pixelSize: 8
                                        opacity: 0.4
                                        color: Kirigami.Theme.textColor
                                        Layout.alignment: Qt.AlignRight
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Footnote ──────────────────────────────────────────────────────────────
    PlasmaComponents.Label {
        visible: mistralTabRoot.hasVibe
        text: i18n("Mistral has no billing API — figures come from local vibe CLI logs.")
        font.pixelSize: 9
        opacity: 0.35
        color: Kirigami.Theme.textColor
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }
}
