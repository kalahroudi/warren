// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import WarrenCore

/// The "From GitHub" pane of the Add site window.
struct GitHubImportView: View {
    @ObservedObject var model: GitHubImportModel
    let close: () -> Void
    @State private var picking = false
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    repository
                    fields
                }
                .padding(.trailing, 6)
            }
            HStack {
                Text("Warren shows each command from this repository and asks before it runs.")
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", action: close).keyboardShortcut(.cancelAction)
                Button("Clone & set up") { model.create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canCreate)
            }
        }
        .sheet(isPresented: $picking) { picker }
    }

    private var repository: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Repository")
                HStack {
                    TextField("github.com/acme/shop-demo", text: $model.address).textFieldStyle(.roundedBorder)
                    Picker("Branch", selection: $model.branch) {
                        ForEach(model.branches, id: \.self) { Text($0).tag($0) }
                        if model.branches.isEmpty {
                            Text("main").tag("")
                        }
                    }
                    .frame(width: 170)
                    .disabled(model.branches.isEmpty)
                }
                if model.inspecting {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Looking up the repository…").font(.system(size: 11.5)).foregroundStyle(.secondary)
                    }
                } else if let problem = model.addressProblem {
                    Text(problem).font(.system(size: 12)).foregroundStyle(.red)
                } else {
                    Text(
                        "Public repositories work straight away. Private ones use the sign-in Git already has: "
                            + "your Keychain, the GitHub CLI, or an SSH key."
                    )
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
                if !model.gitAvailable {
                    Text(GitError.notAvailable.localizedDescription).font(.system(size: 12)).foregroundStyle(.orange)
                }
                Button("Pick from my repos") {
                    model.loadRepositories()
                    picking = true
                }
            }
        }
    }

    private var fields: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Site")
                HStack {
                    Text("Name").frame(width: 70, alignment: .leading)
                    TextField("shop-demo", text: $model.name).textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("Domain").frame(width: 70, alignment: .leading)
                    TextField("shop-demo.test", text: $model.domain).textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("Location").frame(width: 70, alignment: .leading)
                    Text(model.location.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Change…") { model.chooseLocation() }
                }
                if let problem = model.problem {
                    Text(problem).font(.system(size: 12)).foregroundStyle(.red)
                }
            }
        }
    }

    // MARK: Picker

    private var picker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your repositories").font(.system(size: 17, weight: .semibold))
            switch model.cliState {
            case .notInstalled where !model.loadingRepositories:
                Text("Install the GitHub CLI (gh) to list your repositories here. You can still paste an address.")
                    .font(.system(size: 12.5)).foregroundStyle(.secondary)
            case .signedOut where !model.loadingRepositories:
                Text("The GitHub CLI is not signed in. Run gh auth login in a terminal, then try again.")
                    .font(.system(size: 12.5)).foregroundStyle(.secondary)
            default:
                TextField("Search", text: $query).textFieldStyle(.roundedBorder)
                if model.loadingRepositories {
                    ProgressView().controlSize(.small)
                }
                List(filtered) { repo in
                    Button {
                        model.pick(repo)
                        picking = false
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(repo.nameWithOwner).font(.system(size: 13, weight: .medium))
                                if repo.isPrivate {
                                    Chip(text: "Private", tint: .secondary)
                                }
                            }
                            if let text = repo.description, !text.isEmpty {
                                Text(text).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .frame(height: 280)
            }
            HStack {
                Spacer()
                Button("Close") { picking = false }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private var filtered: [GitHubRepository] {
        let text = query.trimmingCharacters(in: .whitespaces).lowercased()
        return text.isEmpty ? model.repositories : model.repositories.filter {
            $0.nameWithOwner.lowercased().contains(text) || ($0.description ?? "").lowercased().contains(text)
        }
    }
}
