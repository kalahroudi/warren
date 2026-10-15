// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Real sites from the registry and the real state of the proxy and DNS server.
/// Services, runtimes, agents and storage do not exist yet, so they keep demo data and are flagged as previews.
@MainActor
public final class LiveProvider: StateProvider {
    private let paths: WarrenPaths
    private let network: NetworkServices
    private let preview = FixtureProvider()

    public init(paths: WarrenPaths, network: NetworkServices? = nil) {
        self.paths = paths
        self.network = network ?? NetworkServices(paths: paths)
    }

    public func snapshot() -> StateSnapshot {
        var snapshot = preview.snapshot()
        let sites = liveSites()
        snapshot.sites = sites
        snapshot.activeRuntimes = Set(sites.map(\.runtime).filter { $0 != Self.noRuntime }).sorted()
        snapshot.network = network.status()
        snapshot.update = nil
        snapshot.paused = false
        snapshot.capabilities = Capabilities(canControlSites: false, canPause: false)
        snapshot.isLive = true
        snapshot.previewSections = ["Services", "Runtimes", "Agents", "Storage"]
        return snapshot
    }

    /// Starting and stopping a site's own dev server arrives with the process manager.
    public func setSite(_: String, running _: Bool) {}

    public func setService(_ id: String, running: Bool) {
        preview.setService(id, running: running)
    }

    public func setPaused(_: Bool) {}

    public func applyUpdate() {}

    static let noRuntime = "No runtime"

    private func liveSites() -> [Site] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ((try? SiteRegistry(paths: paths).list()) ?? []).map { site in
            let runtime = site.runtimes.sorted { $0.key < $1.key }.first
                .map { "\($0.key.capitalized) \($0.value)" } ?? Self.noRuntime
            let listening = site.port.map(PortCheck.isListening) ?? false
            return Site(
                id: site.id,
                domain: site.domains.first ?? site.id,
                stack: "Unknown",
                runtime: runtime,
                detail: site.port.map { ":\($0)" } ?? "no port set",
                path: site.path.hasPrefix(home) ? "~" + site.path.dropFirst(home.count) : site.path,
                state: listening ? .running : .stopped,
                relayURL: nil
            )
        }
    }
}
