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
    private let processes: SiteProcesses
    private var notice: String?

    public init(paths: WarrenPaths, network: NetworkServices? = nil, processes: SiteProcesses? = nil) {
        self.paths = paths
        self.processes = processes ?? SiteProcesses(paths: paths)
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
            canControlSites: true,
            canPause: paused || network.proxy.isInstalled || network.dns.isInstalled
        )
        snapshot.isLive = true
        snapshot.previewSections = ["Services", "Agents", "Storage"]
        return snapshot
    }

    /// Starting needs the user's answer to an approval, so the app does it through `SiteRunModel`.
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
            let detection = FrameworkDetector.detect(site: site)
            let run = Self.runState(processes.state(of: site, detection: detection))
            let port = site.port ?? processes.ports.assigned(for: site.id)
            return Site(
                id: site.id,
                domain: site.domains.first ?? site.id,
                stack: detection.displayName,
                runtime: label,
                detail: port.map { ":\($0)" } ?? Self.detail(for: detection),
                path: site.path.hasPrefix(home) ? "~" + site.path.dropFirst(home.count) : site.path,
                state: run.state,
                relayURL: nil,
                startLine: detection.id == nil && detection.command == nil ? "" : detection.startLine,
                managed: run.managed,
                exitCode: run.exitCode
            )
        }
    }

    private struct RunInfo {
        var state: RunState
        var managed = true
        var exitCode: Int32?
    }

    private static func runState(_ state: SiteRunState) -> RunInfo {
        switch state {
        case .stopped: RunInfo(state: .stopped)
        case .starting: RunInfo(state: .starting)
        case let .running(managed): RunInfo(state: .running, managed: managed)
        case let .crashed(code): RunInfo(state: .crashed, exitCode: code)
        }
    }

    private static func detail(for detection: FrameworkDetection) -> String {
        switch detection.kind {
        case .php: "PHP-FPM"
        case .staticFiles: "static files"
        case .server: "no port yet"
        case .unknown: "no port set"
        }
    }
}
