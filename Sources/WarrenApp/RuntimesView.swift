// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import WarrenCore

struct RuntimesView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "Runtimes",
                       subtitle: "Per-site versions, picked up from .nvmrc, .php-version and friends.")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible())], spacing: 14) {
                ForEach(model.snapshot.runtimeGroups) { group in
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.name).font(.system(size: 14.5, weight: .semibold))
                            Text(group.note).font(.system(size: 11.5)).foregroundStyle(.secondary)
                            ForEach(group.versions) { version in
                                HStack {
                                    Text(version.label).font(.system(size: 13, design: .monospaced))
                                    Spacer()
                                    Text(version.note)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(tint(version))
                                    Text("\(version.sizeMB) MB")
                                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(version.isDefault ? Color.warrenAccent.opacity(0.1) : Color.warrenCard,
                                            in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(24)
    }

    private func tint(_ version: RuntimeVersion) -> Color {
        if version.updateAvailable {
            return .orange
        }
        return version.isDefault ? .warrenAccent : .secondary
    }
}
