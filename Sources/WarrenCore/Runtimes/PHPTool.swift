// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Installs PHP and Composer from Warren's pinned builds into Warren's folder. Nothing outside it is read or
/// written: `PHPRC` and `PHP_INI_SCAN_DIR` point at Warren's own ini files, and Composer keeps its state under
/// `~/.warren` too. See spec 008.
public struct PHPTool: Sendable {
    public typealias Fetch = @Sendable (URL) async throws -> URL

    public let paths: WarrenPaths
    private let releases: [PHPRelease]
    private let composer: ComposerRelease
    private let architecture: CPUArchitecture
    private let fetch: Fetch

    public init(paths: WarrenPaths) {
        self.init(paths: paths, releases: PHPRelease.offered, composer: .current, architecture: .current) {
            try await ToolInstaller(paths: paths).download($0)
        }
    }

    init(
        paths: WarrenPaths,
        releases: [PHPRelease],
        composer: ComposerRelease,
        architecture: CPUArchitecture,
        fetch: @escaping Fetch
    ) {
        self.paths = paths
        self.releases = releases
        self.composer = composer
        self.architecture = architecture
        self.fetch = fetch
    }

    // MARK: Folders

    var versionsDirectory: URL {
        paths.dataDirectory.appendingPathComponent("php", isDirectory: true)
    }

    private var composerDirectory: URL {
        paths.dataDirectory.appendingPathComponent("composer", isDirectory: true)
    }

    /// The folder holding the `composer` command, to put on `PATH` while a PHP is.
    public var composerBin: URL? {
        let wrapper = composerDirectory.appendingPathComponent("bin/composer")
        return FileManager.default.isExecutableFile(atPath: wrapper.path)
            ? wrapper.deletingLastPathComponent() : nil
    }

    private var composerPhar: URL {
        composerDirectory.appendingPathComponent("\(composer.version)/composer.phar")
    }

    func configDirectory(forMinor minor: String) -> URL {
        paths.configDirectory.appendingPathComponent("php/\(minor)", isDirectory: true)
    }

    public var composerHome: URL {
        paths.configDirectory.appendingPathComponent("composer", isDirectory: true)
    }

    // MARK: Inventory

