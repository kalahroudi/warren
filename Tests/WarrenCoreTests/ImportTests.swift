// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import WarrenCore

private final class Sink: @unchecked Sendable {
    private let lock = NSLock()
    private var texts: [String] = []
    private var environments: [[String: String]] = []

    func add(_ text: String) {
        lock.withLock { texts.append(text) }
    }

    func add(environment: [String: String]) {
        lock.withLock { environments.append(environment) }
    }

    var all: String {
        lock.withLock { texts.joined(separator: "\n") }
    }

    var allEnvironments: [[String: String]] {
        lock.withLock { environments }
    }
}

struct ImportTests {
    private let root: URL
    private let paths: WarrenPaths

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("wim-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        paths = WarrenPaths(root: root.appendingPathComponent("home"))
    }

    // MARK: Addresses

    @Test func everyAcceptedFormBecomesACloneAddressAndName() throws {
        struct Case {
            let input: String
            let address: String
            let name: String
            var branch: String?
        }
        let cases = [
            Case(input: "acme/shop", address: "https://github.com/acme/shop.git", name: "shop"),
            Case(input: "github.com/acme/shop", address: "https://github.com/acme/shop.git", name: "shop"),
            Case(input: "https://github.com/acme/shop", address: "https://github.com/acme/shop.git", name: "shop"),
            Case(input: "https://github.com/acme/shop.git", address: "https://github.com/acme/shop.git", name: "shop"),
            Case(
                input: "https://github.com/acme/shop/tree/dev",
                address: "https://github.com/acme/shop.git",
                name: "shop",
                branch: "dev"
            ),
            Case(
                input: "https://github.com/acme/shop/tree/feature/x",
                address: "https://github.com/acme/shop.git",
                name: "shop",
                branch: "feature/x"
            ),
            Case(input: "git@github.com:acme/shop.git", address: "git@github.com:acme/shop.git", name: "shop"),
            Case(
                input: "ssh://git@gitlab.com/acme/shop.git",
                address: "ssh://git@gitlab.com/acme/shop.git",
                name: "shop"
            ),
            Case(
                input: "https://gitlab.com/acme/group/shop.git",
                address: "https://gitlab.com/acme/group/shop.git",
                name: "shop"
            ),
            Case(input: "  acme/my-app.v2  ", address: "https://github.com/acme/my-app.v2.git", name: "my-app.v2"),
        ]
        for item in cases {
            let found = try RepositoryReference.parse(item.input)
            #expect(found.address == item.address, "\(item.input)")
            #expect(found.name == item.name && found.branch == item.branch, "\(item.input)")
        }
        #expect(try RepositoryReference.parse("acme/shop").displayName == "acme/shop")
    }

    @Test func addressesThatCouldRunCommandsOrReadTheDiskAreRefused() {
        for bad in [
            "ext::sh -c touch /tmp/x", "ext::sh", "--upload-pack=touch x", "-oProxyCommand=x", "file:///etc/passwd",
            "/Users/me/repo", "./repo", "../repo", "~/repo", "git://github.com/acme/shop",
            "http://github.com/acme/shop",
        ] {
            #expect(throws: RepositoryError.unsafe(bad)) { try RepositoryReference.parse(bad) }
        }
        for unsupported in ["acme", "acme/shop/extra", "a b/c", "https://github.com/acme", "ftp://x/y/z",
                            "ssh://host"]
        {
            #expect(throws: RepositoryError.self) { try RepositoryReference.parse(unsupported) }
        }
        #expect(throws: RepositoryError.empty) { try RepositoryReference.parse("   ") }
    }

    // MARK: Git

    private func git(_ arguments: [String], in directory: URL) throws {
        let environment = [
            "PATH": "/usr/bin:/bin", "HOME": root.path, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@example.test",
            "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@example.test", "GIT_CONFIG_GLOBAL": "/dev/null",
        ]
        let result = try Shell.run("/usr/bin/git", arguments, environment: environment, directory: directory)
        #expect(result.status == 0, "git \(arguments): \(result.output)")
    }

    /// A bare repository with two branches, `main` being the default.
    private func bareRepository() throws -> URL {
        let work = root.appendingPathComponent("work")
        let bare = root.appendingPathComponent("remote.git")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try git(["init", "-q", "-b", "main"], in: work)
        try "package".write(to: work.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        try git(["add", "."], in: work)
        try git(["commit", "-q", "-m", "first"], in: work)
        try git(["branch", "dev"], in: work)
        try git(["clone", "-q", "--bare", work.path, bare.path], in: root)
        try git(["symbolic-ref", "HEAD", "refs/heads/main"], in: bare)
        return bare
    }

    @Test func aRepositoryIsInspectedForBranchesAndItsDefault() throws {
        let bare = try bareRepository()
        let info = try GitTool(protocols: "https:ssh:file").inspect(bare.path)
        #expect(info.branches == ["main", "dev"] && info.defaultBranch == "main")
    }

    @Test func gitsFailuresBecomePlainSentences() {
        #expect(GitTool.explain("fatal: could not read Username for 'https://github.com': terminal prompts disabled")
            .contains("gh auth login"))
        #expect(GitTool.explain("remote: Repository not found.\nfatal: repository 'x' not found").contains("not found"))
        #expect(GitTool.explain("fatal: unable to access: Could not resolve host: github.com").contains("network"))
        #expect(GitTool.explain("git@github.com: Permission denied (publickey).").contains("SSH address"))
        #expect(GitTool.explain("Host key verification failed.").contains("ssh -T"))
        #expect(GitTool.explain("fatal: transport 'file' not allowed").contains("https or ssh"))
    }

