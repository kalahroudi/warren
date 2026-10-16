// SPDX-License-Identifier: Apache-2.0

import Foundation

public extension RuntimeManager {
    /// What the plan's runtimes resolve to on this machine now (earlier steps may have installed some).
    func needs(for plan: SetupPlan) -> [RuntimeNeed] {
        let inventory = (try? inventory()) ?? []
        return plan.runtimes.map { planned in
            let candidates = inventory.filter { $0.kind == planned.requirement.kind }
            let version = RuntimeResolver.match(planned.requirement, among: candidates.map(\.version))
            return RuntimeNeed(
                requirement: planned.requirement, installedVersion: version,
                installPath: candidates.first { $0.version == version }?.path
            )
        }
    }

    /// The environment a site's commands run in: its runtimes first on `PATH`, pnpm and Yarn when installed, the shared
    /// package caches, and the project's own tool folders. The pnpm store setting is only set for pnpm projects,
    /// because other package managers warn about it.
    func siteEnvironment(plan: SetupPlan, base: [String: String]) -> [String: String] {
        var environment = environment(for: SiteRuntimePlan(siteID: plan.siteID, needs: needs(for: plan)), base: base)
        let tools = ((try? installedTools()) ?? []).filter { ["pnpm", "yarn"].contains($0.name) }
        var front = ["node_modules/.bin", ".venv/bin"].map { plan.folder + "/" + $0 }
        front += tools.map(\.binDirectory.path)
        if let path = environment["PATH"] {
            front.append(path)
        }
        environment["PATH"] = front.joined(separator: ":")
        if plan.detection.packageManager != .pnpm {
            environment["npm_config_store_dir"] = nil
        }
        return environment
    }
}
