// SPDX-License-Identifier: Apache-2.0

import Foundation
import TOMLDecoder

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
        let root: TOMLTable
        do {
            root = try TOMLTable(source: text)
        } catch {
            throw ConfigError.invalid(String(describing: error))
        }
        var config = ProjectConfig()
        do {
            try config.read(root)
        } catch let error as TOMLError {
            throw ConfigError.invalid(String(describing: error))
        }
        return config
    }

    /// Returns nil when the project has no `.warren.toml`.
    public static func load(from directory: URL) throws -> ProjectConfig? {
        let file = directory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try parse(String(contentsOf: file, encoding: .utf8))
    }

    private static let sections: Set = ["runtime", "run", "services"]

    private mutating func read(_ root: TOMLTable) throws {
        for key in root.keys.sorted() {
            switch key {
            case "name":
                name = try root.string(forKey: key)
            case "domains":
                let list = try root.array(forKey: key)
                domains = try (0 ..< list.count).map { try DomainName.normalize(list.string(atIndex: $0)) }
            case _ where Self.sections.contains(key):
                try readSection(key, root.table(forKey: key))
            default:
                warnings.append("unknown key '\(key)' ignored")
            }
        }
    }

    private mutating func readSection(_ section: String, _ table: TOMLTable) throws {
        for key in table.keys.sorted() {
            switch (section, key) {
            case ("runtime", _): runtimes[key] = try table.string(forKey: key)
            case ("services", _): services[key] = try table.string(forKey: key)
            case ("run", "command"): command = try table.string(forKey: key)
            case ("run", "port"):
                let number = try table.integer(forKey: key)
                guard (1 ... 65535).contains(number) else { throw ConfigError.invalidPort(number) }
                port = Int(number)
            default: warnings.append("unknown key '\(section).\(key)' ignored")
            }
        }
    }
}

public enum ConfigError: Error, Equatable, LocalizedError, Sendable {
    case invalid(String)
    case invalidPort(Int64)
    case invalidDomain(String)

    public var errorDescription: String? {
        switch self {
        case let .invalid(message): message
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
