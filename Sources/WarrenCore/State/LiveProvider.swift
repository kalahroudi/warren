// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Real sites from the registry and the real state of the proxy and DNS server.
/// Services, agents and storage do not exist yet, so they keep demo data and are flagged as previews.
@MainActor
public final class LiveProvider: StateProvider {
    private let paths: WarrenPaths
    private let network: NetworkServices
    private let preview = FixtureProvider()
    private let assessor: SetupAssessor
    private var notice: String?

    public init(paths: WarrenPaths, network: NetworkServices? = nil) {
        self.paths = paths
        let network = network ?? NetworkServices(paths: paths)
        self.network = network
        assessor = SetupAssessor(paths: paths, network: network)
    }

    public func snapshot() -> StateSnapshot {
        var snapshot = preview.snapshot()
        let sites = liveSites()
        snapshot.sites = sites
        snapshot.runtimeGroups = []
        snapshot
            .activeRuntimes = Set(sites.flatMap { $0.runtime.components(separatedBy: ", ") }
                .filter { $0 != Self.noRuntime }).sorted()
        snapshot.network = network.status()
        let paused = UserState.load(paths).paused
        // A paused Warren is complete but switched off, so it is not nagged about setup.
        snapshot.setupComplete = paused || assessor.assess(status: snapshot.network).isComplete
        snapshot.update = nil
        snapshot.paused = paused
        snapshot.notice = notice
        // There is only something to pause once local HTTPS or DNS has been set up.
        snapshot.capabilities = Capabilities(
            canControlSites: false,
            canPause: paused || network.proxy.isInstalled || network.dns.isInstalled
        )
        snapshot.isLive = true
        snapshot.previewSections = ["Services", "Agents", "Storage"]
        return snapshot
    }

    /// Starting and stopping a site's own dev server arrives with the process manager.
    public func setSite(_: String, running _: Bool) {}

    public func setService(_ id: String, running: Bool) {
        preview.setService(id, running: running)
    }

    /// Pause stops the background proxy and DNS server and keeps them off, including across logins, until resumed.
    public func setPaused(_ paused: Bool) {
        notice = nil
        do {
            var user = UserState.load(paths)
            if paused {
                try network.stop(.proxy)
                try network.stop(.dns)
            } else {
                let settings = NetworkSettings.load(paths)
                if network.proxy.isInstalled {
                    try network.startProxy(ports: settings.proxyPorts)
                }
                if network.dns.isInstalled {
                    try network.startDNS(port: settings.dnsPort)
                }
            }
            user.paused = paused
            try user.save(paths)
        } catch {
            notice = paused ? "Could not pause: \(error.localizedDescription)" : "Could not resume: \(error.localizedDescription)"
        }
    }

    public func applyUpdate() {}

    static let noRuntime = "No runtime"

    private func liveSites() -> [Site] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ((try? SiteRegistry(paths: paths).list()) ?? []).map { site in
            let runtime = RuntimeResolver.requirements(for: site).map(\.label).joined(separator: ", ")
            let label = runtime.isEmpty ? Self.noRuntime : runtime
            let listening = site.port.map(PortCheck.isListening) ?? false
            return Site(
                id: site.id,
                domain: site.domains.first ?? site.id,
                stack: "Unknown",
                runtime: label,
                detail: site.port.map { ":\($0)" } ?? "no port set",
                path: site.path.hasPrefix(home) ? "~" + site.path.dropFirst(home.count) : site.path,
                state: listening ? .running : .stopped,
                relayURL: nil
            )
        }
    }
}
