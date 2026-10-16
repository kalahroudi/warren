// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation
import WarrenCore

let importUsage = """
usage: warren repo list [--json]
       warren site clone <repo> [name] [--branch <branch>] [--location <folder>] [--domain <name>] [--yes]

  <repo> is owner/name, a github.com address, or another https:// or ssh:// Git address.
  Clones into the location (default ~/Sites), registers the site and runs its setup. Commands from the project ask
  first. Empty .env values are asked one by one (secret ones without echo; Enter skips). --yes approves the
  commands after printing them and skips every value.
"""

func listRepositories(json: Bool) throws {
    let cli = GitHubCLI()
    switch cli.state {
    case .notInstalled: throw CLIError("the GitHub CLI (gh) is not installed. Install it to list your repositories.")
    case .signedOut: throw CLIError("the GitHub CLI is not signed in. Run: gh auth login")
    case .ready: break
    }
    let repositories = try cli.repositories()
    if json {
        printJSON(repositories)
    } else {
        for repository in repositories {
            print(
                "\(repository.nameWithOwner)\(repository.isPrivate ? "  (private)" : "")  \(repository.description ?? "")"
            )
        }
    }
}

func cloneRepository(_ arguments: [String], paths: WarrenPaths) async throws {
    var rest = arguments
    func option(_ name: String) -> String? {
        guard let index = rest.firstIndex(of: name), index + 1 < rest.count else { return nil }
        let value = rest[index + 1]
        rest.removeSubrange(index ... index + 1)
        return value
    }
    let assumeYes = rest.contains("--yes")
    rest.removeAll { $0 == "--yes" }
    let location = option("--location").map { URL(
        fileURLWithPath: ($0 as NSString).expandingTildeInPath,
        isDirectory: true
    ) }
    let branch = option("--branch")
    let domain = option("--domain")
    guard let address = rest.first else { throw CLIError(importUsage) }
    let reference = try RepositoryReference.parse(address)
    let git = GitTool()
    guard git.isAvailable else { throw GitError.notAvailable }
    let info = try git.inspect(reference.address)
    let chosen = branch ?? reference.branch
    if let chosen, !info.branches.contains(chosen) {
        throw CLIError("branch '\(chosen)' not found. Branches: \(info.branches.joined(separator: ", "))")
    }

    let request = NewProjectRequest(
        name: rest.dropFirst().first ?? reference.name, location: location ?? ProjectCreator.defaultLocation,
        domain: domain, source: .repository(reference, branch: chosen)
    )
    let site = try ProjectCreator(paths: paths).create(request)
    syncRunningNetwork(paths: paths)
    print("created \(site.path) as \(site.id) (\(site.domains.joined(separator: ", ")))")

    let clone = ClonePlanner.plan(reference, branch: chosen ?? info.defaultBranch, site: site)
    guard await execute(clone, site: site, paths: paths, assumeYes: assumeYes).succeeded
    else { throw CLIError("the clone did not finish") }

    let manager = RuntimeManager(paths: paths)
    let plan = SetupPlanner(paths: paths).plan(
        for: site, registered: true, inventory: (try? manager.inventory()) ?? [],
        tools: (try? manager.installedTools()) ?? []
    )
    guard !PlanRunner.selectedSteps(plan).isEmpty else {
        print("done")
        return
    }
    guard await execute(plan, site: site, paths: paths, assumeYes: assumeYes).succeeded
    else { throw CLIError("setup is not finished: some steps were skipped, stopped or failed") }
    print("done")
}

/// Asks for each empty variable in the terminal. Secret names are read without echo; Enter skips.
func askValues(_ prompts: [EnvPrompt], domain: String, assumeYes: Bool) -> [String: String] {
    if assumeYes {
        return [:]
    }
    var answers: [String: String] = [:]
    print("values needed (Enter to skip):")
    for prompt in prompts {
        var hint = ""
        switch prompt.offer {
        case .siteURL: hint = " [Enter for \(EnvPrompts.siteURL(domain: domain))]"
        case .generate: hint = " [Enter to generate]"
        case .none: break
        }
        let label = "  \(prompt.name)\(hint): "
        let entered: String
        // Secret names are read without echo on a terminal; piped input is read as it comes.
        if prompt.isSecret, isatty(STDIN_FILENO) != 0, let secret = getpass(label) {
            entered = String(cString: secret)
        } else {
            print(label, terminator: "")
            entered = readLine() ?? ""
        }
        if !entered.isEmpty {
            answers[prompt.name] = entered
        } else if prompt.offer == .siteURL {
            answers[prompt.name] = EnvPrompts.siteURL(domain: domain)
        } else if prompt.offer == .generate {
            answers[prompt.name] = EnvPrompts.generatedSecret()
        }
    }
    return answers
}
