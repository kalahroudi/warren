// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation
import WarrenCore

let dnsUsage = """
usage: warren dns <command>

  install                  download and verify CoreDNS
  start [--port N]         run the DNS server in the background, now and at every login
  stop                     stop it and remove it from login
  restart [--port N]       stop and start it again
  logs [-f]                show the DNS server's log (-f follows it)
  config [--port N]        print the generated Corefile
  run [--port N]           run the DNS server in the foreground (Ctrl-C stops it)
  sync [--port N]          rewrite the Corefile from the site registry (a running server reloads it)
  enable [--yes]           write the macOS resolver files for your domains (asks first, needs your password)
  disable [--yes]          remove the resolver files Warren wrote
  status [--port N]        show what is installed, running, and whether macOS resolves your domains

Default port: the one last used with start, else 5354. WARREN_RESOLVER_DIR overrides /etc/resolver (for testing).
"""

private func parsePort(_ arguments: [String], _ service: DNSService) throws -> Int {
    var port = NetworkSettings.load(service.paths).dnsPort
    var index = 0
    while index < arguments.count {
        let flag = arguments[index]
        if flag == "--yes" {
            index += 1
            continue
        }
        guard flag == "--port", index + 1 < arguments.count, let value = Int(arguments[index + 1]) else {
            throw CLIError("unknown or incomplete option '\(flag)'")
        }
        port = value
        index += 2
    }
    return port
}

private func makeService(_ paths: WarrenPaths) -> DNSService {
    DNSService(paths: paths)
}

private func printNotes(_ plan: DNSPlan) {
    for domain in plan.native {
        print("  \(domain): macOS resolves *.localhost itself, no DNS needed")
    }
    for rejection in plan.rejected {
        print("  rejected \(rejection.domain): \(rejection.reason)")
    }
}

func runDNS(_ arguments: [String], paths: WarrenPaths) async throws {
    let service = makeService(paths)
    let rest = Array(arguments.dropFirst())
    switch arguments.first {
    case "install": try await install(service)
    case "start", "restart": try start(service, rest)
    case "stop": try stopBackground(.dns, paths: paths)
    case "logs": try showLogs(.dns, paths: paths, rest)
    case "config": try config(service, rest)
    case "run": try run(service, rest)
    case "sync": try sync(service, rest)
    case "enable": try enable(service, rest)
    case "disable": try disable(service, rest)
    case "status": try status(service, rest)
    default: throw CLIError("unknown or incomplete command\n\n\(dnsUsage)")
    }
}

private func install(_ service: DNSService) async throws {
    let binary = try await service.install()
    print("installed CoreDNS \(service.release.version) at \(binary.path)")
}

private func config(_ service: DNSService, _ options: [String]) throws {
    let plan = try service.plan(port: parsePort(options, service))
    print(plan.corefile, terminator: "")
    printNotes(plan)
}

private func run(_ service: DNSService, _ options: [String]) throws {
    let launch = try service.prepareRun(port: parsePort(options, service))
    print("answering for: \(launch.plan.zones.joined(separator: ", "))")
    printNotes(launch.plan)
    // Replace this process with CoreDNS, so Ctrl-C reaches it directly and nothing is left behind.
    let argv = ([launch.binary.path] + launch.arguments).map { strdup($0) } + [nil]
    execv(launch.binary.path, argv)
    throw CLIError("could not start CoreDNS: \(String(cString: strerror(errno)))")
}

private func sync(_ service: DNSService, _ options: [String]) throws {
    let plan = try service.sync(port: parsePort(options, service))
    print("wrote the Corefile: \(plan.zones.count) zone(s) (\(plan.zones.joined(separator: ", ")))")
    printNotes(plan)
}

private func enable(_ service: DNSService, _ options: [String]) throws {
    let port = try parsePort(options, service)
    let (plan, entries) = try service.inspectResolvers(port: port)
    printNotes(plan)
    guard !plan.zones.isEmpty else { throw DNSError.noZones }
    guard let script = try service.resolvers.installScript(entries: entries, port: port) else {
        print("the resolver files are already set up")
        return
    }
    print("""
    This writes the files below so macOS sends only these domains to Warren's DNS server
    (127.0.0.1 port \(port)). Everything else keeps using your normal DNS.
    \(service.resolvers.needsPrivilege ? "It asks for your admin password." : "")
    Undo it any time with: warren dns disable

    \(script)
    """)
    guard options.contains("--yes") || confirm("Write these resolver files?") else {
        throw CLIError("cancelled, nothing changed")
    }
    try runScript(script, privileged: service.resolvers.needsPrivilege)
    for entry in service.resolvers.inspect(zones: plan.zones, port: port) {
        print("  \(entry.zone): \(entry.state == .current ? "ready" : "not set up")")
    }
}

private func disable(_ service: DNSService, _ options: [String]) throws {
    guard let script = service.resolvers.removalScript() else {
        print("no resolver files from Warren to remove")
        return
    }
    print("This removes the resolver files Warren wrote:\n\n\(script)")
    guard options.contains("--yes") || confirm("Remove them?") else { throw CLIError("cancelled, nothing changed") }
    try runScript(script, privileged: service.resolvers.needsPrivilege)
    print("removed")
}

private func status(_ service: DNSService, _ options: [String]) throws {
    let status = try service.status(port: parsePort(options, service))
    print("coredns: \(status.installedVersion.map { "installed (\($0))" } ?? "not installed")")
    print("running: \(status.running ? "yes" : "no")")
    for entry in status.resolvers {
        print("resolver \(entry.zone): \(entry.state)")
    }
    for item in status.resolution {
        print("  \(item.domain) -> \(item.resolves ? "resolves to this Mac" : "does not resolve")")
    }
    printNotes(status.plan)
}

private func start(_ service: DNSService, _ options: [String]) throws {
    let services = NetworkServices(paths: service.paths)
    let plan = try services.startDNS(port: parsePort(options, service))
    announceBackground(.dns, services.background)
    print("answering for: \(plan.zones.joined(separator: ", "))")
    printNotes(plan)
}
