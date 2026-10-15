// SPDX-License-Identifier: Apache-2.0

import Foundation

public struct RegisteredSite: Codable, Equatable, Sendable {
    public let id: String
    public let path: String
    public let addedAt: Date
}

/// A registered site with its `.warren.toml` applied over the defaults.
public struct ResolvedSite: Codable, Equatable, Sendable {
    public let id: String
    public let path: String
    public let name: String
    public let domains: [String]
    public let runtimes: [String: String]
    public let command: String?
    public let port: Int?
    public let services: [String: String]
    /// Problems with the project's config. A site with problems still lists, with default settings.
    public let problems: [String]
    public let warnings: [String]
}

public enum RegistryError: Error, Equatable, LocalizedError, Sendable {
    case pathNotFound(String)
    case notADirectory(String)
    case alreadyRegistered(id: String)
    case unknownSite(String)
    case domainConflict(domain: String, otherSite: String)
    case corruptRegistry(backup: String)
    case unsupportedVersion(Int)

    public var errorDescription: String? {
        switch self {
        case let .pathNotFound(path): "no such path: \(path)"
        case let .notADirectory(path): "not a directory: \(path)"
        case let .alreadyRegistered(id): "this folder is already registered as '\(id)'"
        case let .unknownSite(id): "no site with id '\(id)'"
        case let .domainConflict(domain, other): "domain '\(domain)' is already used by site '\(other)'"
        case let .corruptRegistry(backup): "the site registry was unreadable; it was moved to \(backup)"
        case let .unsupportedVersion(version): "the site registry is version \(version), which this Warren does not understand"
        }
    }
}

/// Reads and writes the list of sites. Stateless: every call loads, changes and saves the file.
public struct SiteRegistry: Sendable {
    private struct FileContents: Codable {
        var version = 1
        var sites: [RegisteredSite] = []
    }

    public let paths: WarrenPaths

    public init(paths: WarrenPaths) {
        self.paths = paths
    }

    public func list() throws -> [ResolvedSite] {
        try load().sites.map(resolve)
    }

    public func show(id: String) throws -> ResolvedSite {
        guard let site = try load().sites.first(where: { $0.id == id }) else { throw RegistryError.unknownSite(id) }
        return resolve(site)
    }

    @discardableResult
    public func add(path: String) throws -> ResolvedSite {
        let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw RegistryError.pathNotFound(path)
        }
        guard isDirectory.boolValue else { throw RegistryError.notADirectory(path) }

        var contents = try load()
        if let existing = contents.sites.first(where: { $0.path == url.path }) {
            throw RegistryError.alreadyRegistered(id: existing.id)
        }
        let record = RegisteredSite(
            id: uniqueID(for: url.lastPathComponent, among: contents.sites),
            path: url.path,
            addedAt: Date()
        )
        let resolved = resolve(record)
        for other in contents.sites {
            let claimed = resolve(other).domains
            if let clash = resolved.domains.first(where: claimed.contains) {
                throw RegistryError.domainConflict(domain: clash, otherSite: other.id)
            }
        }
        contents.sites.append(record)
        try save(contents)
        return resolved
    }

    public func remove(id: String) throws {
        var contents = try load()
        guard contents.sites.contains(where: { $0.id == id }) else { throw RegistryError.unknownSite(id) }
        contents.sites.removeAll { $0.id == id }
        try save(contents)
    }

    // MARK: - Resolution

    func resolve(_ site: RegisteredSite) -> ResolvedSite {
        let directory = URL(fileURLWithPath: site.path, isDirectory: true)
        var config = ProjectConfig()
        var problems: [String] = []
        do {
            config = try ProjectConfig.load(from: directory) ?? ProjectConfig()
        } catch {
            problems.append("\(ProjectConfig.fileName): \(error.localizedDescription)")
        }
        return ResolvedSite(
            id: site.id,
            path: site.path,
            name: config.name ?? directory.lastPathComponent,
            domains: config.domains.isEmpty ? ["\(site.id).test"] : config.domains,
            runtimes: config.runtimes,
            command: config.command,
            port: config.port,
            services: config.services,
            problems: problems,
            warnings: config.warnings
        )
    }

    private func uniqueID(for folder: String, among sites: [RegisteredSite]) -> String {
        let base = Self.slug(folder)
        let taken = Set(sites.map(\.id))
        if !taken.contains(base) {
            return base
        }
        var suffix = 2
        while taken.contains("\(base)-\(suffix)") {
            suffix += 1
        }
        return "\(base)-\(suffix)"
    }

    static func slug(_ name: String) -> String {
        var result = ""
        var pendingHyphen = false
        for char in name.lowercased() {
            if char.isASCII, char.isLetter || char.isNumber {
                if pendingHyphen, !result.isEmpty {
                    result.append("-")
                }
                pendingHyphen = false
                result.append(char)
            } else {
                pendingHyphen = true
            }
        }
        return result.isEmpty ? "site" : result
    }

    // MARK: - Storage

    private func load() throws -> FileContents {
        let file = paths.sitesFile
        guard FileManager.default.fileExists(atPath: file.path) else { return FileContents() }
        let data = try Data(contentsOf: file)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let contents = try decoder.decode(FileContents.self, from: data)
            guard contents.version <= 1 else { throw RegistryError.unsupportedVersion(contents.version) }
            return contents
        } catch let error as RegistryError {
            throw error
        } catch {
            let backup = file.appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970))")
            try FileManager.default.moveItem(at: file, to: backup)
            throw RegistryError.corruptRegistry(backup: backup.path)
        }
    }

    private func save(_ contents: FileContents) throws {
        try FileManager.default.createDirectory(at: paths.configDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(contents).write(to: paths.sitesFile, options: .atomic)
    }
}
