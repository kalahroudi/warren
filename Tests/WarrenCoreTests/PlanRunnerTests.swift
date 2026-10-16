// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import WarrenCore

/// Records what it was asked to run and answers from a table, so no real process starts.
private final class FakeExecutor: CommandExecuting, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [[String]] = []
    private var environments: [[String: String]] = []
    var exitCodes: [String: Int32] = [:]
    var hang = false

    var commands: [[String]] {
        lock.withLock { recorded }
    }

    var lastEnvironment: [String: String] {
        lock.withLock { environments.last ?? [:] }
    }

    func run(
        _ command: [String], directory _: URL, environment: [String: String],
        onLine: @escaping @Sendable (String) -> Void
    ) async throws -> Int32 {
        lock.withLock {
            recorded.append(command)
            environments.append(environment)
        }
        onLine("ran \(command.joined(separator: " "))")
        if hang {
            try? await Task.sleep(for: .seconds(30))
            return 143
        }
        return exitCodes[command.joined(separator: " ")] ?? 0
    }
}

private final class Collected: @unchecked Sendable {
    private let lock = NSLock()
    private var all: [PlanRunEvent] = []
    private var asked: [[String]] = []

    func add(_ event: PlanRunEvent) {
        lock.withLock { all.append(event) }
    }

    func asked(_ ids: [String]) {
        lock.withLock { asked.append(ids) }
    }

    var events: [PlanRunEvent] {
        lock.withLock { all }
    }

    var approvals: [[String]] {
        lock.withLock { asked }
    }
}

