// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import WarrenCore

/// One step of a setup plan: its state, what it does, the command, and whether it runs the project's own code.
struct PlanStepRow: View {
    let step: PlanStep
    /// Live progress during or after a run. Nil when showing the plan as it stands.
    var progress: StepProgress?

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
                if let note = progress?.note {
                    Text(note).font(.system(size: 11.5))
                        .foregroundStyle(progress?.status == .failed ? .red : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let line = progress?.lines.last, progress?.status == .running {
                    Text(line).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                }
                if let lines = progress?.lines, !lines.isEmpty, progress?.status != .running {
                    DisclosureGroup("Log") {
                        Text(lines.suffix(40).joined(separator: "\n"))
                            .font(.system(size: 10.5, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .font(.system(size: 11.5))
                }
                if let command = step.commandLine, !step.state.isDone, progress == nil {
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
        if let status = progress?.status, status != .waiting {
            switch status {
            case .running: ProgressView().controlSize(.small)
            case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.warrenAccent)
            case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            case .skipped: Image(systemName: "minus.circle").foregroundStyle(.secondary)
            case .cancelled: Image(systemName: "stop.circle").foregroundStyle(.secondary)
            case .waiting: EmptyView()
            }
        } else {
            planIcon
        }
    }

    @ViewBuilder
    private var planIcon: some View {
        switch step.state {
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.warrenAccent)
        case .todo: Image(systemName: "circle").foregroundStyle(.secondary)
        case .waiting: Image(systemName: "clock").foregroundStyle(.secondary)
        }
    }
}

struct PlanStepList: View {
    let steps: [PlanStep]
    var progress: [String: StepProgress] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(steps) { step in PlanStepRow(step: step, progress: progress[step.id]) }
        }
    }
}
