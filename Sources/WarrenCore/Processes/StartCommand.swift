// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The line that starts a site's server, with the port put where the framework wants it.
public struct StartCommand: Equatable, Sendable {
    /// The command as detected or written in `.warren.toml`, split into words. This is what the user approves and
    /// what trust remembers, so it does not change when the port does.
    public let shown: [String]
    /// The line `/bin/sh -c` runs.
    public let line: String
    public let environment: [String: String]

    public var shownLine: String {
        shown.joined(separator: " ")
    }

    public static func make(_ detection: FrameworkDetection, port: Int) -> StartCommand? {
        guard let command = detection.command?.trimmingCharacters(in: .whitespacesAndNewlines), !command.isEmpty else {
            return nil
        }
        var environment = detection.environment
        var line = command
        switch detection.portHandling {
        case let .environment(name): environment[name] = String(port)
        case let .flag(flag): line += (separator(for: command) ? " -- " : " ") + "\(flag) \(port)"
        case .placeholder: line = command.replacingOccurrences(of: "{port}", with: String(port))
        case .none: break
        }
        environment["PORT"] = environment["PORT"] ?? String(port)
        environment["HOST"] = environment["HOST"] ?? "127.0.0.1"
        return StartCommand(shown: command.split(separator: " ").map(String.init), line: line, environment: environment)
    }

    /// npm passes extra arguments to a script only after `--`.
    private static func separator(for command: String) -> Bool {
        command.hasPrefix("npm run ") && !command.contains(" -- ")
    }
}
