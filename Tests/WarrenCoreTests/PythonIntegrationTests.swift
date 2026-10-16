// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import WarrenCore

/// Runs the real uv: downloads it (about 14 MB) and installs Python 3.13 (about 24 MB). Off by default.
/// Run with `WARREN_INTEGRATION=1 swift test --filter PythonIntegrationTests`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["WARREN_INTEGRATION"] == "1"))
struct PythonIntegrationTests {
    @Test func realUvInstallsRunsAndRemovesPythonInsideWarrensFolder() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("wyi-\(UUID().uuidString.prefix(8))")
        let home = root.appendingPathComponent("home")
        let paths = WarrenPaths(root: root.appendingPathComponent("warren"))
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var base = ProcessInfo.processInfo.environment
        base["HOME"] = home.path
        // A user's own uv settings must not change what Warren does.
        base["UV_PYTHON_INSTALL_DIR"] = root.appendingPathComponent("elsewhere").path
        base["UV_PYTHON_DOWNLOADS"] = "never"
        let uvTool = UvTool(paths: paths, baseEnvironment: base)
        let manager = RuntimeManager(paths: paths, uvTool: uvTool)

        // The pinned download verifies against its checksum, or this throws.
        try await uvTool.ensureInstalled()
        #expect(uvTool.isInstalled)
        #expect(try await uvTool.availableVersions().contains { $0.hasPrefix("3.13.") })

        try await manager.install(.python, version: "3.13")
        let installed = try manager.inventory()
        #expect(installed.map(\.kind) == [.python])
        let python = installed[0].path.appendingPathComponent("bin/python3")
        #expect(try Shell.run(python.path, ["-V"]).output.contains("Python 3.13."))
        #expect(installed[0].bytes > 10_000_000)
        #expect(installed[0].path.path.hasPrefix(paths.dataDirectory.path))

        // A site's environment finds the managed Python and cannot download another one, even with a hostile uv.toml.
        let project = root.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try "python-install-mirror = \"https://example.invalid\"\n".write(
            to: project.appendingPathComponent("uv.toml"), atomically: true, encoding: .utf8
        )
        try "[project]\nname = \"x\"\nversion = \"0\"\nrequires-python = \">=3.12\"\n".write(
            to: project.appendingPathComponent("pyproject.toml"), atomically: true, encoding: .utf8
        )
        let site = ResolvedSite(
            id: "demo", path: project.path, name: "demo", domains: ["demo.test"], runtimes: [:],
            command: nil, port: nil, services: [:], problems: [], warnings: []
        )
        let plan = manager.plan(for: site, installed: installed)
        #expect(plan.missing.isEmpty)
        var environment = manager.environment(for: plan)
        environment["HOME"] = home.path
        let uvPath = try #require(uvTool.binDirectory).appendingPathComponent("uv").path
        let found = try Shell.run(uvPath, ["python", "find"], environment: environment, directory: project)
        #expect(found.status == 0, "\(found.output)")
        #expect(found.output.contains(paths.dataDirectory.path))
        let refused = try Shell.run(uvPath, ["python", "install", "3.12"], environment: environment, directory: project)
        #expect(refused.status != 0)

        // Installing again does nothing; a cancelled install leaves nothing new listed.
        try await manager.install(.python, version: "3.13")
        #expect(try manager.inventory().count == 1)
        let other = Task { try await manager.install(.python, version: "3.12") }
        try await Task.sleep(for: .milliseconds(800))
        other.cancel()
        if await (try? other.value) == nil {
            #expect(try manager.inventory().map(\.version).allSatisfy { $0.hasPrefix("3.13.") })
        }

        // Remove everything installed.
        for runtime in try manager.inventory() {
            try manager.remove(runtime)
        }
        #expect(try manager.inventory().isEmpty)

        // Nothing leaked into the user's home or the "elsewhere" folder.
        #expect(try FileManager.default.contentsOfDirectory(atPath: home.path).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("elsewhere").path))
    }
}
