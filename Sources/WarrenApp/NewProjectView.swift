// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import WarrenCore

/// The "from a template" and "blank project" panes of the Add site window.
struct NewProjectView: View {
    @ObservedObject var model: NewProjectModel
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if model.kind == .template {
                        templates
                    } else {
                        blank
                    }
                    fields
                }
                .padding(.trailing, 6)
            }
            HStack {
                Spacer()
                Button("Cancel", action: close).keyboardShortcut(.cancelAction)
                Button("Create site") { model.create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canCreate)
            }
        }
    }

    // MARK: Templates

    private var templates: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Search starters: next, svelte, laravel…", text: $model.search).textFieldStyle(.roundedBorder)
            ForEach(model.filteredTemplates) { template in
                Button { model.templateID = template.id; model.validate() } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.name).font(.system(size: 13.5, weight: .semibold))
                            Text(template.summary).font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Chip(text: template.runtime.displayName, tint: .secondary)
                    }
                    .padding(10)
                    .background(
                        model.templateID == template.id ? Color.warrenAccent.opacity(0.18) : Color.warrenCard,
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if let template = model.template {
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(text: "What Warren will run")
                        Text(template.commandLine).font(.system(size: 11.5, design: .monospaced))
                            .textSelection(.enabled)
                        Text("Downloads and runs \(template.source). Warren shows this again and asks before it runs.")
                            .font(.system(size: 11.5)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: Blank

    private var blank: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Runtime")
            Picker("Runtime", selection: $model.blank) {
                ForEach(BlankKind.allCases) { Text($0.name).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: model.blank) { _ in model.validate() }
            Card {
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel(text: "You get")
                    let name = model.name.isEmpty ? "my-project" : model.name
                    Text(name + "/").font(.system(size: 12, design: .monospaced))
                    ForEach(model.blank.files(name: name).keys.sorted(), id: \.self) { file in
                        Text("  " + file).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    Text("A few short files Warren writes itself. Nothing is downloaded.")
                        .font(.system(size: 11.5)).foregroundStyle(.secondary).padding(.top, 2)
                }
            }
        }
    }

    // MARK: Name, domain, place

    private var fields: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Site")
                HStack {
                    Text("Name").frame(width: 70, alignment: .leading)
                    TextField("my-store", text: $model.name).textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("Domain").frame(width: 70, alignment: .leading)
                    TextField("my-store.test", text: $model.domain).textFieldStyle(.roundedBorder)
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
                } else {
                    Text(
                        "Creates \(model.location.lastPathComponent)/\(model.name.isEmpty ? "…" : model.name). Nothing is overwritten."
                    )
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
            }
        }
    }
}
