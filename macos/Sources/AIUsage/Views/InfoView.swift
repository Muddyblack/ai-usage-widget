import AppKit
import SwiftUI

struct Contributor: Identifiable, Decodable {
    var id: String { login }
    let login: String
    let contributions: Int
    let avatar_url: String?
    let html_url: String?
}

@MainActor
final class ProjectInfoModel: ObservableObject {
    @Published var starsCount: String = "—"
    @Published var downloadsCount: String = "—"
    @Published var kdeDownloadsCount: String = "—"
    @Published var latestVersion: String = ""
    @Published var releaseStatus: String = "Not checked"
    @Published var contributors: [Contributor] = []
    @Published var isChecking: Bool = false

    let currentVersion: String = "3.1.1"

    func loadAll() {
        checkRelease()
        fetchStats()
        fetchContributors()
    }

    func checkRelease() {
        guard !isChecking else { return }
        isChecking = true
        releaseStatus = i18n("Checking…")

        guard let url = URL(string: "https://api.github.com/repos/Muddyblack/ai-usage-widget/releases/latest") else {
            isChecking = false
            return
        }
        Task {
            do {
                var request = URLRequest(url: url)
                request.setValue("AIUsage-macOS", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tagName = json["tag_name"] as? String else {
                    self.releaseStatus = i18n("Could not check for updates")
                    self.isChecking = false
                    return
                }
                let cleanTag = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
                self.latestVersion = cleanTag
                self.releaseStatus = self.compareVersion(current: self.currentVersion, latest: cleanTag)
            } catch {
                self.releaseStatus = i18n("Could not check for updates")
            }
            self.isChecking = false
        }
    }

    private func compareVersion(current: String, latest: String) -> String {
        let curParts = current.split(separator: ".").compactMap { Int($0) }
        let latParts = latest.split(separator: ".").compactMap { Int($0) }
        guard curParts.count == 3, latParts.count == 3 else { return i18n("Version comparison unavailable") }
        for i in 0..<3 {
            if curParts[i] < latParts[i] { return i18n("Update available") }
            if curParts[i] > latParts[i] { return i18n("Newer than latest release") }
        }
        return i18n("Up to date")
    }

    private func fetchStats() {
        // GitHub stars
        if let url = URL(string: "https://img.shields.io/github/stars/Muddyblack/ai-usage-widget.json") {
            Task {
                if let (data, _) = try? await URLSession.shared.data(from: url),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let val = json["value"] as? String, !val.isEmpty {
                    self.starsCount = val
                }
            }
        }
        // GitHub downloads
        if let url = URL(string: "https://img.shields.io/github/downloads/Muddyblack/ai-usage-widget/total.json") {
            Task {
                if let (data, _) = try? await URLSession.shared.data(from: url),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let val = json["value"] as? String, !val.isEmpty {
                    self.downloadsCount = val
                }
            }
        }
        // OpenDesktop downloads (uses user=Muddyblack endpoint matching README.md)
        let plingQuery = "https://api.pling.com/ocs/v1/content/data/?format=json&user=Muddyblack&pagesize=20&sortmode=alpha"
        let plingUrlStr = "https://img.shields.io/badge/dynamic/json.json?url=" +
            (plingQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "") +
            "&query=" + ("$.data[0].downloads".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "") + "&label=Downloads"
        if let url = URL(string: plingUrlStr) {
            Task {
                if let (data, _) = try? await URLSession.shared.data(from: url),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let val = json["value"] as? String, !val.isEmpty {
                    self.kdeDownloadsCount = val
                }
            }
        }
    }

    private func fetchContributors() {
        guard let url = URL(string: "https://api.github.com/repos/Muddyblack/ai-usage-widget/contributors?per_page=12") else { return }
        Task {
            do {
                var request = URLRequest(url: url)
                request.setValue("AIUsage-macOS", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
                let list = try JSONDecoder().decode([Contributor].self, from: data)
                self.contributors = list.filter { $0.contributions > 0 }
            } catch {}
        }
    }
}

struct InfoView: View {
    @StateObject private var info = ProjectInfoModel()

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack(spacing: 12) {
                    if let icon = Artwork.providerImage("org.muddyblack.aiUsageWidget.svg") ?? NSApp.applicationIconImage {
                        Image(nsImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 52, height: 52)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(i18n("AI Usage Monitor"))
                            .font(.system(size: 16, weight: .semibold))
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.secondary.opacity(0.2))
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Text(verbatim: "M")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.accent)
                                )
                            Button(i18n("By %1 ↗", "Muddyblack")) {
                                open("https://github.com/Muddyblack")
                            }
                            .buttonStyle(.link)
                            .font(.system(size: 11))
                        }
                    }
                }

                Text(i18n("An open-source AI quota & usage monitor for Plasma, Hyprland, macOS and Windows. Explore the project, get updates, or help improve it."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                // Version Card
                VStack(alignment: .leading, spacing: 6) {
                    Text(i18n("Installed version · %1", info.currentVersion))
                        .font(.system(size: 11, weight: .semibold))
                    Text(i18n("Latest stable release · %1", info.latestVersion.isEmpty ? "—" : info.latestVersion))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(info.releaseStatus)
                        .font(.system(size: 11))
                        .foregroundStyle(info.releaseStatus == i18n("Update available") ? Color.accentColor : Color.secondary)

                    HStack(spacing: 8) {
                        Button(info.releaseStatus == i18n("Update available") ? i18n("Get update ↗") : i18n("View latest release ↗")) {
                            open("https://github.com/Muddyblack/ai-usage-widget/releases")
                        }
                        .controlSize(.small)

                        Button(i18n("Check again")) {
                            info.checkRelease()
                        }
                        .controlSize(.small)
                        .disabled(info.isChecking)
                    }
                    .padding(.top, 2)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.15), lineWidth: 1))

                // Statistics
                LazyVGrid(columns: columns, spacing: 8) {
                    statCard(title: i18n("GitHub stars ↗"), value: info.starsCount, icon: "star.svg", url: "https://github.com/Muddyblack/ai-usage-widget/stargazers")
                    statCard(title: i18n("GitHub downloads ↗"), value: info.downloadsCount, icon: "download.svg", url: "https://github.com/Muddyblack/ai-usage-widget/releases")
                    statCard(title: i18n("OpenDesktop downloads ↗"), value: info.kdeDownloadsCount, icon: "download.svg", url: "https://www.opendesktop.org/p/2361382")
                }

                // License Card
                VStack(alignment: .leading, spacing: 2) {
                    Text(i18n("License · %1", "MIT License"))
                        .font(.system(size: 11, weight: .semibold))
                    Text("MIT · " + i18n("From the bundled LICENSE file"))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.15), lineWidth: 1))

                // Contributors
                if !info.contributors.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(i18n("Contributors"))
                                .font(.system(size: 12, weight: .semibold))
                            Spacer()
                            Button(i18n("See all on GitHub ↗")) {
                                open("https://github.com/Muddyblack/ai-usage-widget/graphs/contributors")
                            }
                            .buttonStyle(.link)
                            .font(.system(size: 10))
                        }

                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(info.contributors) { c in
                                Button {
                                    if let url = c.html_url { open(url) }
                                } label: {
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(Color.secondary.opacity(0.2))
                                            .frame(width: 24, height: 24)
                                            .overlay(
                                                Text(String(c.login.prefix(1)).uppercased())
                                                    .font(.system(size: 10, weight: .bold))
                                                    .foregroundStyle(.accent)
                                            )
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(c.login)
                                                .font(.system(size: 11, weight: .medium))
                                                .lineLimit(1)
                                            Text(c.contributions == 1 ? "1 commit" : "\(c.contributions) commits")
                                                .font(.system(size: 9))
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06)))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.12), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                // Support the project
                VStack(alignment: .leading, spacing: 6) {
                    Text(i18n("Support the project"))
                        .font(.system(size: 12, weight: .semibold))

                    LazyVGrid(columns: columns, spacing: 8) {
                        fundingCard(name: "GitHub Sponsors", icon: "githubsponsors.svg", url: "https://github.com/sponsors/muddyblack")
                        fundingCard(name: "Ko-fi", icon: "kofi.svg", url: "https://ko-fi.com/muddyblack")
                        fundingCard(name: "Buy Me a Coffee", icon: "buymeacoffee.svg", url: "https://buymeacoffee.com/muddyblack")
                    }
                }

                // Footer Links
                HStack(spacing: 12) {
                    Button(i18n("View source on GitHub ↗")) {
                        open("https://github.com/Muddyblack/ai-usage-widget")
                    }
                    .controlSize(.small)

                    Button(i18n("Report an issue ↗")) {
                        open("https://github.com/Muddyblack/ai-usage-widget/issues")
                    }
                    .controlSize(.small)
                }
                .padding(.top, 4)
            }
            .padding(16)
        }
        .onAppear {
            info.loadAll()
        }
    }

    private func statCard(title: String, value: String, icon: String, url: String) -> some View {
        Button {
            open(url)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if let img = Artwork.providerImage(icon) {
                        Image(nsImage: img)
                            .resizable()
                            .frame(width: 16, height: 16)
                    }
                    Spacer()
                    Text(value)
                        .font(.system(size: 16, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func fundingCard(name: String, icon: String, url: String) -> some View {
        Button {
            open(url)
        } label: {
            HStack(spacing: 8) {
                if let img = Artwork.providerImage(icon) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 18, height: 18)
                }
                Text(name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
