// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import WarrenCore

/// Asks before any code that came with the project runs: the exact commands, one at a time to switch off.
struct ApprovalSheet: View {
    let approval: PendingApproval
    let decide: (_ approved: Set<String>, _ trust: Bool) -> Void
    @State private var selected: Set<String>
    @State private var trust = false

    init(approval: PendingApproval, decide: @escaping (Set<String>, Bool) -> Void) {
        self.approval = approval
        self.decide = decide
        _selected = State(initialValue: Set(approval.steps.filter(\.enabledByDefault).map(\.id)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Run these commands?").font(.system(size: 17, weight: .semibold))
            Text(introduction)
                .font(.system(size: 12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(approval.steps) { step in
                        Toggle(isOn: binding(step.id)) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(step.title).font(.system(size: 13, weight: .medium))
                                Text(step.commandLine ?? "")
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(Color.warrenCard, in: RoundedRectangle(cornerRadius: 5))
                                if let source = step.payload["thirdParty"] {
                                    Text("Downloads and runs \(source).").font(.system(size: 11.5))
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 260)
            Toggle("Trust this project: run these commands without asking next time", isOn: $trust)
                .font(.system(size: 12))
            Text(
                "Only for projects you wrote. A command that changes later asks again. You can stop trusting from the site's page."
            )
            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Skip these steps") { decide([], false) }
                Button("Cancel") { decide([], false) }.keyboardShortcut(.cancelAction)
                Button("Run these commands") { decide(selected, trust) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selected.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 560)
    }

    private var introduction: String {
        approval.steps.contains { $0.payload["thirdParty"] != nil }
            ? "This downloads code from the internet and runs it, in \(approval.folder). Check it before you continue."
            : "These run code that came with this project, in \(approval.folder). Check them before you continue."
    }

    private func binding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { selected.contains(id) },
            set: {
                if $0 {
                    selected.insert(id)
                } else {
                    selected.remove(id)
                }
            }
        )
    }
}
