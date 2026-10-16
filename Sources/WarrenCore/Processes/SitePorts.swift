// SPDX-License-Identifier: Apache-2.0

import Foundation

public extension WarrenPaths {
    var stateDirectory: URL {
        root.appendingPathComponent("state", isDirectory: true)
    }

    var portsFile: URL {
        stateDirectory.appendingPathComponent("ports.json")
    }
}

public enum SitePortError: Error, Equatable, LocalizedError, Sendable {
    case taken(port: Int, holder: String?)
    case noneFree

    public var errorDescription: String? {
        switch self {
        case let .taken(port, holder):
            "port \(port), set as run.port in .warren.toml, is in use" + (holder.map { " by \($0)" } ?? "")
        case .noneFree: "no free port between \(SitePorts.range.lowerBound) and \(SitePorts.range.upperBound)"
        }
    }
}

/// The port each site's server listens on. An explicit `run.port` always wins; otherwise Warren picks a free one and
/// keeps it for the site, so its address in logs and bookmarks stays the same.
public struct SitePorts: Sendable {
    public static let range = 4100 ... 4999

    private struct Contents: Codable {
        var version = 1
        var ports: [String: Int] = [:]
    }

    public let paths: WarrenPaths
    private let isFree: @Sendable (Int) -> Bool

    public init(paths: WarrenPaths, isFree: @escaping @Sendable (Int) -> Bool = SitePorts.systemIsFree) {
        self.paths = paths
        self.isFree = isFree
    }

    /// Nothing accepts connections on the port and nothing can bind it.
    public static func systemIsFree(_ port: Int) -> Bool {
        PortCheck.isFree(port) && !PortCheck.isListening(port)
    }

    /// The port kept for a site, if one has been chosen.
    public func assigned(for siteID: String) -> Int? {
        load().ports[siteID]
    }

    /// The port to start the site on. Call it when the site is not running.
    public func resolve(for site: ResolvedSite) throws -> Int {
        if let explicit = site.port {
            guard isFree(explicit) else { throw SitePortError.taken(
                port: explicit,
                holder: PortCheck.holder(of: explicit)
            ) }
            return explicit
        }
        var contents = load()
        if let kept = contents.ports[site.id], isFree(kept) {
            return kept
        }
        let others = Set(contents.ports.filter { $0.key != site.id }.values)
        guard let port = Self.range.first(where: { !others.contains($0) && isFree($0) }) else {
            throw SitePortError.noneFree
        }
        contents.ports[site.id] = port
        try save(contents)
        return port
    }

    /// Forgets the site's port, when the site is removed.
    public func forget(_ siteID: String) {
        var contents = load()
        guard contents.ports.removeValue(forKey: siteID) != nil else { return }
        try? save(contents)
    }

    private func load() -> Contents {
        guard let data = try? Data(contentsOf: paths.portsFile),
              let contents = try? JSONDecoder().decode(Contents.self, from: data) else { return Contents() }
        return contents
    }

    private func save(_ contents: Contents) throws {
        try FileManager.default.createDirectory(at: paths.stateDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(contents).write(to: paths.portsFile, options: .atomic)
    }
}
