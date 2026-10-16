// SPDX-License-Identifier: Apache-2.0

import CryptoKit
import Foundation
import Testing
@testable import WarrenCore

struct PHPTests {
    private let root: URL
    private let paths: WarrenPaths

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("wp-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        paths = WarrenPaths(root: root.appendingPathComponent("home"))
    }

    private func project(_ files: [String: String]) throws -> URL {
        let directory = root.appendingPathComponent("project-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, text) in files {
            try text.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        return directory
    }

    private func requirements(_ files: [String: String], runtimes: [String: String] = [:]) throws
        -> [RuntimeRequirement]
    {
        let directory = try project(files)
        let site = ResolvedSite(
            id: "demo", path: directory.path, name: "demo", domains: ["demo.test"], runtimes: runtimes,
            command: nil, port: nil, services: [:], problems: [], warnings: []
        )
        return RuntimeResolver.requirements(for: site)
    }

    // MARK: Which version a site wants

    @Test func warrenConfigWinsOverPHPVersionFileAndComposer() throws {
        let found = try requirements(
            [".php-version": "8.2\n", "composer.json": #"{"require":{"php":"^8.1"}}"#], runtimes: ["php": "8.4"]
        )
        #expect(found == [RuntimeRequirement(kind: .php, requested: "8.4", source: .warrenConfig)])
    }

    @Test func versionFilesWinOverComposer() throws {
        let tools = try requirements([
            ".tool-versions": "php 8.3.12\n",
            "composer.json": #"{"require":{"php":"^8.1"}}"#
        ])
        #expect(tools == [RuntimeRequirement(kind: .php, requested: "8.3.12", source: .file(".tool-versions"))])
        let file = try requirements([".php-version": "8.2\n"])
        #expect(file == [RuntimeRequirement(kind: .php, requested: "8.2", source: .file(".php-version"))])
    }

    @Test func composerIsUsedLastAndThePlatformTargetWins() throws {
        let required = try requirements(["composer.json": #"{"require":{"php":"^8.2","laravel/framework":"^11"}}"#])
        #expect(required == [RuntimeRequirement(kind: .php, requested: "^8.2", source: .composer)])
        let platform = try requirements([
            "composer.json": #"{"require":{"php":"^8.2"},"config":{"platform":{"php":"8.3.0"}}}"#,
        ])
        #expect(platform.first?.requested == "8.3.0")
        #expect(try requirements(["composer.json": #"{"name":"x/y"}"#]).isEmpty)
    }

    @Test func composerConstraintsAreRead() {
        func allows(_ constraint: String, _ version: String) -> Bool? {
            VersionRange(composer: constraint).map { range in SemanticVersion(version).map(range.contains) ?? false }
        }
        #expect(allows("^8.2", "8.4.1") == true)
        #expect(allows("^8.2", "8.1.9") == false)
        #expect(allows(">=8.1,<8.4", "8.3.5") == true)
        #expect(allows(">=8.1,<8.4", "8.4.0") == false)
        #expect(allows("8.2.*", "8.2.9") == true)
        #expect(allows("8.2.*", "8.3.0") == false)
        #expect(allows("~8.2", "8.9.0") == true)
        #expect(allows("~8.2.1", "8.3.0") == false)
        #expect(allows("8.1 | 8.3", "8.3.4") == true)
        #expect(allows("8.1 || 8.3", "8.2.4") == false)
        #expect(allows("not a version", "8.3.0") == nil)
    }

    @Test func aComposerRangeInstallsTheNewestOfferedMinorThatFits() {
        let requirement = RuntimeRequirement(kind: .php, requested: "^8.2", source: .composer)
        let offered = ["8.2.30", "8.3.31", "8.4.23", "8.5.8"]
        #expect(RuntimeResolver.versionToInstall(for: requirement, available: offered) == "8.5.8")
        let tight = RuntimeRequirement(kind: .php, requested: ">=8.1 <8.4", source: .composer)
        #expect(RuntimeResolver.versionToInstall(for: tight, available: offered) == "8.3.31")
        #expect(RuntimeResolver.match(tight, among: ["8.2.30", "8.4.23"]) == "8.2.30")
    }

    // MARK: The pinned table

    @Test func everyOfferedBuildIsPinnedForBothArchitectures() throws {
        for release in PHPRelease.offered {
            for architecture in [CPUArchitecture.arm64, .intel] {
                let asset = try release.asset(for: architecture)
                guard case let .sha256(hash) = asset.checksum else { Issue.record("expected SHA-256"); return }
                #expect(hash.count == 64)
                #expect(asset.url.absoluteString.contains("php-\(release.version)"))
            }
        }
        #expect(PHPRelease.offered.map(\.minor) == PHPRelease.offered.map(\.minor).sorted())
    }

    // MARK: Installing

    private func fakeBuild(version: String = "8.3.99") throws -> (PHPRelease, Data) {
        let staging = root.appendingPathComponent("staging-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(
            at: staging.appendingPathComponent("bin"),
            withIntermediateDirectories: true
        )
        for name in ["php", "php-fpm"] {
            try "#!/bin/sh\necho \(name)\n".write(
                to: staging.appendingPathComponent("bin/\(name)"), atomically: true, encoding: .utf8
            )
        }
        let archive = root.appendingPathComponent("\(UUID().uuidString.prefix(6)).tar.gz")
        _ = try Shell.run("/usr/bin/tar", ["-czf", archive.path, "-C", staging.path, "bin"])
        let data = try Data(contentsOf: archive)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let asset = ToolAsset(url: URL(string: "https://example.test/php-\(version).tar.gz")!, checksum: .sha256(hash))
        return (PHPRelease(version: version, assets: [.arm64: asset, .intel: asset]), data)
    }

    private func tool(_ release: PHPRelease, archive: Data, composer: Data = Data("phar".utf8),
                      counter: Counter = Counter()) -> PHPTool
    {
        let composerHash = SHA256.hash(data: composer).map { String(format: "%02x", $0) }.joined()
        let composerRelease = ComposerRelease(
            version: "9.9.9",
            asset: ToolAsset(url: URL(string: "https://example.test/composer.phar")!, checksum: .sha256(composerHash))
        )
        let directory = root
        return PHPTool(paths: paths, releases: [release], composer: composerRelease, architecture: .arm64) { url in
            counter.add(url.lastPathComponent)
            let file = directory.appendingPathComponent("dl-\(UUID().uuidString.prefix(6))")
            try (url.lastPathComponent == "composer.phar" ? composer : archive).write(to: file)
            return file
        }
    }

    @Test func installingPutsPHPFPMComposerAndTheIniInWarrensFolder() async throws {
        let (release, archive) = try fakeBuild()
        let php = tool(release, archive: archive)
        try await php.install(version: "8.3")

        let installed = php.installed()
        #expect(installed.map(\.version) == ["8.3.99"])
        #expect(FileManager.default
            .isExecutableFile(atPath: installed[0].path.appendingPathComponent("bin/php-fpm").path))
        #expect(php.composerBin != nil)
        let wrapper = try String(
            contentsOf: #require(php.composerBin).appendingPathComponent("composer"),
            encoding: .utf8
        )
        #expect(wrapper.contains("exec php") && wrapper.contains("9.9.9/composer.phar"))
        #expect(FileManager.default
            .fileExists(atPath: php.configDirectory(forMinor: "8.3").appendingPathComponent("php.ini").path))
        #expect(installed[0].path.path.hasPrefix(paths.dataDirectory.path))
    }

    @Test func installingAgainDownloadsNothing() async throws {
        let (release, archive) = try fakeBuild()
        let downloads = Counter()
        let php = tool(release, archive: archive, counter: downloads)
        try await php.install(version: "latest")
        try await php.install(version: "8.3.99")
        #expect(downloads.all == ["php-8.3.99.tar.gz", "composer.phar"])
    }

    @Test func aWrongHashFailsAndLeavesNothingBehind() async throws {
        let (release, archive) = try fakeBuild()
        var tampered = archive
        tampered.append(0)
        let php = tool(release, archive: tampered)
        await #expect(throws: ToolInstallError.self) { try await php.install(version: "8.3") }
        #expect(php.installed().isEmpty)
        let hidden = (try? FileManager.default.contentsOfDirectory(atPath: php.versionsDirectory.path)) ?? []
        #expect(hidden.isEmpty)
    }

    @Test func aCancelledInstallListsNothing() async throws {
        let (release, archive) = try fakeBuild()
        let php = PHPTool(
            paths: paths, releases: [release], composer: .current, architecture: .arm64
        ) { [root] _ in
            let file = root.appendingPathComponent("slow-\(UUID().uuidString.prefix(6))")
            try archive.write(to: file)
            try await Task.sleep(for: .seconds(30))
            return file
        }
        let task = Task { try await php.install(version: "8.3") }
        try await Task.sleep(for: .milliseconds(200))
        task.cancel()
        await #expect(throws: (any Error).self) { try await task.value }
        #expect(php.installed().isEmpty)
    }

    @Test func anUnknownVersionIsRefused() async throws {
        let (release, archive) = try fakeBuild()
        let php = tool(release, archive: archive)
        await #expect(throws: RuntimeError.self) { try await php.install(version: "7.4") }
    }

    @Test func aUserEditedIniSurvivesAnotherInstall() async throws {
        let (release, archive) = try fakeBuild()
        let php = tool(release, archive: archive)
        try await php.install(version: "8.3")
        let ini = php.configDirectory(forMinor: "8.3").appendingPathComponent("php.ini")
        try "memory_limit = 1G\n".write(to: ini, atomically: true, encoding: .utf8)
        try await php.install(version: "8.3")
        try php.writeDefaultConfig(minor: "8.3")
        #expect(try String(contentsOf: ini, encoding: .utf8) == "memory_limit = 1G\n")
    }

    @Test func removingTheLastPHPRemovesComposerToo() async throws {
        let (release, archive) = try fakeBuild()
        let php = tool(release, archive: archive)
        try await php.install(version: "8.3")
        try php.uninstall(#require(php.installed().first))
        #expect(php.installed().isEmpty)
        #expect(php.composerBin == nil)
    }

    // MARK: Environment

    @Test func aPHPSiteGetsItsOwnIniComposerAndPathFirst() async throws {
        let (release, archive) = try fakeBuild()
        let php = tool(release, archive: archive)
        try await php.install(version: "8.3")
        let runtime = try #require(php.installed().first)
        let need = RuntimeNeed(
            requirement: RuntimeRequirement(kind: .php, requested: "8.3", source: .file(".php-version")),
            installedVersion: runtime.version, installPath: runtime.path
        )
        let manager = RuntimeManager(paths: paths, php: php)
        let environment = manager.environment(
            for: SiteRuntimePlan(siteID: "demo", needs: [need]), base: ["PATH": "/usr/bin", "HOME": "/nowhere"]
        )
        let config = php.configDirectory(forMinor: "8.3")
        #expect(environment["PHPRC"] == config.path)
        #expect(environment["PHP_INI_SCAN_DIR"] == config.appendingPathComponent("conf.d").path)
        #expect(environment["COMPOSER_HOME"]?.hasPrefix(paths.configDirectory.path) == true)
        #expect(environment["COMPOSER_CACHE_DIR"]?.hasPrefix(paths.packagesCacheDirectory.path) == true)
        let path = try #require(environment["PATH"]).split(separator: ":").map(String.init)
        #expect(path.first == runtime.path.appendingPathComponent("bin").path)
        #expect(try path.contains(#require(php.composerBin).path))
        #expect(path.last == "/usr/bin")
        #expect(environment["HOME"] == "/nowhere")
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var names: [String] = []
    var all: [String] {
        lock.withLock { names }
    }

    func add(_ name: String) {
        lock.withLock { names.append(name) }
    }
}
