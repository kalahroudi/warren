// SPDX-License-Identifier: Apache-2.0

import Foundation
import WarrenCore

let siteSetupUsage = """
usage: warren site setup <site> [--yes] [--dry-run]

  Runs the site's setup plan. Each command that runs code from the project asks first.
  --yes       approve every command in the plan (prints them first)
  --dry-run   print what would run and change nothing
"""

func runSiteSetup(_ arguments: [String], paths: WarrenPaths) async throws {
    let flags = Set(arguments.filter { $0.hasPrefix("--") })
    guard let id = arguments.first(where: { !$0.hasPrefix("--") }) else { throw CLIError(siteSetupUsage) }
    if let unknown = flags.first(where: { !["--yes", "--dry-run"].contains($0) }) {
        throw CLIError("unknown option \(unknown)\n\n\(siteSetupUsage)")
    }
    let registry = SiteRegistry(paths: paths)
    let site = try registry.show(id: id)
    let manager = RuntimeManager(paths: paths)
    let plan = SetupPlanner(paths: paths).plan(
        for: site, registered: true, inventory: (try? manager.inventory()) ?? [],
        tools: (try? manager.installedTools()) ?? []
    )
    let steps = PlanRunner.selectedSteps(plan)
    guard !steps.isEmpty else {
        print("nothing to do: \(site.id) is set up")
        return
    }
    let titles = Dictionary(uniqueKeysWithValues: plan.steps.map { ($0.id, $0.title) })
    print("setup for \(site.id):")
    for step in steps {
        print("  \(step.runsProjectCode ? "!" : "-") \(step.title)\(step.commandLine.map { "   $ \($0)" } ?? "")")
    }
    print("  (! runs code from this project)")
    if flags.contains("--dry-run") {
        return
    }

    let runner = PlanRunner(paths: paths, site: site, manager: manager)
    let assumeYes = flags.contains("--yes")
    let summary = await runner.run(
        plan: plan,
        approve: { askForApproval($0, assumeYes: assumeYes) },
        onEvent: { printEvent($0, titles: titles, logs: paths.setupLogsDirectory.appendingPathComponent(id)) }
    )
    guard summary.succeeded else {
        throw CLIError(summary.failed
            .isEmpty ? "setup is not finished: some steps were skipped or stopped" : "setup failed")
    }
    print("done")
}

/// Asks `[y/N]` for each command that runs project code, unless `--yes` was given.
private func askForApproval(_ steps: [PlanStep], assumeYes: Bool) -> PlanApproval {
    if assumeYes {
        return .all(steps)
    }
    var approved = Set<String>()
    for step in steps {
        print("run \(step.commandLine ?? step.title)? [y/N] ", terminator: "")
        if readLine()?.lowercased().hasPrefix("y") == true {
            approved.insert(step.id)
        }
    }
    return PlanApproval(approved: approved)
}

private func printEvent(_ event: PlanRunEvent, titles: [String: String], logs: URL) {
    switch event {
    case let .stepStarted(step): print("> \(titles[step] ?? step)")
    case let .output(_, line): print("    \(line)")
    case let .stepFinished(step, result): printResult(
            result,
            title: titles[step] ?? step,
            log: logs.appendingPathComponent("\(step).log")
        )
    case .finished: break
    }
}

private func printResult(_ result: StepResult, title: String, log: URL) {
    switch result {
    case .done: print("  done: \(title)")
    case let .skipped(reason): print("  skipped: \(title) (\(reason))")
    case .cancelled: print("  stopped: \(title)")
    case let .failed(code, lines):
        print("  FAILED (exit \(code)): \(title)")
        if let advice = PlanRunner.advice(forFailureLines: lines, exitCode: code) {
            print("  \(advice)")
        }
        print("  log: \(log.path)")
    }
}
