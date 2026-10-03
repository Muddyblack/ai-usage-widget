import QtQuick

// Local ledgers share the same panel presentation and backend stats contract.
PanelSlot {
    id: slot
    required property Item rootItem
    required property string providerId
    readonly property var provider: rootItem.rawProviderById(providerId) || ({})
    readonly property var reading: (provider.slots || [])[0] || ({})
    readonly property var metadata: rootItem.providerById(providerId) || ({})
    pct: reading.pct || 0
    iconColor: metadata.color || "#888888"
    iconSource: Qt.resolvedUrl("../icons/" + (metadata.icon || ""))
    iconText: (metadata.label || providerId).slice(0, 2)
    stale: rootItem.stale && rootItem.panelShows(providerId)
    visible: rootItem.panelShows(providerId) && !rootItem.showSettings
    showCost: !provider.ok || (reading.text !== null && reading.text !== undefined)
    costText: reading.text === null || reading.text === undefined ? "—" : String(reading.text)
    tooltipText: reading.tooltip || metadata.label || providerId
}
