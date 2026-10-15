// SPDX-License-Identifier: Apache-2.0

import Foundation

public struct ProxyPorts: Equatable, Sendable {
    public var http: Int
    public var https: Int

    public init(http: Int = 80, https: Int = 443) {
        self.http = http
        self.https = https
    }
}

public struct ProxyRoute: Equatable, Sendable {
    public let siteID: String
    public let domains: [String]
    public let port: Int
}

public struct ProxySkippedSite: Equatable, Sendable {
    public let siteID: String
    public let reason: String
}

/// What the proxy will serve, and the Caddy configuration that implements it.
public struct ProxyPlan: Sendable {
    public let routes: [ProxyRoute]
    public let skipped: [ProxySkippedSite]
    public let configJSON: String
}

public enum ProxyError: Error, Equatable, LocalizedError, Sendable {
    case invalidPort(Int)
    case samePorts(Int)
    case socketPathTooLong(String)
    case notInstalled
    case portInUse(port: Int, holder: String?)
    case notRunning
    case rootCertificateMissing

    public var errorDescription: String? {
        switch self {
        case let .invalidPort(port): "port \(port) is out of range (1 to 65535)"
        case let .samePorts(port): "the HTTP and HTTPS ports must differ (both are \(port))"
        case let .socketPathTooLong(path):
            "the admin socket path is too long for macOS (104 bytes at most): \(path). Use a shorter WARREN_HOME."
        case .notInstalled: "Caddy is not installed. Run: warren proxy install"
        case let .portInUse(port, holder): "port \(port) is already in use" + (holder.map { " by \($0)" } ?? "")
        case .notRunning: "the proxy is not running. Start it with: warren proxy run"
        case .rootCertificateMissing: "Warren's root certificate does not exist yet. Start the proxy once with: warren proxy run"
        }
    }
}

/// Where the proxy keeps its files, all under `~/Warren`.
public extension WarrenPaths {
    var caddyDataDirectory: URL {
        dataDirectory.appendingPathComponent("caddy", isDirectory: true)
    }

    var caddyConfigFile: URL {
        runDirectory.appendingPathComponent("caddy.json")
    }

    var caddyAdminSocket: URL {
        runDirectory.appendingPathComponent("caddy.sock")
    }

    var caddyRootCertificate: URL {
        caddyDataDirectory.appendingPathComponent("pki/authorities/local/root.crt")
    }

    /// The admin socket path, checked against the macOS limit for Unix socket paths.
    func validatedAdminSocket() throws -> URL {
        let socket = caddyAdminSocket
        guard socket.path.utf8.count < 104 else { throw ProxyError.socketPathTooLong(socket.path) }
        return socket
    }
}

public enum CaddyConfig {
    private static let loopback = ["127.0.0.1/32", "::1/128"]

    /// Warren's own check page. The setup wizard loads it to prove DNS, the certificate and the proxy all work.
    public static let selfCheckDomain = "warren.test"
    public static let selfCheckBody = "Warren is working"

    /// Names users cannot claim for a site.
    public static let reservedDomains: Set = [selfCheckDomain]

    /// Builds the routes and Caddy JSON for the given sites. Output is sorted, so the same input gives the same config.
    public static func plan(sites: [ResolvedSite], ports: ProxyPorts, paths: WarrenPaths) throws -> ProxyPlan {
        for port in [ports.http, ports.https] where !(1 ... 65535).contains(port) {
            throw ProxyError.invalidPort(port)
        }
        guard ports.http != ports.https else { throw ProxyError.samePorts(ports.http) }
        let socket = try paths.validatedAdminSocket()

        var routes: [ProxyRoute] = []
        var skipped: [ProxySkippedSite] = []
        for site in sites.sorted(by: { $0.id < $1.id }) {
            if let port = site.port {
                routes.append(ProxyRoute(siteID: site.id, domains: site.domains, port: port))
            } else {
                skipped.append(ProxySkippedSite(siteID: site.id, reason: "no run.port in .warren.toml"))
            }
        }
        let json = try render(routes: routes, ports: ports, paths: paths, socket: socket)
        return ProxyPlan(routes: routes, skipped: skipped, configJSON: json)
    }

    private static func render(routes: [ProxyRoute], ports: ProxyPorts, paths: WarrenPaths,
                               socket: URL) throws -> String
    {
        let localOnly: [String: Any] = ["remote_ip": ["ranges": loopback]]
        let selfCheck: [String: Any] = [
            "match": [["host": [selfCheckDomain], "remote_ip": ["ranges": loopback]]],
            "handle": [["handler": "static_response", "status_code": 200, "body": selfCheckBody]],
            "terminal": true,
        ]
        var httpRoutes: [[String: Any]] = [selfCheck] + routes.map { route in
            [
                "match": [["host": route.domains, "remote_ip": ["ranges": loopback]]],
                "handle": [["handler": "reverse_proxy", "upstreams": [["dial": "localhost:\(route.port)"]]]],
                "terminal": true,
            ]
        }
        httpRoutes.append([
            "match": [["not": [localOnly]]],
            "handle": [["handler": "static_response", "status_code": 403, "body": "Warren: local access only"]],
            "terminal": true,
        ])
        httpRoutes.append([
            "handle": [["handler": "static_response", "status_code": 404, "body": "Warren: no such site"]],
            "terminal": true,
        ])

        let domains = [selfCheckDomain] + routes.flatMap(\.domains)
        var apps: [String: Any] = [
            "http": [
                "http_port": ports.http,
                "https_port": ports.https,
                "servers": ["warren": ["listen": [":\(ports.https)"], "routes": httpRoutes]],
            ],
            // Warren never lets Caddy touch the system keychain. Trust is an explicit user action.
            "pki": ["certificate_authorities": ["local": ["install_trust": false]]],
        ]
        apps["tls"] = ["automation": ["policies": [["subjects": domains, "issuers": [["module": "internal"]]]]]]
        let config: [String: Any] = [
            "admin": ["listen": "unix/\(socket.path)|0600"],
            "storage": ["module": "file_system", "root": paths.caddyDataDirectory.path],
            "apps": apps,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: config,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        return String(bytes: data, encoding: .utf8) ?? ""
    }
}
