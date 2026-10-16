// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Builds the setup plan for a project. Reads files and the machine's state; never runs anything from the project.
public struct SetupPlanner: Sendable {
    public let paths: WarrenPaths

    public init(paths: WarrenPaths) {
        self.paths = paths
    }

    /// `registered` says whether the site is already in the registry, which decides the last step's state.
    public func plan(for site: ResolvedSite, registered: Bool, inventory: [InstalledRuntime]) -> SetupPlan {
        let directory = URL(fileURLWithPath: site.path, isDirectory: true)
        let files = ProjectFiles(directory: directory)
        let detection = FrameworkDetector.detect(site: site)
        let envInfo = readEnv(in: directory)
        let services = envInfo.example.map { ServiceHints.needs(in: $0.file, file: $0.name) } ?? []

        let runtimes = plannedRuntimes(site: site, detection: detection, inventory: inventory)
        var steps: [PlanStep] = []
        steps += runtimeSteps(runtimes)
        let runtimeIDs = steps.filter { !$0.state.isDone }.map(\.id)

        if let dependencies = dependenciesStep(detection: detection, files: files, waitsFor: runtimeIDs) {
            steps.append(dependencies)
        }
        let envStep = envFileStep(envInfo, directory: directory)
        if let envStep {
            steps.append(envStep)
        }
        let serviceSteps = services.map(serviceStep)
        steps += serviceSteps
        steps += applicationSteps(detection: detection, env: envInfo, directory: directory, steps: steps)
        steps += databaseSteps(detection: detection, steps: steps)
        steps += optionalSteps(directory: directory, files: files, detection: detection)
        steps.append(siteStep(site, registered: registered))

        let summary = EnvSummary(
            example: envInfo.example?.name,
            envExists: envInfo.current != nil,
            emptyVariables: envInfo.example?.file.emptyKeys ?? []
        )
        return SetupPlan(
            siteID: site.id, folder: site.path, detection: detection, runtimes: runtimes,
            env: summary, services: services, steps: steps
        )
    }

    // MARK: Runtimes

