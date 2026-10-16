// SPDX-License-Identifier: Apache-2.0

import Foundation
import WarrenCore

let newProjectUsage = """
usage: warren template list [--json]
       warren site new <template> <name> [--location <folder>] [--domain <name>] [--yes]
       warren site new --blank <static|node|bun|php|python> <name> [--location <folder>] [--domain <name>] [--yes]

  Creates a folder, registers it as a site, and runs its setup. Commands that download or run code ask first;
  --yes approves them after printing them.
"""

private struct TemplateOutput: Encodable {
    let id: String
    let name: String
    let summary: String
    let runtime: String
    let command: [String]
}

func listTemplates(json: Bool) {
    if json {
        printJSON(ProjectTemplate.all.map {
            TemplateOutput(
                id: $0.id,
                name: $0.name,
                summary: $0.summary,
                runtime: $0.runtime.rawValue,
                command: $0.command
            )
        })
        return
    }
    for template in ProjectTemplate.all {
        print("\(template.id.padding(toLength: 12, withPad: " ", startingAt: 0))\(template.name): \(template.summary)")
    }
    print("\nblank kinds: \(BlankKind.allCases.map(\.rawValue).joined(separator: ", "))")
}

func newProject(_ arguments: [String], paths: WarrenPaths) async throws {
    var rest = arguments
    func option(_ name: String) -> String? {
        guard let index = rest.firstIndex(of: name), index + 1 < rest.count else { return nil }
        let value = rest[index + 1]
        rest.removeSubrange(index ... index + 1)
        return value
    }
    let assumeYes = rest.contains("--yes")
    rest.removeAll { $0 == "--yes" }
    let location = option("--location").map { URL(
        fileURLWithPath: ($0 as NSString).expandingTildeInPath,
        isDirectory: true
    ) }
    let domain = option("--domain")
    let blankKind = option("--blank")

    let source: NewProjectSource
    let name: String
    if let blankKind {
        guard let kind = BlankKind(rawValue: blankKind), let first = rest.first else { throw CLIError(newProjectUsage) }
        (source, name) = (.blank(kind), first)
    } else {
        guard rest.count >= 2, let template = ProjectTemplate.named(rest[0])
        else { throw CLIError("unknown template '\(rest.first ?? "")'\n\n\(newProjectUsage)") }
        (source, name) = (.template(template), rest[1])
    }
    let request = NewProjectRequest(
        name: name, location: location ?? ProjectCreator.defaultLocation, domain: domain, source: source
    )
    let site = try ProjectCreator(paths: paths).create(request)
    syncRunningNetwork(paths: paths)
    print("created \(site.path) as \(site.id) (\(site.domains.joined(separator: ", ")))")

    let manager = RuntimeManager(paths: paths)
    if case let .template(template) = source {
        let plan = TemplatePlanner.plan(template, site: site, inventory: (try? manager.inventory()) ?? [])
        let summary = await execute(plan, site: site, paths: paths, assumeYes: assumeYes)
        guard summary.succeeded else { throw CLIError("creating the project did not finish") }
    }
    let plan = SetupPlanner(paths: paths).plan(
        for: site, registered: true, inventory: (try? manager.inventory()) ?? [],
        tools: (try? manager.installedTools()) ?? []
    )
    guard !PlanRunner.selectedSteps(plan).isEmpty else {
        print("done")
        return
    }
    let summary = await execute(plan, site: site, paths: paths, assumeYes: assumeYes)
    guard summary.succeeded else { throw CLIError("setup is not finished: some steps were skipped, stopped or failed") }
    print("done")
}
