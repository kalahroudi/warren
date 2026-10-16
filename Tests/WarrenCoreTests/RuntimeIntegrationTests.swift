// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import WarrenCore

/// Runs the real mise: downloads it (about 44 MB) and installs Bun (about 30 MB).
/// Off by default. Run with `WARREN_INTEGRATION=1 swift test --filter RuntimeIntegrationTests`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["WARREN_INTEGRATION"] == "1"))
struct RuntimeIntegrationTests {
    @Test func realMiseInstallsRunsAndRemovesBunInsideWarrensFolder() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("wri-\(UUID().uuidString.prefix(8))")
        let home = root.appendingPathComponent("home")
        let paths = WarrenPaths(root: root.appendingPathComponent("warren"))
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var base = ProcessInfo.processInfo.environment
        base["HOME"] = home.path
        let mise = MiseTool(paths: paths, baseEnvironment: base)
        let manager = RuntimeManager(paths: paths, mise: mise)

        // The pinned download verifies against its checksum, or this throws.
        try await mise.ensureInstalled()
        #expect(mise.isInstalled)

        // A hostile mise.toml must not run anything, even when mise is run inside that project.
        let evil = root.appendingPathComponent("evil")
        try FileManager.default.createDirectory(at: evil, withIntermediateDirectories: true)
        let marker = root.appendingPathComponent("pwned")
        try """
        [env]
        A = "{{ exec(command='touch \(marker.path)-template') }}"
        _.source = "\(root.path)/source.sh"
        [tasks.x]
        run = "touch \(marker.path)-task"
        """.write(to: evil.appendingPathComponent("mise.toml"), atomically: true, encoding: .utf8)
        try "touch \(marker.path)-source\n".write(
            to: root.appendingPathComponent("source.sh"), atomically: true, encoding: .utf8
        )
        _ = try? mise.run(["ls", "--json"], in: evil)
        _ = try? mise.run(["env", "--json"], in: evil)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix("pwned") }
        #expect(leftovers.isEmpty)

        // Install, run, install again.
        try await manager.install(.bun, version: "1.4.3")
        var installed = try manager.inventory()
        #expect(installed.map(\.id) == ["bun@1.4.3"])
        #expect(installed[0].bytes > 10_000_000)
        let bun = installed[0].path.appendingPathComponent("bin/bun").path
        #expect(try Shell.run(bun, ["-v"]).output.trimmingCharacters(in: .whitespacesAndNewlines) == "1.4.3")
        try await manager.install(.bun, version: "1.4.3")
        #expect(try manager.inventory().count == 1)

        // A cancelled install leaves nothing listed.
        let node = Task { try await manager.install(.node, version: "22") }
        try await Task.sleep(for: .seconds(2))
        node.cancel()
        _ = try? await node.value
        #expect(try manager.inventory().map(\.id) == ["bun@1.4.3"])

        // Remove.
        try manager.remove(installed[0])
        installed = try manager.inventory()
        #expect(installed.isEmpty)

        // Nothing leaked into the user's own mise folders.
        for folder in [".config/mise", ".local/share/mise", ".cache/mise", ".local/state/mise"] {
            #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent(folder).path))
        }
    }
}
