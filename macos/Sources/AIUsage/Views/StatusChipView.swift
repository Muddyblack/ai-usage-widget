import SwiftUI

/// The provider's service status, in the popover's header.
///
/// The same five states and the same words as `hyprland/StatusChip.qml`, so
/// "Partial Outage" means the same thing on every frontend and the translation
/// is already in the catalog. A provider whose status page publishes no
/// machine-readable feed comes through with no indicator and a URL; that is a
/// link and says so, rather than a dot claiming to know something.
struct StatusChipView: View {
    let status: ServiceStatus

    /// A page with no feed behind it: nothing is known, but it can be opened.
    private var isLinkOnly: Bool { status.indicator.isEmpty && !status.url.isEmpty }

    private var label: String {
        switch status.indicator {
        case "critical": return i18n("Major Outage")
        case "major": return i18n("Partial Outage")
        case "minor": return i18n("Minor Issues")
        case "none": return i18n("Operational")
        default: return i18n("Status")
        }
    }

    private var color: Color {
        switch status.indicator {
        case "critical": return .red
        case "major": return .orange
        case "minor": return .yellow
        case "none": return .green
        default: return .secondary
        }
    }

    /// What hovering says: the state, then whatever the feed reported.
    private var tooltip: String {
        var lines = [i18n("Status") + "  ·  " + (status.description.isEmpty ? i18n("Unknown") : status.description)]
        if !status.latestUpdate.isEmpty {
            lines.append(i18n("Latest update:") + " " + status.latestUpdate)
        }
        if !status.url.isEmpty {
            lines.append(i18n("Click to open status page"))
        }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        Group {
            if let url = URL(string: status.url), !status.url.isEmpty {
                Link(destination: url) { chip }.buttonStyle(.plain)
            } else {
                chip
            }
        }
        .help(tooltip)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tooltip)
    }

    private var chip: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            // Only a state worth reacting to says so in words; "Operational" is
            // the expected case and a green dot is enough of it.
            if status.isTrouble || isLinkOnly {
                Text(label)
                    .font(.system(size: 10, weight: status.isTrouble ? .semibold : .regular))
                    .foregroundStyle(status.isTrouble ? color : .secondary)
            }
        }
        .contentShape(Rectangle())
    }
}
