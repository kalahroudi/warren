// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI
import WarrenCore

/// State of the Add site window: a chosen folder, what Warren found in it, the setup plan, and the name and
/// domain to register. Building the plan reads files only; nothing from the project runs. See spec 011.
@MainActor
final class AddSiteModel: ObservableObject {
    @Published private(set) var folder: URL?
    @Published var name = ""
    @Published var domain = ""
    @Published private(set) var plan: SetupPlan?
    /// Why the site cannot be added yet: an unreadable folder, a registered folder, a bad or taken domain.
    @Published private(set) var problem: String?
    @Published private(set) var adding = false

    private let paths: WarrenPaths
    private let onAdded: (ResolvedSite, Bool) -> Void
    private var generation = 0

    init(paths: WarrenPaths, onAdded: @escaping (ResolvedSite, Bool) -> Void) {
        self.paths = paths
        self.onAdded = onAdded
    }

    var canAdd: Bool {
        plan != nil && problem == nil && !adding && !domain.isEmpty
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose the project folder to add as a site."
        if panel.runModal() == .OK, let url = panel.url {
            use(folder: url)
        }
    }

    /// Takes a folder from the open panel or a drop, and fills in the default name and domain.
    func use(folder url: URL) {
        folder = url
        name = ""
        domain = ""
        refresh()
    }

    /// Recomputes the plan after a change to the name or domain. Empty fields are filled with the defaults.
    func refresh() {
        guard let folder else { return }
        generation += 1
        let current = generation
        let paths = paths
        let (typedName, typedDomain) = (name, domain)
        Task {
            let result = await Task.detached { Self.build(
                folder: folder,
                name: typedName,
                domain: typedDomain,
                paths: paths
            ) }.value
            guard current == generation else { return }
            plan = result.plan
            problem = result.problem
            if let site = result.site {
                if name.isEmpty {
                    name = site.name
                }
                if domain.isEmpty {
                    domain = site.domains.first ?? ""
                }
            }
        }
    }

    private struct Built: Sendable {
        let site: ResolvedSite?
        let plan: SetupPlan?
        let problem: String?
    }

    private nonisolated static func build(folder: URL, name: String, domain: String, paths: WarrenPaths) -> Built {
        let registry = SiteRegistry(paths: paths)
        let inventory = (try? RuntimeManager(paths: paths).inventory()) ?? []
        var problem: String?
        var site: ResolvedSite?
        do {
            site = try registry.preview(
                path: folder.path, name: name,
                domains: domain.isEmpty ? nil : [domain.trimmingCharacters(in: .whitespaces)]
            )
        } catch {
            problem = error.localizedDescription
            // Still show the plan with the default settings, unless the folder itself is the problem.
            site = try? registry.preview(path: folder.path)
        }
        let plan = site.map { SetupPlanner(paths: paths).plan(for: $0, registered: false, inventory: inventory) }
        return Built(site: site, plan: plan, problem: problem)
    }

    func add(runSetup: Bool = false) {
        guard let folder, canAdd else { return }
        adding = true
        let (paths, name, domain) = (paths, name, domain.trimmingCharacters(in: .whitespaces))
        Task {
            do {
                let site = try await Task.detached {
                    let site = try SiteRegistry(paths: paths).add(path: folder.path, name: name, domains: [domain])
                    // Bring a running proxy and DNS server up to date, as `warren site add` does. A failure here
                    // does not undo the registration.
                    _ = NetworkServices(paths: paths).applyRegistryChange()
                    return site
                }.value
                adding = false
                onAdded(site, runSetup)
            } catch {
                adding = false
                problem = error.localizedDescription
            }
        }
    }
}
