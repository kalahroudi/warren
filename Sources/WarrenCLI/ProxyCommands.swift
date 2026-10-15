// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation
import WarrenCore

let proxyUsage = """
usage: warren proxy <command>

  install                        download and verify Caddy
  start [ports]                  run the proxy in the background, now and at every login
  stop                           stop it and remove it from login
  restart [ports]                stop and start it again
  logs [-f]                      show the proxy's log (-f follows it)
  config [ports]                 print the generated Caddy config
  run [ports]                    run the proxy in the foreground (Ctrl-C stops it)
  reload [ports]                 apply the current sites to the running proxy
  trust [--yes]                  trust Warren's local root certificate (asks first)
  untrust                        remove that trust
  status [ports]                 show what is installed, running and routed

ports: --http-port N --https-port N   (defaults: the ports last used with start, else 80 and 443)
"""

private func parsePorts(_ arguments: [String], _ service: ProxyService) throws -> ProxyPorts {
    var ports = NetworkSettings.load(service.paths).proxyPorts
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
    case "start", "restart": try start(service, rest)
    case "stop": try stopBackground(.proxy, paths: paths)
    case "logs": try showLogs(.proxy, paths: paths, rest)
    case "config": try print(service.plan(ports: parsePorts(rest, service)).configJSON)
    case "run": try run(service, rest)
    case "reload": try reload(service, rest)
    case "trust": try trust(service, paths: paths, rest)
    case "untrust": try untrust(service, paths: paths)
    case "status": try status(service, rest)
    default: throw CLIError("unknown or incomplete command\n\n\(proxyUsage)")
    }
}

private func install(_ service: ProxyService) async throws {
    let binary = try await service.install()
    print("installed Caddy \(service.release.version) at \(binary.path)")
}

private func run(_ service: ProxyService, _ options: [String]) throws {
    let launch = try service.prepareRun(ports: parsePorts(options, service))
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
    let plan = try service.reload(ports: parsePorts(options, service))
    print("reloaded: \(plan.routes.count) site(s) routed")
    printSkipped(plan)
}

private func trust(_ service: ProxyService, paths: WarrenPaths, _ options: [String]) throws {
    let script = try TrustManager(paths: paths).trustScript()
    print("""
    This adds Warren's local root certificate to your system keychain as a trusted root, so
    browsers accept https://<your sites>. It asks for your admin password. The certificate can
    issue certificates for any name, and its key stays in \(paths.caddyDataDirectory.path).
    Undo it any time with: warren proxy untrust

    \(script)
    """)
    guard options.contains("--yes") || confirm("Trust Warren's root certificate?") else {
        throw CLIError("cancelled, nothing changed")
    }
    try runScript(script, privileged: true)
    print("trusted: \(service.rootTrusted() == true ? "yes" : "no")")
}

private func untrust(_ service: ProxyService, paths: WarrenPaths) throws {
    try runScript(TrustManager(paths: paths).untrustScript(), privileged: true)
    print("Warren's root certificate is no longer trusted (trusted: \(service.rootTrusted() == true ? "yes" : "no"))")
}

private func status(_ service: ProxyService, _ options: [String]) throws {
    let status = try service.status(ports: parsePorts(options, service))
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

private func start(_ service: ProxyService, _ options: [String]) throws {
    let services = NetworkServices(paths: service.paths)
    let plan = try services.startProxy(ports: parsePorts(options, service))
    announceBackground(.proxy, services.background)
    for route in plan.routes {
        print("routing \(route.domains.joined(separator: ", ")) -> localhost:\(route.port)")
    }
    printSkipped(plan)
}
