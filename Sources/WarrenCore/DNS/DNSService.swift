// SPDX-License-Identifier: Apache-2.0

import Foundation

public struct DNSStatus: Sendable {
    public let installedVersion: String?
    public let running: Bool
    public let plan: DNSPlan
    public let resolvers: [ResolverEntry]
    /// For each site domain: whether the real macOS resolver returns a loopback address for it.
    public let resolution: [(domain: String, resolves: Bool)]
}

public struct DNSLaunch: Sendable {
    public let binary: URL
    public let arguments: [String]
    public let plan: DNSPlan
}

/// Drives the managed CoreDNS and the resolver files that point macOS at it.
public struct DNSService: Sendable {
    public let paths: WarrenPaths
    public let release: ToolRelease
    public let resolvers: ResolverManager
    private let installer: ToolInstaller

    public init(paths: WarrenPaths, resolvers: ResolverManager = ResolverManager(), release: ToolRelease = .coredns) {
        self.paths = paths
        self.release = release
        self.resolvers = resolvers
        installer = ToolInstaller(paths: paths)
    }

    public func plan(port: Int) throws -> DNSPlan {
        let domains = try SiteRegistry(paths: paths).list().flatMap(\.domains)
        return try DNSPlanner.plan(domains: domains, port: port)
    }

    public func install() async throws -> URL {
        try await installer.install(release)
    }

    /// Writes the Corefile. A running CoreDNS notices the change and reloads by itself.
    @discardableResult
    public func sync(port: Int) throws -> DNSPlan {
        let plan = try plan(port: port)
        try FileManager.default.createDirectory(
            at: paths.runDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        try Data(plan.corefile.utf8).write(to: paths.dnsCorefile, options: .atomic)
        return plan
    }

    public func prepareRun(port: Int) throws -> DNSLaunch {
        guard installer.isInstalled(release) else { throw DNSError.notInstalled }
        let plan = try sync(port: port)
        guard !plan.zones.isEmpty else { throw DNSError.noZones }
        guard PortCheck.isFree(port) else { throw DNSError.portInUse(port: port, holder: PortCheck.holder(of: port)) }
        return DNSLaunch(
            binary: installer.binaryURL(for: release),
            arguments: ["-conf", paths.dnsCorefile.path],
            plan: plan
        )
    }

    /// The same command as `prepareRun`, described as a launchd job. Writes the Corefile first.
    public func launchAgent(port: Int, logFile: URL) throws -> (agent: LaunchAgent, plan: DNSPlan) {
        guard installer.isInstalled(release) else { throw DNSError.notInstalled }
        let plan = try sync(port: port)
        guard !plan.zones.isEmpty else { throw DNSError.noZones }
        let agent = LaunchAgent(
            kind: .dns, program: installer.binaryURL(for: release),
            arguments: ["-conf", paths.dnsCorefile.path], environment: [:], logFile: logFile
        )
        return (agent, plan)
    }

    public var isInstalled: Bool {
        installer.isInstalled(release)
    }

    public func inspectResolvers(port: Int) throws -> (plan: DNSPlan, entries: [ResolverEntry]) {
        let plan = try plan(port: port)
        return (plan, resolvers.inspect(zones: plan.zones, port: port))
    }

    public func status(port: Int) throws -> DNSStatus {
        let (plan, entries) = try inspectResolvers(port: port)
        let domains = try SiteRegistry(paths: paths).list().flatMap(\.domains)
        return DNSStatus(
            installedVersion: installer.isInstalled(release) ? release.version : nil,
            running: PortCheck.holder(of: port)?.hasPrefix(release.name) == true,
            plan: plan,
            resolvers: entries,
            resolution: Set(domains).sorted().map { ($0, Self.systemResolves($0)) }
        )
    }

    /// Asks the real macOS resolver, the same path browsers use, whether the name points at this Mac.
    static func systemResolves(_ domain: String) -> Bool {
        guard let result = try? Shell.run("/usr/bin/dscacheutil", ["-q", "host", "-a", "name", domain])
        else { return false }
        return result.output.contains("ip_address: 127.0.0.1") || result.output.contains("ipv6_address: ::1")
    }
}
