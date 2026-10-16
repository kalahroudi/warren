// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import WarrenCore

/// What fills a new project's folder before its normal setup plan: a template's scaffolder or a repository clone.
enum FirstRun {
    case template(ProjectTemplate)
    case clone(RepositoryReference, branch: String?)
}

/// Progress of one step in a run.
struct StepProgress: Equatable {
    enum Status: Equatable { case waiting, running, done, failed, skipped, cancelled }

    var status = Status.waiting
    /// The last lines of output, newest last.
    var lines: [String] = []
    var note: String?
}

/// Variables waiting for the user's answers.
struct PendingValues: Identifiable {
    let id = UUID()
    let prompts: [EnvPrompt]
    let domain: String
    let envIsIgnored: Bool
    let continuation: CheckedContinuation<[String: String], Never>
}

/// Steps waiting for the user's decision before any project code runs.
struct PendingApproval: Identifiable {
    let id = UUID()
    let steps: [PlanStep]
    let folder: String
    let continuation: CheckedContinuation<PlanApproval, Never>
}

/// Runs a site's setup plan and keeps what the Setup card shows: per-step progress, the approval question, the
/// result. One run at a time. See spec 012.
@MainActor
final class SetupRunModel: ObservableObject {
    @Published private(set) var siteID: String?
    @Published private(set) var steps: [PlanStep] = []
    @Published private(set) var progress: [String: StepProgress] = [:]
    @Published private(set) var running = false
    @Published private(set) var summary: RunSummary?
    @Published var pendingApproval: PendingApproval?
    @Published var pendingValues: PendingValues?
    @Published private(set) var trusted: [String: Int] = [:]

    private let paths: WarrenPaths
    private let enabled: Bool
    private let onFinished: () -> Void
    private var task: Task<Void, Never>?

    init(paths: WarrenPaths, enabled: Bool, onFinished: @escaping () -> Void) {
        self.paths = paths
        self.enabled = enabled
        self.onFinished = onFinished
    }

    func isShowing(_ id: String) -> Bool {
        siteID == id && !steps.isEmpty
    }

    /// Starts a run for a registered site, planning from the machine as it is now. For a new project made from a
    /// template, the scaffolder runs first and the project's normal plan follows once it has finished.
    func start(siteID id: String, first: FirstRun? = nil, optional: Set<String> = []) {
        guard enabled, !running else { return }
        siteID = id
        steps = []
        progress = [:]
        summary = nil
        running = true
        let paths = paths
        task = Task { [weak self] in
            guard let prepared = await Task.detached(operation: { Self.prepare(id, first: first, paths: paths) })
                .value
            else {
                self?.running = false
                return
            }
            guard let self else { return }
            var result = await execute(prepared.plan, site: prepared.site, optional: optional)
            if first != nil, result.succeeded,
               let next = await Task.detached(operation: { Self.prepare(id, first: nil, paths: paths) }).value
            {
                result = await execute(next.plan, site: next.site, optional: [])
            }
            summary = result
            running = false
            loadTrust(id)
            onFinished()
        }
    }

    /// Runs one plan, showing its steps and progress.
    private func execute(_ plan: SetupPlan, site: ResolvedSite, optional: Set<String>) async -> RunSummary {
        steps = PlanRunner.selectedSteps(plan, optional: optional)
        progress = Dictionary(uniqueKeysWithValues: steps.map { ($0.id, StepProgress()) })
        let folder = site.path
        let domain = site.domains.first ?? "\(site.id).test"
        let ignored = EnvEditor.isIgnored(in: URL(fileURLWithPath: folder))
        return await PlanRunner(paths: paths, site: site).run(
            plan: plan,
            optional: optional,
            approve: { [weak self] risky in
                await withCheckedContinuation { continuation in
                    Task { @MainActor in
                        guard let self else { return continuation.resume(returning: .none) }
                        self.pendingApproval = PendingApproval(steps: risky, folder: folder, continuation: continuation)
                    }
                }
            },
            values: { [weak self] prompts in
                await withCheckedContinuation { continuation in
                    Task { @MainActor in
                        guard let self else { return continuation.resume(returning: [:]) }
                        self.pendingValues = PendingValues(
                            prompts: prompts, domain: domain, envIsIgnored: ignored, continuation: continuation
                        )
                    }
                }
            },
            onEvent: { [weak self] event in
                Task { @MainActor in self?.apply(event) }
            }
        )
    }

    private nonisolated static func prepare(
        _ id: String, first: FirstRun?, paths: WarrenPaths
    ) -> (site: ResolvedSite, plan: SetupPlan)? {
        guard let site = try? SiteRegistry(paths: paths).show(id: id) else { return nil }
        let manager = RuntimeManager(paths: paths)
        let inventory = (try? manager.inventory()) ?? []
        switch first {
        case let .template(template)?:
            return (site, TemplatePlanner.plan(template, site: site, inventory: inventory))
        case let .clone(reference, branch)?:
            return (site, ClonePlanner.plan(reference, branch: branch, site: site))
        case nil:
            break
        }
        let plan = SetupPlanner(paths: paths).plan(
            for: site, registered: true, inventory: inventory, tools: (try? manager.installedTools()) ?? []
        )
        return (site, plan)
    }

    /// Answers the approval sheet. Approved steps run; the rest are skipped.
    func resolve(_ approval: PendingApproval, approved: Set<String>, trust: Bool) {
        pendingApproval = nil
        approval.continuation.resume(returning: PlanApproval(approved: approved, trust: trust))
    }

    /// Answers the values sheet. An empty dictionary keeps the placeholders.
    func resolve(_ pending: PendingValues, values: [String: String]) {
        pendingValues = nil
        pending.continuation.resume(returning: values)
    }

    func stop() {
        task?.cancel()
        if let pending = pendingApproval {
            resolve(pending, approved: [], trust: false)
        }
        if let pending = pendingValues {
            resolve(pending, values: [:])
        }
    }

    private func apply(_ event: PlanRunEvent) {
        switch event {
        case let .stepStarted(id):
            progress[id, default: StepProgress()].status = .running
        case let .output(id, line):
            var entry = progress[id, default: StepProgress()]
            // mise draws progress bars; keep one tidy line for the steps that run it.
            let isInstall = steps.first { $0.id == id }
                .map { $0.kind == .runtime || $0.kind == .packageManager } ?? false
            entry.lines.append(isInstall ? RuntimesModel.shorten(line) : line)
            if entry.lines.count > 200 {
                entry.lines.removeFirst(entry.lines.count - 200)
            }
            progress[id] = entry
        case let .stepFinished(id, result):
            var entry = progress[id, default: StepProgress()]
            switch result {
            case .done: entry.status = .done
            case let .failed(code, lines):
                entry.status = .failed
                entry.note = PlanRunner.advice(forFailureLines: lines, exitCode: code) ?? "It exited with status \(code)."
            case let .skipped(reason):
                entry.status = .skipped
                entry.note = reason
            case .cancelled: entry.status = .cancelled
            }
            progress[id] = entry
        case .finished:
            break
        }
    }

    // MARK: Trust

    func loadTrust(_ id: String) {
        let paths = paths
        Task {
            let count = await Task.detached { (try? SiteRegistry(paths: paths).trustedCommands(id: id).count) ?? 0 }
                .value
            trusted[id] = count
        }
    }

    func stopTrusting(_ id: String) {
        let paths = paths
        Task {
            await Task.detached { try? SiteRegistry(paths: paths).setTrustedCommands(id: id, []) }.value
            trusted[id] = 0
        }
    }
}
