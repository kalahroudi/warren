// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Works out which runtime versions a site asks for, and which installed version satisfies each.
/// Order: `[runtime]` in `.warren.toml`, then the project's version files, then `engines.node`.
public enum RuntimeResolver {
    public static func requirements(for site: ResolvedSite) -> [RuntimeRequirement] {
        let directory = URL(fileURLWithPath: site.path, isDirectory: true)
        var found: [RuntimeKind: RuntimeRequirement] = [:]
        for (name, version) in site.runtimes {
            if let kind = RuntimeKind(rawValue: name) {
                found[kind] = RuntimeRequirement(kind: kind, requested: version, source: .warrenConfig)
            }
        }
        for requirement in versionFiles(in: directory) where found[requirement.kind] == nil {
            found[requirement.kind] = requirement
        }
        if found[.node] == nil, let range = enginesNode(in: directory) {
            found[.node] = RuntimeRequirement(kind: .node, requested: range, source: .engines)
        }
        return RuntimeKind.allCases.compactMap { found[$0] }
    }

    /// `.nvmrc`, `.node-version`, `.bun-version` and `.tool-versions`.
    static func versionFiles(in directory: URL) -> [RuntimeRequirement] {
        var found: [RuntimeRequirement] = []
        for kind in RuntimeKind.allCases {
            for name in kind.versionFiles {
                if let text = read(directory.appendingPathComponent(name)), let version = normalize(firstToken(text)) {
                    found.append(RuntimeRequirement(kind: kind, requested: version, source: .file(name)))
                    break
                }
            }
        }
        if let text = read(directory.appendingPathComponent(".tool-versions")) {
            for line in text.split(whereSeparator: \.isNewline) {
                let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
                // "nodejs" is asdf's name for Node.
                guard fields.count >= 2, !fields[0].hasPrefix("#"),
                      let kind = RuntimeKind(rawValue: fields[0] == "nodejs" ? "node" : fields[0]),
                      !found.contains(where: { $0.kind == kind }),
                      let version = normalize(fields[1]) else { continue }
                found.append(RuntimeRequirement(kind: kind, requested: version, source: .file(".tool-versions")))
            }
        }
        return found
    }

    /// The range in `package.json` `engines.node`, as written.
    static func enginesNode(in directory: URL) -> String? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("package.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let engines = json["engines"] as? [String: Any],
              let node = engines["node"] as? String,
              VersionRange(node) != nil else { return nil }
        return node.trimmingCharacters(in: .whitespaces)
    }

    /// Turns what version files write into what mise understands: `v22.1.0` to `22.1.0`, `lts/iron` to `lts-iron`.
    static func normalize(_ text: String) -> String? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.hasPrefix("#") else { return nil }
        if value.hasPrefix("lts/") {
            value = value == "lts/*" ? "lts" : "lts-" + value.dropFirst(4)
        }
        if ["node", "stable", "latest"].contains(value) {
            return "latest"
        }
        if value.hasPrefix("v"), value.dropFirst().first?.isNumber == true {
            value.removeFirst()
        }
        return value
    }

    private static func read(_ file: URL) -> String? {
        try? String(contentsOf: file, encoding: .utf8)
    }

    private static func firstToken(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).first(where: { !$0.hasPrefix("#") }).map(String.init) ?? ""
    }

    // MARK: Matching

    /// The highest installed version that satisfies the requirement, or nil if none does.
    public static func match(_ requirement: RuntimeRequirement, among installed: [String]) -> String? {
        let versions = installed.compactMap { text in SemanticVersion(text).map { (text, $0) } }
        let matching: [(String, SemanticVersion)]
        switch requirement.source {
        case .engines:
            guard let range = VersionRange(requirement.requested) else { return nil }
            matching = versions.filter { range.contains($0.1) }
        default:
            let wanted = requirement.requested
            if wanted == "latest" || wanted.hasPrefix("lts") {
                matching = versions
            } else {
                matching = versions.filter { $0.0 == wanted || $0.0.hasPrefix(wanted + ".") }
            }
        }
        return matching.max { $0.1 < $1.1 }?.0
    }

    /// The version to install for a requirement. Plain requests go to mise as written. A range is resolved against
    /// the releases that exist: the newest that satisfies it, preferring long-term-support lines (even majors).
    public static func versionToInstall(for requirement: RuntimeRequirement, available: [String]) -> String? {
        guard requirement.source == .engines else { return requirement.requested }
        guard let range = VersionRange(requirement.requested) else { return nil }
        let candidates = available.compactMap { text in SemanticVersion(text).map { (text, $0) } }
            .filter { range.contains($0.1) }
        let longTerm = candidates.filter { $0.1.major.isMultiple(of: 2) }
        return (longTerm.isEmpty ? candidates : longTerm).max { $0.1 < $1.1 }?.0
    }
}
