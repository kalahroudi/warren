// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation
import WarrenCore

let proxyUsage = """
usage: warren proxy <command>

  install                        download and verify Caddy
  config [ports]                 print the generated Caddy config
  run [ports]                    run the proxy in the foreground (Ctrl-C stops it)
  reload [ports]                 apply the current sites to the running proxy
  trust [--yes]                  trust Warren's local root certificate (asks first)
  untrust                        remove that trust
  status [ports]                 show what is installed, running and routed

ports: --http-port N --https-port N   (defaults 80 and 443)
"""

private func parsePorts(_ arguments: [String]) throws -> ProxyPorts {
    var ports = ProxyPorts()
    var index = 0
    while index < arguments.count {
        let flag = arguments[index]
        guard flag == "--http-port" || flag == "--https-port", index + 1 < arguments.count,
              let value = Int(arguments[index + 1])
        else {
            throw CLIError("unknown or incomplete option '\(flag)'")
        }
        if flag == "--http-port" {
            ports.http = value
        } else {
            ports.https = value
        }
        index += 2
    }
    return ports
}

private func printSkipped(_ plan: ProxyPlan) {
    for skipped in plan.skipped {
        print("  skipped \(skipped.siteID): \(skipped.reason)")
    }
}

func runProxy(_ arguments: [String], paths: WarrenPaths) async throws {
    let service = ProxyService(paths: paths)
    let rest = Array(arguments.dropFirst())
    switch arguments.first {
    case "install": try await install(service)
    case "config": try print(service.plan(ports: parsePorts(rest)).configJSON)
    case "run": try run(service, rest)
    case "reload": try reload(service, rest)
    case "trust": try trust(service, paths: paths, rest)
    case "untrust": try untrust(service)
    case "status": try status(service, rest)
    default: throw CLIError("unknown or incomplete command\n\n\(proxyUsage)")
    }
}

private func install(_ service: ProxyService) async throws {
    let binary = try await service.install()
    print("installed Caddy \(service.release.version) at \(binary.path)")
}

private func run(_ service: ProxyService, _ options: [String]) throws {
    let launch = try service.prepareRun(ports: parsePorts(options))
    for route in launch.plan
        .routes
    {
        print("routing \(route.domains.joined(separator: ", ")) -> localhost:\(route.port)")
    }
    printSkipped(launch.plan)
    for (key, value) in launch.environment {
        setenv(key, value, 1)
    }
    // Replace this process with Caddy, so Ctrl-C reaches it directly and nothing is left behind.
    let argv = ([launch.binary.path] + launch.arguments).map { strdup($0) } + [nil]
    execv(launch.binary.path, argv)
    throw CLIError("could not start Caddy: \(String(cString: strerror(errno)))")
}

private func reload(_ service: ProxyService, _ options: [String]) throws {
    let plan = try service.reload(ports: parsePorts(options))
    print("reloaded: \(plan.routes.count) site(s) routed")
    printSkipped(plan)
}

private func trust(_ service: ProxyService, paths: WarrenPaths, _ options: [String]) throws {
    let command = try service.trustCommand()
    print("""
    This adds Warren's local root certificate to your system trust store, so browsers
    accept https://<your sites>. It asks for your admin password. The certificate can
    issue certificates for any name, and its key stays in \(paths.caddyDataDirectory.path).
    Undo it any time with: warren proxy untrust
    """)
    guard options.contains("--yes") || confirm("Trust Warren's root certificate?") else {
        throw CLIError("cancelled, nothing changed")
    }
    guard try runForeground(command.binary, command.arguments) == 0
    else { throw CLIError("trusting the certificate failed") }
}

private func untrust(_ service: ProxyService) throws {
    let command = try service.untrustCommand()
    guard try runForeground(command.binary, command.arguments) == 0 else { throw CLIError("removing trust failed") }
    print("Warren's root certificate is no longer trusted")
}

private func status(_ service: ProxyService, _ options: [String]) throws {
    let status = try service.status(ports: parsePorts(options))
    print("caddy:   \(status.installedVersion.map { "installed (\($0))" } ?? "not installed")")
    print("running: \(status.running ? "yes" : "no")")
    print("trusted: \(status.rootTrusted.map { $0 ? "yes" : "no" } ?? "no root certificate yet")")
    for route in status.routes {
        print("  \(route.domains.joined(separator: ", ")) -> localhost:\(route.port)")
    }
    for skipped in status.skipped {
        print("  skipped \(skipped.siteID): \(skipped.reason)")
    }
}
