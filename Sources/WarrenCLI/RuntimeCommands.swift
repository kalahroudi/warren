// SPDX-License-Identifier: Apache-2.0

import Foundation
import WarrenCore

let runtimeUsage = """
usage: warren runtime <command>

  list [--json]                      installed runtimes and their size
  available <runtime> [--json]       versions that can be installed (node, bun, php)
  install <runtime>[@version]        install a version (default: latest)
  remove <runtime>@<version>         remove an installed version
  which <runtime>                    the newest installed version's folder
  env <site> [--json]                the environment to run a site in (runtimes first on PATH)
  composer <site> -- <arguments>     run Composer in a site's folder with the site's PHP
"""

private struct InstalledOutput: Encodable {
    let runtime: String
    let version: String
    let path: String
    let bytes: Int64
}

func runRuntime(_ arguments: [String], paths: WarrenPaths) async throws {
    let json = arguments.contains("--json")
    let rest = arguments.filter { $0 != "--json" }
    let manager = RuntimeManager(paths: paths)
    switch (rest.first, rest.dropFirst().first) {
    case ("list", nil):
        let installed = try manager.inventory()
        if json {
            printJSON(installed.map {
                InstalledOutput(runtime: $0.kind.rawValue, version: $0.version, path: $0.path.path, bytes: $0.bytes)
            })
        } else if installed.isEmpty {
            print("no runtimes installed")
        } else {
            for runtime in installed {
                print("\(runtime.kind.rawValue)@\(runtime.version)  \(megabytes(runtime.bytes))  \(runtime.path.path)")
            }
        }
    case let ("available", name?):
        let versions = try await manager.available(kind(name))
        print(json ? jsonText(versions) : versions.suffix(30).joined(separator: "\n"))
    case let ("install", spec?):
        let (kind, version) = try parse(spec)
        print("installing \(kind.rawValue)@\(version ?? "latest")")
        try await manager.install(kind, version: version ?? "latest") { print("  \($0)") }
        print("done")
    case let ("remove", spec?):
        try removeRuntime(spec, manager: manager)
    case let ("which", name?):
        let wanted = try kind(name)
        let newest = try manager.inventory().filter { $0.kind == wanted }.last
        guard let newest else { throw CLIError("\(wanted.rawValue) is not installed") }
        print(newest.path.appendingPathComponent("bin").path)
    case let ("env", id?):
        let site = try SiteRegistry(paths: paths).show(id: id)
        let plan = try manager.plan(for: site, installed: manager.inventory())
        let base = ProcessInfo.processInfo.environment
        let environment = manager.environment(for: plan, base: base).filter { base[$0.key] != $0.value }
        if json {
            printJSON(environment)
        } else {
            environment.sorted { $0.key < $1.key }.forEach { print("\($0.key)=\($0.value)") }
        }
        for need in plan.missing {
            FileHandle.standardError.write(Data("warren: \(need.requirement.label) is not installed\n".utf8))
        }
    case let ("composer", id?):
        try runComposer(
            site: id,
            arguments: Array(rest.drop { $0 != "--" }.dropFirst()),
            manager: manager,
            paths: paths
        )
    default:
        throw CLIError("unknown or incomplete command\n\n\(runtimeUsage)")
    }
}

private func removeRuntime(_ spec: String, manager: RuntimeManager) throws {
    let (kind, version) = try parse(spec)
    guard let version else { throw CLIError("say which version: \(kind.rawValue)@<version>") }
    guard let runtime = try manager.inventory().first(where: { $0.kind == kind && $0.version == version }) else {
        throw CLIError("\(kind.rawValue)@\(version) is not installed")
    }
    try manager.remove(runtime)
    print("removed \(runtime.id)")
}

private func runComposer(site id: String, arguments: [String], manager: RuntimeManager, paths: WarrenPaths) throws {
    let site = try SiteRegistry(paths: paths).show(id: id)
    let plan = try manager.plan(for: site, installed: manager.inventory())
    guard plan.needs.contains(where: { $0.requirement.kind == .php && $0.isInstalled }) else {
        throw CLIError("PHP is not installed for \(id). Run: warren runtime install php")
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["composer"] + arguments
    process.environment = manager.environment(for: plan)
    process.currentDirectoryURL = URL(fileURLWithPath: site.path, isDirectory: true)
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus != 0 {
        throw CLIError("composer exited with status \(process.terminationStatus)")
    }
}

private func kind(_ name: String) throws -> RuntimeKind {
    guard let kind = RuntimeKind(rawValue: name) else {
        throw CLIError(
            "unknown runtime '\(name)'. Choose from: \(RuntimeKind.allCases.map(\.rawValue).joined(separator: ", "))"
        )
    }
    return kind
}

private func parse(_ spec: String) throws -> (RuntimeKind, String?) {
    let parts = spec.split(separator: "@", maxSplits: 1).map(String.init)
    return try (kind(parts[0]), parts.count > 1 ? parts[1] : nil)
}

private func megabytes(_ bytes: Int64) -> String {
    "\(bytes / 1_000_000) MB"
}

private func jsonText(_ value: some Encodable) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
}
