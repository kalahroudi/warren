// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum RuntimeError: Error, Equatable, LocalizedError, Sendable {
    case toolFailed(String)
    case noSuchVersion(String)

    public var errorDescription: String? {
        switch self {
        case let .toolFailed(message): message
        case let .noSuchVersion(name): "no version of \(name) is available to install"
        }
    }
}

/// One installed runtime version.
public struct InstalledRuntime: Equatable, Hashable, Identifiable, Sendable {
    public let kind: RuntimeKind
    public let version: String
    public let path: URL
    public let bytes: Int64

    public var id: String {
        "\(kind.rawValue)@\(version)"
    }
}

/// A tool mise installed that is not a runtime, such as pnpm or Yarn.
public struct InstalledTool: Equatable, Sendable {
    public let name: String
    public let version: String
    public let path: URL

    /// The folder to put on `PATH`: pnpm sits at the top of its folder, Yarn in `bin`.
    public var binDirectory: URL {
        let bin = path.appendingPathComponent("bin")
        return FileManager.default.fileExists(atPath: bin.path) ? bin : path
    }
}

/// Drives the managed mise binary. Everything it touches lives inside Warren's folder, and a project's own
/// mise files can never run commands (`MISE_NO_ENV`). See spec 007.
public struct MiseTool: Sendable {
    public let paths: WarrenPaths
    private let installer: ToolInstaller
    private let release: ToolRelease
    private let baseEnvironment: [String: String]

    public init(
        paths: WarrenPaths,
        release: ToolRelease = .mise,
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.paths = paths
        installer = ToolInstaller(paths: paths)
        self.release = release
        self.baseEnvironment = baseEnvironment
    }

    public var isInstalled: Bool {
        installer.isInstalled(release)
    }

    private var executable: String {
        installer.binaryURL(for: release).path
    }

    /// Downloads and verifies mise if it is not there yet.
    public func ensureInstalled() async throws {
        if !isInstalled {
            try await installer.install(release)
        }
    }

    /// The environment for every mise call. Inherited `MISE_*` settings are dropped so a user's own mise setup
    /// cannot change what Warren does, and its folders are never read or written.
    func environment() -> [String: String] {
        var environment = baseEnvironment.filter { !$0.key.hasPrefix("MISE_") }
        environment["MISE_DATA_DIR"] = paths.dataDirectory.appendingPathComponent("mise").path
        environment["MISE_CACHE_DIR"] = paths.cacheDirectory.appendingPathComponent("mise").path
        environment["MISE_STATE_DIR"] = paths.runDirectory.appendingPathComponent("mise").path
        environment["MISE_CONFIG_DIR"] = neutralDirectory.path
        environment["MISE_GLOBAL_CONFIG_FILE"] = neutralDirectory.appendingPathComponent("config.toml").path
        // A project's mise.toml could otherwise run commands through [env] templates and scripts.
        environment["MISE_NO_ENV"] = "1"
        environment["MISE_YES"] = "1"
        environment["MISE_AUTO_INSTALL"] = "0"
        environment["NO_COLOR"] = "1"
        return environment
    }

    /// An empty folder to run in, so no project's config is picked up.
    private var neutralDirectory: URL {
        paths.configDirectory.appendingPathComponent("mise", isDirectory: true)
    }

    func run(_ arguments: [String], in directory: URL? = nil) throws -> String {
        try FileManager.default.createDirectory(at: neutralDirectory, withIntermediateDirectories: true)
        let result = try Shell.run(
            executable,
            arguments,
            environment: environment(),
            directory: directory ?? neutralDirectory
        )
        guard result.status == 0 else { throw RuntimeError.toolFailed(Self.lastLine(of: result.output)) }
        return result.output
    }

    // MARK: Commands

    /// Stable releases of a runtime, oldest first.
    public func availableVersions(_ kind: RuntimeKind) throws -> [String] {
        try run(["ls-remote", kind.rawValue])
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .compactMap { text in SemanticVersion(text).map { ($0, text) } }
            .filter { $0.1.split(separator: ".").count == 3 }
            .sorted { $0.0 < $1.0 }
            .map(\.1)
    }

    public func installed() throws -> [InstalledRuntime] {
        guard isInstalled else { return [] }
        return try Self.parseInstalled(run(["ls", "--json"]))
    }

