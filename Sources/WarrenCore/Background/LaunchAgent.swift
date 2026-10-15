// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum BackgroundKind: String, CaseIterable, Sendable {
    case proxy
    case dns

    /// The launchd label. A placeholder prefix until Warren has a real identifier domain.
    public var label: String {
        "dev.warren.\(rawValue)"
    }
}

/// A per-user launchd job that runs one of Warren's managed binaries.
public struct LaunchAgent: Equatable, Sendable {
    public let kind: BackgroundKind
    public let program: URL
    public let arguments: [String]
    public let environment: [String: String]
    public let logFile: URL

    /// The property list launchd reads. It starts the job at login and restarts it if it exits.
    public func plist() throws -> Data {
        var dictionary: [String: Any] = [
            "Label": kind.label,
            "ProgramArguments": [program.path] + arguments,
            "RunAtLoad": true,
            "KeepAlive": true,
            "ProcessType": "Background",
            "StandardOutPath": logFile.path,
            "StandardErrorPath": logFile.path,
        ]
        if !environment.isEmpty {
            dictionary["EnvironmentVariables"] = environment
        }
        return try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
    }
}

/// The part of launchd Warren needs. A protocol so tests do not start real jobs.
public protocol LaunchControlling: Sendable {
    func bootstrap(plist: URL) throws
    func bootout(label: String) throws
    func isLoaded(label: String) -> Bool
}

public struct LaunchCtl: LaunchControlling {
    private let domain: String

    public init(userID: uid_t = getuid()) {
        domain = "gui/\(userID)"
    }

    public func bootstrap(plist: URL) throws {
        let result = try Shell.run("/bin/launchctl", ["bootstrap", domain, plist.path])
        guard result.status == 0 else { throw BackgroundError.launchctl(result.output) }
    }

    public func bootout(label: String) throws {
        let result = try Shell.run("/bin/launchctl", ["bootout", "\(domain)/\(label)"])
        guard result.status == 0 else { throw BackgroundError.launchctl(result.output) }
    }

    public func isLoaded(label: String) -> Bool {
        ((try? Shell.run("/bin/launchctl", ["print", "\(domain)/\(label)"]))?.status ?? 1) == 0
    }
}

public enum BackgroundError: Error, Equatable, LocalizedError, Sendable {
    case launchctl(String)
    case notStarted

    public var errorDescription: String? {
        switch self {
        case let .launchctl(output): "launchd refused the request: \(output.trimmingCharacters(in: .whitespacesAndNewlines))"
        case .notStarted: "it is not running in the background. Start it with: warren proxy start (or dns start)"
        }
    }
}

/// Installs, starts and stops Warren's background jobs under `~/Library/LaunchAgents`.
public struct BackgroundServices: Sendable {
    public let paths: WarrenPaths
    public let agentsDirectory: URL
    public let launch: any LaunchControlling

    public init(
        paths: WarrenPaths,
        agentsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true),
        launch: any LaunchControlling = LaunchCtl()
    ) {
        self.paths = paths
        self.agentsDirectory = agentsDirectory
        self.launch = launch
    }

    public func plistURL(_ kind: BackgroundKind) -> URL {
        agentsDirectory.appendingPathComponent("\(kind.label).plist")
    }

    public func logURL(_ kind: BackgroundKind) -> URL {
        paths.logsDirectory.appendingPathComponent("\(kind.rawValue).log")
    }

    public func isLoaded(_ kind: BackgroundKind) -> Bool {
        launch.isLoaded(label: kind.label)
    }

    /// Writes the plist and (re)starts the job. Safe to call when it is already running.
    public func start(_ agent: LaunchAgent) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: agentsDirectory, withIntermediateDirectories: true)
        try manager.createDirectory(at: paths.logsDirectory, withIntermediateDirectories: true)
        try agent.plist().write(to: plistURL(agent.kind), options: .atomic)
        if launch.isLoaded(label: agent.kind.label) {
            try launch.bootout(label: agent.kind.label)
        }
        try launch.bootstrap(plist: plistURL(agent.kind))
    }

    /// Stops the job and removes its plist, so it does not come back at the next login.
    public func stop(_ kind: BackgroundKind) throws {
        if launch.isLoaded(label: kind.label) {
            try launch.bootout(label: kind.label)
        }
        try? FileManager.default.removeItem(at: plistURL(kind))
    }
}

public extension WarrenPaths {
    var logsDirectory: URL {
        root.appendingPathComponent("logs", isDirectory: true)
    }

    var networkSettingsFile: URL {
        configDirectory.appendingPathComponent("network.json")
    }
}
