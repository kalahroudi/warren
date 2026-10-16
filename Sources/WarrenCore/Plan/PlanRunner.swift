// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum StepResult: Equatable, Sendable {
    case done
    case failed(exitCode: Int32, lastLines: [String])
    case skipped(String)
    case cancelled
}

public enum PlanRunEvent: Sendable {
    case stepStarted(String)
    case output(step: String, line: String)
    case stepFinished(step: String, result: StepResult)
    case finished(RunSummary)
}

public struct RunSummary: Equatable, Sendable {
    /// Step ids in the order they were handled.
    public let order: [String]
    public let results: [String: StepResult]
    public let cancelled: Bool

    public var failed: [String] {
        order.filter {
            if case .failed = results[$0] {
                true
            } else {
                false
            }
        }
    }

    /// Steps that were left out: not approved, or waiting on one that failed.
    public var skipped: [String] {
        order.filter {
            if case .skipped = results[$0] {
                true
            } else {
                false
            }
        }
    }

    /// Every step that was due to run ran and finished.
    public var succeeded: Bool {
        !cancelled && failed.isEmpty && skipped.isEmpty
    }
}

/// What the user decided about the steps that run the project's own code.
public struct PlanApproval: Sendable {
    public let approved: Set<String>
    /// Remember these commands for this site, so they do not ask again.
    public let trust: Bool

    public init(approved: Set<String>, trust: Bool = false) {
        self.approved = approved
        self.trust = trust
    }

    public static func all(_ steps: [PlanStep]) -> PlanApproval {
        PlanApproval(approved: Set(steps.map(\.id)))
    }

    public static let none = PlanApproval(approved: [])
}

/// Works through a setup plan: Warren's own steps in-process, the project's commands as processes, each reported
/// as events. Steps that run the project's code need approval first. See spec 012.
public struct PlanRunner: Sendable {
    public typealias Approval = @Sendable ([PlanStep]) async -> PlanApproval
    public typealias Events = @Sendable (PlanRunEvent) -> Void
    /// Answers for the variables `.env` leaves empty: name to value. Variables left out stay empty.
    public typealias Values = @Sendable ([EnvPrompt]) async -> [String: String]

    public let paths: WarrenPaths
    public let site: ResolvedSite
    private let manager: RuntimeManager
    private let executor: any CommandExecuting
    private let baseEnvironment: [String: String]

    public init(
        paths: WarrenPaths,
        site: ResolvedSite,
        manager: RuntimeManager? = nil,
        executor: any CommandExecuting = ProcessGroupExecutor(),
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.paths = paths
        self.site = site
        self.manager = manager ?? RuntimeManager(paths: paths)
        self.executor = executor
        self.baseEnvironment = baseEnvironment
    }

    private var directory: URL {
        URL(fileURLWithPath: site.path, isDirectory: true)
    }

    /// The steps a run would handle: on by default (or ticked), not done, not waiting, and not the site step.
    public static func selectedSteps(_ plan: SetupPlan, optional: Set<String> = []) -> [PlanStep] {
        plan.steps.filter { step in
            guard step.kind != .site, step.kind != .service else { return false }
            if case .waiting = step.state {
                return false
            }
            return !step.state.isDone && (step.enabledByDefault || optional.contains(step.id))
        }
    }

    @discardableResult
    public func run(
        plan: SetupPlan, optional: Set<String> = [], approve: Approval,
        values: @escaping Values = { _ in [:] }, onEvent: @escaping Events
    ) async -> RunSummary {
        let selected = Self.selectedSteps(plan, optional: optional)
        let approved = await approvedSteps(selected.filter(\.runsProjectCode), approve: approve)

        var results: [String: StepResult] = [:]
        var order: [String] = []
        func finish(_ step: PlanStep, _ result: StepResult) {
            results[step.id] = result
            order.append(step.id)
            onEvent(.stepFinished(step: step.id, result: result))
        }

        for step in selected {
            if Task.isCancelled {
                finish(step, .cancelled)
                continue
            }
            if step.runsProjectCode, !approved.contains(step.id) {
                finish(step, .skipped("not approved"))
                continue
            }
            if let blocker = step.waitsFor.first(where: { results[$0].map { $0 != .done } ?? false }) {
                finish(step, .skipped("\(blocker) did not finish"))
                continue
            }
            onEvent(.stepStarted(step.id))
            await finish(step, perform(step, plan: plan, values: values, onEvent: onEvent))
        }
        let summary = RunSummary(order: order, results: results, cancelled: Task.isCancelled)
        onEvent(.finished(summary))
        return summary
    }

