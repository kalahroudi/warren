// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI
import WarrenCore

/// State of the "From GitHub" pane: the address, its branches, name, domain and place. Looking a repository up
/// downloads nothing; creating makes the folder and registers the site, and the clone runs as a plan step.
@MainActor
final class GitHubImportModel: ObservableObject {
    @Published var address = "" {
        didSet { addressChanged() }
    }

    @Published private(set) var reference: RepositoryReference?
    @Published private(set) var branches: [String] = []
    @Published var branch = ""
    @Published private(set) var inspecting = false
    @Published private(set) var addressProblem: String?
    @Published var name = "" {
        didSet { nameChanged() }
    }

    @Published var domain = "" {
        didSet {
            if !updatingDomain {
                domainEdited = !domain.isEmpty
            }; validate()
        }
    }

    @Published var location = ProjectCreator.defaultLocation {
        didSet { validate() }
    }

    @Published private(set) var problem: String?
    @Published private(set) var creating = false
    @Published private(set) var repositories: [GitHubRepository] = []
    @Published private(set) var cliState = GitHubCLIState.notInstalled
    @Published private(set) var loadingRepositories = false

    private let paths: WarrenPaths
    private let onCreated: (ResolvedSite, RepositoryReference, String?) -> Void
    private var domainEdited = false
    private var updatingDomain = false
    private var nameEdited = false
    private var updatingName = false
    private var inspection = 0
    private var validation = 0

    init(paths: WarrenPaths, onCreated: @escaping (ResolvedSite, RepositoryReference, String?) -> Void) {
        self.paths = paths
        self.onCreated = onCreated
    }

    var canCreate: Bool {
        reference != nil && addressProblem == nil && problem == nil && !creating && !inspecting
            && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var gitAvailable: Bool {
        GitTool().isAvailable
    }

    // MARK: Address and branches

    private func addressChanged() {
        inspection += 1
        let current = inspection
        branches = []
        reference = nil
        let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            addressProblem = nil
            return
        }
        do {
            let parsed = try RepositoryReference.parse(text)
            addressProblem = nil
            reference = parsed
            if !nameEdited {
                setName(parsed.name)
            }
            if let hinted = parsed.branch {
                branch = hinted
            }
            inspecting = true
            Task {
                // Wait a moment so typing does not look the repository up at every keystroke.
                try? await Task.sleep(for: .milliseconds(500))
                guard current == inspection else { return }
                let outcome = await Task.detached { () -> (RepositoryInfo?, String?) in
                    do { return try (GitTool().inspect(parsed.address), nil) } catch { return (
                        nil,
                        error.localizedDescription
                    ) }
                }.value
                guard current == inspection else { return }
                inspecting = false
                if let info = outcome.0 {
                    branches = info.branches
                    if branch.isEmpty || !info.branches
                        .contains(branch)
                    {
                        branch = info.defaultBranch ?? info.branches.first ?? ""
                    }
                } else {
                    addressProblem = outcome.1
                }
            }
        } catch {
            addressProblem = error.localizedDescription
        }
    }

    // MARK: Name, domain, place

    private func setName(_ value: String) {
        updatingName = true
        name = value
        updatingName = false
    }

    private func nameChanged() {
        if !updatingName {
            nameEdited = !name.isEmpty
        }
        if !domainEdited {
            updatingDomain = true
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            domain = trimmed.isEmpty ? "" : ProjectCreator.defaultDomain(forName: trimmed)
            updatingDomain = false
        }
        validate()
    }

    func chooseLocation() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            location = url
        }
    }

    private var request: NewProjectRequest? {
        guard let reference else { return nil }
        return NewProjectRequest(
            name: name.trimmingCharacters(in: .whitespaces), location: location, domain: domain.isEmpty ? nil : domain,
            source: .repository(reference, branch: branch.isEmpty ? nil : branch)
        )
    }

    func validate() {
        guard let request, !request.name.isEmpty else {
            problem = nil
            return
        }
        validation += 1
        let current = validation
        let paths = paths
        Task {
            let message = await Task.detached { () -> String? in
                do { try ProjectCreator(paths: paths).validate(request) } catch { return error.localizedDescription }
                return nil
            }.value
            if current == validation {
                problem = message
            }
        }
    }

    func create() {
        guard canCreate, let request, let reference else { return }
        creating = true
        let paths = paths
        let chosen = branch.isEmpty ? nil : branch
        Task {
            do {
                let site = try await Task.detached { try ProjectCreator(paths: paths).create(request) }.value
                _ = await Task.detached { NetworkServices(paths: paths).applyRegistryChange() }.value
                creating = false
                onCreated(site, reference, chosen)
            } catch {
                creating = false
                problem = error.localizedDescription
            }
        }
    }

    // MARK: My repositories

    func loadRepositories() {
        guard !loadingRepositories else { return }
        loadingRepositories = true
        Task {
            let outcome = await Task.detached { () -> (GitHubCLIState, [GitHubRepository]) in
                let cli = GitHubCLI()
                let state = cli.state
                return (state, state == .ready ? ((try? cli.repositories()) ?? []) : [])
            }.value
            cliState = outcome.0
            repositories = outcome.1
            loadingRepositories = false
        }
    }

    func pick(_ repository: GitHubRepository) {
        address = repository.nameWithOwner
    }
}
