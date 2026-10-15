// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum AdminError: Error, Equatable, LocalizedError, Sendable {
    case cancelled
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .cancelled: "cancelled, nothing was changed"
        case let .failed(message): "the step failed: \(message)"
        }
    }
}

/// Runs a shell script behind the standard macOS password dialog (Touch ID works in it).
/// This is the system's own `do shell script ... with administrator privileges`, so Warren never handles a password.
public enum AdminRunner {
    /// Runs the script. `privileged: false` skips the dialog, which is only for tests.
    @discardableResult
    public static func run(script: String, prompt: String, privileged: Bool = true) throws -> String {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("warren-\(UUID().uuidString).sh")
        try Data(script.utf8).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        defer { try? FileManager.default.removeItem(at: file) }

        let result = try Shell.run(
            "/usr/bin/osascript",
            ["-e", appleScript(running: file, prompt: prompt, privileged: privileged)]
        )
        guard result.status == 0 else {
            // osascript reports a dismissed password dialog as error -128.
            if result.output.contains("-128") || result.output.localizedCaseInsensitiveContains("user canceled") {
                throw AdminError.cancelled
            }
            throw AdminError.failed(result.output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func appleScript(running file: URL, prompt: String, privileged: Bool) -> String {
        let command = escape("/bin/sh '\(file.path)'")
        guard privileged else { return "do shell script \"\(command)\"" }
        return "do shell script \"\(command)\" with prompt \"\(escape(prompt))\" with administrator privileges"
    }

    /// Escapes text for use inside an AppleScript string literal.
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
