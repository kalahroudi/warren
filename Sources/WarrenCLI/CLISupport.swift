// SPDX-License-Identifier: Apache-2.0

import Foundation
import WarrenCore

struct CLIError: Error, LocalizedError {
    let message: String
    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}

/// Runs a program with this terminal's input and output, so prompts such as a password work.
func runForeground(_ binary: URL, _ arguments: [String]) throws -> Int32 {
    let process = Process()
    process.executableURL = binary
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    return process.terminationStatus
}

func confirm(_ question: String) -> Bool {
    print("\(question) [y/N] ", terminator: "")
    guard let answer = readLine()?.lowercased() else { return false }
    return answer == "y" || answer == "yes"
}

/// Writes a shell script to a private temporary file and runs it, with sudo when it needs admin rights.
func runScript(_ script: String, privileged: Bool) throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("warren-\(UUID().uuidString).sh")
    try Data(script.utf8).write(to: file, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    defer { try? FileManager.default.removeItem(at: file) }

    let status = privileged
        ? try runForeground(URL(fileURLWithPath: "/usr/bin/sudo"), ["/bin/sh", file.path])
        : try runForeground(URL(fileURLWithPath: "/bin/sh"), [file.path])
    guard status == 0 else { throw CLIError("the script failed (exit \(status)); nothing more was changed") }
}

func announceBackground(_ kind: BackgroundKind, _ background: BackgroundServices) {
    print("""
    started \(kind.label) in the background. It starts at every login and restarts if it stops.
    launch agent: \(background.plistURL(kind).path)
    log:          \(background.logURL(kind).path)
    Undo it with: warren \(kind.rawValue) stop
    """)
}

func stopBackground(_ kind: BackgroundKind, paths: WarrenPaths) throws {
    try NetworkServices(paths: paths).stop(kind)
    print("stopped \(kind.label) and removed it from login")
}

func showLogs(_ kind: BackgroundKind, paths: WarrenPaths, _ options: [String]) throws {
    let log = BackgroundServices(paths: paths).logURL(kind)
    guard FileManager.default.fileExists(atPath: log.path) else { throw CLIError("no log yet at \(log.path)") }
    let arguments = options.contains("-f") ? ["-n", "50", "-f", log.path] : ["-n", "100", log.path]
    _ = try runForeground(URL(fileURLWithPath: "/usr/bin/tail"), arguments)
}

/// After the site list changes, brings a running proxy and DNS server up to date and reports any problem.
func syncRunningNetwork(paths: WarrenPaths) {
    for problem in NetworkServices(paths: paths).applyRegistryChange() {
        FileHandle.standardError.write(Data("warren: could not update \(problem)\n".utf8))
    }
}
