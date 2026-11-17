import AppKit
import SwiftUI
import SessionModel

/// The release check (issue #35): MISSION.md §2's one exception, D12.
/// Once a day, one GET of GitHub's latest-release record for this
/// repository, and a banner with the download when it is newer than
/// this build. The request carries nothing about the reviewer's work.
/// Settings → Updates turns it off. API:
/// https://docs.github.com/en/rest/releases/releases#get-the-latest-release
@Observable @MainActor
final class UpdateCheck {
    static let enabledKey = "updateCheckEnabled"
    static let lastCheckKey = "updateCheckLast"
    static let releaseAPI = URL(string: "https://api.github.com/repos/SpaceTrucker2196/PatchAdams/releases/latest")!

    struct Release: Sendable, Equatable {
        var version: ReleaseVersion
        var page: URL
        var download: URL?
    }

    /// This build's version; a debug hook can pretend an older one.
    var currentVersion = ReleaseVersion(tag: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") ?? ReleaseVersion(components: [0])
    /// A release newer than this build, until Download or Later.
    var available: Release?
    /// What the last check found, for Settings.
    var lastResult: String?
    var isChecking = false

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) == nil ? true : UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// At launch: a check when the last one is a day old or more.
    func checkIfDue() {
        guard Self.isEnabled else { return }
        let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) >= 24 * 60 * 60 else { return }
        Task { await check() }
    }

    func check() async {
        isChecking = true
        defer { isChecking = false }
        do {
            var request = URLRequest(url: Self.releaseAPI, timeoutInterval: 10)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, _) = try await URLSession.shared.data(for: request)
            let record = try JSONDecoder().decode(GitHubRelease.self, from: data)
            UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
            guard let version = ReleaseVersion(tag: record.tag_name), let page = URL(string: record.html_url) else {
                lastResult = String(localized: "GitHub answered with a release this app cannot read: \(record.tag_name)")
                return
            }
            let dmg = record.assets.first { $0.name.hasSuffix(".dmg") }.flatMap { URL(string: $0.browser_download_url) }
            if version > currentVersion {
                available = Release(version: version, page: page, download: dmg)
                lastResult = String(localized: "Patch Adams \(version.description) is available; this is \(currentVersion.description).")
            } else {
                available = nil
                lastResult = String(localized: "Up to date: \(currentVersion.description) is the latest release.")
            }
        } catch {
            lastResult = String(localized: "Could not reach GitHub: \(error.localizedDescription)")
        }
    }

    /// The DMG when the release has one, else its page.
    func download() {
        guard let release = available else { return }
        NSWorkspace.shared.open(release.download ?? release.page)
        available = nil
    }
}

/// The fields of GitHub's release record this app reads.
private struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        var name: String
        var browser_download_url: String
    }
    var tag_name: String
    var html_url: String
    var assets: [Asset]
}

/// The reminder across the top of the window: the new version, Download, Later.
struct UpdateBanner: View {
    let updates: UpdateCheck

    var body: some View {
        if let release = updates.available {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(Color(nsColor: SpacetruckerPalette.amber))
                Text(String(localized: "Patch Adams \(release.version.description) is out. This is \(updates.currentVersion.description)."))
                Spacer()
                Button(String(localized: "Download")) { updates.download() }.buttonStyle(.borderedProminent)
                Button(String(localized: "Later")) { updates.available = nil }
            }
            .font(.ui(.callout))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(Color(nsColor: SpacetruckerPalette.amber).opacity(0.22).background(Color(nsColor: .windowBackgroundColor)))
        }
    }
}
