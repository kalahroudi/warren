// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import WarrenCore

/// One step of a setup plan: its state, what it does, the command, and whether it runs the project's own code.
struct PlanStepRow: View {
    let step: PlanStep

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            icon.frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(step.title).font(.system(size: 13, weight: .medium))
                    if !step.enabledByDefault {
                        Chip(text: "Off", tint: .secondary)
                    }
                    if step.runsProjectCode, !step.state.isDone {
                        Chip(text: "Runs code from this project", tint: .orange)
                    }
                }
                Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(
                    horizontal: false,
                    vertical: true
                )
                if let command = step.commandLine, !step.state.isDone {
                    Text(command)
                        .font(.system(size: 11, design: .monospaced))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.warrenCard, in: RoundedRectangle(cornerRadius: 5))
                }
            }
            Spacer(minLength: 0)
        }
        .opacity(step.enabledByDefault ? 1 : 0.65)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        if case let .waiting(reason) = step.state {
            return "\(step.detail) Waiting: \(reason)."
        }
        return step.detail
    }

    @ViewBuilder
    private var icon: some View {
        switch step.state {
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.warrenAccent)
        case .todo: Image(systemName: "circle").foregroundStyle(.secondary)
        case .waiting: Image(systemName: "clock").foregroundStyle(.secondary)
        }
    }
}

struct PlanStepList: View {
    let steps: [PlanStep]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(steps) { step in PlanStepRow(step: step) }
        }
    }
}
