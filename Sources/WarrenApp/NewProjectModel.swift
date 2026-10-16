// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI
import WarrenCore

/// State of the "from a template" and "blank project" sources in the Add site window. Checking the name, place and
/// domain reads files only; creating writes the folder and registers the site. See spec 013.
@MainActor
final class NewProjectModel: ObservableObject {
    enum Kind: Equatable { case template, blank }

    @Published var kind = Kind.template
    @Published var search = ""
    @Published var templateID = ProjectTemplate.all.first?.id ?? ""
    @Published var blank = BlankKind.node
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

    private let paths: WarrenPaths
    private let onCreated: (ResolvedSite, ProjectTemplate?) -> Void
    private var domainEdited = false
    private var updatingDomain = false
    private var generation = 0

    init(paths: WarrenPaths, onCreated: @escaping (ResolvedSite, ProjectTemplate?) -> Void) {
        self.paths = paths
        self.onCreated = onCreated
    }

    var template: ProjectTemplate? {
        ProjectTemplate.named(templateID)
    }

    var filteredTemplates: [ProjectTemplate] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return query.isEmpty ? ProjectTemplate.all : ProjectTemplate.all.filter {
            $0.name.lowercased().contains(query) || $0.summary.lowercased().contains(query)
        }
    }

    var request: NewProjectRequest? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let source: NewProjectSource
        switch kind {
        case .template:
            guard let template else { return nil }
            source = .template(template)
        case .blank:
            source = .blank(blank)
        }
        return NewProjectRequest(
            name: trimmed,
            location: location,
            domain: domain.isEmpty ? nil : domain,
            source: source
        )
    }

    var canCreate: Bool {
        problem == nil && !creating && !name.trimmingCharacters(in: .whitespaces).isEmpty && request != nil
    }

    func chooseLocation() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose where the new project's folder goes."
        if panel.runModal() == .OK, let url = panel.url {
            location = url
        }
    }

    private func nameChanged() {
        if !domainEdited {
            updatingDomain = true
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            domain = trimmed.isEmpty ? "" : ProjectCreator.defaultDomain(forName: trimmed)
            updatingDomain = false
        }
        validate()
    }

    func validate() {
        guard let request, !request.name.isEmpty else {
            problem = nil
            return
        }
        generation += 1
        let current = generation
        let paths = paths
        Task {
            let message = await Task.detached { () -> String? in
                do { try ProjectCreator(paths: paths).validate(request) } catch { return error.localizedDescription }
                return nil
            }.value
            if current == generation {
                problem = message
            }
        }
    }

    func create() {
        guard canCreate, let request else { return }
        creating = true
        let paths = paths
        let template = template.flatMap { kind == .template ? $0 : nil }
        Task {
            do {
                let site = try await Task.detached { try ProjectCreator(paths: paths).create(request) }.value
                _ = await Task.detached { NetworkServices(paths: paths).applyRegistryChange() }.value
                creating = false
                onCreated(site, template)
            } catch {
                creating = false
                problem = error.localizedDescription
            }
        }
    }
}
