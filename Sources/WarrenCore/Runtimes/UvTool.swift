// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Drives the managed uv binary to install and remove Python. Everything it touches lives inside Warren's folder,
/// and no project or user configuration is read. See spec 009.
public struct UvTool: Sendable {
    public let paths: WarrenPaths
    private let installer: ToolInstaller
    private let release: ToolRelease
    private let baseEnvironment: [String: String]

    public init(
        paths: WarrenPaths,
        release: ToolRelease = .uvCLI,
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

    /// The folder holding `uv`, to put on `PATH` while a Python is.
    public var binDirectory: URL? {
        isInstalled ? installer.binaryURL(for: release).deletingLastPathComponent() : nil
    }

    var pythonDirectory: URL {
        paths.dataDirectory.appendingPathComponent("python", isDirectory: true)
    }

    /// An empty folder to run in, so no project's files are picked up.
    private var neutralDirectory: URL {
        paths.configDirectory.appendingPathComponent("uv", isDirectory: true)
    }

    public func ensureInstalled() async throws {
        if !isInstalled {
            try await installer.install(release)
        }
    }

    /// The settings that keep uv inside Warren's folder, shared by Warren's own calls and a site's environment.
    static func isolation(_ paths: WarrenPaths) -> [String: String] {
        [
            "UV_PYTHON_INSTALL_DIR": paths.dataDirectory.appendingPathComponent("python").path,
            "UV_CACHE_DIR": paths.packagesCacheDirectory.appendingPathComponent("uv").path,
            "UV_NO_CONFIG": "1",
            "UV_PYTHON_PREFERENCE": "only-managed",
            "UV_PYTHON_INSTALL_BIN": "0",
        ]
    }

    /// The environment for every uv call. Inherited `UV_*` settings are dropped.
    func environment() -> [String: String] {
        var environment = baseEnvironment.filter { !$0.key.hasPrefix("UV_") }
        environment.merge(Self.isolation(paths)) { _, new in new }
        environment["UV_NO_PROGRESS"] = "1"
        environment["NO_COLOR"] = "1"
        return environment
    }

    func run(_ arguments: [String]) throws -> String {
        try FileManager.default.createDirectory(at: neutralDirectory, withIntermediateDirectories: true)
        let result = try Shell.run(executable, arguments, environment: environment(), directory: neutralDirectory)
        guard result.status == 0 else { throw RuntimeError.toolFailed(Self.lastLine(of: result.output)) }
        return result.output
    }

    // MARK: Commands

    private struct Entry: Decodable {
        let version: String
        let path: String?
        let implementation: String
        let variant: String
    }

    /// Stable CPython releases uv can install, newest patch of each minor, oldest first.
    public func availableVersions() async throws -> [String] {
        try await ensureInstalled()
        return try Self.parseAvailable(run(["python", "list", "--only-downloads", "--output-format", "json"]))
    }

    static func parseAvailable(_ json: String) throws -> [String] {
        let entries = try JSONDecoder().decode([Entry].self, from: Data(json.utf8))
        return entries
            .filter { $0.implementation == "cpython" && $0.variant == "default" }
            .compactMap { entry in SemanticVersion(entry.version).map { ($0, entry.version) } }
            .filter { $0.1.split(separator: ".").count == 3 }
            .sorted { $0.0 < $1.0 }
            .map(\.1)
    }

    public func installed() throws -> [InstalledRuntime] {
        guard isInstalled else { return [] }
        return try Self.parseInstalled(run(["python", "list", "--only-installed", "--output-format", "json"]))
    }

    static func parseInstalled(_ json: String) throws -> [InstalledRuntime] {
        let entries = try JSONDecoder().decode([Entry].self, from: Data(json.utf8))
        var seen = Set<String>()
        var found: [InstalledRuntime] = []
        for entry in entries where entry.implementation == "cpython" && entry.variant == "default" {
            guard let path = entry.path, seen.insert(entry.version).inserted else { continue }
            // .../cpython-3.13.16-.../bin/python3.13 -> the install folder, through uv's minor-version link.
            let root = URL(fileURLWithPath: path).deletingLastPathComponent().deletingLastPathComponent()
                .resolvingSymlinksInPath()
            found.append(InstalledRuntime(
                kind: .python, version: entry.version, path: root, bytes: DirectorySize.bytes(of: root)
            ))
        }
        return found
            .sorted {
                (SemanticVersion($0.version) ?? SemanticVersion(0)) <
                    (SemanticVersion($1.version) ?? SemanticVersion(0))
            }
    }

    /// Installs one version (`3.13`, `3.13.16` or `latest`), reporting uv's progress lines. Cancelling the task
    /// stops the install.
    public func install(version: String, onProgress: @escaping @Sendable (String) -> Void = { _ in }) async throws {
        try await ensureInstalled()
        try FileManager.default.createDirectory(at: neutralDirectory, withIntermediateDirectories: true)
        var request = version
        if version == "latest" {
            guard let newest = try await availableVersions().last else { throw RuntimeError.noSuchVersion("Python") }
            request = newest
        }
        let result = try await Shell.stream(
            executable, ["python", "install", request],
            environment: environment(), directory: neutralDirectory,
            onLine: { line in
                if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                    onProgress(line.trimmingCharacters(in: .whitespaces))
                }
            }
        )
        try Task.checkCancellation()
        guard result.status == 0 else { throw RuntimeError.toolFailed(Self.lastLine(of: result.output)) }
    }

    public func uninstall(_ runtime: InstalledRuntime) throws {
        _ = try run(["python", "uninstall", runtime.version])
    }

    /// uv's last meaningful line, which is where it puts the reason (`error: ...`).
    static func lastLine(of output: String) -> String {
        let lines = output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        let text = lines.last(where: { !$0.isEmpty && !$0.hasPrefix("hint:") }) ?? "uv failed"
        return text.hasPrefix("error: ") ? String(text.dropFirst(7)) : text
    }

    // MARK: Environment

    /// What a Python site needs on top of the shared caches: uv first on `PATH` (by the caller), the same folders,
    /// and no interpreter downloads, so only Warren's install action fetches one.
    public func siteEnvironment() -> [String: String] {
        var environment = Self.isolation(paths)
        environment["UV_PYTHON_DOWNLOADS"] = "never"
        return environment
    }
}
