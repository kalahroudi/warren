// SPDX-License-Identifier: Apache-2.0

import Foundation

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
