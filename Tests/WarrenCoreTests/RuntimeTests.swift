// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import WarrenCore

struct RuntimeTests {
    private let root: URL
    private let paths: WarrenPaths

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("wr-\(UUID().uuidString.prefix(8))")
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

    private func site(_ directory: URL, runtimes: [String: String] = [:]) -> ResolvedSite {
        ResolvedSite(
            id: "demo", path: directory.path, name: "demo", domains: ["demo.test"], runtimes: runtimes,
            command: nil, port: nil, services: [:], problems: [], warnings: []
        )
    }

    private func requirements(_ files: [String: String],
                              runtimes: [String: String] = [:]) throws -> [RuntimeRequirement]
    {
        try RuntimeResolver.requirements(for: site(project(files), runtimes: runtimes))
    }

    // MARK: Which version a site wants

    @Test func warrenConfigWinsOverVersionFilesAndEngines() throws {
        let found = try requirements(
            [".nvmrc": "20\n", "package.json": #"{"engines":{"node":">=18"}}"#],
            runtimes: ["node": "22"]
        )
        #expect(found == [RuntimeRequirement(kind: .node, requested: "22", source: .warrenConfig)])
    }

    @Test func versionFilesWinOverEngines() throws {
        let found = try requirements([".nvmrc": "v20.11.1\n", "package.json": #"{"engines":{"node":">=18"}}"#])
        #expect(found == [RuntimeRequirement(kind: .node, requested: "20.11.1", source: .file(".nvmrc"))])
    }

    @Test func enginesAreUsedLast() throws {
        let found = try requirements(["package.json": #"{"engines":{"node":">=18 <23"}}"#])
        #expect(found == [RuntimeRequirement(kind: .node, requested: ">=18 <23", source: .engines)])
    }

    @Test func nothingIsAskedForWhenAProjectSaysNothing() throws {
        #expect(try requirements(["package.json": #"{"name":"x"}"#]).isEmpty)
    }

    @Test func toolVersionsNamesNodeAndBun() throws {
        let found = try requirements([".tool-versions": "# runtimes\nnodejs 22.1.0\nbun 1.4.3\npython 3.13\n"])
        #expect(found.map(\.label) == ["Node 22.1.0", "Bun 1.4.3"])
    }

    @Test func versionFileSpellingsAreNormalised() {
        #expect(RuntimeResolver.normalize("v22.1.0") == "22.1.0")
        #expect(RuntimeResolver.normalize("lts/*") == "lts")
        #expect(RuntimeResolver.normalize("lts/iron") == "lts-iron")
        #expect(RuntimeResolver.normalize("node") == "latest")
        #expect(RuntimeResolver.normalize("  \n") == nil)
    }

    @Test func anUnreadableEnginesRangeIsIgnored() throws {
        #expect(try requirements(["package.json": #"{"engines":{"node":"1.2.3-beta - 2"}}"#]).isEmpty)
    }

    // MARK: Ranges and matching

    @Test(arguments: [
        (">=18", "20.1.0", true), (">=18", "16.0.0", false),
        ("^20.1", "20.9.0", true), ("^20.1", "21.0.0", false), ("^20.1", "20.0.9", false),
        ("~20.1.2", "20.1.9", true), ("~20.1.2", "20.2.0", false),
        ("20.x", "20.5.5", true), ("20", "21.0.0", false),
        (">=18 <23", "22.4.0", true), (">=18 <23", "23.0.0", false),
        ("18 || 20", "20.3.0", true), ("18 || 20", "19.0.0", false),
        (">= 18", "18.0.0", true), (">18", "18.0.0", false), ("<=20", "20.9.9", true), ("*", "1.0.0", true),
    ])
    func rangesMatchLikeNpmDoes(range: String, version: String, expected: Bool) throws {
        let parsed = try #require(VersionRange(range))
        #expect(try parsed.contains(#require(SemanticVersion(version))) == expected)
    }

    @Test func installedVersionsAreMatchedByPrefix() {
        let wanted = RuntimeRequirement(kind: .node, requested: "22", source: .file(".nvmrc"))
        #expect(RuntimeResolver.match(wanted, among: ["20.1.0", "22.4.0", "22.23.3", "220.0.0"]) == "22.23.3")
        let exact = RuntimeRequirement(kind: .node, requested: "22.4.0", source: .warrenConfig)
        #expect(RuntimeResolver.match(exact, among: ["22.4.0", "22.23.3"]) == "22.4.0")
        #expect(RuntimeResolver.match(wanted, among: ["20.1.0"]) == nil)
    }

    @Test func latestAndLtsAcceptTheNewestInstalled() {
        let lts = RuntimeRequirement(kind: .node, requested: "lts", source: .file(".nvmrc"))
        #expect(RuntimeResolver.match(lts, among: ["20.1.0", "22.4.0"]) == "22.4.0")
        #expect(RuntimeResolver.match(lts, among: []) == nil)
    }

    @Test func enginesPickTheNewestInstalledThatFits() {
        let engines = RuntimeRequirement(kind: .node, requested: ">=18 <23", source: .engines)
        #expect(RuntimeResolver.match(engines, among: ["16.0.0", "20.1.0", "22.4.0", "24.0.0"]) == "22.4.0")
    }

    @Test func enginesInstallPrefersALongTermSupportLine() {
        let engines = RuntimeRequirement(kind: .node, requested: ">=18", source: .engines)
        let available = ["18.0.0", "20.5.0", "21.0.0", "22.1.0", "23.2.0"]
        #expect(RuntimeResolver.versionToInstall(for: engines, available: available) == "22.1.0")
        let tight = RuntimeRequirement(kind: .node, requested: "23", source: .engines)
        #expect(RuntimeResolver.versionToInstall(for: tight, available: available) == "23.2.0")
        let plain = RuntimeRequirement(kind: .node, requested: "22", source: .file(".nvmrc"))
        #expect(RuntimeResolver.versionToInstall(for: plain, available: available) == "22")
    }

    @Test func oneVersionPerMajorKeepsTheNewest() {
        let list = RuntimeManager.latestPerMajor(["20.1.0", "22.4.0", "20.9.0", "22.23.3", "21.0.0"])
        #expect(list == ["22.23.3", "21.0.0", "20.9.0"])
    }

    // MARK: The mise environment and commands

    /// A stand-in for mise that records how it was called and answers like the real one.
    private func fakeMise(listing: String = "{}") throws -> (MiseTool, log: URL) {
        let log = root.appendingPathComponent("calls.log")
        let tool = MiseTool(
            paths: paths,
            baseEnvironment: [
                "PATH": "/usr/bin:/bin",
                "HOME": root.path,
                "MISE_DATA_DIR": "/elsewhere",
                "MISE_FAKE": "1"
            ]
        )
        let binary = ToolInstaller(paths: paths).binaryURL(for: .mise)
        try FileManager.default.createDirectory(
            at: binary.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let script = """
        #!/bin/sh
        echo "$@ | $MISE_DATA_DIR | $MISE_NO_ENV | $MISE_FAKE | $PWD" >> '\(log.path)'
        case "$1" in
          ls) cat <<'JSON'
        \(listing)
        JSON
          ;;
          ls-remote) printf '22.1.0\\n22.2.0\\n23.0.0-rc.1\\n20.9.0\\nlatest\\n' ;;
          install) echo "downloading"; echo "mise WARN  bun installed but not activated"; echo "  mise use bun" ;;
          uninstall) ;;
        esac
        """
        try script.write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        return (tool, log)
    }

    @Test func miseRunsInsideWarrensFolderAndIgnoresTheUsersOwnSettings() throws {
        let (tool, log) = try fakeMise()
        let environment = tool.environment()
        #expect(environment["MISE_DATA_DIR"] == paths.dataDirectory.appendingPathComponent("mise").path)
        #expect(environment["MISE_CACHE_DIR"]?.hasPrefix(paths.cacheDirectory.path) == true)
        #expect(environment["MISE_CONFIG_DIR"]?.hasPrefix(paths.configDirectory.path) == true)
        #expect(environment["MISE_FAKE"] == nil)
        #expect(environment["MISE_NO_ENV"] == "1")
        #expect(environment["MISE_AUTO_INSTALL"] == "0")
        _ = try tool.availableVersions(.node)
        let call = try String(contentsOf: log, encoding: .utf8)
        #expect(call.contains("| \(paths.dataDirectory.appendingPathComponent("mise").path) | 1 |"))
        #expect(!call.contains("/elsewhere"))
    }

    @Test func availableVersionsAreStableReleasesOldestFirst() throws {
        let (tool, _) = try fakeMise()
        #expect(try tool.availableVersions(.node) == ["20.9.0", "22.1.0", "22.2.0"])
    }

    @Test func installedRuntimesAreReadFromMisesListing() throws {
        let node = root.appendingPathComponent("installs/node/22.1.0")
        try FileManager.default.createDirectory(at: node, withIntermediateDirectories: true)
        try Data(count: 5000).write(to: node.appendingPathComponent("blob"))
        let listing = """
        {"node":[{"version":"22.1.0","install_path":"\(node.path)","installed":true},
                 {"version":"18.0.0","install_path":"/nowhere","installed":false}],
         "deno":[{"version":"2.0.0","install_path":"/x","installed":true}]}
        """
        let (tool, _) = try fakeMise(listing: listing)
        let found = try tool.installed()
        #expect(found.map(\.id) == ["node@22.1.0"])
        #expect(found[0].bytes >= 5000)
    }

    @Test func nothingIsInstalledUntilMiseIsDownloaded() throws {
        #expect(try MiseTool(paths: paths).installed().isEmpty)
    }

    @Test func installAsksMiseForThatVersionAndHidesItsReminders() async throws {
        let (tool, log) = try fakeMise()
        let lines = LineBox()
        try await tool.install(.bun, version: "1.4.3") { lines.add($0) }
        #expect(try String(contentsOf: log, encoding: .utf8).contains("install bun@1.4.3 |"))
        #expect(lines.all == ["downloading"])
    }

    @Test func removingAVersionAsksMiseToUninstallIt() throws {
        let (tool, log) = try fakeMise()
        try tool.uninstall(InstalledRuntime(kind: .node, version: "22.1.0", path: root, bytes: 0))
        #expect(try String(contentsOf: log, encoding: .utf8).contains("uninstall node@22.1.0 |"))
    }

    @Test func aFailingMiseReportsItsLastLine() {
        #expect(MiseTool.lastLine(of: "mise ERROR no such version\nmise ERROR Version: 1\n") == "no such version")
    }

    // MARK: Plans and environment

    @Test func aPlanSaysWhatIsInstalledAndWhatIsMissing() throws {
        let installed = [
            InstalledRuntime(kind: .node, version: "22.4.0", path: root.appendingPathComponent("n22"), bytes: 1),
        ]
        let directory = try project([".nvmrc": "22", ".bun-version": "1.4.3"])
        let plan = RuntimeManager(paths: paths).plan(for: site(directory), installed: installed)
        #expect(plan.needs.map(\.isInstalled) == [true, false])
        #expect(plan.missing.map(\.requirement.label) == ["Bun 1.4.3"])
        #expect(RuntimeManager.sites(using: installed[0], in: [plan]) == ["demo"])
    }

    @Test func theEnvironmentPutsRuntimesFirstAndSetsTheCaches() {
        let path = root.appendingPathComponent("n22")
        let need = RuntimeNeed(
            requirement: RuntimeRequirement(kind: .node, requested: "22", source: .warrenConfig),
            installedVersion: "22.4.0", installPath: path
        )
        let environment = RuntimeManager(paths: paths)
            .environment(for: SiteRuntimePlan(siteID: "demo", needs: [need]), base: ["PATH": "/usr/bin", "KEEP": "1"])
        #expect(environment["PATH"] == "\(path.path)/bin:/usr/bin")
        #expect(environment["KEEP"] == "1")
        #expect(environment["npm_config_cache"] == paths.packagesCacheDirectory.appendingPathComponent("npm").path)
        #expect(environment["BUN_INSTALL_CACHE_DIR"]?.hasPrefix(paths.packagesCacheDirectory.path) == true)
    }

    @Test func clearingThePackagesCacheFreesItsSpace() throws {
        let cache = paths.packagesCacheDirectory.appendingPathComponent("npm")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data(count: 20000).write(to: cache.appendingPathComponent("pkg"))
        #expect(PackageCaches.bytes(paths) >= 20000)
        try PackageCaches.clear(paths)
        #expect(PackageCaches.bytes(paths) == 0)
        try PackageCaches.clear(paths)
    }

    @Test func theMisePinCoversBothArchitecturesAndLooksInsideTheArchive() throws {
        let release = ToolRelease.mise
        #expect(release.pathInArchive == "mise/bin/mise")
        for architecture in [CPUArchitecture.arm64, .intel] {
            let asset = try release.asset(for: architecture)
            guard case let .sha256(hash) = asset.checksum else { Issue.record("expected SHA-256"); return }
            #expect(hash.count == 64)
            #expect(asset.url.absoluteString.contains(release.version))
        }
    }
}

private final class LineBox: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    var all: [String] {
        lock.withLock { lines }
    }

    func add(_ line: String) {
        lock.withLock { lines.append(line) }
    }
}