    static func parseInstalled(_ json: String) throws -> [InstalledRuntime] {
        struct Entry: Decodable {
            let version: String
            let installPath: String?
            let installed: Bool?

            enum CodingKeys: String, CodingKey {
                case version
                case installPath = "install_path"
                case installed
            }
        }
        guard let data = json.data(using: .utf8) else { return [] }
        let listing = try JSONDecoder().decode([String: [Entry]].self, from: data)
        var found: [InstalledRuntime] = []
        for (name, entries) in listing {
            guard let kind = RuntimeKind(rawValue: name) else { continue }
            for entry in entries where entry.installed != false {
                guard let path = entry.installPath else { continue }
                let url = URL(fileURLWithPath: path, isDirectory: true)
                found.append(InstalledRuntime(
                    kind: kind, version: entry.version, path: url, bytes: DirectorySize.bytes(of: url)
                ))
            }
        }
        return found.sorted { ($0.kind.rawValue, SemanticVersion($0.version) ?? SemanticVersion(0))
            < ($1.kind.rawValue, SemanticVersion($1.version) ?? SemanticVersion(0))
        }
    }

    /// Installs one version, reporting mise's progress lines. Cancelling the task stops the install.
    public func install(
        _ kind: RuntimeKind,
        version: String,
        onProgress: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws {
        try await ensureInstalled()
        try FileManager.default.createDirectory(at: neutralDirectory, withIntermediateDirectories: true)
        let result = try await Shell.stream(
            executable, ["install", "\(kind.rawValue)@\(version)"],
            environment: environment(), directory: neutralDirectory,
            onLine: { line in
                if !Self.isNoise(line) {
                    onProgress(line)
                }
            }
        )
        try Task.checkCancellation()
        guard result.status == 0 else { throw RuntimeError.toolFailed(Self.lastLine(of: result.output)) }
    }

    /// Every installed tool that is not a runtime.
    public func installedTools() throws -> [InstalledTool] {
        guard isInstalled else { return [] }
        return try Self.parseTools(run(["ls", "--json"]))
    }

    static func parseTools(_ json: String) throws -> [InstalledTool] {
        struct Entry: Decodable {
            let version: String
            let installPath: String?
            let installed: Bool?

            enum CodingKeys: String, CodingKey {
                case version
                case installPath = "install_path"
                case installed
            }
        }
        let listing = try JSONDecoder().decode([String: [Entry]].self, from: Data(json.utf8))
        return listing.flatMap { name, entries in
            entries.compactMap { entry -> InstalledTool? in
                guard RuntimeKind(rawValue: name) == nil, entry.installed != false, let path = entry.installPath
                else { return nil }
                return InstalledTool(
                    name: name,
                    version: entry.version,
                    path: URL(fileURLWithPath: path, isDirectory: true)
                )
            }
        }.sorted { ($0.name, $0.version) < ($1.name, $1.version) }
    }

    /// Installs a tool such as `pnpm` at a version (`9.1.0` or `latest`).
    public func installTool(
        _ name: String, version: String, onProgress: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws {
        try await ensureInstalled()
        try FileManager.default.createDirectory(at: neutralDirectory, withIntermediateDirectories: true)
        let result = try await Shell.stream(
            executable, ["install", "\(name)@\(version)"],
            environment: environment(), directory: neutralDirectory,
            onLine: { line in
                if !Self.isNoise(line) {
                    onProgress(line)
                }
            }
        )
        try Task.checkCancellation()
        guard result.status == 0 else { throw RuntimeError.toolFailed(Self.lastLine(of: result.output)) }
    }

    public func uninstall(_ runtime: InstalledRuntime) throws {
        _ = try run(["uninstall", "\(runtime.kind.rawValue)@\(runtime.version)"])
    }

    /// mise's reminders about activating a tool in a config file, which Warren never does.
    static func isNoise(_ line: String) -> Bool {
        line.contains("not activated") || line.contains("To install and activate") || line
            .trimmingCharacters(in: .whitespaces) == "mise use bun"
            || line.trimmingCharacters(in: .whitespaces).hasPrefix("mise use ")
    }

    /// mise's last meaningful line, which is where it puts the reason.
    static func lastLine(of output: String) -> String {
        let lines = output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        let text = lines
            .last(where: { !$0.isEmpty && !$0.hasPrefix("Version:") && !$0.hasPrefix("mise ERROR Version") })
            ?? "mise failed"
        return text.replacingOccurrences(of: "mise ERROR ", with: "")
    }
}
