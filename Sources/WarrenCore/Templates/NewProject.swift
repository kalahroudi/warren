// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum NewProjectError: Error, Equatable, LocalizedError, Sendable {
    case invalidName(String)
    case folderNotEmpty(String)
    case locationNotWritable(String)
    case locationNotAFolder(String)
    case noName

    public var errorDescription: String? {
        switch self {
        case .noName: "Give the project a name."
        case let .invalidName(name):
            "'\(name)' cannot be a folder name. Use letters, digits, - _ and ., not starting with a dot, up to 64 characters."
        case let .folderNotEmpty(path): "\(path) already exists and is not empty."
        case let .locationNotWritable(path): "Warren cannot write to \(path)."
        case let .locationNotAFolder(path): "\(path) is not a folder."
        }
    }
}

public enum NewProjectSource: Equatable, Sendable {
    case template(ProjectTemplate)
    case blank(BlankKind)
}

public struct NewProjectRequest: Equatable, Sendable {
    public var name: String
    public var location: URL
    public var domain: String?
    public var source: NewProjectSource

    public init(name: String, location: URL, domain: String? = nil, source: NewProjectSource) {
        self.name = name
        self.location = location
        self.domain = domain
        self.source = source
    }

    public var folder: URL {
        location.appendingPathComponent(name, isDirectory: true)
    }
}

/// Checks a new project's name, place and domain, creates its folder, and registers it as a site.
public struct ProjectCreator: Sendable {
    public let paths: WarrenPaths

    public init(paths: WarrenPaths) {
        self.paths = paths
    }

    /// `~/Sites`, or the folder in `WARREN_SITES` (for tests and demos).
    public static var defaultLocation: URL {
        if let custom = ProcessInfo.processInfo.environment["WARREN_SITES"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Sites", isDirectory: true)
    }

    /// The domain a name gets when none is chosen.
    public static func defaultDomain(forName name: String) -> String {
        "\(SiteRegistry.slug(name)).test"
    }

    /// Letters, digits, `-`, `_` and `.`; not starting with a dot; at most 64 characters.
    public static func isValidFolderName(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 64 && !name.hasPrefix(".")
            && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }
    }

    /// Throws the first problem found, in plain words. Writes nothing.
    public func validate(_ request: NewProjectRequest) throws {
        let name = request.name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { throw NewProjectError.noName }
        guard Self.isValidFolderName(name) else { throw NewProjectError.invalidName(name) }
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: request.location.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else { throw NewProjectError.locationNotAFolder(request.location.path) }
            guard fileManager.isWritableFile(atPath: request.location.path)
            else { throw NewProjectError.locationNotWritable(request.location.path) }
        }
        if fileManager.fileExists(atPath: request.folder.path) {
            let entries = (try? fileManager.contentsOfDirectory(atPath: request.folder.path)) ?? ["?"]
            guard entries.allSatisfy({ $0 == ".DS_Store" }) else {
                throw NewProjectError.folderNotEmpty(request.folder.path)
            }
        }
        try SiteRegistry(paths: paths).checkDomains([request.domain ?? Self.defaultDomain(forName: name)])
    }

    /// Creates the folder (and the blank project's files), then registers the site. Nothing is overwritten.
    public func create(_ request: NewProjectRequest) throws -> ResolvedSite {
        try validate(request)
        let fileManager = FileManager.default
        let folder = request.folder
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        var written: [URL] = []
        do {
            if case let .blank(kind) = request.source {
                for (path, text) in kind.files(name: request.name) {
                    let file = folder.appendingPathComponent(path)
                    try fileManager.createDirectory(
                        at: file.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try text.write(to: file, atomically: true, encoding: .utf8)
                    written.append(file)
                }
            }
            if case let .template(template) = request.source {
                for (path, text) in template.seedFiles {
                    let file = folder.appendingPathComponent(path)
                    try text.write(to: file, atomically: true, encoding: .utf8)
                    written.append(file)
                }
            }
            let domain = request.domain ?? Self.defaultDomain(forName: request.name)
            return try SiteRegistry(paths: paths).add(path: folder.path, name: request.name, domains: [domain])
        } catch {
            // Undo only what this call made: its own files, and the folder if that leaves it empty.
            written.forEach { try? fileManager.removeItem(at: $0) }
            try? fileManager.removeItem(at: folder.appendingPathComponent("public"))
            if (try? fileManager.contentsOfDirectory(atPath: folder.path))?.isEmpty == true {
                try? fileManager.removeItem(at: folder)
            }
            throw error
        }
    }
}
