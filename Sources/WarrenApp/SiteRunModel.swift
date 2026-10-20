// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import WarrenCore

/// Starts and stops sites for the window and the popover, and keeps what the site page shows about it: that a
/// start or stop is under way, why one failed, and the end of the log. See spec 015.
@MainActor
final class SiteRunModel: ObservableObject {
    @Published private(set) var busy: Set<String> = []
    @Published private(set) var failures: [String: String] = [:]
    @Published private(set) var log: [String] = []
    @Published var pendingApproval: PendingApproval?

    private let paths: WarrenPaths
    private let enabled: Bool
    private let onChange: () -> Void
    private let needsWindow: (String) -> Void

    /// `needsWindow` brings the main window forward, for a question asked from the popover.
    init(paths: WarrenPaths, enabled: Bool, needsWindow: @escaping (String) -> Void, onChange: @escaping () -> Void) {
        self.paths = paths
        self.enabled = enabled
        self.needsWindow = needsWindow
        self.onChange = onChange
    }

    func start(_ id: String) {
        run(id) { site, processes, approve in try await processes.start(site, approve: approve) }
    }

    func stop(_ id: String) {
        run(id) { site, processes, _ in try processes.stop(site) }
    }

    func restart(_ id: String) {
        run(id) { site, processes, approve in
            try processes.stop(site)
            try await processes.start(site, approve: approve)
        }
    }

    private func run(
        _ id: String,
        _ work: @escaping @Sendable (ResolvedSite, SiteProcesses, PlanRunner.Approval) async throws -> Void
    ) {
        guard enabled, !busy.contains(id) else { return }
        busy.insert(id)
        failures[id] = nil
        let paths = paths
        Task {
            let outcome: String? = await Task.detached {
                do {
                    let site = try SiteRegistry(paths: paths).show(id: id)
                    let approve: PlanRunner.Approval = { [weak self] steps in
                        await self?.ask(steps, site: site) ?? .none
                    }
                    try await work(site, SiteProcesses(paths: paths), approve)
                    return nil
                } catch StartError.declined {
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }.value
            busy.remove(id)
            failures[id] = outcome
            onChange()
        }
    }

    private func ask(_ steps: [PlanStep], site: ResolvedSite) async -> PlanApproval {
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                self.pendingApproval = PendingApproval(steps: steps, folder: site.path, continuation: continuation)
                self.needsWindow(site.id)
            }
        }
    }

    func resolve(_ approval: PendingApproval, approved: Set<String>, trust: Bool) {
        pendingApproval = nil
        approval.continuation.resume(returning: PlanApproval(approved: approved, trust: trust))
    }

    /// Reads the end of the site's log, for the Logs card.
    func loadLog(_ id: String) async {
        let paths = paths
        let lines = await Task.detached { SiteProcesses(paths: paths).lastLines(id, count: 14) }.value
        if lines != log {
            log = lines
        }
    }

    func logFile(_ id: String) -> URL {
        paths.siteLog(id)
    }
}
