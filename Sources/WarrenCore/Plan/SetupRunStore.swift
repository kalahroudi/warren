// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Steps that succeeded and cannot be re-checked from files, such as migrations. A step counts as done while the
/// command that ran is the command in the plan.
public struct SetupRunStore: Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public let command: [String]
        public let date: Date
    }

    private struct FileContents: Codable {
        var version = 1
        /// Site id, then step id.
        var runs: [String: [String: Entry]] = [:]
    }

    public let paths: WarrenPaths

    public init(paths: WarrenPaths) {
        self.paths = paths
    }

    public func completed(site: String) -> [String: Entry] {
        load().runs[site] ?? [:]
    }

    public func record(site: String, step: String, command: [String]) throws {
        var contents = load()
        contents.runs[site, default: [:]][step] = Entry(command: command, date: Date())
        try save(contents)
    }

    public func forget(site: String, step: String? = nil) throws {
        var contents = load()
        if let step {
            contents.runs[site]?[step] = nil
        } else {
            contents.runs[site] = nil
        }
        try save(contents)
    }

    private func load() -> FileContents {
        guard let data = try? Data(contentsOf: paths.setupRunsFile) else { return FileContents() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(FileContents.self, from: data)) ?? FileContents()
    }

    private func save(_ contents: FileContents) throws {
        try FileManager.default.createDirectory(at: paths.configDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(contents).write(to: paths.setupRunsFile, options: .atomic)
    }
}
