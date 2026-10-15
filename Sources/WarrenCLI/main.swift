// SPDX-License-Identifier: Apache-2.0

import Foundation
import WarrenCore

let usage = """
usage: warren <command>

  site add <path>              register a folder as a site
  site list [--json]           list registered sites
  site show <id> [--json]      show one site's resolved settings
  site remove <id>             unregister a site (never deletes files)
  proxy <command>              local HTTPS proxy (see: warren proxy)
  dns <command>                local DNS for your domains (see: warren dns)
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
case "setup":
    do {
        try runSetup(Array(arguments.dropFirst()), paths: .fromEnvironment())
    } catch {
        fail(error.localizedDescription)
    }
case nil, "help", "--help", "-h": print(usage)
default: fail("unknown command '\(arguments[0])'\n\n\(usage)")
}