    // MARK: Approval

    /// Steps whose commands the user has already trusted for this site are approved without asking. Everything
    /// else goes to the approval handler once.
    private func approvedSteps(_ steps: [PlanStep], approve: Approval) async -> Set<String> {
        guard !steps.isEmpty else { return [] }
        let registry = SiteRegistry(paths: paths)
        let trusted = (try? registry.trustedCommands(id: site.id)) ?? []
        if steps.allSatisfy({ step in step.command.map { trusted.contains($0) } ?? false }) {
            return Set(steps.map(\.id))
        }
        let decision = await approve(steps)
        let approved = steps.filter { decision.approved.contains($0.id) }
        if decision.trust {
            let commands = approved.compactMap(\.command)
            try? registry.setTrustedCommands(id: site.id, trusted + commands.filter { !trusted.contains($0) })
        }
        return Set(approved.map(\.id))
    }

    // MARK: Performing a step

    private func perform(_ step: PlanStep, plan: SetupPlan, values: Values,
                         onEvent: @escaping Events) async -> StepResult
    {
        let log = StepLog(paths: paths, site: site.id, step: step.id)
        let tail = LineTail(limit: 20)
        let emit: @Sendable (String) -> Void = { line in
            log.write(line)
            tail.add(line)
            onEvent(.output(step: step.id, line: line))
        }
        defer { log.close() }
        do {
            switch step.kind {
            case .runtime: try await installRuntime(step, plan: plan, emit: emit)
            case .packageManager: try await installTool(step, emit: emit)
            case .envFile: try copyEnvFile(plan: plan, emit: emit)
            case .envValues: try await fillEnvValues(step, plan: plan, values: values, emit: emit)
            case .application where step.command == nil: try createSQLiteFile(emit: emit)
            default:
                guard let command = step.command else { return .skipped("nothing to run") }
                emit("$ \(step.commandLine ?? command.joined(separator: " "))")
                let code = try await executor.run(
                    command, directory: directory, environment: environment(plan: plan), onLine: emit
                )
                if Task.isCancelled {
                    return .cancelled
                }
                guard code == 0 else { return .failed(exitCode: code, lastLines: tail.lines) }
                if SetupPlanner.isRemembered(step) {
                    try? SetupRunStore(paths: paths).record(site: site.id, step: step.id, command: command)
                }
            }
            return Task.isCancelled ? .cancelled : .done
        } catch is CancellationError {
            return .cancelled
        } catch {
            emit(error.localizedDescription)
            return Task.isCancelled ? .cancelled : .failed(exitCode: 1, lastLines: tail.lines)
        }
    }

    private func installRuntime(
        _ step: PlanStep,
        plan: SetupPlan,
        emit: @escaping @Sendable (String) -> Void
    ) async throws {
        guard let planned = plan.runtimes.first(where: { step.id == "runtime-\($0.requirement.kind.rawValue)" })
        else { throw RuntimeError.noSuchVersion(step.title) }
        try await manager.install(planned.requirement, onProgress: emit)
    }

    private func installTool(_ step: PlanStep, emit: @escaping @Sendable (String) -> Void) async throws {
        guard let tool = step.payload["tool"], let version = step.payload["version"]
        else { throw RuntimeError.noSuchVersion(step.title) }
        try await manager.mise.installTool(tool, version: version, onProgress: emit)
    }

    private func copyEnvFile(plan: SetupPlan, emit: @Sendable (String) -> Void) throws {
        guard let example = plan.env.example else { return }
        let target = directory.appendingPathComponent(".env")
        guard !FileManager.default.fileExists(atPath: target.path) else {
            emit(".env already exists; left as it is")
            return
        }
        try FileManager.default.copyItem(at: directory.appendingPathComponent(example), to: target)
        emit("Copied \(example) to .env")
        if !plan.env.emptyVariables.isEmpty {
            emit("Still empty: \(plan.env.emptyVariables.joined(separator: ", "))")
        }
    }

