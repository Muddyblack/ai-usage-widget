import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: antigravityTabRoot
    property Item rootItem

    visible: rootItem.enabledTabs[rootItem.activeTab] === "antigravity" && !rootItem.showSettings
    Layout.fillWidth: true
    spacing: 12

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        visible: rootItem.antigravityEmail !== "" || rootItem.antigravityPlanType !== ""
        Kirigami.Icon {
            source: "user-identity"
            width: 14
            height: 14
            color: rootItem.googleBlue
            isMask: true
            opacity: 0.7
        }
        PlasmaComponents.Label {
            text: rootItem.antigravityEmail || i18n("Gemini Code Assist")
            font.pixelSize: 10
            opacity: 0.6
            color: Kirigami.Theme.textColor
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
        Rectangle {
            visible: rootItem.antigravityPlanType !== ""
            implicitHeight: 18
            implicitWidth: planLabel.implicitWidth + 16
            Layout.alignment: Qt.AlignVCenter
            radius: 4
            color: rootItem.antigravityPlanType === "Free" ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0.26, 0.66, 0.33, 0.18)
            border.width: 1
            border.color: rootItem.antigravityPlanType === "Free" ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0.26, 0.66, 0.33, 0.35)
            PlasmaComponents.Label {
                id: planLabel
                anchors.centerIn: parent
                text: rootItem.antigravityPlanType
                font.pixelSize: 10
                font.bold: true
                color: rootItem.antigravityPlanType === "Free" ? Kirigami.Theme.textColor : rootItem.googleGreen
            }
        }
        StatusChip {
            Layout.alignment: Qt.AlignVCenter
            status: rootItem.providerStatus.antigravity
        }
    }

    PopupRow {
        visible: rootItem.antigravityPromptCreditsMonthly > 0
        label: i18n("Prompt Credits")
        resetText: rootItem.antigravityResetTime ? i18n("resets %1", rootItem.antigravityResetTime) : ""
        countdownText: rootItem.antigravityCountdown === "resetting..." ? i18n("resetting...") : (rootItem.antigravityCountdown ? i18n("in %1", rootItem.antigravityCountdown) : "")
        value: rootItem.antigravityPromptCreditsMonthly > 0 ? (1 - rootItem.antigravityPromptCreditsAvailable / rootItem.antigravityPromptCreditsMonthly) * 100 : 0
        barColor: rootItem.googleBlue
        tokenText: i18n("%1 / %2 left", rootItem.antigravityPromptCreditsAvailable, rootItem.formatTokens(rootItem.antigravityPromptCreditsMonthly))
        tooltipText: i18n("Prompt Credits\nUsed: %1%", Math.round(value)) + "  ·  " + i18n("%1 / %2 left", rootItem.antigravityPromptCreditsAvailable, rootItem.formatTokens(rootItem.antigravityPromptCreditsMonthly)) + (rootItem.antigravityResetTime ? "\n" + i18n("Resets: %1", rootItem.antigravityResetTime) : "")
    }

    // Only when it says something the family rows below do not: with one model
    // per family (the agy CLI's view) it is just their average, a third copy of
    // the same numbers. The IDE's per-model view, or no families at all, keeps it.
    PopupRow {
        visible: rootItem.antigravityPromptCreditsMonthly === 0 && Object.keys(rootItem.antigravityModels).length > 0 && (rootItem.antigravityGroups.length === 0 || rootItem.antigravityGroups.some(function (g) {
                return (g.models || []).length > 1;
            }))
        label: i18n("Overall Quota")
        resetText: rootItem.antigravityResetTime ? i18n("resets %1", rootItem.antigravityResetTime) : ""
        countdownText: rootItem.antigravityCountdown === "resetting..." ? i18n("resetting...") : (rootItem.antigravityCountdown ? i18n("in %1", rootItem.antigravityCountdown) : "")
        value: rootItem.antigravityPct
        barColor: rootItem.googleBlue
        etaText: rootItem.usageHistory.length >= 0 ? rootItem.etaToFull("ag", rootItem.antigravityPct) : ""
        deltaText: rootItem.usageHistory.length >= 0 ? rootItem.periodDelta("ag", rootItem.antigravityPct, 30 * 24 * 3600000, i18n("last month")) : ""
        tooltipText: i18n("Average quota usage across Gemini models") + "\n" + i18n("%1% used", Math.round(rootItem.antigravityPct)) + (rootItem.antigravityResetTime ? "\n" + i18n("Resets: %1", rootItem.antigravityResetTime) : "")
    }

    // ── Model Quotas, grouped by pooled-quota family ───────────────────────────
    // Mirrors the Antigravity IDE's "Gemini Models" / "Claude & GPT Models"
    // grouping (each group shares a 5-hour reset window), while keeping the
    // richer per-model bars underneath each group header.
    //
    // A family that holds a single model — all the agy CLI reports — is one
    // full row instead, as in the Hyprland and Windows popups: a header with its
    // percentage over a sub-row carrying the same name and the same percentage
    // only printed every number twice.
    ColumnLayout {
        id: groupsSection
        Layout.fillWidth: true
        spacing: 10
        visible: rootItem.antigravityGroups.length > 0

        readonly property bool perModel: rootItem.antigravityGroups.some(function (g) {
            return (g.models || []).length > 1;
        })

        Rectangle {
            visible: groupsSection.perModel
            Layout.fillWidth: true
            height: 1
            color: Qt.rgba(1, 1, 1, 0.08)
        }
        PlasmaComponents.Label {
            visible: groupsSection.perModel
            text: i18n("Model Quotas")
            font.bold: true
            font.pixelSize: 11
            opacity: 0.7
            color: Kirigami.Theme.textColor
        }

        Repeater {
            model: rootItem.antigravityGroups
            ColumnLayout {
                id: groupCol
                Layout.fillWidth: true
                spacing: 5
                required property var modelData
                readonly property var group: modelData
                readonly property bool perModel: (group.models || []).length > 1
                readonly property color familyColor: group.key === "gemini" ? rootItem.googleBlue : rootItem.googleGreen

                // One model in the family: the family is the row.
                PopupRow {
                    visible: !groupCol.perModel
                    label: groupCol.group.label
                    resetText: groupCol.group.resetTime ? "resets " + groupCol.group.resetTime : ""
                    countdownText: {
                        var cd = groupCol.group.resetDate ? rootItem.formatCountdown(groupCol.group.resetDate) : "";
                        return cd === "resetting..." ? cd : (cd ? "in " + cd : "");
                    }
                    value: groupCol.group.isExhausted ? 100 : groupCol.group.usedPct
                    barColor: groupCol.familyColor
                    tooltipText: rootItem.antigravityGroupLabel(groupCol.group.label) + "\n" + Math.round(value) + "% used" + (groupCol.group.isExhausted ? "\n⚠ Quota exhausted" : "") + (groupCol.group.resetTime ? "\nResets: " + groupCol.group.resetTime : "")
                }

                // Group header: name, shared reset countdown, pooled usage %.
                RowLayout {
                    visible: groupCol.perModel
                    Layout.fillWidth: true
                    spacing: 6
                    Rectangle {
                        width: 7
                        height: 7
                        radius: 3.5
                        Layout.alignment: Qt.AlignVCenter
                        color: groupCol.group.key === "gemini" ? rootItem.googleBlue : rootItem.googleGreen
                    }
                    PlasmaComponents.Label {
                        text: rootItem.antigravityGroupLabel(groupCol.group.label)
                        font.pixelSize: 10
                        font.bold: true
                        opacity: 0.85
                        color: Kirigami.Theme.textColor
                    }
                    PlasmaComponents.Label {
                        visible: groupCol.group.resetDate !== null
                        text: {
                            var cd = rootItem.formatCountdown(groupCol.group.resetDate);
                            return cd && cd !== "resetting..." ? "· " + i18n("resets in %1", cd) : (cd === "resetting..." ? i18n("· resetting…") : "");
                        }
                        font.pixelSize: 9
                        opacity: 0.45
                        color: Kirigami.Theme.textColor
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    Item {
                        Layout.fillWidth: true
                        visible: groupCol.group.resetDate === null
                    }
                    PlasmaComponents.Label {
                        text: Math.round(groupCol.group.usedPct) + "%"
                        font.pixelSize: 10
                        font.bold: true
                        color: {
                            if (groupCol.group.usedPct >= 90)
                                return rootItem.dangerColor;
                            if (groupCol.group.usedPct >= 70)
                                return rootItem.warningColor;
                            return groupCol.group.key === "gemini" ? rootItem.googleBlue : rootItem.googleGreen;
                        }
                    }
                }

                // Per-model bars within the group.
                Repeater {
                    model: groupCol.perModel ? groupCol.group.models : []
                    // Wrap in a plain Item so the MouseArea can use anchors.fill
                    // without conflicting with the layout delegate.
                    Item {
                        Layout.fillWidth: true
                        Layout.leftMargin: 13
                        implicitHeight: modelRow.implicitHeight

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            propagateComposedEvents: true
                            QQC2.ToolTip.visible: containsMouse
                            QQC2.ToolTip.delay: 400
                            QQC2.ToolTip.text: {
                                var m = rootItem.antigravityModels[modelData];
                                if (!m)
                                    return modelData;
                                var txt = (m.displayName || modelData) + "\n" + i18n("%1% used", Math.round(m.usedPct));
                                if (m.isExhausted)
                                    txt += i18n("\n⚠ Quota exhausted");
                                if (m.resetTime)
                                    txt += "\n" + i18n("Resets: %1", Qt.formatDateTime(new Date(m.resetTime), "MMM d, hh:mm"));
                                return txt;
                            }
                        }

                        RowLayout {
                            id: modelRow
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8

                            PlasmaComponents.Label {
                                text: rootItem.antigravityModels[modelData] ? (rootItem.antigravityModels[modelData].displayName || modelData) : modelData
                                font.pixelSize: 10
                                color: rootItem.antigravityModels[modelData] && rootItem.antigravityModels[modelData].isExhausted ? rootItem.dangerColor : Kirigami.Theme.textColor
                                opacity: rootItem.antigravityModels[modelData] && rootItem.antigravityModels[modelData].isExhausted ? 1.0 : 0.65
                                Layout.preferredWidth: 120
                                elide: Text.ElideRight
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                height: 6
                                radius: 3
                                color: Qt.rgba(1, 1, 1, 0.06)
                                border.width: 1
                                border.color: Qt.rgba(1, 1, 1, 0.10)
                                Rectangle {
                                    anchors {
                                        left: parent.left
                                        top: parent.top
                                        bottom: parent.bottom
                                        margins: 1
                                    }
                                    width: {
                                        var m = rootItem.antigravityModels[modelData];
                                        return m ? Math.max(0, (parent.width - 2) * (m.usedPct / 100)) : 0;
                                    }
                                    radius: 2
                                    color: {
                                        var m = rootItem.antigravityModels[modelData];
                                        var defColor = groupCol.group.key === "gemini" ? rootItem.googleBlue : rootItem.googleGreen;
                                        if (!m)
                                            return defColor;
                                        return m.isExhausted ? rootItem.dangerColor : m.usedPct >= 70 ? rootItem.warningColor : defColor;
                                    }
                                    Behavior on width {
                                        NumberAnimation {
                                            duration: 500
                                            easing.type: Easing.OutCubic
                                        }
                                    }
                                }
                            }
                            PlasmaComponents.Label {
                                text: {
                                    var m = rootItem.antigravityModels[modelData];
                                    if (!m)
                                        return "—";
                                    return m.isExhausted ? "100%" : Math.round(m.usedPct) + "%";
                                }
                                font.pixelSize: 10
                                font.bold: true
                                color: {
                                    var m = rootItem.antigravityModels[modelData];
                                    if (!m)
                                        return Kirigami.Theme.textColor;
                                    if (m.isExhausted || m.usedPct >= 90)
                                        return rootItem.dangerColor;
                                    if (m.usedPct >= 70)
                                        return rootItem.warningColor;
                                    return groupCol.group.key === "gemini" ? rootItem.googleBlue : rootItem.googleGreen;
                                }
                                Layout.preferredWidth: 35
                                horizontalAlignment: Text.AlignRight
                            }
                        }
                    }
                }
            }
        }
    }
}
