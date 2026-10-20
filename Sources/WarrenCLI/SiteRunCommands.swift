// SPDX-License-Identifier: Apache-2.0

import Foundation
import WarrenCore

let siteRunUsage = """
usage: warren site start <site> [--yes]
       warren site stop <site>
       warren site restart <site> [--yes]
       warren site status [<site>] [--json]
       warren site logs <site> [-n <lines>] [--follow]

  start asks before it runs the project's start command, unless the command is already trusted or --yes is given.
"""

private struct SiteStatusLine: Encodable {
    let id: String
    let state: String
    let address: String
    let port: Int?
    let exitCode: Int32?
}

func runSiteProcess(_ verb: String, _ arguments: [String], paths: WarrenPaths) async throws {
    let flags = arguments.filter { $0.hasPrefix("-") }
    var positional = arguments.filter { !$0.hasPrefix("-") }
    var lineCount = 40
    if let index = arguments.firstIndex(of: "-n"), arguments.indices.contains(index + 1),
       let count = Int(arguments[index + 1])
    {
        lineCount = count
        positional.removeAll { $0 == arguments[index + 1] }
    }
    let registry = SiteRegistry(paths: paths)
    let processes = SiteProcesses(paths: paths)
    if verb == "status" {
        try printStatus(positional.first, json: flags.contains("--json"), registry: registry, processes: processes)
        return
    }
    guard let id = positional.first else { throw CLIError(siteRunUsage) }
    let site = try registry.show(id: id)
    switch verb {
    case "start", "restart":
        if verb == "restart" {
            try processes.stop(site)
        }
        print("starting \(site.id)…")
        let assumeYes = flags.contains("--yes")
        try await processes.start(site, approve: { askForApproval($0, assumeYes: assumeYes) })
        print("running at https://\(site.domains.first ?? site.id)")
    case "stop":
        try processes.stop(site)
        print("stopped \(site.id)")
    case "logs":
        try followLogs(site, processes: processes, count: lineCount, follow: flags.contains("--follow"))
    default:
        throw CLIError(siteRunUsage)
    }
}

private func printStatus(_ id: String?, json: Bool, registry: SiteRegistry, processes: SiteProcesses) throws {
    let sites = try id.map { try [registry.show(id: $0)] } ?? registry.list()
    let lines = sites.map { site -> SiteStatusLine in
        let state = processes.state(of: site)
        var code: Int32?
        if case let .crashed(exit) = state {
            code = exit
        }
        return SiteStatusLine(
            id: site.id, state: state.word, address: "https://\(site.domains.first ?? site.id)",
            port: site.port ?? processes.ports.assigned(for: site.id), exitCode: code
        )
    }
    if json {
        printJSON(lines)
        return
    }
    if lines.isEmpty {
        print("no sites registered")
    }
    for line in lines {
        print("\(line.id)  \(line.state)  \(line.address)\(line.port.map { "  port \($0)" } ?? "")")
    }
}

private func followLogs(_ site: ResolvedSite, processes: SiteProcesses, count: Int, follow: Bool) throws {
    let log = processes.logURL(site.id)
    guard FileManager.default.fileExists(atPath: log.path) else { throw CLIError("\(site.id) has no log yet") }
    processes.lastLines(site.id, count: count).forEach { print($0) }
    guard follow else { return }
    let handle = try FileHandle(forReadingFrom: log)
    try handle.seekToEnd()
    while true {
        let data = handle.availableData
        if data.isEmpty {
            Thread.sleep(forTimeInterval: 0.4)
        } else {
            FileHandle.standardOutput.write(data)
        }
    }
}
