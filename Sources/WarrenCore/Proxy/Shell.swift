// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Runs a command-line tool and captures its output.
enum Shell {
    struct Result {
        let status: Int32
        let output: String
    }

    static func run(_ executable: String, _ arguments: [String]) throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(status: process.terminationStatus, output: String(bytes: data, encoding: .utf8) ?? "")
    }
}