struct PlanRunnerTests {
    private let root: URL
    private let paths: WarrenPaths
    private let project: URL
    private let site: ResolvedSite

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("wpr-\(UUID().uuidString.prefix(8))")
        paths = WarrenPaths(root: root.appendingPathComponent("home"))
        project = root.appendingPathComponent("shop")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        site = try SiteRegistry(paths: paths).add(path: project.path)
    }

    private func step(
        _ id: String, kind: PlanStepKind = .dependencies, command: [String]? = nil, code: Bool = true,
        state: PlanStepState = .todo, waits: [String] = [], enabled: Bool = true, own: Bool = false
    ) -> PlanStep {
        PlanStep(
            id: id, kind: kind, title: id, detail: "", command: own ? nil : command ?? [id], runsProjectCode: code,
            state: state, waitsFor: waits, enabledByDefault: enabled
        )
    }

    private func plan(_ steps: [PlanStep], example: String? = nil, empty: [String] = []) -> SetupPlan {
        SetupPlan(
            siteID: site.id, folder: project.path, detection: .unknown, runtimes: [],
            env: EnvSummary(example: example, envExists: false, emptyVariables: empty), services: [], steps: steps
        )
    }

    @discardableResult
    private func run(
        _ plan: SetupPlan, executor: FakeExecutor, optional: Set<String> = [],
        decision: @escaping @Sendable ([PlanStep]) -> PlanApproval = { .all($0) }, collected: Collected = Collected()
    ) async -> (RunSummary, Collected) {
        let runner = PlanRunner(paths: paths, site: site, executor: executor, baseEnvironment: ["PATH": "/usr/bin"])
        let summary = await runner.run(plan: plan, optional: optional, approve: { steps in
            collected.asked(steps.map(\.id))
            return decision(steps)
        }, onEvent: { collected.add($0) })
        return (summary, collected)
    }

    // MARK: Order and selection

    @Test func stepsRunInOrderAndSkipDoneWaitingOffAndSiteSteps() async {
        let executor = FakeExecutor()
        let steps = [
            step("a"), step("done", state: .done), step("later", state: .waiting("x")),
            step("optional", enabled: false), step("site", kind: .site, own: true), step("b"),
            step("svc", kind: .service, own: true),
        ]
        let (summary, _) = await run(plan(steps), executor: executor)
        #expect(executor.commands == [["a"], ["b"]])
        #expect(summary.order == ["a", "b"] && summary.succeeded)
    }

    @Test func aTickedOptionalStepRuns() async {
        let executor = FakeExecutor()
        await run(plan([step("a"), step("optional", enabled: false)]), executor: executor, optional: ["optional"])
        #expect(executor.commands == [["a"], ["optional"]])
    }

    @Test func aFailureSkipsWhatDependsOnItAndKeepsGoingWithTheRest() async {
        let executor = FakeExecutor()
        executor.exitCodes = ["a": 3]
        let steps = [step("a"), step("b", waits: ["a"]), step("c")]
        let (summary, _) = await run(plan(steps), executor: executor)
        #expect(executor.commands == [["a"], ["c"]])
        #expect(summary.results["a"] == .failed(exitCode: 3, lastLines: ["$ a", "ran a"]))
        #expect(summary.results["b"] == .skipped("a did not finish"))
        #expect(summary.results["c"] == .done)
        #expect(summary.failed == ["a"] && !summary.succeeded)
    }

    @Test func eventsReportStartOutputAndFinishInOrder() async {
        let executor = FakeExecutor()
        let (_, collected) = await run(plan([step("a")]), executor: executor)
        var kinds: [String] = []
        for event in collected.events {
            switch event {
            case .stepStarted: kinds.append("start")
            case .output: kinds.append("output")
            case .stepFinished: kinds.append("finish")
            case .finished: kinds.append("end")
            }
        }
        #expect(kinds == ["start", "output", "output", "finish", "end"])
    }

    // MARK: Approval

    @Test func approvalIsAskedOnlyForStepsThatRunProjectCode() async {
        let executor = FakeExecutor()
        let steps = [
            step("install"),
            step("copy", kind: .envFile, code: false, own: true),
            step("migrate", kind: .database)
        ]
        let (_, collected) = await run(plan(steps), executor: executor)
        #expect(collected.approvals == [["install", "migrate"]])
    }

    @Test func nothingIsAskedWhenNoStepRunsProjectCode() async {
        let executor = FakeExecutor()
        let (_, collected) = await run(plan([step("free", code: false)]), executor: executor)
        #expect(collected.approvals.isEmpty)
        #expect(executor.commands == [["free"]])
    }

    @Test func aStepThatIsNotApprovedIsSkippedAndSoIsWhatNeedsIt() async {
        let executor = FakeExecutor()
        let steps = [step("install"), step("migrate", waits: ["install"]), step("free", code: false)]
        let (summary, _) = await run(
            plan(steps),
            executor: executor,
            decision: { _ in PlanApproval(approved: ["migrate"]) }
        )
        #expect(summary.results["install"] == .skipped("not approved"))
        #expect(summary.results["migrate"] == .skipped("install did not finish"))
        #expect(executor.commands == [["free"]])
    }

    @Test func cancellingTheApprovalRunsNoProjectCode() async {
        let executor = FakeExecutor()
        let (summary, _) = await run(plan([step("install")]), executor: executor, decision: { _ in .none })
        #expect(executor.commands.isEmpty && summary.results["install"] == .skipped("not approved"))
    }

    // MARK: Trust

    @Test func trustedCommandsAreNotAskedAboutAgainButAChangedCommandIs() async throws {
        let executor = FakeExecutor()
        let first = [step("install", command: ["npm", "ci"])]
        await run(plan(first), executor: executor, decision: { PlanApproval(approved: Set($0.map(\.id)), trust: true) })
        #expect(try SiteRegistry(paths: paths).trustedCommands(id: site.id) == [["npm", "ci"]])

        let (_, again) = await run(plan(first), executor: executor)
        #expect(again.approvals.isEmpty)
        #expect(executor.commands.count == 2)

        let changed = [step("install", command: ["npm", "install", "--ignore-scripts=false"])]
        let (_, asked) = await run(plan(changed), executor: executor)
        #expect(asked.approvals == [["install"]])
    }

    @Test func approvalWithoutTrustIsNotRemembered() async throws {
        let executor = FakeExecutor()
        await run(plan([step("install")]), executor: executor)
        #expect(try SiteRegistry(paths: paths).trustedCommands(id: site.id).isEmpty)
        let (_, asked) = await run(plan([step("install")]), executor: executor)
        #expect(asked.approvals == [["install"]])
    }

    @Test func trustCanBeCleared() throws {
        let registry = SiteRegistry(paths: paths)
        try registry.setTrustedCommands(id: site.id, [["npm", "ci"]])
        try registry.setTrustedCommands(id: site.id, [])
        #expect(try registry.trustedCommands(id: site.id).isEmpty)
    }

    // MARK: Warren's own steps

    @Test func theEnvFileIsCopiedWithoutOverwritingAndSQLiteIsCreated() async throws {
        try "A=1\nB=\n".write(to: project.appendingPathComponent(".env.example"), atomically: true, encoding: .utf8)
        let steps = [
            step("env", kind: .envFile, code: false, own: true),
            step("sqlite", kind: .application, code: false, own: true),
        ]
        let executor = FakeExecutor()
        let (summary, collected) = await run(plan(steps, example: ".env.example", empty: ["B"]), executor: executor)
        #expect(summary.succeeded && executor.commands.isEmpty && collected.approvals.isEmpty)
        #expect(try String(contentsOf: project.appendingPathComponent(".env"), encoding: .utf8) == "A=1\nB=\n")
        #expect(FileManager.default.fileExists(atPath: project.appendingPathComponent("database/database.sqlite").path))

        try "A=mine\n".write(to: project.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        await run(plan([steps[0]], example: ".env.example"), executor: executor)
        #expect(try String(contentsOf: project.appendingPathComponent(".env"), encoding: .utf8) == "A=mine\n")
    }

    // MARK: Memory

    @Test func aSuccessfulMigrationIsRememberedUntilItsCommandChanges() async throws {
        try """
        {"require":{"php":"^8.2","laravel/framework":"^11"}}
        """.write(to: project.appendingPathComponent("composer.json"), atomically: true, encoding: .utf8)
        FileManager.default.createFile(atPath: project.appendingPathComponent("artisan").path, contents: nil)
        let planner = SetupPlanner(paths: paths)
        let before = planner.plan(for: site, registered: true, inventory: [])
        #expect(before.steps.first { $0.id == "migrate" }?.state == .todo)

        let migrate = try #require(before.steps.first { $0.id == "migrate" })
        await run(plan([migrate]), executor: FakeExecutor())
        let after = planner.plan(for: site, registered: true, inventory: [])
        #expect(after.steps.first { $0.id == "migrate" }?.state == .done)

        try SetupRunStore(paths: paths).record(
            site: site.id,
            step: "migrate",
            command: ["php", "artisan", "migrate:fresh"]
        )
        let changed = planner.plan(for: site, registered: true, inventory: [])
        #expect(changed.steps.first { $0.id == "migrate" }?.state == .todo)
        try SetupRunStore(paths: paths).forget(site: site.id)
        #expect(SetupRunStore(paths: paths).completed(site: site.id).isEmpty)
    }

    @Test func aFailedStepIsNotRemembered() async {
        let executor = FakeExecutor()
        executor.exitCodes = ["migrate": 1]
        await run(plan([step("migrate", kind: .database)]), executor: executor)
        #expect(SetupRunStore(paths: paths).completed(site: site.id).isEmpty)
    }

    // MARK: Environment, logs, stop

    @Test func commandsGetTheNonInteractiveEnvironment() async {
        let executor = FakeExecutor()
        await run(plan([step("a")]), executor: executor)
        #expect(executor.lastEnvironment["CI"] == "1")
        #expect(executor.lastEnvironment["COMPOSER_NO_INTERACTION"] == "1")
        #expect(executor.lastEnvironment["npm_config_cache"]?.hasPrefix(paths.packagesCacheDirectory.path) == true)
    }

    @Test func eachStepWritesItsLog() async throws {
        await run(plan([step("a")]), executor: FakeExecutor())
        let log = paths.setupLogsDirectory.appendingPathComponent("\(site.id)/a.log")
        #expect(try String(contentsOf: log, encoding: .utf8) == "$ a\nran a\n")
    }

    @Test func stoppingCancelsTheRunningStepAndTheRest() async {
        let executor = FakeExecutor()
        executor.hang = true
        let runner = PlanRunner(paths: paths, site: site, executor: executor, baseEnvironment: ["PATH": "/usr/bin"])
        let subject = plan([step("a", code: false), step("b", code: false)])
        let task = Task { await runner.run(plan: subject, approve: { .all($0) }, onEvent: { _ in }) }
        try? await Task.sleep(for: .milliseconds(200))
        task.cancel()
        let summary = await task.value
        #expect(summary.cancelled)
        #expect(summary.results["a"] == .cancelled && summary.results["b"] == .cancelled)
    }

    @Test func familiarFailuresGetAPlainNextAction() {
        #expect(PlanRunner.advice(forFailureLines: ["sh: composer: command not found"], exitCode: 127) != nil)
        #expect(PlanRunner.advice(forFailureLines: ["Error: listen EADDRINUSE :::3000"], exitCode: 1) != nil)
        #expect(PlanRunner.advice(forFailureLines: ["getaddrinfo ENOTFOUND registry.npmjs.org"], exitCode: 1) != nil)
        #expect(PlanRunner.advice(forFailureLines: ["some other error"], exitCode: 1) == nil)
    }
}
