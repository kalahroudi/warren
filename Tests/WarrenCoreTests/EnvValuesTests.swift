// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import WarrenCore

private final class Sink: @unchecked Sendable {
    private let lock = NSLock()
    private var texts: [String] = []
    private var environments: [[String: String]] = []

    func add(_ text: String) {
        lock.withLock { texts.append(text) }
    }

    func add(environment: [String: String]) {
        lock.withLock { environments.append(environment) }
    }

    var all: String {
        lock.withLock { texts.joined(separator: "\n") }
    }

    var allEnvironments: [[String: String]] {
        lock.withLock { environments }
    }
}

private struct SilentExecutor: CommandExecuting {
    let sink: Sink

    func run(
        _ command: [String], directory _: URL, environment: [String: String],
        onLine: @escaping @Sendable (String) -> Void
    ) async throws -> Int32 {
        sink.add(environment: environment)
        onLine("ran \(command.joined(separator: " "))")
        return 0
    }
}

struct EnvValuesTests {
    private let root: URL
    private let paths: WarrenPaths

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("wev-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        paths = WarrenPaths(root: root.appendingPathComponent("home"))
    }

    // MARK: Values

    @Test func promptsAreClassifiedAndOffersAreLimitedToTheNamedLists() {
        let env = EnvFile("""
        APP_KEY=
        APP_URL=
        NEXTAUTH_URL=
        AUTH_SECRET=
        STRIPE_SECRET_KEY=
        NEXT_PUBLIC_STRIPE_KEY=
        DATABASE_PASSWORD=
        NAME=
        FILLED=yes
        """)
        let prompts = EnvPrompts.prompts(for: env)
        #expect(prompts.map(\.name) == [
            "APP_URL",
            "NEXTAUTH_URL",
            "AUTH_SECRET",
            "STRIPE_SECRET_KEY",
            "NEXT_PUBLIC_STRIPE_KEY",
            "DATABASE_PASSWORD",
            "NAME"
        ])
        func prompt(_ name: String) -> EnvPrompt? {
            prompts.first { $0.name == name }
        }
        #expect(prompt("APP_URL")?.offer == .siteURL && prompt("APP_URL")?.isSecret == false)
        #expect(prompt("AUTH_SECRET")?.offer == .generate && prompt("AUTH_SECRET")?.isSecret == true)
        #expect(prompt("STRIPE_SECRET_KEY")?.offer == EnvPrompt.Offer.none && prompt("STRIPE_SECRET_KEY")?
            .isSecret == true)
        #expect(prompt("NEXT_PUBLIC_STRIPE_KEY")?.isSecret == false)
        #expect(prompt("DATABASE_PASSWORD")?.isSecret == true && prompt("NAME")?.isSecret == false)
        #expect(EnvPrompts.siteURL(domain: "shop.test") == "https://shop.test")
        let first = EnvPrompts.generatedSecret()
        #expect(first.count == 64 && first != EnvPrompts.generatedSecret())
    }

    @Test func placeholdersCountAsUnsetButRealDefaultsDoNot() throws {
        let env = EnvFile("""
        FIRECRAWL_KEY="YOUR_KEY"
        TOKEN=<paste token>
        OTHER=changeme
        MASKED=xxxxxxxxxxxx
        DB_PASSWORD=password
        HOST=localhost
        PORT=3000
        EMPTY=
        """)
        #expect(env.unsetKeys == ["FIRECRAWL_KEY", "TOKEN", "OTHER", "MASKED", "EMPTY"])
        let file = root.appendingPathComponent(".env")
        try "FIRECRAWL_KEY=\"YOUR_KEY\"\nDB_PASSWORD=password\n".write(to: file, atomically: true, encoding: .utf8)
        try EnvEditor.apply(["FIRECRAWL_KEY": "fc-123", "DB_PASSWORD": "ignored"], to: file)
        let result = try String(contentsOf: file, encoding: .utf8)
        #expect(result == "FIRECRAWL_KEY=fc-123\nDB_PASSWORD=password\n", "got: \(result)")
    }

    @Test func theEditorChangesOnlyTheChosenEmptyLinesAndKeepsTheRest() throws {
        let file = root.appendingPathComponent(".env")
        let original = "# comment\nAPP_NAME=Shop\nKEY_A=\nexport KEY_B=\nKEEP=already\n\nTAIL=\n"
        try original.write(to: file, atomically: true, encoding: .utf8)
        let written = try EnvEditor.apply(
            ["KEY_A": "abc", "KEY_B": "with space", "KEEP": "ignored", "NEW": "n", "EMPTY": ""],
            to: file
        )
        #expect(written == ["KEY_A", "KEY_B", "NEW"])
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text ==
            "# comment\nAPP_NAME=Shop\nKEY_A=abc\nexport KEY_B='with space'\nKEEP=already\n\nTAIL=\nNEW=n\n")
        #expect(try EnvEditor.apply([:], to: file).isEmpty)
        #expect(EnvEditor.quoted("a#b") == "'a#b'" && EnvEditor.quoted("it's") == "\"it's\"" && EnvEditor
            .quoted("plain") == "plain")
        #expect(EnvEditor.quoted("it's $x") == "\"it's \\$x\"")
    }

    @Test func gitignoreCoverageIsDetected() throws {
        let project = root.appendingPathComponent("p")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        #expect(!EnvEditor.isIgnored(in: project))
        try "node_modules\n.env\n".write(
            to: project.appendingPathComponent(".gitignore"),
            atomically: true,
            encoding: .utf8
        )
        #expect(EnvEditor.isIgnored(in: project))
        try "node_modules\n# .env\n".write(
            to: project.appendingPathComponent(".gitignore"),
            atomically: true,
            encoding: .utf8
        )
        #expect(!EnvEditor.isIgnored(in: project))
    }

    // MARK: The values step

    private func planFor(_ files: [String: String]) throws -> (ResolvedSite, SetupPlan) {
        let folder = root.appendingPathComponent("proj-\(UUID().uuidString.prefix(5))")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, text) in files {
            try text.write(
                to: folder.appendingPathComponent(name),
                atomically: true,
                encoding: .utf8
            )
        }
        let site = try SiteRegistry(paths: paths).add(path: folder.path)
        return (site, SetupPlanner(paths: paths).plan(for: site, registered: true, inventory: []))
    }

    @Test func theValuesStepAsksOnlyWhileThereIsSomethingToAskAndNotAgainAfterASkip() async throws {
        let (site, plan) = try planFor(["index.html": "x", ".env.example": "A_KEY=\nB=\nC=1\n"])
        let step = try #require(plan.steps.first { $0.id == "env-values" })
        #expect(step.state == .todo && step.payload["names"] == "A_KEY,B" && step.waitsFor == ["env"] && !step
            .runsProjectCode)
        #expect(try #require(plan.steps.firstIndex { $0.id == "env" }) < plan.steps
            .firstIndex { $0.id == "env-values" }!)

        let runner = PlanRunner(
            paths: paths,
            site: site,
            executor: SilentExecutor(sink: Sink()),
            baseEnvironment: ["PATH": "/usr/bin"]
        )
        await runner.run(plan: plan, approve: { .all($0) }, values: { _ in [:] }, onEvent: { _ in })
        let after = SetupPlanner(paths: paths).plan(for: site, registered: true, inventory: [])
        #expect(after.steps.first { $0.id == "env-values" }?.state == .done)

        // A variable added to the example later asks again.
        try "A_KEY=\nB=\nC=1\nD_TOKEN=\n".write(
            to: URL(fileURLWithPath: site.path).appendingPathComponent(".env.example"), atomically: true,
            encoding: .utf8
        )
        let again = SetupPlanner(paths: paths).plan(for: site, registered: true, inventory: [])
        #expect(again.steps.first { $0.id == "env-values" }?.state == .todo)
    }

    @Test func aProjectWithNothingEmptyHasNoValuesStep() throws {
        let (_, plan) = try planFor(["index.html": "x", ".env.example": "A=1\n"])
        #expect(!plan.steps.contains { $0.id == "env-values" })
    }

    @Test func aSecretValueIsWrittenToEnvAndNowhereElse() async throws {
        let sentinel = "s3ntinel-\(UUID().uuidString)"
        let (site, plan) = try planFor(["index.html": "x", ".env.example": "STRIPE_SECRET_KEY=\nOTHER=\n"])
        let sink = Sink()
        let runner = PlanRunner(
            paths: paths,
            site: site,
            executor: SilentExecutor(sink: sink),
            baseEnvironment: ["PATH": "/usr/bin"]
        )
        let summary = await runner.run(
            plan: plan, approve: { .all($0) },
            values: { prompts in
                #expect(prompts.map(\.name) == ["STRIPE_SECRET_KEY", "OTHER"])
                return ["STRIPE_SECRET_KEY": sentinel, "NOT_ASKED": "x"]
            },
            onEvent: { event in
                switch event {
                case let .output(_, line): sink.add(line)
                case let .stepFinished(step, result): sink.add("\(step) \(result)")
                default: break
                }
            }
        )
        #expect(summary.succeeded)
        let env = try String(
            contentsOf: URL(fileURLWithPath: site.path).appendingPathComponent(".env"),
            encoding: .utf8
        )
        #expect(env.contains("STRIPE_SECRET_KEY=\(sentinel)") && !env.contains("NOT_ASKED"))

        var everywhere = sink.all
        for file in [paths.setupRunsFile] + (FileManager.default.enumerator(
            at: paths.setupLogsDirectory,
            includingPropertiesForKeys: nil
        )?.allObjects as? [URL] ?? []) {
            everywhere += (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        }
        #expect(!everywhere.contains(sentinel))
        #expect(!sink.allEnvironments.contains { $0.values.contains(sentinel) })
        #expect(everywhere.contains("Saved 1 value to .env"))
    }
}
