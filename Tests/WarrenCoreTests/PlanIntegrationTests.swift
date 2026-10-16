// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import WarrenCore

/// Runs the real mise to install pnpm (about 60 MB), then a step that uses it. Off by default.
/// Run with `WARREN_INTEGRATION=1 swift test --filter PlanIntegrationTests`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["WARREN_INTEGRATION"] == "1"))
struct PlanIntegrationTests {
    private final class Lines: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [String] = []
        var all: [String] {
            lock.withLock { stored }
        }

        func add(_ line: String) {
            lock.withLock { stored.append(line) }
        }
    }

    @Test func pnpmIsInstalledThroughMiseAndFoundByTheNextStep() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("wpi2-\(UUID().uuidString.prefix(8))")
        let paths = WarrenPaths(root: root.appendingPathComponent("warren"))
        let project = root.appendingPathComponent("app")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var base = ProcessInfo.processInfo.environment
        base["HOME"] = root.appendingPathComponent("home").path
        try FileManager.default.createDirectory(atPath: base["HOME"] ?? "", withIntermediateDirectories: true)
        let site = try SiteRegistry(paths: paths).add(path: project.path)
        let steps = [
            PlanStep(
                id: "tool-pnpm", kind: .packageManager, title: "Install pnpm", detail: "", command: nil,
                runsProjectCode: false, state: .todo, waitsFor: [], enabledByDefault: true,
                payload: ["tool": "pnpm", "version": "9.15.0"]
            ),
            PlanStep(
                id: "version", kind: .dependencies, title: "pnpm --version", detail: "", command: ["pnpm", "--version"],
                runsProjectCode: false, state: .todo, waitsFor: ["tool-pnpm"], enabledByDefault: true
            ),
        ]
        let plan = SetupPlan(
            siteID: site.id, folder: project.path, detection: .unknown, runtimes: [],
            env: EnvSummary(example: nil, envExists: false, emptyVariables: []), services: [], steps: steps
        )
        let runner = PlanRunner(paths: paths, site: site, baseEnvironment: base)
        let output = Lines()
        let summary = await runner.run(plan: plan, approve: { .all($0) }, onEvent: { event in
            if case let .output(step, line) = event, step == "version" {
                output.add(line)
            }
        })
        #expect(summary.succeeded, "\(summary.results)")
        #expect(output.all.contains("9.15.0"))
        let tools = try RuntimeManager(paths: paths).installedTools()
        #expect(tools.map(\.name) == ["pnpm"] && tools[0].path.path.hasPrefix(paths.dataDirectory.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: base["HOME"] ?? "").isEmpty)
    }
}
