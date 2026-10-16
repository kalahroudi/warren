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

/// What answers for a site's names.
public enum ProxyTarget: Equatable, Sendable {
    /// A server on a loopback port.
    case server(port: Int)
    /// PHP files in `root` through the PHP-FPM listening on `socket`.
    case php(socket: String, root: String)
    /// Files in `root`, served as they are.
    case staticFiles(root: String)

    public var summary: String {
        switch self {
        case let .server(port): "localhost:\(port)"
        case let .php(_, root): "PHP-FPM, \(root)"
        case let .staticFiles(root): "files in \(root)"
        }
    }
}

public struct ProxyRoute: Equatable, Sendable {
    public let siteID: String
    public let domains: [String]
    public let target: ProxyTarget
}

public struct ProxySkippedSite: Equatable, Sendable {
    public let siteID: String
    public let domains: [String]
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
    public static let notRunningBody = "Warren: this site is not running. Start it from Warren's menu bar item."

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
            switch SiteServing.target(for: site, paths: paths) {
            case let .success(target): routes.append(ProxyRoute(siteID: site.id, domains: site.domains, target: target))
            case let .failure(reason): skipped.append(ProxySkippedSite(
                    siteID: site.id,
                    domains: site.domains,
                    reason: reason.text
                ))
            }
        }
        let json = try render(routes: routes, stopped: skipped, ports: ports, paths: paths, socket: socket)
        return ProxyPlan(routes: routes, skipped: skipped, configJSON: json)
    }

    /// The handlers for one site. PHP follows what Caddy's `php_fastcgi` directive expands to: try the file, then the
    /// directory's `index.php`, then `index.php`, and send `.php` requests to FPM; everything else is a file.
    static func handlers(for target: ProxyTarget) -> [[String: Any]] {
        switch target {
        case let .server(port):
            return [["handler": "reverse_proxy", "upstreams": [["dial": "localhost:\(port)"]]]]
        case let .staticFiles(root):
            return [["handler": "file_server", "root": root, "index_names": ["index.html"]]]
        case let .php(socket, root):
            let tryFiles: [String: Any] = [
                "root": root,
                "try_files": ["{http.request.uri.path}", "{http.request.uri.path}/index.php", "index.php"],
                "split_path": [".php"],
            ]
            return [[
                "handler": "subroute",
                "routes": [
                    [
                        "match": [["file": tryFiles]],
                        "handle": [["handler": "rewrite", "uri": "{http.matchers.file.relative}"]],
                    ],
                    [
                        "match": [["path": ["*.php"]]],
                        "handle": [[
                            "handler": "reverse_proxy",
                            "upstreams": [["dial": "unix/\(socket)"]],
                            "transport": ["protocol": "fastcgi", "root": root, "split_path": [".php"]],
                        ]],
                        "terminal": true,
                    ],
                    ["handle": [["handler": "file_server", "root": root]]],
                ],
            ]]
        }
    }

    private static func render(routes: [ProxyRoute], stopped: [ProxySkippedSite], ports: ProxyPorts,
                               paths: WarrenPaths, socket: URL) throws -> String
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
                "handle": handlers(for: route.target),
                "terminal": true,
            ]
        }
        // A site that is not running still gets its certificate and a plain page, instead of a browser error.
        httpRoutes += stopped.filter { !$0.domains.isEmpty }.map { site in
            [
                "match": [["host": site.domains, "remote_ip": ["ranges": loopback]]],
                "handle": [["handler": "static_response", "status_code": 503, "body": notRunningBody]],
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

        let domains = [selfCheckDomain] + routes.flatMap(\.domains) + stopped.flatMap(\.domains)
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
