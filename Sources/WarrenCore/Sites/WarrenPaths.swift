// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Where Warren keeps its state. `WARREN_HOME` relocates everything.
public struct WarrenPaths: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo
        .environment) -> WarrenPaths
    {
        if let custom = environment["WARREN_HOME"], !custom.isEmpty {
            return WarrenPaths(root: URL(fileURLWithPath: custom, isDirectory: true))
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return WarrenPaths(root: home.appendingPathComponent("Warren", isDirectory: true))
    }

    public var configDirectory: URL {
        root.appendingPathComponent("config", isDirectory: true)
    }

    public var sitesFile: URL {
        configDirectory.appendingPathComponent("sites.json")
    }
}
