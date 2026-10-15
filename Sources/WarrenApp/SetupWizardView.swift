// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import WarrenCore

struct StepChanges {
    var heading = "What will change"
    let text: String
    let detail: String
}

struct StepLink {
    let title: String
    let run: () -> Void
}

struct StepPrimary {
    let title: String
    var disabled = false
    let run: () -> Void
}

struct SetupWizardView: View {
    @ObservedObject var model: SetupModel
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            rail.frame(width: 270)
            Divider()
            content
        }
        .frame(width: 960, height: 640)
    }

    // MARK: - Rail

    private var rail: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                AppMark(size: 30)
                Text("Set up Warren").font(.system(size: 17, weight: .semibold))
            }
            .padding(.horizontal, 8)
            Text("About two minutes. You can quit and pick up where you left off.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.bottom, 14)
            ForEach(Array(model.steps.enumerated()), id: \.element) { index, step in
                railRow(index: index, step: step)
            }
            Spacer()
            Text("Everything here can be undone from this window.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
        }
        .padding(18)
        .background(Color.primary.opacity(0.035))
    }

    private func railRow(index: Int, step: SetupStep) -> some View {
        let selected = model.current == step
        let done = step != .welcome && step != .done && model.state(of: step).isDone
        return Button { model.go(to: step) } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(done ? Color.warrenAccent : .clear)
                    Circle().strokeBorder(
                        done ? .clear : (selected ? Color.warrenAccent : Color.secondary.opacity(0.5)),
                        lineWidth: 1.5
                    )
                    if done {
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.black.opacity(0.75))
                    } else {
                        Text("\(index + 1)").font(.system(size: 11, weight: .bold))
                            .foregroundStyle(selected ? Color.warrenAccent : .secondary)
                    }
                }
                .frame(width: 22, height: 22)
                Text(step.title).font(.system(size: 13.5, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected || done ? .primary : .secondary)
                Spacer()
            }
            .padding(10)
            .background(selected ? Color.warrenAccent.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(selected ? Color.warrenAccent.opacity(0.35) : .clear))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch model.current {
        case .welcome: welcome
        case .https: httpsStep
        case .trust: trustStep
        case .domains: domainsStep
        case .check: checkStep
        case .done: doneStep
        }
    }

    func page(
        step: SetupStep? = nil,
        title: String,
        intro: String,
        changes: StepChanges? = nil,
        body: AnyView,
        hint: String?,
        undo: StepLink? = nil,
        skip: StepLink? = nil,
        primary: StepPrimary
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let step {
                stepHeader(step)
            }
            Text(title).font(.system(size: 26, weight: .semibold)).padding(.top, 10).padding(.bottom, 8)
            Text(intro).font(.system(size: 14)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let changes {
                changesBox(changes).padding(.top, 20)
            }
            body.padding(.top, 20)
            if let message = model.message {
                Text(message).font(.system(size: 12.5)).foregroundStyle(.orange).padding(.top, 12)
            }
            Spacer(minLength: 12)
            footer(hint: hint, undo: undo, skip: skip, primary: primary)
        }
        .padding(.horizontal, 36)
        .padding(.top, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func stepHeader(_ step: SetupStep) -> some View {
        let state = model.state(of: step)
        let index = (model.steps.firstIndex(of: step) ?? 0) + 1
        return HStack(spacing: 10) {
            Text("STEP \(index) OF \(model.steps.count)").font(.system(size: 12, weight: .semibold)).tracking(0.6)
                .foregroundStyle(.secondary)
            switch state {
            case .done: Chip(text: "Done", tint: .warrenAccent)
            case .pending: Chip(text: "Not done yet", tint: .orange)
            case let .attention(text): Chip(text: text, tint: .orange)
            }
        }
    }

    private func changesBox(_ changes: StepChanges) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "lock").font(.system(size: 18)).foregroundStyle(Color.warrenAccent)
            VStack(alignment: .leading, spacing: 4) {
                Text(changes.heading.uppercased()).font(.system(size: 12, weight: .semibold)).tracking(0.5)
                    .foregroundStyle(Color.warrenAccent)
                Text(changes.text).font(.system(size: 14))
                Text(changes.detail).font(.system(size: 12.5)).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.warrenAccent.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.warrenAccent.opacity(0.25)))
    }

    private func footer(
        hint: String?,
        undo: StepLink?,
        skip: StepLink?,
        primary: StepPrimary
    ) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                if model.current != .welcome {
                    Button("Back") { model.back() }.disabled(model.busy != nil)
                }
                if let busy = model.busy {
                    ProgressView().controlSize(.small)
                    Text(busy).font(.system(size: 12)).foregroundStyle(.secondary)
                } else if let hint {
                    Text(hint).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                if let undo {
                    Button(undo.title, action: undo.run).disabled(model.busy != nil)
                }
                if let skip {
                    Button(skip.title, action: skip.run).buttonStyle(.plain).foregroundStyle(.secondary)
                }
                Button(primary.title, action: primary.run)
                    .buttonStyle(.borderedProminent)
                    .tint(.warrenAccent)
                    .disabled(primary.disabled || model.busy != nil)
            }
            .padding(.vertical, 16)
        }
    }
}
