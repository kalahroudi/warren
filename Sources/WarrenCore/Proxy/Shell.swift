// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Runs a command-line tool and captures its output.
enum Shell {
    struct Result {
        let status: Int32
        let output: String
    }

    static func run(
        _ executable: String,
        _ arguments: [String],
        environment: [String: String]? = nil,
        directory: URL? = nil
    ) throws -> Result {
        let process = makeProcess(executable, arguments, environment: environment, directory: directory)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(status: process.terminationStatus, output: String(bytes: data, encoding: .utf8) ?? "")
    }

    /// Like `run`, but reports each output line as it arrives and stops the process if the task is cancelled.
    static func stream(
        _ executable: String,
        _ arguments: [String],
        environment: [String: String]? = nil,
        directory: URL? = nil,
        onLine: @escaping @Sendable (String) -> Void
    ) async throws -> Result {
        let process = makeProcess(executable, arguments, environment: environment, directory: directory)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let collector = LineCollector(onLine: onLine)
        pipe.fileHandleForReading.readabilityHandler = { handle in collector.append(handle.availableData) }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { finished in
                    pipe.fileHandleForReading.readabilityHandler = nil
                    collector.append(pipe.fileHandleForReading.readDataToEndOfFile())
                    continuation.resume(returning: Result(status: finished.terminationStatus, output: collector.text))
                }
                do {
                    try process.run()
                } catch {
                    pipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }
    }

    private static func makeProcess(
        _ executable: String,
        _ arguments: [String],
        environment: [String: String]?,
        directory: URL?
    ) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment {
            process.environment = environment
        }
        process.currentDirectoryURL = directory
        return process
    }
}

/// Collects output and hands it on a line at a time.
private final class LineCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = ""
    private var all = ""
    private let onLine: @Sendable (String) -> Void

    init(onLine: @escaping @Sendable (String) -> Void) {
        self.onLine = onLine
    }

    var text: String {
        lock.withLock { all }
    }

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        let lines: [String] = lock.withLock {
            let chunk = String(bytes: data, encoding: .utf8) ?? ""
            all += chunk
            pending += chunk
            var complete = pending.components(separatedBy: CharacterSet(charactersIn: "\r\n"))
            pending = complete.removeLast()
            return complete.filter { !$0.isEmpty }
        }
        lines.forEach(onLine)
    }
}
