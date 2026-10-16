// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The plan that creates a project from a template: the runtime it needs, then the framework's own scaffolder run in
/// the new empty folder. The 012 runner runs it unchanged. Once it has run, the normal setup plan takes over.
public enum TemplatePlanner {
    public static func plan(_ template: ProjectTemplate, site: ResolvedSite,
                            inventory: [InstalledRuntime]) -> SetupPlan
    {
        let requirement = RuntimeRequirement(
            kind: template.runtime,
            requested: template.runtimeRequest,
            source: .warrenConfig
        )
        let installed = RuntimeResolver.match(
            requirement, among: inventory.filter { $0.kind == template.runtime }.map(\.version)
        )
        let runtime = PlannedRuntime(
            label: requirement.label, source: "needed by \(template.name)", installedVersion: installed,
            proposed: true, requirement: requirement
        )
        let runtimeID = "runtime-\(template.runtime.rawValue)"
        var steps: [PlanStep] = []
        if installed == nil {
            steps.append(PlanStep(
                id: runtimeID, kind: .runtime, title: "Install \(requirement.label)",
                detail: "Needed to run the \(template.name) scaffolder. Downloaded into Warren's folder.", command: nil,
                runsProjectCode: false, state: .todo, waitsFor: [], enabledByDefault: true
            ))
        }
        steps.append(PlanStep(
            id: "scaffold", kind: .scaffold, title: "Create the project with \(template.name)",
            detail: "Downloads and runs \(template.source). Installing dependencies comes after.",
            command: template.command, runsProjectCode: true, state: .todo,
            waitsFor: installed == nil ? [runtimeID] : [], enabledByDefault: true,
            payload: ["thirdParty": template.source]
        ))
        return SetupPlan(
            siteID: site.id, folder: site.path, detection: .unknown, runtimes: [runtime],
            env: EnvSummary(example: nil, envExists: false, emptyVariables: []), services: [], steps: steps
        )
    }
}
