// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import UniformTypeIdentifiers
import WarrenCore

struct AddSiteView: View {
    enum Source { case folder, github, template, blank }

    @ObservedObject var model: AddSiteModel
    @ObservedObject var project: NewProjectModel
    @ObservedObject var repository: GitHubImportModel
    let close: () -> Void
    @State private var dropTargeted = false
    @State private var source = Source.folder

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            sources
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                Text("Add a site").font(.system(size: 20, weight: .semibold))
                if source == .folder {
                    if model.folder == nil {
                        chooser
                    } else {
                        ScrollView { review.padding(.trailing, 6) }
                    }
                    Spacer(minLength: 0)
                    footer
                } else if source == .github {
                    GitHubImportView(model: repository, close: close)
                } else {
                    NewProjectView(model: project, close: close)
                }
            }
            .padding(22)
        }
        .frame(width: 960, height: 660)
        .onChange(of: model.name) { _ in model.refresh() }
        .onChange(of: model.domain) { _ in model.refresh() }
    }

    // MARK: Sources

    private var sources: some View {
        VStack(alignment: .leading, spacing: 6) {
            source("Folder", symbol: "folder", note: nil, selected: source == .folder) { source = .folder }
            source("From GitHub", symbol: "arrow.down.circle", note: nil, selected: source == .github) {
                source = .github
                repository.validate()
            }
            source("From a template", symbol: "square.stack.3d.up", note: nil, selected: source == .template) {
                source = .template
                project.kind = .template
                project.validate()
            }
            source("Blank project", symbol: "doc", note: nil, selected: source == .blank) {
                source = .blank
                project.kind = .blank
                project.validate()
            }
            Spacer()
        }
        .padding(14)
        .frame(width: 210)
    }

    private func source(
        _ title: String, symbol: String, note: String?, selected: Bool, action: (() -> Void)?
    ) -> some View {
        let enabled = action != nil
        return Button { action?() } label: {
            HStack {
                Label(title, systemImage: symbol).font(.system(size: 13, weight: selected ? .semibold : .regular))
                Spacer()
                if let note {
                    Text(note).font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(selected ? Color.warrenCard : .clear, in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(enabled ? .primary : .secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: Folder chooser

    private var chooser: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.plus").font(.system(size: 34)).foregroundStyle(.secondary)
            Text("Choose a project folder").font(.system(size: 15, weight: .semibold))
            Text("Warren looks at it, shows what it takes to run, and changes nothing until you say so.")
                .font(.system(size: 12.5)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Choose folder…") { model.chooseFolder() }
                .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                .foregroundStyle(dropTargeted ? Color.warrenAccent : Color.secondary.opacity(0.4))
        )
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in model.use(folder: url) }
            }
            return true
        }
    }

    // MARK: Review

    private var review: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "folder").foregroundStyle(.secondary)
                Text(model.folder?.path ?? "").font(.system(size: 12, design: .monospaced)).lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Change…") { model.chooseFolder() }
            }
            if let plan = model.plan {
                found(plan)
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(text: "Setup plan")
                        PlanStepList(steps: plan.steps)
                        Text(
                            "Warren shows each command that runs code from the project and asks before it runs."
                        )
                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                    }
                }
            }
            fields
        }
    }

    private func found(_ plan: SetupPlan) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "What Warren found")
                line("Framework", plan.detection.displayName)
                line("Starts with", plan.detection.startLine)
                if let manager = plan.detection.packageManager {
                    line("Package manager", manager.rawValue)
                }
                ForEach(plan.runtimes, id: \.label) { runtime in
                    line(
                        "Runtime",
                        "\(runtime.label) · \(runtime.installedVersion.map { "installed \($0)" } ?? "not installed") · \(runtime.source)"
                    )
                }
                ForEach(plan.services, id: \.id) { service in
                    line("Service", "\(service.name) · \(service.evidence)")
                }
            }
        }
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.system(size: 11.5)).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
            Text(value).font(.system(size: 12.5)).textSelection(.enabled)
        }
    }

    private var fields: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Site")
                HStack {
                    Text("Name").frame(width: 70, alignment: .leading)
                    TextField("Name", text: $model.name).textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("Domain").frame(width: 70, alignment: .leading)
                    TextField("shop.test", text: $model.domain).textFieldStyle(.roundedBorder)
                }
                if let problem = model.problem {
                    Text(problem).font(.system(size: 12)).foregroundStyle(.red)
                } else {
                    Text("Stored with the site in Warren. Nothing is written into the project.")
                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel", action: close).keyboardShortcut(.cancelAction)
            Button("Add site") { model.add() }
                .disabled(!model.canAdd)
            Button("Add and run setup") { model.add(runSetup: true) }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canAdd || (model.plan.map { PlanRunner.selectedSteps($0) } ?? []).isEmpty)
        }
    }
}
