// SPDX-License-Identifier: Apache-2.0

import Foundation
import Security

/// One variable `.env` leaves empty, and what Warren can offer for it.
public struct EnvPrompt: Identifiable, Equatable, Codable, Sendable {
    public enum Offer: String, Codable, Sendable {
        case none
        /// The site's own address.
        case siteURL
        /// A random value, for a secret that belongs to this project alone.
        case generate
    }

    public let name: String
    public let isSecret: Bool
    public let offer: Offer

    public var id: String {
        name
    }
}

public enum EnvPrompts {
    private static let siteURLNames: Set = [
        "APP_URL", "NEXTAUTH_URL", "AUTH_URL", "BETTER_AUTH_URL", "SITE_URL", "BASE_URL", "PUBLIC_URL",
        "NEXT_PUBLIC_APP_URL", "NEXT_PUBLIC_SITE_URL", "NEXT_PUBLIC_BASE_URL", "NEXT_PUBLIC_URL", "VITE_APP_URL",
    ]

    /// Secrets that belong to this project alone, so a random local value is right. Third-party keys are not here.
    private static let generatedNames: Set = [
        "AUTH_SECRET", "NEXTAUTH_SECRET", "BETTER_AUTH_SECRET", "SESSION_SECRET", "JWT_SECRET", "COOKIE_SECRET",
        "ENCRYPTION_KEY", "SECRET_KEY", "SECRET_KEY_BASE", "APP_SECRET",
    ]

    private static let secretWords = ["KEY", "SECRET", "TOKEN", "PASSWORD", "DSN", "PRIVATE", "CREDENTIAL"]
    private static let publicPrefixes = ["NEXT_PUBLIC_", "VITE_", "PUBLIC_", "NUXT_PUBLIC_"]

    /// The empty variables worth asking about. `APP_KEY` is left to Laravel's key step.
    static func prompts(for env: EnvFile) -> [EnvPrompt] {
        prompts(current: env, example: nil)
    }

    /// Variables empty or placeholders in `.env`, plus ones the example leaves unset that `.env` does not have yet.
    static func prompts(current: EnvFile?, example: EnvFile?) -> [EnvPrompt] {
        var names = current?.unsetKeys ?? []
        for name in example?.unsetKeys ?? [] where !names.contains(name) && current?[name] == nil {
            names.append(name)
        }
        return names.filter { $0 != "APP_KEY" }.map { name in
            let isPublic = publicPrefixes.contains { name.hasPrefix($0) }
            let isSecret = !isPublic && secretWords.contains { name.contains($0) } && !siteURLNames.contains(name)
            let offer: EnvPrompt.Offer = siteURLNames.contains(name) ? .siteURL
                : generatedNames.contains(name) ? .generate : .none
            return EnvPrompt(name: name, isSecret: isSecret, offer: offer)
        }
    }

    /// What the "use the site's address" offer fills in.
    public static func siteURL(domain: String) -> String {
        "https://\(domain)"
    }

    /// 32 random bytes as hex, from the system's secure generator.
    public static func generatedSecret() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "no secure random bytes")
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

/// Fills chosen empty variables in a `.env` file, changing only their lines.
public enum EnvEditor {
    /// Only variables that are empty or placeholders in the file are changed; the rest of the file is kept as it is. A
    /// variable
    /// with no line is added at the end. Returns the names that were written.
    @discardableResult
    public static func apply(_ values: [String: String], to file: URL) throws -> [String] {
        let original = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        var written: [String] = []
        var lines = original.components(separatedBy: "\n")
        let current = EnvFile(original)
        for (name, value) in values.sorted(by: { $0.key < $1.key }) where !value.isEmpty {
            if let existing = current[name], !existing.isEmpty, !EnvFile.isPlaceholder(existing) {
                continue
            }
            if let index = lines.firstIndex(where: { isAssignment($0, of: name) }) {
                let prefix = lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("export ") ? "export " : ""
                lines[index] = "\(prefix)\(name)=\(quoted(value))"
            } else {
                if lines.last == "" {
                    lines.removeLast()
                }
                lines.append("\(name)=\(quoted(value))")
                lines.append("")
            }
            written.append(name)
        }
        guard !written.isEmpty else { return [] }
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        return written
    }

    private static func isAssignment(_ line: String, of name: String) -> Bool {
        var text = line.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("export ") {
            text = String(text.dropFirst(7)).trimmingCharacters(in: .whitespaces)
        }
        return text.hasPrefix(name + "=") || text.hasPrefix(name + " =")
    }

    /// Plain when it is plain; single quotes when it has spaces, `#`, `$` or quotes; double quotes if it has `'`.
    static func quoted(_ value: String) -> String {
        let special = value.contains { $0.isWhitespace || "#$\"'\\`".contains($0) }
        guard special else { return value }
        if !value.contains("'") {
            return "'\(value)'"
        }
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
        return "\"\(escaped)\""
    }

    /// Whether `.gitignore` covers `.env`, for the note on the values sheet. Unknown (no `.gitignore`) counts as no.
    public static func isIgnored(in project: URL) -> Bool {
        guard let text = try? String(contentsOf: project.appendingPathComponent(".gitignore"), encoding: .utf8)
        else { return false }
        return text.split(whereSeparator: \.isNewline).contains { line in
            let entry = line.trimmingCharacters(in: .whitespaces)
            return [".env", "/.env", ".env*", ".env.*", "*.env", ".env.local"].contains(entry) && !entry.hasPrefix("#")
        }
    }
}
