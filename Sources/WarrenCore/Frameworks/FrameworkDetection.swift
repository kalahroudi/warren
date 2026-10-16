// SPDX-License-Identifier: Apache-2.0

import Foundation

/// How a site is served.
public enum ServeKind: String, Codable, Sendable {
    /// A process listens on a port and the proxy forwards to it.
    case server
    /// PHP files served through PHP-FPM (spec 015).
    case php
    /// Files served directly.
    case staticFiles = "static"
    case unknown
}

/// Where the start command came from.
public enum CommandSource: String, Codable, Sendable {
    case warrenConfig
    /// The project's own `dev` or `start` script.
    case script
    /// The framework's usual command, when the project has no script for it.
    case framework

    public var label: String {
        switch self {
        case .warrenConfig: ".warren.toml"
        case .script: "package script"
        case .framework: "framework default"
        }
    }
}

/// How a development server is told which port to use.
public enum PortHandling: Equatable, Codable, Sendable {
    /// Through an environment variable, such as `PORT`.
    case environment(String)
    /// Through a flag appended to the command, such as `--port`.
    case flag(String)
    /// The command contains `{port}`, to be replaced.
    case placeholder
    /// Nothing to pass: PHP-FPM and static files have no port of their own.
    case none
}

public enum PackageManager: String, Codable, Sendable {
    case npm, pnpm, yarn, bun, composer, pip
    case uvCLI = "uv"
}

/// What Warren found out about a project folder: what it is and how to run it. Only reads files.
public struct FrameworkDetection: Equatable, Codable, Sendable {
    public var id: String?
    public var name: String?
    public var kind: ServeKind
    public var command: String?
    public var commandSource: CommandSource?
    public var packageManager: PackageManager?
    public var portHandling: PortHandling
    /// Folder the web server serves, relative to the project, for `php` and `static`.
    public var documentRoot: String?
    /// Variables to run the command with.
    public var environment: [String: String]
    public var notes: [String]

    public static let unknown = FrameworkDetection(
        id: nil, name: nil, kind: .unknown, command: nil, commandSource: nil, packageManager: nil,
        portHandling: .none, documentRoot: nil, environment: [:], notes: []
    )

    /// The name for the Sites page.
    public var displayName: String {
        name ?? "Unknown"
    }

    /// The "Starts with" line for the Sites page.
    public var startLine: String {
        switch kind {
        case .php: "Served by PHP-FPM from \(documentRoot.map { $0 == "." ? "the project folder" : "\($0)/" } ?? "the project folder")"
        case .staticFiles: "Served as static files"
        case .server, .unknown:
            if let command {
                commandSource == .warrenConfig ? "\(command) (from .warren.toml)" : command
            } else {
                "No start command found"
            }
        }
    }
}
