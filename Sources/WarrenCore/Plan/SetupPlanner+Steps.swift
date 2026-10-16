// SPDX-License-Identifier: Apache-2.0

import Foundation

extension SetupPlanner {
    // MARK: pnpm and Yarn

    /// pnpm and Yarn are installed through mise, at the version `packageManager` names, or the latest.
    func packageManagerStep(detection: FrameworkDetection, files: ProjectFiles, tools: [InstalledTool])
        -> PlanStep?
    {
        guard detection.packageManager == .pnpm || detection.packageManager == .yarn,
              let manager = detection.packageManager?.rawValue else { return nil }
        var version = "latest"
        if let field = files.packageManagerField, field.hasPrefix(manager + "@") {
            version = String(field.dropFirst(manager.count + 1).prefix { $0 != "+" })
        }
        let installed = tools.first { $0.name == manager && (version == "latest" || $0.version == version) }
        return PlanStep(
            id: "tool-\(manager)", kind: .packageManager,
            title: installed == nil ? "Install \(manager)" : "\(manager) installed",
            detail: installed.map { "Using \($0.version)." }
                ??
                "The project uses \(manager)\(version == "latest" ? "" : " \(version)"). Downloaded into Warren's folder.",
            command: nil, runsProjectCode: false, state: installed == nil ? .todo : .done, waitsFor: [],
            enabledByDefault: true, payload: ["tool": manager, "version": version]
        )
    }

    // MARK: Runtimes

    func plannedRuntimes(site: ResolvedSite, detection: FrameworkDetection, inventory: [InstalledRuntime])
        -> [PlannedRuntime]
    {
        var requirements = RuntimeResolver.requirements(for: site)
        var proposed = Set<RuntimeKind>()
        if let implied = impliedRuntime(detection), !requirements.contains(where: { $0.kind == implied }) {
            let version = implied == .node ? "lts" : "latest"
            requirements.append(RuntimeRequirement(kind: implied, requested: version, source: .warrenConfig))
            proposed.insert(implied)
        }
        return requirements.map { requirement in
            let installed = inventory.filter { $0.kind == requirement.kind }.map(\.version)
            return PlannedRuntime(
                label: requirement.label,
                source: proposed.contains(requirement.kind) ? "suggested" : requirement.source.label,
                installedVersion: RuntimeResolver.match(requirement, among: installed),
                proposed: proposed.contains(requirement.kind),
                requirement: requirement
            )
        }
    }

    /// The runtime a project needs even when it names no version.
    func impliedRuntime(_ detection: FrameworkDetection) -> RuntimeKind? {
        switch detection.packageManager {
        case .npm, .pnpm, .yarn: .node
        case .bun: .bun
        case .composer: .php
        case .uvCLI, .pip: .python
        case nil: detection.kind == .php ? .php : nil
        }
    }

    func runtimeSteps(_ runtimes: [PlannedRuntime]) -> [PlanStep] {
        runtimes.map { runtime in
            let name = runtime.label
            let detail = runtime.proposed
                ? "The project names no version, so Warren suggests the newest. Downloaded into Warren's folder."
                : "From \(runtime.source). Downloaded into Warren's folder."
            return PlanStep(
                id: "runtime-\(name.split(separator: " ").first.map { $0.lowercased() } ?? "runtime")",
                kind: .runtime, title: runtime.installedVersion == nil ? "Install \(name)" : "\(name) installed",
                detail: runtime.installedVersion.map { "Using \($0)." } ?? detail, command: nil,
                runsProjectCode: false, state: runtime.installedVersion == nil ? .todo : .done,
                waitsFor: [], enabledByDefault: true
            )
        }
    }

    // MARK: Steps the project suggests

    func optionalSteps(directory: URL, files: ProjectFiles, detection: FrameworkDetection) -> [PlanStep] {
        var result: [PlanStep] = []
        if let command = devContainerCommand(in: directory) {
            result.append(PlanStep(
                id: "optional-devcontainer", kind: .optional, title: "Run the project's dev container setup",
                detail: "postCreateCommand from devcontainer.json. Off unless you turn it on.",
                command: command, runsProjectCode: true, state: .todo, waitsFor: [], enabledByDefault: false
            ))
        }
        let manager = detection.packageManager ?? .npm
        if files.hasPackageJSON, let name = ["setup", "bootstrap"].first(where: { files.scripts[$0] != nil }) {
            result.append(PlanStep(
                id: "optional-script-\(name)", kind: .optional, title: "Run the project's \(name) script",
                detail: "The \"\(name)\" script from package.json. Off unless you turn it on.",
                command: [manager.rawValue, "run", name], runsProjectCode: true, state: .todo, waitsFor: [],
                enabledByDefault: false
            ))
        }
        return result
    }

    /// `postCreateCommand` from `devcontainer.json` (a string or an argument array). The file may carry comments.
    func devContainerCommand(in directory: URL) -> [String]? {
        for name in [".devcontainer/devcontainer.json", ".devcontainer.json"] {
            guard let text = try? String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
            else { continue }
            let cleaned = text.split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
            guard let json = try? JSONSerialization.jsonObject(with: Data(cleaned.utf8)) as? [String: Any]
            else { continue }
            if let text = json["postCreateCommand"] as? String, !text.isEmpty {
                return ["/bin/sh", "-c", text]
            }
            if let list = json["postCreateCommand"] as? [String], !list.isEmpty {
                return list
            }
        }
        return nil
    }

    func siteStep(_ site: ResolvedSite, registered: Bool) -> PlanStep {
        let domain = site.domains.first ?? "\(site.id).test"
        return PlanStep(
            id: "site", kind: .site, title: registered ? "Site added" : "Add the site at https://\(domain)",
            detail: registered ? "https://\(domain)" :
                "Registers the folder with Warren. Nothing in the project changes.",
            command: nil, runsProjectCode: false, state: registered ? .done : .todo, waitsFor: [],
            enabledByDefault: true
        )
    }
}
