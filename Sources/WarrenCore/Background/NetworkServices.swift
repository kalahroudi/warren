// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Starts, stops and inspects the background proxy and DNS server, and keeps them in step with the site registry.
public struct NetworkServices: Sendable {
    public let paths: WarrenPaths
    public let background: BackgroundServices
    public let proxy: ProxyService
    public let dns: DNSService

    public init(
        paths: WarrenPaths,
        background: BackgroundServices? = nil,
        resolvers: ResolverManager = ResolverManager()
    ) {
        self.paths = paths
        self.background = background ?? BackgroundServices(paths: paths)
        proxy = ProxyService(paths: paths)
        dns = DNSService(paths: paths, resolvers: resolvers)
    }

    @discardableResult
    public func startProxy(ports: ProxyPorts) throws -> ProxyPlan {
        if !background.isLoaded(.proxy) {
            for port in [ports.http, ports.https] where !PortCheck.isFree(port) {
                throw ProxyError.portInUse(port: port, holder: PortCheck.holder(of: port))
            }
        }
        let agent = try proxy.launchAgent(ports: ports, logFile: background.logURL(.proxy))
        try background.start(agent)
        clearPause()
        var settings = NetworkSettings.load(paths)
        settings.httpPort = ports.http
        settings.httpsPort = ports.https
        try settings.save(paths)
        return try proxy.plan(ports: ports)
    }

    @discardableResult
    public func startDNS(port: Int) throws -> DNSPlan {
        if !background.isLoaded(.dns), !PortCheck.isFree(port) {
            throw DNSError.portInUse(port: port, holder: PortCheck.holder(of: port))
        }
        let (agent, plan) = try dns.launchAgent(port: port, logFile: background.logURL(.dns))
        try background.start(agent)
        clearPause()
        var settings = NetworkSettings.load(paths)
        settings.dnsPort = port
        try settings.save(paths)
        return plan
    }

    /// Starting something on purpose ends a pause.
    private func clearPause() {
        var user = UserState.load(paths)
        guard user.paused else { return }
        user.paused = false
        try? user.save(paths)
    }

    public func stop(_ kind: BackgroundKind) throws {
        try background.stop(kind)
    }

    public func status() -> NetworkStatus {
        let settings = NetworkSettings.load(paths)
        return NetworkStatus(
            proxy: ServiceStatus(
                installed: proxy.isInstalled,
                running: background.isLoaded(.proxy) && proxy.isRunning()
            ),
            dns: ServiceStatus(
                installed: dns.isInstalled,
                running: background.isLoaded(.dns) && PortCheck.isListening(settings.dnsPort)
            ),
            rootTrusted: proxy.rootTrusted()
        )
    }

    /// Applies the current registry to whatever is running: the proxy reloads and the Corefile is rewritten.
    /// Returns a message for each problem; an empty list means everything that is running is up to date.
    public func applyRegistryChange() -> [String] {
        let settings = NetworkSettings.load(paths)
        var problems: [String] = []
        if background.isLoaded(.proxy) {
            do { _ = try proxy.reload(ports: settings.proxyPorts) } catch {
                problems.append("proxy: \(error.localizedDescription)")
            }
        }
        if background.isLoaded(.dns) {
            do { try dns.sync(port: settings.dnsPort) } catch { problems.append("dns: \(error.localizedDescription)") }
        }
        return problems
    }
}
