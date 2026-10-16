// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum RepositoryError: Error, Equatable, LocalizedError, Sendable {
    case empty
    case unsupported(String)
    case unsafe(String)

    public var errorDescription: String? {
        switch self {
        case .empty: "Enter a repository, such as acme/shop or https://github.com/acme/shop."
        case let .unsupported(text):
            "'\(text)' is not a repository address Warren understands. Use owner/name, a github.com address, "
                + "or an https:// or ssh:// Git address."
        case let .unsafe(text):
            "Warren will not clone '\(text)': that kind of address can run commands or read local files."
        }
    }
}

/// A repository address as the user wrote it, turned into something safe to hand to `git clone`.
public struct RepositoryReference: Equatable, Sendable {
    /// The address passed to Git.
    public let address: String
    /// The folder name suggested for it (`shop` for `acme/shop`).
    public let name: String
    /// A branch named in the address (`/tree/<branch>`), if any.
    public let branch: String?
    /// `owner/repo` for GitHub addresses, shown in the UI.
    public let displayName: String

    /// `acme/shop`, `github.com/acme/shop`, `https://github.com/acme/shop[/tree/branch]`,
    /// `git@github.com:acme/shop.git`,
    /// and other `https://` or `ssh://` addresses. Anything that could run a command or read the disk is refused.
    public static func parse(_ input: String) throws -> RepositoryReference {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw RepositoryError.empty }
        guard !text.hasPrefix("-"), !text.contains("::"), !text.lowercased().hasPrefix("file:"),
              !text.hasPrefix("/"), !text.hasPrefix("."), !text.hasPrefix("~"), !text.lowercased().hasPrefix("git://"),
              !text.lowercased().hasPrefix("http://")
        else { throw RepositoryError.unsafe(text) }
        guard !text.contains(where: \.isWhitespace) else { throw RepositoryError.unsupported(text) }

        if let scp = scpAddress(text) {
            return scp
        }
        if text.contains("://") {
            return try url(text)
        }
        return try shorthand(text)
    }

    // MARK: Forms

    /// `git@host:owner/repo.git`
    private static func scpAddress(_ text: String) -> RepositoryReference? {
        guard !text.contains("://"), let atSign = text.firstIndex(of: "@"), let colon = text.firstIndex(of: ":"),
              atSign < colon
        else { return nil }
        let host = text[text.index(after: atSign) ..< colon]
        let path = String(text[text.index(after: colon)...])
        guard !host.isEmpty, host.allSatisfy({ $0.isLetter || $0.isNumber || ".-".contains($0) }),
              path.split(separator: "/").count >= 2, !path.hasPrefix("/") else { return nil }
        return RepositoryReference(
            address: text, name: repoName(path), branch: nil, displayName: path.replacingOccurrences(
                of: ".git",
                with: ""
            )
        )
    }

    private static func url(_ text: String) throws -> RepositoryReference {
        guard let components = URLComponents(string: text), let scheme = components.scheme?.lowercased(),
              ["https", "ssh"].contains(scheme), let host = components.host, !host.isEmpty
        else { throw RepositoryError.unsupported(text) }
        var parts = components.path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { throw RepositoryError.unsupported(text) }
        var branch: String?
        if host == "github.com", parts.count >= 4, parts[2] == "tree" {
            branch = parts[3...].joined(separator: "/")
            parts = Array(parts.prefix(2))
        }
        let path = parts.joined(separator: "/")
        let address = host == "github.com" && scheme == "https"
            ? "https://github.com/\(trimmedGit(path)).git" : text.replacingOccurrences(
                of: "/tree/\(branch ?? "")",
                with: ""
            )
        return RepositoryReference(
            address: address, name: repoName(path), branch: branch,
            displayName: host == "github.com" ? trimmedGit(path) : "\(host)/\(trimmedGit(path))"
        )
    }

    /// `acme/shop` or `github.com/acme/shop`
    private static func shorthand(_ text: String) throws -> RepositoryReference {
        var parts = text.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if parts.first?.lowercased() == "github.com" || parts.first?.lowercased() == "www.github.com" {
            parts.removeFirst()
            return try url("https://github.com/" + parts.joined(separator: "/"))
        }
        let valid: (String) -> Bool = { part in
            !part.isEmpty && part.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }
        }
        guard parts.count == 2, parts.allSatisfy(valid) else { throw RepositoryError.unsupported(text) }
        return try url("https://github.com/" + text)
    }

    private static func trimmedGit(_ path: String) -> String {
        path.hasSuffix(".git") ? String(path.dropLast(4)) : path
    }

    private static func repoName(_ path: String) -> String {
        trimmedGit(String(path.split(separator: "/").last ?? "project"))
    }
}
