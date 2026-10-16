// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A dotenv file read for its keys and values. Nothing in it is run or expanded.
struct EnvFile: Equatable, Sendable {
    /// Variables in file order. The last assignment of a key wins.
    private(set) var variables: [(key: String, value: String)] = []

    init(_ text: String) {
        for rawLine in text.split(whereSeparator: \.isNewline) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            if line.hasPrefix("export ") {
                line = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            }
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, key.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") })
            else { continue }
            variables.removeAll { $0.key == key }
            variables.append((key, Self.value(String(line[line.index(after: equals)...]))))
        }
    }

    init(contentsOf url: URL) {
        self.init((try? String(contentsOf: url, encoding: .utf8)) ?? "")
    }

    static func == (lhs: EnvFile, rhs: EnvFile) -> Bool {
        lhs.variables.map { "\($0.key)=\($0.value)" } == rhs.variables.map { "\($0.key)=\($0.value)" }
    }

    subscript(key: String) -> String? {
        variables.first { $0.key == key }?.value
    }

    var keys: [String] {
        variables.map(\.key)
    }

    /// Keys whose value is empty: the ones a person has to fill in.
    var emptyKeys: [String] {
        variables.filter(\.value.isEmpty).map(\.key)
    }

    /// Keys a person still has to fill in: empty, or a placeholder such as `YOUR_KEY` or `<token>`.
    var unsetKeys: [String] {
        variables.filter { $0.value.isEmpty || Self.isPlaceholder($0.value) }.map(\.key)
    }

    /// Example values that stand in for a real one. Real defaults (`password`, `localhost`) are not placeholders.
    static func isPlaceholder(_ value: String) -> Bool {
        let text = value.lowercased().trimmingCharacters(in: .whitespaces)
        if text.isEmpty {
            return true
        }
        if text.hasPrefix("<"), text.hasSuffix(">") {
            return true
        }
        if text.hasPrefix("your_") || text.hasPrefix("your-") || text.hasPrefix("your ") {
            return true
        }
        return ["changeme", "change_me", "change-me", "replace_me", "replace-me", "todo", "xxx"]
            .contains { text.contains($0) }
            || text.contains("xxxxxxxx")
    }

    /// Strips quotes and a trailing ` # comment` from an unquoted value.
    private static func value(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespaces)
        for quote in ["\"", "'"] where text.hasPrefix(quote) {
            let rest = text.dropFirst()
            if let end = rest.firstIndex(of: Character(quote)) {
                return String(rest[..<end])
            }
        }
        if let hash = text.range(of: " #") {
            return String(text[..<hash.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        return text
    }

    static let exampleNames = [".env.example", ".env.sample", ".env.dist", ".env.template"]
}
