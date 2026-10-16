// SPDX-License-Identifier: Apache-2.0

import Foundation
import TOMLDecoder

/// The few small files detection reads. Nothing here runs anything.
struct ProjectFiles: Sendable {
    let directory: URL
    let nodeDependencies: Set<String>
    let scripts: [String: String]
    let packageManagerField: String?
    let composerPackages: Set<String>
    let pythonPackages: Set<String>
    let hasUvProject: Bool

    init(directory: URL) {
        self.directory = directory
        let package = Self.json(directory.appendingPathComponent("package.json"))
        var dependencies = Set<String>()
        for key in ["dependencies", "devDependencies"] {
            dependencies.formUnion((package?[key] as? [String: Any])?.keys.map(\.self) ?? [])
        }
        nodeDependencies = dependencies
        scripts = (package?["scripts"] as? [String: Any])?.compactMapValues { $0 as? String } ?? [:]
        packageManagerField = package?["packageManager"] as? String

        let composer = Self.json(directory.appendingPathComponent("composer.json"))
        var packages = Set<String>()
        for key in ["require", "require-dev"] {
            packages.formUnion((composer?[key] as? [String: Any])?.keys.map(\.self) ?? [])
        }
        composerPackages = packages

        let python = Self.pythonDependencies(in: directory)
        pythonPackages = python.packages
        hasUvProject = python.usesUv
    }

    func exists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent(relativePath).path)
    }

    func hasNode(_ package: String) -> Bool {
        nodeDependencies.contains(package)
    }

    var hasPackageJSON: Bool {
        exists("package.json")
    }

    private static func json(_ file: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Package names from `pyproject.toml` dependencies and `requirements*.txt`, lowercased.
    private static func pythonDependencies(in directory: URL) -> (packages: Set<String>, usesUv: Bool) {
        var names = Set<String>()
        var lines: [String] = []
        var usesUv = FileManager.default.fileExists(atPath: directory.appendingPathComponent("uv.lock").path)
        if let text = try? String(contentsOf: directory.appendingPathComponent("pyproject.toml"), encoding: .utf8),
           let root = try? TOMLTable(source: text)
        {
            if let project = try? root.table(forKey: "project"), let list = try? project.array(forKey: "dependencies") {
                lines += (0 ..< list.count).compactMap { try? list.string(atIndex: $0) }
            }
            if let tool = try? root.table(forKey: "tool"), (try? tool.table(forKey: "uv")) != nil {
                usesUv = true
            }
        }
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in files where name.hasPrefix("requirements") && name.hasSuffix(".txt") {
            let text = (try? String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)) ?? ""
            lines += text.split(whereSeparator: \.isNewline).map(String.init)
        }
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), !trimmed.hasPrefix("-") else { continue }
            let name = trimmed.prefix { $0.isLetter || $0.isNumber || "-_.".contains($0) }
            if !name.isEmpty {
                names.insert(name.lowercased().replacingOccurrences(of: "_", with: "-"))
            }
        }
        return (names, usesUv)
    }
}
