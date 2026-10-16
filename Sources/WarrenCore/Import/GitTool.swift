// SPDX-License-Identifier: Apache-2.0

import Foundation

public struct RepositoryInfo: Equatable, Sendable {
    public let branches: [String]
    public let defaultBranch: String?
}

public enum GitError: Error, Equatable, LocalizedError, Sendable {
    case notAvailable
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .notAvailable:
            "Git is not installed. Install the Command Line Tools (run xcode-select --install in a terminal), then try again."
        case let .failed(message): message
        }
    }
}

/// Warren's use of the system Git: the settings every call carries, looking a repository up, and turning Git's
/// failures into plain sentences. Git's own credential helpers do the signing in.
public struct GitTool: Sendable {
    public let executable: String
    private let protocols: String
    private let base: [String: String]

    /// `protocols` is what `GIT_ALLOW_PROTOCOL` permits. Production only ever uses `https:ssh`; tests widen it to
    /// reach a local repository.
    public init(
        executable: String = "/usr/bin/git", protocols: String = "https:ssh",
        base: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.executable = executable
        self.protocols = protocols
        self.base = base
    }

    /// The settings that make a Git call safe and non-interactive: only the named transports (so `ext::` cannot run a
    /// command), no terminal or SSH prompts (a credential failure is an error, not a hidden prompt), and timeouts.
    public static func safeEnvironment(protocols: String = "https:ssh") -> [String: String] {
        [
            "GIT_ALLOW_PROTOCOL": protocols,
            "GIT_TERMINAL_PROMPT": "0",
            "GIT_SSH_COMMAND": "ssh -o BatchMode=yes -o ConnectTimeout=10",
            "GIT_HTTP_LOW_SPEED_LIMIT": "1000",
            "GIT_HTTP_LOW_SPEED_TIME": "20",
            "GIT_LFS_SKIP_SMUDGE": "0",
        ]
    }

    /// Git is usable when the Command Line Tools (or Xcode) are installed. Asked without running `git`, which would
    /// open a system installer dialog on a Mac that lacks them.
    public var isAvailable: Bool {
        guard FileManager.default.isExecutableFile(atPath: executable) else { return false }
        if executable != "/usr/bin/git" {
            return true
        }
        guard let result = try? Shell.run("/usr/bin/xcode-select", ["-p"]) else { return false }
        return result.status == 0
    }

    private var environment: [String: String] {
        base.merging(Self.safeEnvironment(protocols: protocols)) { _, new in new }
    }

    /// The branches of a repository and which one is the default, without downloading it.
    public func inspect(_ address: String) throws -> RepositoryInfo {
        guard isAvailable else { throw GitError.notAvailable }
        let result = try Shell.run(
            executable, ["ls-remote", "--symref", "--", address, "HEAD", "refs/heads/*"], environment: environment
        )
        guard result.status == 0 else { throw GitError.failed(Self.explain(result.output)) }
        return Self.parseLsRemote(result.output)
    }

    static func parseLsRemote(_ output: String) -> RepositoryInfo {
        var branches: [String] = []
        var defaultBranch: String?
        for line in output.split(whereSeparator: \.isNewline) {
            let text = String(line)
            if text.hasPrefix("ref: refs/heads/") {
                defaultBranch = String(text.dropFirst("ref: refs/heads/".count).prefix { $0 != "\t" })
            } else if let range = text.range(of: "\trefs/heads/") {
                branches.append(String(text[range.upperBound...]))
            }
        }
        let ordered = branches.sorted { lhs, rhs in
            if lhs == defaultBranch {
                return true
            }
            if rhs == defaultBranch {
                return false
            }
            return lhs < rhs
        }
        return RepositoryInfo(branches: ordered, defaultBranch: defaultBranch ?? (ordered.first))
    }

    /// Git's failure text as a sentence a person can act on.
    public static func explain(_ output: String) -> String {
        let text = output.lowercased()
        if text.contains("terminal prompts disabled") || text.contains("authentication failed")
            || text.contains("could not read username") || text.contains("permission denied (publickey")
        {
            return "Git could not sign in to this repository. For GitHub, run gh auth login in a terminal, "
                + "or use an SSH address with a key in your agent."
        }
        if text.contains("not found") || text.contains("does not exist") || text.contains("repository not found") {
            return "That repository was not found, or your account cannot see it."
        }
        if text.contains("could not resolve host") || text.contains("network is unreachable")
            || text.contains("timed out") || text.contains("operation too slow")
        {
            return "The network looks unreachable. Check the connection and try again."
        }
        if text.contains("host key verification failed") {
            return "SSH does not know this host yet. Connect once from a terminal (ssh -T git@github.com) and accept its key."
        }
        if text.contains("transport"), text.contains("not allowed") {
            return "Warren only clones over https or ssh."
        }
        let last = output.split(whereSeparator: \.isNewline).last.map(String.init)?.trimmingCharacters(in: .whitespaces)
        return last.flatMap { $0.isEmpty ? nil : $0 } ?? "Git could not read this repository."
    }
}
