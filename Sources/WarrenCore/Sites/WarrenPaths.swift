// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Where Warren keeps its state. `WARREN_HOME` relocates everything.
public struct WarrenPaths: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// `WARREN_HOME` if set, else `~/Warren`. On a case-insensitive disk `~/Warren` is the same folder as a source
    /// checkout at `~/warren`, so if it holds Warren's own `Package.swift` the state goes in `~/.warren` instead.
    public static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> WarrenPaths {
        if let custom = environment["WARREN_HOME"], !custom.isEmpty {
            return WarrenPaths(root: URL(fileURLWithPath: custom, isDirectory: true))
        }
        let visible = home.appendingPathComponent("Warren", isDirectory: true)
        if FileManager.default.fileExists(atPath: visible.appendingPathComponent("Package.swift").path) {
            return WarrenPaths(root: home.appendingPathComponent(".warren", isDirectory: true))
        }
        return WarrenPaths(root: visible)
    }

    public var configDirectory: URL {
        root.appendingPathComponent("config", isDirectory: true)
    }

    public var sitesFile: URL {
        configDirectory.appendingPathComponent("sites.json")
    }

    public var binDirectory: URL {
        root.appendingPathComponent("bin", isDirectory: true)
    }

    public var dataDirectory: URL {
        root.appendingPathComponent("data", isDirectory: true)
    }

    public var runDirectory: URL {
        root.appendingPathComponent("run", isDirectory: true)
    }
}
