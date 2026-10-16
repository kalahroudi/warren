// SPDX-License-Identifier: Apache-2.0

import Foundation

public struct GitHubRepository: Identifiable, Equatable, Codable, Sendable {
    public let nameWithOwner: String
    public let description: String?
    public let isPrivate: Bool

    public var id: String {
        nameWithOwner
    }
}

public enum GitHubCLIState: Equatable, Sendable {
    case notInstalled
    case signedOut
    case ready
}

/// The GitHub CLI, used only to list the user's repositories. Not installed or signed in by Warren.
public struct GitHubCLI: Sendable {
    private let executable: String?
    private let environment: [String: String]

    public init(
        executable: String? = GitHubCLI.locate(), environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.executable = executable
        self.environment = environment
    }

    /// Homebrew puts `gh` outside the PATH a menu bar app inherits, so the usual places are checked too.
    public static func locate() -> String? {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let folders = path.split(separator: ":").map(String.init) + ["/opt/homebrew/bin", "/usr/local/bin"]
        return folders.map { "\($0)/gh" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public var state: GitHubCLIState {
        guard let executable else { return .notInstalled }
        let result = try? Shell.run(executable, ["auth", "status"], environment: environment)
        return result?.status == 0 ? .ready : .signedOut
    }

    public func repositories(limit: Int = 100) throws -> [GitHubRepository] {
        guard let executable else { return [] }
        let result = try Shell.run(
            executable,
            ["repo", "list", "--limit", String(limit), "--json", "nameWithOwner,description,isPrivate"],
            environment: environment
        )
        guard result.status == 0
        else { throw GitError.failed(result.output.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return try Self.parse(result.output)
    }

    static func parse(_ json: String) throws -> [GitHubRepository] {
        try JSONDecoder().decode([GitHubRepository].self, from: Data(json.utf8))
    }
}
