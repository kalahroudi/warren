// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import WarrenCore

/// Asks for the variables `.env` leaves empty, once. Hidden fields for secrets; offers where Warren can answer.
struct ValuesSheet: View {
    let pending: PendingValues
    let decide: ([String: String]) -> Void
    @State private var values: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(pending.prompts.count == 1 ? "One value needed" : "Values needed")")
                .font(.system(size: 17, weight: .semibold))
            Text(
                "These are empty in the project's .env.example. Fill in what you have; skip the rest to keep placeholders."
            )
            .font(.system(size: 12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(pending.prompts) { prompt in field(prompt) }
                }
            }
            .frame(maxHeight: 300)
            if !pending.envIsIgnored {
                Text(".env is not in this project's .gitignore. Do not commit it.")
                    .font(.system(size: 11.5)).foregroundStyle(.orange)
            }
            HStack {
                Text("Values go into .env in the project and nowhere else.").font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Skip") { decide([:]) }.keyboardShortcut(.cancelAction)
                Button("Save") { decide(values.filter { !$0.value.isEmpty }) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 560)
    }

    private func binding(_ name: String) -> Binding<String> {
        Binding(get: { values[name] ?? "" }, set: { values[name] = $0 })
    }

    private func field(_ prompt: EnvPrompt) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(prompt.name).font(.system(size: 12, weight: .medium, design: .monospaced))
            HStack {
                if prompt.isSecret {
                    SecureField("Value", text: binding(prompt.name)).textFieldStyle(.roundedBorder)
                } else {
                    TextField("Value", text: binding(prompt.name)).textFieldStyle(.roundedBorder)
                }
                switch prompt.offer {
                case .siteURL:
                    Button("Use \(EnvPrompts.siteURL(domain: pending.domain))") {
                        values[prompt.name] = EnvPrompts.siteURL(domain: pending.domain)
                    }
                case .generate:
                    Button("Generate") { values[prompt.name] = EnvPrompts.generatedSecret() }
                case .none:
                    EmptyView()
                }
            }
        }
    }
}