    /// Asks for the empty variables, writes the answers into `.env`, and remembers that it asked. Neither the values
    /// nor
    /// anything derived from them is logged or reported; only how many were saved.
    private func fillEnvValues(
        _ step: PlanStep, plan: SetupPlan, values: Values, emit: @Sendable (String) -> Void
    ) async throws {
        let target = directory.appendingPathComponent(".env")
        let source = FileManager.default.fileExists(atPath: target.path)
            ? EnvFile(contentsOf: target) : plan.env.example
            .map { EnvFile(contentsOf: directory.appendingPathComponent($0)) }
        let names = Set((step.payload["names"] ?? "").split(separator: ",").map(String.init))
        let prompts = source.map { EnvPrompts.prompts(for: $0).filter { names.contains($0.name) } } ?? []
        let answers = prompts.isEmpty ? [:] : await values(prompts)
        let allowed = answers.filter { names.contains($0.key) }
        let saved = try allowed.isEmpty ? [] : EnvEditor.apply(allowed, to: target)
        emit(saved
            .isEmpty ? "No values entered; placeholders kept" :
            "Saved \(saved.count) value\(saved.count == 1 ? "" : "s") to .env")
        if let command = step.memoryCommand {
            try? SetupRunStore(paths: paths).record(site: site.id, step: step.id, command: command)
        }
    }

    private func createSQLiteFile(emit: @Sendable (String) -> Void) throws {
        let file = directory.appendingPathComponent("database/database.sqlite")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: file.path) {
            FileManager.default.createFile(atPath: file.path, contents: nil)
        }
        emit("Created database/database.sqlite")
    }

    // MARK: Environment

    /// The site's runtime environment as the machine is now (earlier steps may have installed runtimes), with pnpm
    /// and Yarn on `PATH` and settings that keep tools from asking questions.
    private func environment(plan: SetupPlan) async -> [String: String] {
        let inventory = (try? manager.inventory()) ?? []
        let needs = plan.runtimes.map { planned -> RuntimeNeed in
            let candidates = inventory.filter { $0.kind == planned.requirement.kind }
            let version = RuntimeResolver.match(planned.requirement, among: candidates.map(\.version))
            return RuntimeNeed(
                requirement: planned.requirement, installedVersion: version,
                installPath: candidates.first { $0.version == version }?.path
            )
        }
        var environment = manager.environment(
            for: SiteRuntimePlan(siteID: site.id, needs: needs),
            base: baseEnvironment
        )
        let tools = ((try? manager.installedTools()) ?? []).filter { ["pnpm", "yarn"].contains($0.name) }
        if !tools.isEmpty {
            let current = environment["PATH"].map { [$0] } ?? []
            environment["PATH"] = (tools.map(\.binDirectory.path) + current).joined(separator: ":")
        }
        environment.merge([
            "CI": "1", "NO_COLOR": "1", "npm_config_yes": "true", "COMPOSER_NO_INTERACTION": "1",
            "DEBIAN_FRONTEND": "noninteractive",
        ]) { _, new in new }
        return environment
    }

    /// A plain next action for failures that look familiar.
    public static func advice(forFailureLines lines: [String], exitCode: Int32) -> String? {
        let text = lines.joined(separator: "\n").lowercased()
        if lines.contains(where: { $0.hasPrefix("$ /usr/bin/git") }) {
            return GitTool.explain(lines.joined(separator: "\n"))
        }
        if exitCode == 127 || text.contains("command not found") || text.contains("was not found") {
            return "A tool this step needs is not installed. Run the earlier steps first, or install it."
        }
        if text.contains("eaddrinuse") || text.contains("address already in use") {
            return "Another program is using that port. Stop it and run this step again."
        }
        if text.contains("eacces") || text.contains("permission denied") {
            return "The project folder or a file in it is not writable by you."
        }
        if ["enotfound", "etimedout", "econnreset", "could not resolve host", "network is unreachable"]
            .contains(where: text.contains)
        {
            return "The network looks unreachable. Check the connection and run this step again."
        }
        return nil
    }
}

/// The last few lines of a step's output.
private final class LineTail: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []
    private let limit: Int

    init(limit: Int) {
        self.limit = limit
    }

    var lines: [String] {
        lock.withLock { stored }
    }

    func add(_ line: String) {
        lock.withLock {
            stored.append(line)
            if stored.count > limit {
                stored.removeFirst(stored.count - limit)
            }
        }
    }
}

/// A step's output on disk, replaced by the next run of that step.
private final class StepLog: @unchecked Sendable {
    private let lock = NSLock()
    private var handle: FileHandle?

    init(paths: WarrenPaths, site: String, step: String) {
        let directory = paths.setupLogsDirectory.appendingPathComponent(site, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("\(step).log")
        FileManager.default.createFile(atPath: file.path, contents: nil)
        handle = try? FileHandle(forWritingTo: file)
    }

    func write(_ line: String) {
        lock.withLock { try? handle?.write(contentsOf: Data((line + "\n").utf8)) }
    }

    func close() {
        lock.withLock {
            try? handle?.close()
            handle = nil
        }
    }
}
