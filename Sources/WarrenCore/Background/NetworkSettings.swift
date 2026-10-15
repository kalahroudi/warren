// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The ports the background proxy and DNS server were started with, so later commands and the app
/// reload them with the same ports instead of the defaults.
public struct NetworkSettings: Codable, Equatable, Sendable {
    public var httpPort: Int
    public var httpsPort: Int
    public var dnsPort: Int

    public init(httpPort: Int = 80, httpsPort: Int = 443, dnsPort: Int = DNSPlanner.defaultPort) {
        self.httpPort = httpPort
        self.httpsPort = httpsPort
        self.dnsPort = dnsPort
    }

    public var proxyPorts: ProxyPorts {
        ProxyPorts(http: httpPort, https: httpsPort)
    }

    /// The defaults, or ports from `WARREN_HTTP_PORT`, `WARREN_HTTPS_PORT` and `WARREN_DNS_PORT`
    /// (used by tests and verification, so nothing has to bind ports 80 and 443).
    public static func defaults(_ environment: [String: String] = ProcessInfo.processInfo
        .environment) -> NetworkSettings
    {
        func port(_ key: String, _ fallback: Int) -> Int {
            environment[key].flatMap(Int.init) ?? fallback
        }
        return NetworkSettings(
            httpPort: port("WARREN_HTTP_PORT", 80),
            httpsPort: port("WARREN_HTTPS_PORT", 443),
            dnsPort: port("WARREN_DNS_PORT", DNSPlanner.defaultPort)
        )
    }

    /// The saved settings, or the defaults if none were saved or the file is unreadable.
    public static func load(_ paths: WarrenPaths) -> NetworkSettings {
        guard let data = try? Data(contentsOf: paths.networkSettingsFile),
              let settings = try? JSONDecoder().decode(NetworkSettings.self, from: data)
        else { return defaults() }
        return settings
    }

    public func save(_ paths: WarrenPaths) throws {
        try FileManager.default.createDirectory(at: paths.configDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: paths.networkSettingsFile, options: .atomic)
    }
}
