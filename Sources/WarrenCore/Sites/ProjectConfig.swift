// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The contents of a project's `.warren.toml`, validated. Nothing here is acted on yet.
public struct ProjectConfig: Equatable, Codable, Sendable {
    public static let fileName = ".warren.toml"

    public var name: String?
    public var domains: [String] = []
    public var runtimes: [String: String] = [:]
    public var command: String?
    public var port: Int?
    public var services: [String: String] = [:]
    public var warnings: [String] = []

    public init() {}

    public static func parse(_ text: String) throws -> ProjectConfig {
        let document = try TOML.parse(text)
        var config = ProjectConfig()
        try config.readTopLevel(document.tables[""] ?? [:])
        try config.readRuntime(document.tables["runtime"] ?? [:])
        try config.readRun(document.tables["run"] ?? [:])
        try config.readServices(document.tables["services"] ?? [:])
        for table in document.tables.keys.sorted() where !["", "runtime", "run", "services"].contains(table) {
            config.warnings.append("unknown table [\(table)] ignored")
        }
        return config
    }

    /// Returns nil when the project has no `.warren.toml`.
    public static func load(from directory: URL) throws -> ProjectConfig? {
        let file = directory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try parse(String(contentsOf: file, encoding: .utf8))
    }

    private mutating func readTopLevel(_ table: [String: TOMLValue]) throws {
        for (key, value) in table.sorted(by: { $0.key < $1.key }) {
            switch (key, value) {
            case let ("name", .string(text)): name = text
            case let ("domains", .strings(list)): domains = try list.map(DomainName.normalize)
            case ("name", _), ("domains", _): throw ConfigError.wrongType(
                    key: key,
                    expected: key == "name" ? "a string" : "an array of strings"
                )
            default: warnings.append("unknown key '\(key)' ignored")
            }
        }
    }

    private mutating func readRuntime(_ table: [String: TOMLValue]) throws {
        for (key, value) in table.sorted(by: { $0.key < $1.key }) {
            guard case let .string(version) = value else { throw ConfigError.wrongType(
                key: "runtime.\(key)",
                expected: "a version string"
            ) }
            runtimes[key] = version
        }
    }

    private mutating func readRun(_ table: [String: TOMLValue]) throws {
        for (key, value) in table.sorted(by: { $0.key < $1.key }) {
            switch (key, value) {
            case let ("command", .string(text)): command = text
            case let ("port", .integer(number)):
                guard (1 ... 65535).contains(number) else { throw ConfigError.invalidPort(number) }
                port = number
            case ("command", _): throw ConfigError.wrongType(key: "run.command", expected: "a string")
            case ("port", _): throw ConfigError.wrongType(key: "run.port", expected: "an integer")
            default: warnings.append("unknown key 'run.\(key)' ignored")
            }
        }
    }

    private mutating func readServices(_ table: [String: TOMLValue]) throws {
        for (key, value) in table.sorted(by: { $0.key < $1.key }) {
            guard case let .string(version) = value else { throw ConfigError.wrongType(
                key: "services.\(key)",
                expected: "a version string"
            ) }
            services[key] = version
        }
    }
}

public enum ConfigError: Error, Equatable, LocalizedError, Sendable {
    case wrongType(key: String, expected: String)
    case invalidPort(Int)
    case invalidDomain(String)

    public var errorDescription: String? {
        switch self {
        case let .wrongType(key, expected): "'\(key)' must be \(expected)"
        case let .invalidPort(number): "port \(number) is out of range (1 to 65535)"
        case let .invalidDomain(name):
            "'\(name)' is not a valid domain (lowercase letters, digits and hyphens, at least two labels)"
        }
    }
}

public enum DomainName {
    /// Lowercases and validates a domain: at least two labels of `a-z`, `0-9`, `-`, no leading or trailing hyphen.
    public static func normalize(_ input: String) throws -> String {
        let name = input.lowercased()
        let labels = name.split(separator: ".", omittingEmptySubsequences: false)
        let valid = name.count <= 253 && labels.count >= 2 && labels.allSatisfy { label in
            !label.isEmpty && label.count <= 63 && !label.hasPrefix("-") && !label.hasSuffix("-")
                && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }
        guard valid else { throw ConfigError.invalidDomain(input) }
        return name
    }
}