    @Test func aMissingRepositoryGivesTheNotFoundSentence() throws {
        let missing = root.appendingPathComponent("nothing.git")
        #expect(throws: GitError.self) { try GitTool(protocols: "https:ssh:file").inspect(missing.path) }
    }

    @Test func everyGitCallCarriesTheSafeSettings() {
        let settings = GitTool.safeEnvironment()
        #expect(settings["GIT_ALLOW_PROTOCOL"] == "https:ssh")
        #expect(settings["GIT_TERMINAL_PROMPT"] == "0")
        #expect(settings["GIT_SSH_COMMAND"]?.contains("BatchMode=yes") == true)
        let plan = ClonePlanner.plan(
            (try? RepositoryReference.parse("acme/shop")) ?? RepositoryReference(
                address: "",
                name: "",
                branch: nil,
                displayName: ""
            ),
            branch: nil, site: ResolvedSite(
                id: "s", path: root.path, name: "s", domains: ["s.test"], runtimes: [:], command: nil, port: nil,
                services: [:], problems: [], warnings: []
            )
        )
        #expect(plan.steps[0].payload["env.GIT_ALLOW_PROTOCOL"] == "https:ssh")
        #expect(plan.steps[0].payload["env.GIT_TERMINAL_PROMPT"] == "0")
    }

    @Test func theExtTransportCannotRunACommandEvenIfItReachesGit() throws {
        let marker = root.appendingPathComponent("pwned")
        let address = "ext::sh -c 'touch \(marker.path)'"
        #expect(throws: GitError.self) { try GitTool().inspect(address) }
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    // MARK: Clone

    @Test func aCloneRunsAsAPlanStepInTheNewFolderAndItsFailureLeavesTheSite() async throws {
        let bare = try bareRepository()
        let creator = ProjectCreator(paths: paths)
        let reference = RepositoryReference(address: bare.path, name: "remote", branch: nil, displayName: "acme/remote")
        let site = try creator.create(NewProjectRequest(
            name: "cloned", location: root.appendingPathComponent("Sites"), source: .repository(
                reference,
                branch: "dev"
            )
        ))
        var plan = ClonePlanner.plan(reference, branch: "dev", site: site)
        // The test repository is local, so the file transport is allowed for this one step.
        plan.steps[0].payload["env.GIT_ALLOW_PROTOCOL"] = "https:ssh:file"
        var base = ProcessInfo.processInfo.environment
        base["HOME"] = root.path
        let lines = Sink()
        let summary = await PlanRunner(paths: paths, site: site, baseEnvironment: base)
            .run(plan: plan, approve: { .all($0) }, onEvent: { event in
                if case let .output(_, line) = event {
                    lines.add(line)
                }
            })
        #expect(summary.succeeded, "\(summary.results) \(lines.all)")
        #expect(FileManager.default
            .fileExists(atPath: URL(fileURLWithPath: site.path).appendingPathComponent("package.json").path))

        // Cloning into a folder that now has files fails, the site and its files stay, and the reason is plain.
        let again = await PlanRunner(paths: paths, site: site, baseEnvironment: base)
            .run(plan: plan, approve: { .all($0) }, onEvent: { _ in })
        if case let .failed(_, tail) = again.results["clone"] {
            #expect(PlanRunner.advice(forFailureLines: tail, exitCode: 128) != nil || !tail.isEmpty)
        } else {
            Issue.record("a second clone into a filled folder should fail")
        }
        #expect(try SiteRegistry(paths: paths).show(id: site.id).id == site.id)
    }

    @Test func theCloneStepRunsNoProjectCodeSoItNeedsNoApproval() throws {
        let site = ResolvedSite(
            id: "s", path: root.path, name: "s", domains: ["s.test"], runtimes: [:], command: nil, port: nil,
            services: [:], problems: [], warnings: []
        )
        let plan = try ClonePlanner.plan(RepositoryReference.parse("acme/shop"), branch: "main", site: site)
        let step = plan.steps[0]
        #expect(!step.runsProjectCode && step.kind == .clone)
        #expect(step.command == [
            "/usr/bin/git",
            "clone",
            "--progress",
            "--branch",
            "main",
            "--",
            "https://github.com/acme/shop.git",
            "."
        ])
    }

    // MARK: The GitHub CLI

    @Test func theRepositoryListIsReadFromGhsJSON() throws {
        let json = """
        [{"nameWithOwner":"acme/shop","description":"A shop","isPrivate":true},
         {"nameWithOwner":"acme/site","description":null,"isPrivate":false}]
        """
        let repos = try GitHubCLI.parse(json)
        #expect(repos.map(\.nameWithOwner) == ["acme/shop", "acme/site"])
        #expect(repos[0].isPrivate && repos[1].description == nil)
        #expect(GitHubCLI(executable: nil).state == .notInstalled)
        #expect(try GitHubCLI(executable: nil).repositories().isEmpty)
    }
}
