// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import WarrenCore

/// Downloads the newest pinned PHP (about 40 MB) and Composer, then runs them. Off by default.
/// Run with `WARREN_INTEGRATION=1 swift test --filter PHPIntegrationTests`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["WARREN_INTEGRATION"] == "1"))
struct PHPIntegrationTests {
    @Test func realPHPRunsFPMAndComposerInsideWarrensFolder() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("wpi-\(UUID().uuidString.prefix(8))")
        let home = root.appendingPathComponent("home")
        let paths = WarrenPaths(root: root.appendingPathComponent("warren"))
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let php = PHPTool(paths: paths)
        let manager = RuntimeManager(paths: paths, php: php)

        // The pinned downloads verify against their hashes, or this throws.
        let version = try #require(php.available().last)
        try await manager.install(.php, version: version)
        let runtime = try #require(php.installed().first)
        #expect(runtime.version == version)

        let project = root.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try #"{"require":{"php":">=8.2","psr/log":"^3.0"}}"#.write(
            to: project.appendingPathComponent("composer.json"), atomically: true, encoding: .utf8
        )
        let site = ResolvedSite(
            id: "demo", path: project.path, name: "demo", domains: ["demo.test"], runtimes: [:],
            command: nil, port: nil, services: [:], problems: [], warnings: []
        )
        let plan = try manager.plan(for: site, installed: manager.inventory())
        #expect(plan.missing.isEmpty)
        var environment = manager.environment(for: plan)
        environment["HOME"] = home.path

        // The extension set covers the popular stacks.
        let modules = try Shell.run(
            runtime.path.appendingPathComponent("bin/php").path,
            ["-m"],
            environment: environment
        )
        .output.lowercased()
        for name in [
            "pdo_sqlite",
            "pdo_mysql",
            "pdo_pgsql",
            "mysqli",
            "intl",
            "zend opcache",
            "sodium",
            "mbstring",
            "gd"
        ] {
            #expect(modules.contains(name), "missing \(name)")
        }

        // php-fpm accepts a configuration and reads Warren's ini.
        let fpmConfig = root.appendingPathComponent("fpm.conf")
        try """
        [global]
        error_log = \(root.path)/fpm.log
        [www]
        listen = \(root.path)/fpm.sock
        pm = static
        pm.max_children = 1
        """.write(to: fpmConfig, atomically: true, encoding: .utf8)
        let fpm = try Shell.run(
            runtime.path.appendingPathComponent("bin/php-fpm").path, ["-t", "-y", fpmConfig.path],
            environment: environment
        )
        #expect(fpm.status == 0, "\(fpm.output)")

        // Composer installs a package with Warren's PHP and keeps its state in Warren's folder.
        let composer = try Shell.run(
            "/usr/bin/env",
            ["composer", "install", "--no-interaction"],
            environment: environment,
            directory: project
        )
        #expect(composer.status == 0, "\(composer.output)")
        #expect(FileManager.default.fileExists(atPath: project.appendingPathComponent("vendor/psr/log").path))
        #expect(PackageCaches.bytes(paths) > 0)
        for folder in [".composer", ".config/composer", ".cache/composer"] {
            #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent(folder).path))
        }
    }
}