    public func installed() -> [InstalledRuntime] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: versionsDirectory.path)) ?? []
        return names.filter { !$0.hasPrefix(".") }.compactMap { name in
            let root = versionsDirectory.appendingPathComponent(name, isDirectory: true)
            guard FileManager.default.isExecutableFile(atPath: root.appendingPathComponent("bin/php").path),
                  SemanticVersion(name) != nil else { return nil }
            return InstalledRuntime(kind: .php, version: name, path: root, bytes: DirectorySize.bytes(of: root))
        }
        .sorted {
            (SemanticVersion($0.version) ?? SemanticVersion(0)) < (SemanticVersion($1.version) ?? SemanticVersion(0))
        }
    }

    /// The versions Warren can install, oldest first.
    public func available() -> [String] {
        releases.map(\.version)
            .sorted { (SemanticVersion($0) ?? SemanticVersion(0)) < (SemanticVersion($1) ?? SemanticVersion(0)) }
    }

    /// The build to install for `8.3`, `8.3.31` or `latest`.
    func release(for requested: String) -> PHPRelease? {
        let matching = requested == "latest" || requested.hasPrefix("lts")
            ? releases : releases.filter { $0.version == requested || $0.version.hasPrefix(requested + ".") }
        return matching
            .max {
                (SemanticVersion($0.version) ?? SemanticVersion(0)) <
                    (SemanticVersion($1.version) ?? SemanticVersion(0))
            }
    }

    // MARK: Install

    /// Installs one version and Composer. Does nothing if it is already there. Cancelling leaves nothing listed:
    /// the folder is built under a hidden name and renamed last.
    public func install(
        version requested: String,
        onProgress: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws {
        guard let release = release(for: requested) else { throw RuntimeError.noSuchVersion("PHP \(requested)") }
        if !installed().contains(where: { $0.version == release.version }) {
            try await installBuild(release, onProgress: onProgress)
        }
        try writeDefaultConfig(minor: release.minor)
        try await installComposer(onProgress: onProgress)
    }

    private func installBuild(_ release: PHPRelease, onProgress: @Sendable (String) -> Void) async throws {
        let asset = try release.asset(for: architecture)
        onProgress("Downloading PHP \(release.version)")
        let archive = try await fetch(asset.url)
        defer { try? FileManager.default.removeItem(at: archive) }
        try Task.checkCancellation()
        onProgress("Verifying PHP \(release.version)")
        let (expected, actual) = try ToolInstaller.compare(archive, against: asset.checksum)
        guard actual == expected else { throw ToolInstallError.checksumMismatch(expected: expected, actual: actual) }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: versionsDirectory, withIntermediateDirectories: true)
        let building = versionsDirectory.appendingPathComponent(".installing-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: building, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: building) }
        onProgress("Unpacking PHP \(release.version)")
        let result = try Shell.run("/usr/bin/tar", ["-xzf", archive.path, "-C", building.path])
        guard result.status == 0 else { throw ToolInstallError.extractionFailed(result.output) }
        for name in ["php", "php-fpm"] {
            let binary = building.appendingPathComponent("bin/\(name)")
            guard fileManager.fileExists(atPath: binary.path) else { throw ToolInstallError.binaryMissing(name) }
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        }
        try Task.checkCancellation()
        let destination = versionsDirectory.appendingPathComponent(release.version, isDirectory: true)
        try? fileManager.removeItem(at: destination)
        try fileManager.moveItem(at: building, to: destination)
    }

    private func installComposer(onProgress: @Sendable (String) -> Void) async throws {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: composerPhar.path) {
            onProgress("Downloading Composer \(composer.version)")
            let download = try await fetch(composer.asset.url)
            defer { try? fileManager.removeItem(at: download) }
            let (expected, actual) = try ToolInstaller.compare(download, against: composer.asset.checksum)
            guard actual == expected
            else { throw ToolInstallError.checksumMismatch(expected: expected, actual: actual) }
            try fileManager.createDirectory(
                at: composerPhar.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? fileManager.removeItem(at: composerPhar)
            try fileManager.moveItem(at: download, to: composerPhar)
        }
        // `php` is found on the PATH Warren builds for the site, so the wrapper always uses the site's PHP.
        let wrapper = composerDirectory.appendingPathComponent("bin/composer")
        try fileManager.createDirectory(at: wrapper.deletingLastPathComponent(), withIntermediateDirectories: true)
        let script = "#!/bin/sh\nexec php '\(composerPhar.path)' \"$@\"\n"
        try Data(script.utf8).write(to: wrapper, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapper.path)
    }

    /// A development-friendly `php.ini` for a minor, written once. A user's edits are never overwritten.
    func writeDefaultConfig(minor: String) throws {
        let directory = configDirectory(forMinor: minor)
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: directory.appendingPathComponent("conf.d"),
            withIntermediateDirectories: true
        )
        let ini = directory.appendingPathComponent("php.ini")
        guard !fileManager.fileExists(atPath: ini.path) else { return }
        let text = """
        ; Written once by Warren and never overwritten. Put extra settings in conf.d/ or edit this file.
        memory_limit = 512M
        display_errors = On
        error_reporting = E_ALL
        date.timezone = \(TimeZone.current.identifier)
        opcache.enable_cli = 0
        opcache.validate_timestamps = 1
        opcache.revalidate_freq = 0

        """
        try Data(text.utf8).write(to: ini, options: .atomic)
    }

    public func uninstall(_ runtime: InstalledRuntime) throws {
        try FileManager.default.removeItem(at: runtime.path)
        // Composer is only useful with a PHP.
        if installed().isEmpty {
            try? FileManager.default.removeItem(at: composerDirectory)
        }
    }

    // MARK: Environment

    /// The variables that point PHP and Composer at Warren's folders for the PHP in `runtime`.
    public func environment(for runtime: InstalledRuntime) -> [String: String] {
        let minor = runtime.version.split(separator: ".").prefix(2).joined(separator: ".")
        let config = configDirectory(forMinor: minor)
        return [
            "PHPRC": config.path,
            "PHP_INI_SCAN_DIR": config.appendingPathComponent("conf.d").path,
            "COMPOSER_HOME": composerHome.path,
        ]
    }
}
