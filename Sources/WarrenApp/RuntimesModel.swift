// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import WarrenCore

/// What the Runtimes page and the site cards show. The slow work (listing, sizing, installing) runs off the main
/// thread. Nothing here polls: it reloads when a page appears, when the sites change, and after each action.
@MainActor
final class RuntimesModel: ObservableObject {
    struct Installing: Equatable {
        let label: String
        var progress: String
    }

    private struct Loaded: Sendable {
        let inventory: [InstalledRuntime]
        let plans: [SiteRuntimePlan]
        let cacheBytes: Int64
    }

    @Published private(set) var installed: [InstalledRuntime] = []
    @Published private(set) var plans: [SiteRuntimePlan] = []
    @Published private(set) var releases: [RuntimeKind: [String]] = [:]
    @Published private(set) var cacheBytes: Int64 = 0
    @Published private(set) var loaded = false
    @Published private(set) var installing: Installing?
    @Published private(set) var loadingReleases: RuntimeKind?
    @Published var message: String?

    private let paths: WarrenPaths
    private let manager: RuntimeManager
    private let enabled: Bool
    private var installTask: Task<Void, Never>?

    /// With `enabled` false (demo mode) the model never touches the disk.
    init(paths: WarrenPaths, enabled: Bool) {
        self.paths = paths
        self.enabled = enabled
        manager = RuntimeManager(paths: paths)
    }

    func plan(for siteID: String) -> SiteRuntimePlan? {
        plans.first { $0.siteID == siteID }
    }

    func sites(using runtime: InstalledRuntime) -> [String] {
        RuntimeManager.sites(using: runtime, in: plans)
    }

    func reload() {
        guard enabled else { return }
        let paths = paths
        let manager = manager
        Task {
            let result = await Task.detached { () -> Loaded? in
                guard let inventory = try? manager.inventory() else { return nil }
                let sites = (try? SiteRegistry(paths: paths).list()) ?? []
                return Loaded(
                    inventory: inventory,
                    plans: sites.map { manager.plan(for: $0, installed: inventory) },
                    cacheBytes: PackageCaches.bytes(paths)
                )
            }.value
            guard let result else {
                message = "Could not read the installed runtimes."
                return
            }
            installed = result.inventory
            plans = result.plans
            cacheBytes = result.cacheBytes
            loaded = true
        }
    }

    // MARK: Actions

    func install(_ kind: RuntimeKind, version: String) {
        run(label: "\(kind.displayName) \(version)") { [manager] progress in
            try await manager.install(kind, version: version, onProgress: progress)
        }
    }

    func install(_ requirement: RuntimeRequirement) {
        run(label: requirement.label) { [manager] progress in
            try await manager.install(requirement, onProgress: progress)
        }
    }

    func cancelInstall() {
        installTask?.cancel()
    }

    private func run(
        label: String,
        _ work: @escaping @Sendable (@escaping @Sendable (String) -> Void) async throws -> Void
    ) {
        guard enabled, installing == nil else { return }
        message = nil
        installing = Installing(label: label, progress: "Starting…")
        installTask = Task { [weak self] in
            do {
                try await work { line in
                    Task { @MainActor in self?.installing?.progress = Self.shorten(line) }
                }
            } catch is CancellationError {
                self?.message = nil
            } catch {
                self?.message = "Could not install \(label): \(error.localizedDescription)"
            }
            self?.installing = nil
            self?.reload()
        }
    }

    /// Fetches the list of versions to pick from. The first call downloads mise.
    func loadReleases(for kind: RuntimeKind) {
        guard enabled, loadingReleases == nil else { return }
        loadingReleases = kind
        let manager = manager
        Task {
            do {
                let all = try await Task.detached { try await manager.available(kind) }.value
                // PHP lines are minors of one major, so every offered version is listed.
                releases[kind] = kind == .php ? all.reversed() : RuntimeManager.latestPerMajor(all)
            } catch {
                message = "Could not list \(kind.displayName) versions: \(error.localizedDescription)"
            }
            loadingReleases = nil
        }
    }

    func remove(_ runtime: InstalledRuntime) {
        guard enabled else { return }
        let manager = manager
        Task {
            do {
                try await Task.detached { try manager.remove(runtime) }.value
                message = nil
            } catch {
                message = "Could not remove \(runtime.id): \(error.localizedDescription)"
            }
            reload()
        }
    }

    func clearPackagesCache() {
        guard enabled else { return }
        let paths = paths
        Task {
            do {
                try await Task.detached { try PackageCaches.clear(paths) }.value
                message = nil
            } catch {
                message = "Could not clear the packages cache: \(error.localizedDescription)"
            }
            reload()
        }
    }

    /// A progress line for one row: mise's bar characters and colour codes are dropped.
    nonisolated static func shorten(_ line: String) -> String {
        let cleaned = line.replacingOccurrences(of: "mise ", with: "")
            .filter { !"█░▒▓".contains($0) }
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return cleaned.count > 70 ? String(cleaned.prefix(70)) + "…" : cleaned
    }
}

enum Size {
    static func text(_ bytes: Int64) -> String {
        bytes == 0 ? "0 KB" : ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
