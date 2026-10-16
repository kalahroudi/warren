// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import WarrenCore

/// Progress of one step in a run.
struct StepProgress: Equatable {
    enum Status: Equatable { case waiting, running, done, failed, skipped, cancelled }

    var status = Status.waiting
    /// The last lines of output, newest last.
    var lines: [String] = []
    var note: String?
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

    /// Starts a run for a registered site, planning from the machine as it is now.
    func start(siteID id: String, optional: Set<String> = []) {
        guard enabled, !running else { return }
        siteID = id
        steps = []
        progress = [:]
        summary = nil
        running = true
        let paths = paths
        task = Task { [weak self] in
            guard let prepared = await Task.detached(operation: { Self.prepare(id, paths: paths) }).value else {
                self?.running = false
                return
            }
            guard let self else { return }
            steps = PlanRunner.selectedSteps(prepared.plan, optional: optional)
            progress = Dictionary(uniqueKeysWithValues: steps.map { ($0.id, StepProgress()) })
            let runner = PlanRunner(paths: paths, site: prepared.site)
            let folder = prepared.site.path
            let result = await runner.run(plan: prepared.plan, optional: optional, approve: { [weak self] risky in
                await withCheckedContinuation { continuation in
                    Task { @MainActor in
                        guard let self else { return continuation.resume(returning: .none) }
                        self.pendingApproval = PendingApproval(steps: risky, folder: folder, continuation: continuation)
                    }
                }
            }, onEvent: { [weak self] event in
                Task { @MainActor in self?.apply(event) }
            })
            summary = result
            running = false
            loadTrust(id)
            onFinished()
        }
    }

    private nonisolated static func prepare(_ id: String,
                                            paths: WarrenPaths) -> (site: ResolvedSite, plan: SetupPlan)?
    {
        guard let site = try? SiteRegistry(paths: paths).show(id: id) else { return nil }
        let manager = RuntimeManager(paths: paths)
        let plan = SetupPlanner(paths: paths).plan(
            for: site, registered: true, inventory: (try? manager.inventory()) ?? [],
            tools: (try? manager.installedTools()) ?? []
        )
        return (site, plan)
    }

    /// Answers the approval sheet. Approved steps run; the rest are skipped.
    func resolve(_ approval: PendingApproval, approved: Set<String>, trust: Bool) {
        pendingApproval = nil
        approval.continuation.resume(returning: PlanApproval(approved: approved, trust: trust))
    }

    func stop() {
        task?.cancel()
        if let pending = pendingApproval {
            resolve(pending, approved: [], trust: false)
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