    private func plannedRuntimes(site: ResolvedSite, detection: FrameworkDetection, inventory: [InstalledRuntime])
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
                proposed: proposed.contains(requirement.kind)
            )
        }
    }

    /// The runtime a project needs even when it names no version.
    private func impliedRuntime(_ detection: FrameworkDetection) -> RuntimeKind? {
        switch detection.packageManager {
        case .npm, .pnpm, .yarn: .node
        case .bun: .bun
        case .composer: .php
        case .uvCLI, .pip: .python
        case nil: detection.kind == .php ? .php : nil
        }
    }

    private func runtimeSteps(_ runtimes: [PlannedRuntime]) -> [PlanStep] {
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

    // MARK: Dependencies

    private func dependenciesStep(detection: FrameworkDetection, files: ProjectFiles,
                                  waitsFor: [String]) -> PlanStep?
    {
        guard let manager = detection.packageManager else { return nil }
        let command: [String]
        let folder: String
        let lockfile: String?
        switch manager {
        case .npm:
            let locked = files.exists("package-lock.json")
            command = locked ? ["npm", "ci"] : ["npm", "install"]
            (folder, lockfile) = ("node_modules", locked ? "package-lock.json" : nil)
        case .pnpm:
            let locked = files.exists("pnpm-lock.yaml")
            command = locked ? ["pnpm", "install", "--frozen-lockfile"] : ["pnpm", "install"]
            (folder, lockfile) = ("node_modules", locked ? "pnpm-lock.yaml" : nil)
        case .yarn:
            (command, folder, lockfile) = (
                ["yarn", "install"],
                "node_modules",
                files.exists("yarn.lock") ? "yarn.lock" : nil
            )
        case .bun:
            (command, folder) = (["bun", "install"], "node_modules")
            lockfile = ["bun.lock", "bun.lockb"].first(where: files.exists)
        case .composer:
            (command, folder, lockfile) = (
                ["composer", "install"],
                "vendor",
                files.exists("composer.lock") ? "composer.lock" : nil
            )
        case .uvCLI:
            (command, folder, lockfile) = (["uv", "sync"], ".venv", files.exists("uv.lock") ? "uv.lock" : nil)
        case .pip:
            guard files.exists("requirements.txt") else { return nil }
            (command, folder, lockfile) = (["uv", "pip", "install", "-r", "requirements.txt"], ".venv", nil)
        }
        let done = isInstalled(folder, lockfile: lockfile, in: files)
        let detail = done ? "\(folder) is up to date." : dependenciesDetail(manager, hasLockfile: lockfile != nil)
        return PlanStep(
            id: "dependencies", kind: .dependencies,
            title: done ? "Dependencies installed" : "Install dependencies", detail: detail,
            command: manager == .pip ? ["uv", "venv", "&&"] + command : command, runsProjectCode: true,
            state: done ? .done : .todo, waitsFor: waitsFor, enabledByDefault: true
        )
    }

    private func dependenciesDetail(_ manager: PackageManager, hasLockfile: Bool) -> String {
        var text = "Runs \(manager.rawValue) in the project folder. Install scripts from the project run."
        if manager == .npm, !hasLockfile {
            text += " This creates package-lock.json in the project."
        }
        return text
    }

    /// The folder exists and is not older than the lockfile.
    private func isInstalled(_ folder: String, lockfile: String?, in files: ProjectFiles) -> Bool {
        let fileManager = FileManager.default
        let installed = files.directory.appendingPathComponent(folder)
        guard fileManager.fileExists(atPath: installed.path) else { return false }
        guard let lockfile,
              let lockDate = try? fileManager
              .attributesOfItem(atPath: files.directory.appendingPathComponent(lockfile)
                  .path)[.modificationDate] as? Date,
              let folderDate = try? fileManager.attributesOfItem(atPath: installed.path)[.modificationDate] as? Date
        else { return true }
        return folderDate >= lockDate
    }

    // MARK: Environment and services

    private struct EnvInfo {
        var example: (name: String, file: EnvFile)?
        var current: EnvFile?
    }

    private func readEnv(in directory: URL) -> EnvInfo {
        var info = EnvInfo()
        let fileManager = FileManager.default
        if let name = EnvFile.exampleNames
            .first(where: { fileManager.fileExists(atPath: directory.appendingPathComponent($0).path) })
        {
            info.example = (name, EnvFile(contentsOf: directory.appendingPathComponent(name)))
        }
        let current = directory.appendingPathComponent(".env")
        if fileManager.fileExists(atPath: current.path) {
            info.current = EnvFile(contentsOf: current)
        }
        return info
    }

    private func envFileStep(_ info: EnvInfo, directory _: URL) -> PlanStep? {
        guard let example = info.example else { return nil }
        if info.current != nil {
            return PlanStep(
                id: "env", kind: .envFile, title: ".env exists", detail: "Your .env is left as it is.", command: nil,
                runsProjectCode: false, state: .done, waitsFor: [], enabledByDefault: true
            )
        }
        let empty = example.file.emptyKeys
        var detail = "Copies \(example.name) to .env."
        if !empty.isEmpty {
            let shown = empty.prefix(4).joined(separator: ", ")
            detail += " Still empty afterwards: \(shown)\(empty.count > 4 ? " and \(empty.count - 4) more" : "")."
        }
        return PlanStep(
            id: "env", kind: .envFile, title: "Create .env", detail: detail, command: nil,
            runsProjectCode: false, state: .todo, waitsFor: [], enabledByDefault: true
        )
    }

    private func serviceStep(_ need: ServiceNeed) -> PlanStep {
        PlanStep(
            id: "service-\(need.id)", kind: .service, title: "Start \(need.name)",
            detail: "Wanted because \(need.evidence).", command: nil, runsProjectCode: false,
            state: .waiting("arrives with the service manager"), waitsFor: [], enabledByDefault: true
        )
    }

    // MARK: Application setup and database

    private func applicationSteps(
        detection: FrameworkDetection, env: EnvInfo, directory: URL, steps: [PlanStep]
    ) -> [PlanStep] {
        guard detection.id == "laravel" else { return [] }
        let source = env.current ?? env.example?.file
        var result: [PlanStep] = []
        let hasKey = !(env.current?["APP_KEY"] ?? "").isEmpty
        let pending = steps.filter { !$0.state.isDone && ["dependencies", "env"].contains($0.id) }.map(\.id)
        result.append(PlanStep(
            id: "app-key", kind: .application, title: hasKey ? "Application key set" : "Generate the application key",
            detail: hasKey ? "APP_KEY is already in .env." : "Runs artisan to fill APP_KEY in .env.",
            command: ["php", "artisan", "key:generate"], runsProjectCode: true,
            state: hasKey ? .done : .todo, waitsFor: pending, enabledByDefault: true
        ))
        if source?["DB_CONNECTION"]?.lowercased() == "sqlite" {
            let file = directory.appendingPathComponent("database/database.sqlite")
            let exists = FileManager.default.fileExists(atPath: file.path)
            result.append(PlanStep(
                id: "sqlite", kind: .application,
                title: exists ? "SQLite database exists" : "Create the SQLite database",
                detail: "database/database.sqlite", command: nil, runsProjectCode: false,
                state: exists ? .done : .todo, waitsFor: [], enabledByDefault: true
            ))
        }
        return result
    }

    private func databaseSteps(detection: FrameworkDetection, steps: [PlanStep]) -> [PlanStep] {
        let command: [String]
        switch detection.id {
        case "laravel": command = ["php", "artisan", "migrate", "--no-interaction"]
        case "django": command = ["python", "manage.py", "migrate", "--no-input"]
        default: return []
        }
        let before = steps.filter { ["dependencies", "env", "app-key", "sqlite"].contains($0.id) && !$0.state.isDone }
        let waitingService = steps.first { $0.kind == .service && !$0.state.isDone }
        let state: PlanStepState = waitingService
            .map { .waiting("after \($0.title.replacingOccurrences(of: "Start ", with: ""))") } ?? .todo
        return [PlanStep(
            id: "migrate", kind: .database, title: "Set up the database tables",
            detail: "Runs the project's migrations. Safe to run again.", command: command, runsProjectCode: true,
            state: state, waitsFor: before.map(\.id) + (waitingService.map { [$0.id] } ?? []), enabledByDefault: true
        )]
    }

    // MARK: Steps the project suggests

    private func optionalSteps(directory: URL, files: ProjectFiles, detection: FrameworkDetection) -> [PlanStep] {
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

    private func siteStep(_ site: ResolvedSite, registered: Bool) -> PlanStep {
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
