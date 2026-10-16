// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import WarrenCore

struct PythonTests {
    private let root: URL
    private let paths: WarrenPaths

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("wy-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        paths = WarrenPaths(root: root.appendingPathComponent("home"))
    }

    private func requirements(_ files: [String: String], runtimes: [String: String] = [:]) throws
        -> [RuntimeRequirement]
    {
        let directory = root.appendingPathComponent("project-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, text) in files {
            try text.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        let site = ResolvedSite(
            id: "demo", path: directory.path, name: "demo", domains: ["demo.test"], runtimes: runtimes,
            command: nil, port: nil, services: [:], problems: [], warnings: []
        )
        return RuntimeResolver.requirements(for: site)
    }

    private func pyproject(_ requires: String) -> String {
        "[project]\nname = \"x\"\nversion = \"0\"\nrequires-python = \"\(requires)\"\n"
    }

    // MARK: Which version a site wants

    @Test func warrenConfigWinsOverVersionFilesAndPyproject() throws {
        let found = try requirements(
            [".python-version": "3.11\n", "pyproject.toml": pyproject(">=3.9")], runtimes: ["python": "3.13"]
        )
        #expect(found == [RuntimeRequirement(kind: .python, requested: "3.13", source: .warrenConfig)])
    }

    @Test func versionFilesWinOverPyproject() throws {
        let file = try requirements([".python-version": "3.12\n", "pyproject.toml": pyproject(">=3.9")])
        #expect(file == [RuntimeRequirement(kind: .python, requested: "3.12", source: .file(".python-version"))])
        let tools = try requirements([".tool-versions": "python 3.12.4\nnodejs 22\n"])
        #expect(tools.contains(RuntimeRequirement(kind: .python, requested: "3.12.4", source: .file(".tool-versions"))))
    }

    @Test func pyprojectIsUsedLast() throws {
        let found = try requirements(["pyproject.toml": pyproject(">=3.10,<3.13")])
        #expect(found == [RuntimeRequirement(kind: .python, requested: ">=3.10,<3.13", source: .pyproject)])
        #expect(try requirements(["pyproject.toml": "[project]\nname = \"x\"\n"]).isEmpty)
        #expect(try requirements(["pyproject.toml": pyproject("!=3.9.*")]).isEmpty)
    }

    @Test func pep440SpecifiersAreRead() {
        func allows(_ specifier: String, _ version: String) -> Bool? {
            VersionRange(pep440: specifier).map { range in SemanticVersion(version).map(range.contains) ?? false }
        }
        #expect(allows(">=3.10", "3.13.1") == true)
        #expect(allows(">=3.10", "3.9.9") == false)
        #expect(allows(">=3.10, <3.13", "3.12.9") == true)
        #expect(allows(">=3.10,<3.13", "3.13.0") == false)
        #expect(allows("==3.12.*", "3.12.4") == true)
        #expect(allows("==3.12.*", "3.13.0") == false)
        #expect(allows("~=3.11", "3.14.0") == true)
        #expect(allows("~=3.11", "3.10.0") == false)
        #expect(allows("~=3.11.2", "3.12.0") == false)
        #expect(allows(">= 3.9", "3.9.0") == true)
        #expect(allows("!=3.9.1", "3.9.0") == nil)
        #expect(allows("===3.9", "3.9.0") == nil)
    }

    @Test func aRangePicksTheNewestFittingVersion() {
        let requirement = RuntimeRequirement(kind: .python, requested: ">=3.10,<3.13", source: .pyproject)
        let offered = ["3.10.19", "3.11.14", "3.12.12", "3.13.9"]
        #expect(RuntimeResolver.versionToInstall(for: requirement, available: offered) == "3.12.12")
        #expect(RuntimeResolver.match(requirement, among: ["3.9.1", "3.11.2", "3.13.1"]) == "3.11.2")
        let plain = RuntimeRequirement(kind: .python, requested: "3.12", source: .file(".python-version"))
        #expect(RuntimeResolver.match(plain, among: ["3.12.1", "3.12.4", "3.13.0"]) == "3.12.4")
    }

    // MARK: The uv pin and commands

    @Test func theUvPinCoversBothArchitecturesAndLooksInsideEachArchive() throws {
        for (architecture, folder) in [(CPUArchitecture.arm64, "aarch64"), (.intel, "x86_64")] {
            let asset = try ToolRelease.uvCLI.asset(for: architecture)
            guard case let .sha256(hash) = asset.checksum else { Issue.record("expected SHA-256"); return }
            #expect(hash.count == 64)
            #expect(asset.pathInArchive == "uv-\(folder)-apple-darwin/uv")
            #expect(asset.url.absoluteString.contains(ToolRelease.uvCLI.version))
        }
    }

    private func fakeUv(installedJSON: String = "[]") throws -> (UvTool, log: URL) {
        let log = root.appendingPathComponent("uv.log")
        let tool = UvTool(
            paths: paths,
            baseEnvironment: [
                "PATH": "/usr/bin:/bin",
                "HOME": root.path,
                "UV_PYTHON_INSTALL_DIR": "/elsewhere",
                "UV_FAKE": "1"
            ]
        )
        let binary = ToolInstaller(paths: paths).binaryURL(for: .uvCLI)
        try FileManager.default.createDirectory(
            at: binary.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let script = """
        #!/bin/sh
        echo "$@ | $UV_PYTHON_INSTALL_DIR | $UV_NO_CONFIG | $UV_FAKE | $PWD" >> '\(log.path)'
        case "$2" in
          list)
            case "$3" in
              --only-downloads) cat <<'JSON'
        [{"version":"3.12.12","path":null,"implementation":"cpython","variant":"default"},
         {"version":"3.13.9","path":null,"implementation":"cpython","variant":"default"},
         {"version":"3.13.9","path":null,"implementation":"cpython","variant":"freethreaded"},
         {"version":"3.16.0a1","path":null,"implementation":"cpython","variant":"default"},
         {"version":"3.11.14","path":null,"implementation":"pypy","variant":"default"}]
        JSON
              ;;
              *) cat <<'JSON'
        \(installedJSON)
        JSON
              ;;
            esac ;;
          install) echo "Downloading cpython"; echo ""; echo "Installed Python $3" ;;
          uninstall) ;;
        esac
        """
        try script.write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        return (tool, log)
    }

    @Test func uvRunsInsideWarrensFolderAndIgnoresTheUsersOwnSettings() async throws {
        let (tool, log) = try fakeUv()
        let environment = tool.environment()
        #expect(environment["UV_PYTHON_INSTALL_DIR"] == paths.dataDirectory.appendingPathComponent("python").path)
        #expect(environment["UV_CACHE_DIR"]?.hasPrefix(paths.packagesCacheDirectory.path) == true)
        #expect(environment["UV_NO_CONFIG"] == "1")
        #expect(environment["UV_PYTHON_PREFERENCE"] == "only-managed")
        #expect(environment["UV_FAKE"] == nil)
        _ = try await tool.availableVersions()
        let call = try String(contentsOf: log, encoding: .utf8)
        #expect(call.contains("| \(paths.dataDirectory.appendingPathComponent("python").path) | 1 |"))
        #expect(!call.contains("/elsewhere"))
        #expect(call.contains(paths.configDirectory.path))
    }

    @Test func availableVersionsAreStableCPythonOldestFirst() async throws {
        let (tool, _) = try fakeUv()
        #expect(try await tool.availableVersions() == ["3.12.12", "3.13.9"])
    }

    @Test func installedPythonsAreReadFromUvsListing() throws {
        let install = root.appendingPathComponent("python/cpython-3.13.9-macos-aarch64-none")
        try FileManager.default.createDirectory(
            at: install.appendingPathComponent("bin"),
            withIntermediateDirectories: true
        )
        try Data(count: 5000).write(to: install.appendingPathComponent("bin/blob"))
        let json = """
        [{"version":"3.13.9","path":"\(install.path)/bin/python3.13","implementation":"cpython","variant":"default"},
         {"version":"3.13.9","path":"\(install.path)/bin/python3","implementation":"cpython","variant":"default"},
         {"version":"3.12.1","path":null,"implementation":"cpython","variant":"default"}]
        """
        let (tool, _) = try fakeUv(installedJSON: json)
        let found = try tool.installed()
        #expect(found.map(\.id) == ["python@3.13.9"])
        #expect(found[0].path.lastPathComponent == "cpython-3.13.9-macos-aarch64-none")
        #expect(found[0].bytes >= 5000)
    }

    @Test func nothingIsInstalledUntilUvIsDownloaded() throws {
        #expect(try UvTool(paths: paths).installed().isEmpty)
    }

    @Test func installAsksUvForThatVersionAndLatestMeansTheNewest() async throws {
        let (tool, log) = try fakeUv()
        let lines = LineBox()
        try await tool.install(version: "3.12") { lines.add($0) }
        try await tool.install(version: "latest")
        let calls = try String(contentsOf: log, encoding: .utf8)
        #expect(calls.contains("python install 3.12 |"))
        #expect(calls.contains("python install 3.13.9 |"))
        #expect(lines.all == ["Downloading cpython", "Installed Python 3.12"])
    }

    @Test func removingAVersionAsksUvToUninstallIt() throws {
        let (tool, log) = try fakeUv()
        try tool.uninstall(InstalledRuntime(kind: .python, version: "3.13.9", path: root, bytes: 0))
        #expect(try String(contentsOf: log, encoding: .utf8).contains("python uninstall 3.13.9 |"))
    }

    @Test func aFailingUvReportsItsErrorLine() {
        let output = "error: No download found for request: cpython-3.99\nhint: try another\n"
        #expect(UvTool.lastLine(of: output) == "No download found for request: cpython-3.99")
    }

    // MARK: Environment

    @Test func aPythonSiteGetsPythonAndUvFirstAndCannotDownloadInterpreters() throws {
        let (uvTool, _) = try fakeUv()
        let python = root.appendingPathComponent("python/cpython-3.13.9-macos-aarch64-none")
        let need = RuntimeNeed(
            requirement: RuntimeRequirement(kind: .python, requested: "3.13", source: .file(".python-version")),
            installedVersion: "3.13.9", installPath: python
        )
        let environment = RuntimeManager(paths: paths, uvTool: uvTool)
            .environment(for: SiteRuntimePlan(siteID: "demo", needs: [need]), base: ["PATH": "/usr/bin"])
        let path = try #require(environment["PATH"]).split(separator: ":").map(String.init)
        #expect(path.first == python.appendingPathComponent("bin").path)
        #expect(try path.contains(#require(uvTool.binDirectory).path))
        #expect(path.last == "/usr/bin")
        #expect(environment["UV_PYTHON_DOWNLOADS"] == "never")
        #expect(environment["UV_NO_CONFIG"] == "1")
        #expect(environment["UV_PYTHON_INSTALL_DIR"] == paths.dataDirectory.appendingPathComponent("python").path)
        #expect(environment["PIP_CACHE_DIR"] == paths.packagesCacheDirectory.appendingPathComponent("pip").path)
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
