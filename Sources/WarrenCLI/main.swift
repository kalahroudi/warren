// SPDX-License-Identifier: Apache-2.0

import Foundation
import WarrenCore

let usage = """
usage: warren <command>

  site add <path>              register a folder as a site
  site list [--json]           list registered sites
  site show <id> [--json]      show one site's resolved settings
  site detect <site or folder> [--json]  what the project is and how it starts
  site plan <site or folder> [--json]  what it takes to run the project
  site setup <id> [--yes]      run the setup plan (asks before running project code)
  site new <template> <name>   create a project from a template or --blank <kind> (see: warren template list)
  template list [--json]       the starters Warren can create
  site remove <id>             unregister a site (never deletes files)
  proxy <command>              local HTTPS proxy (see: warren proxy)
  dns <command>                local DNS for your domains (see: warren dns)
  runtime <command>            Node, Bun, PHP and Python versions (see: warren runtime)
  setup status                 which setup steps are done
  --version                    print the version

Warren keeps its state in ~/Warren (override with WARREN_HOME).
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("warren: \(message)\n".utf8))
    exit(1)
}

func printJSON(_ value: some Encodable) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(value),
          let text = String(data: data, encoding: .utf8) else { fail("could not encode output") }
    print(text)
}

func describe(_ site: ResolvedSite) {
    print("\(site.id)  \(site.domains.joined(separator: ", "))  \(site.path)")
    for problem in site.problems {
        print("  problem: \(problem)")
    }
    for warning in site.warnings {
        print("  warning: \(warning)")
    }
}

/// A registered site's id, or a folder.
func detect(_ target: String, registry: SiteRegistry) throws -> FrameworkDetection {
    if let site = try? registry.show(id: target) {
        return FrameworkDetector.detect(site: site)
    }
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: target, isDirectory: &isDirectory), isDirectory.boolValue else {
        throw CLIError("'\(target)' is neither a registered site nor a folder")
    }
    let directory = URL(fileURLWithPath: target, isDirectory: true).standardizedFileURL
    let config = try? ProjectConfig.load(from: directory)
    return FrameworkDetector.detect(in: directory, command: config?.command, domains: config?.domains ?? [])
}

/// The plan for a registered site, or for a folder that is not registered yet.
func setupPlan(_ target: String, registry: SiteRegistry) throws -> SetupPlan {
    let inventory = (try? RuntimeManager(paths: registry.paths).inventory()) ?? []
    let planner = SetupPlanner(paths: registry.paths)
    if let site = try? registry.show(id: target) {
        return planner.plan(for: site, registered: true, inventory: inventory)
    }
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: target, isDirectory: &isDirectory), isDirectory.boolValue else {
        throw CLIError("'\(target)' is neither a registered site nor a folder")
    }
    let site = try registry.preview(path: target)
    return planner.plan(for: site, registered: false, inventory: inventory)
}

func describe(_ plan: SetupPlan) {
    describe(plan.detection)
    print("  setup plan:")
    for step in plan.steps {
        let mark: String = switch step.state {
        case .done: "[x]"
        case .todo: step.enabledByDefault ? "[ ]" : "[-]"
        case .waiting: "[~]"
        }
        print("    \(mark) \(step.title)\(step.runsProjectCode && !step.state.isDone ? "  (runs project code)" : "")")
        if let command = step.commandLine, !step.state.isDone {
            print("          $ \(command)")
        }
        if case let .waiting(reason) = step.state {
            print("          waiting: \(reason)")
        }
    }
}

func describe(_ detection: FrameworkDetection) {
    print("  framework: \(detection.displayName)")
    print("  starts with: \(detection.startLine)")
    if let manager = detection.packageManager {
        print("  package manager: \(manager.rawValue)")
    }
    for note in detection.notes {
        print("  note: \(note)")
    }
}

func runSite(_ arguments: [String], registry: SiteRegistry) throws {
    let json = arguments.contains("--json")
    let rest = arguments.filter { $0 != "--json" }
    switch (rest.first, rest.dropFirst().first) {
    case let ("add", path?):
        let site = try registry.add(path: path)
        describe(site)
        syncRunningNetwork(paths: registry.paths)
    case ("list", nil):
        let sites = try registry.list()
        if json {
            printJSON(sites)
        } else if sites.isEmpty {
            print("no sites registered")
        } else {
            sites.forEach(describe)
        }
    case let ("show", id?):
        let site = try registry.show(id: id)
        if json {
            printJSON(site)
        } else {
            describe(site)
            describe(FrameworkDetector.detect(site: site))
        }
    case let ("plan", target?):
        let plan = try setupPlan(target, registry: registry)
        if json {
            printJSON(plan)
        } else {
            describe(plan)
        }
    case let ("detect", target?):
        let detection = try detect(target, registry: registry)
        if json {
            printJSON(detection)
        } else {
            describe(detection)
        }
    case let ("remove", id?):
        try registry.remove(id: id)
        print("removed \(id)")
        syncRunningNetwork(paths: registry.paths)
    default:
        fail("unknown or incomplete command\n\n\(usage)")
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "--version": print("warren \(Warren.version)")
case "template":
    if arguments.dropFirst().first == "list" {
        listTemplates(json: arguments.contains("--json"))
    } else {
        fail(newProjectUsage)
    }
case "site" where arguments.dropFirst().first == "new":
    do {
        try await newProject(Array(arguments.dropFirst(2)), paths: .fromEnvironment())
    } catch {
        fail(error.localizedDescription)
    }
case "site" where arguments.dropFirst().first == "setup":
    do {
        try await runSiteSetup(Array(arguments.dropFirst(2)), paths: .fromEnvironment())
    } catch {
        fail(error.localizedDescription)
    }
case "site":
    do {
        try runSite(Array(arguments.dropFirst()), registry: SiteRegistry(paths: .fromEnvironment()))
    } catch {
        fail(error.localizedDescription)
    }
case "proxy":
    do {
        try await runProxy(Array(arguments.dropFirst()), paths: .fromEnvironment())
    } catch {
        fail(error.localizedDescription)
    }
case "dns":
    do {
        try await runDNS(Array(arguments.dropFirst()), paths: .fromEnvironment())
    } catch {
        fail(error.localizedDescription)
    }
case "runtime":
    do {
        try await runRuntime(Array(arguments.dropFirst()), paths: .fromEnvironment())
    } catch {
        fail(error.localizedDescription)
    }
case "setup":
    do {
        try runSetup(Array(arguments.dropFirst()), paths: .fromEnvironment())
    } catch {
        fail(error.localizedDescription)
    }
case nil, "help", "--help", "-h": print(usage)
default: fail("unknown command '\(arguments[0])'\n\n\(usage)")
}
