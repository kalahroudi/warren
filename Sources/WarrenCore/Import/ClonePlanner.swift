// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The plan that fills a new, registered, empty folder with a repository. Run by the 012 runner; once it has run, the
/// project's normal setup plan takes over. Cloning runs no code from the repository, so the step needs no approval.
public enum ClonePlanner {
    public static func plan(_ reference: RepositoryReference, branch: String?, site: ResolvedSite) -> SetupPlan {
        var command = ["/usr/bin/git", "clone", "--progress"]
        if let branch = branch ?? reference.branch, !branch.isEmpty {
            command += ["--branch", branch]
        }
        command += ["--", reference.address, "."]
        var payload: [String: String] = [:]
        for (key, value) in GitTool.safeEnvironment() {
            payload["env.\(key)"] = value
        }
        let step = PlanStep(
            id: "clone", kind: .clone, title: "Clone \(reference.displayName)",
            detail: "Downloads the repository into the project folder. Nothing from it runs.",
            command: command, runsProjectCode: false, state: .todo, waitsFor: [], enabledByDefault: true,
            payload: payload
        )
        return SetupPlan(
            siteID: site.id, folder: site.path, detection: .unknown, runtimes: [],
            env: EnvSummary(example: nil, envExists: false, emptyVariables: []), services: [], steps: [step]
        )
    }
}
