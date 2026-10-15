// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation

public struct ProxyStatus: Sendable {
    public let installedVersion: String?
    public let running: Bool
    /// Nil until Warren's root certificate exists.
    public let rootTrusted: Bool?
    public let routes: [ProxyRoute]
    public let skipped: [ProxySkippedSite]
}

/// Everything needed to start Caddy in the foreground.
public struct ProxyLaunch: Sendable {
    public let binary: URL
    public let arguments: [String]
    public let environment: [String: String]
    public let plan: ProxyPlan
}

/// Drives the managed Caddy: config from the site registry, run, reload, and explicit trust.
public struct ProxyService: Sendable {
    public let paths: WarrenPaths
    public let release: ToolRelease
    private let installer: ToolInstaller

    public init(paths: WarrenPaths, release: ToolRelease = .caddy) {
        self.paths = paths
        self.release = release
        installer = ToolInstaller(paths: paths)
    }

    public func plan(ports: ProxyPorts) throws -> ProxyPlan {
        try CaddyConfig.plan(sites: SiteRegistry(paths: paths).list(), ports: ports, paths: paths)
    }

    public func install() async throws -> URL {
        try await installer.install(release)
    }

    public func prepareRun(ports: ProxyPorts) throws -> ProxyLaunch {
        let binary = try installedBinary()
        let plan = try writeConfig(ports: ports)
        for port in [ports.http, ports.https] where !PortCheck.isFree(port) {
            throw ProxyError.portInUse(port: port, holder: PortCheck.holder(of: port))
        }
        let environment = [
            "XDG_DATA_HOME": paths.dataDirectory.path,
            "XDG_CONFIG_HOME": paths.configDirectory.path,
        ]
        return ProxyLaunch(
            binary: binary,
            arguments: ["run", "--config", paths.caddyConfigFile.path],
            environment: environment,
            plan: plan
        )
    }

    /// Regenerates the config from the registry and applies it to the running proxy without a restart.
    public func reload(ports: ProxyPorts) throws -> ProxyPlan {
        let binary = try installedBinary()
        guard isRunning() else { throw ProxyError.notRunning }
        let plan = try writeConfig(ports: ports)
        let socket = try paths.validatedAdminSocket()
        let result = try Shell.run(
            binary.path,
            ["reload", "--config", paths.caddyConfigFile.path, "--address", "unix/\(socket.path)"]
        )
        guard result.status == 0 else { throw ToolInstallError.downloadFailed("reload failed: \(result.output)") }
        return plan
    }

    public func trustCommand() throws -> (binary: URL, arguments: [String]) {
        let binary = try installedBinary()
        guard isRunning() else { throw ProxyError.notRunning }
        return try (binary, ["trust", "--address", "unix/\(paths.validatedAdminSocket().path)"])
    }

    public func untrustCommand() throws -> (binary: URL, arguments: [String]) {
        let binary = try installedBinary()
        guard FileManager.default.fileExists(atPath: paths.caddyRootCertificate.path) else {
            throw ProxyError.rootCertificateMissing
        }
        return (binary, ["untrust", "--cert", paths.caddyRootCertificate.path])
    }

    public func status(ports: ProxyPorts) throws -> ProxyStatus {
        let plan = try plan(ports: ports)
        return ProxyStatus(
            installedVersion: installer.isInstalled(release) ? release.version : nil,
            running: isRunning(),
            rootTrusted: rootTrusted(),
            routes: plan.routes,
            skipped: plan.skipped
        )
    }

    public func isRunning() -> Bool {
        guard let socket = try? paths.validatedAdminSocket() else { return false }
        return UnixSocket.canConnect(to: socket.path)
    }

    /// Whether the system trusts Warren's root certificate. Nil if the certificate does not exist yet.
    public func rootTrusted() -> Bool? {
        let certificate = paths.caddyRootCertificate
        guard FileManager.default.fileExists(atPath: certificate.path) else { return nil }
        let result = try? Shell.run("/usr/bin/security", ["verify-cert", "-c", certificate.path])
        return result?.status == 0
    }

    private func installedBinary() throws -> URL {
        guard installer.isInstalled(release) else { throw ProxyError.notInstalled }
        return installer.binaryURL(for: release)
    }

    private func writeConfig(ports: ProxyPorts) throws -> ProxyPlan {
        let plan = try plan(ports: ports)
        let manager = FileManager.default
        for directory in [paths.runDirectory, paths.dataDirectory, paths.caddyDataDirectory] {
            try manager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        try Data(plan.configJSON.utf8).write(to: paths.caddyConfigFile, options: .atomic)
        return plan
    }
}

enum UnixSocket {
    static func canConnect(to path: String) -> Bool {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { return false }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            for (index, byte) in bytes.enumerated() {
                buffer[index] = UInt8(bitPattern: byte)
            }
        }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        return result == 0
    }
}
