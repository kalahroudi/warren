// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import WarrenCore

struct StorageView: View {
    @ObservedObject var model: AppModel

    private static let barColors: [Color] = [.warrenAccent, .blue, .purple, .orange]

    var body: some View {
        let storage = model.snapshot.storage
        return VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "Storage", subtitle: "Everything Warren keeps on disk, and what is safe to get back.")
            HStack(alignment: .top, spacing: 14) {
                usage(storage)
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Reclaimable").font(.system(size: 12)).foregroundStyle(.secondary)
                        Text(gigabytes(storage.reclaimableGigabytes))
                            .font(.system(size: 30, weight: .bold)).foregroundStyle(Color.warrenAccent)
                        Text("Nothing here is your source code. All of it comes back on demand.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
            }
            HStack(alignment: .top, spacing: 14) {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("What would be removed").font(.system(size: 14.5, weight: .semibold))
                        ForEach(storage.reclaim) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.title).font(.system(size: 13.5, weight: .medium))
                                    Text(item.note).font(.system(size: 12)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(gigabytes(item.gigabytes)).font(.system(size: 13, design: .monospaced))
                            }
                        }
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Policies").font(.system(size: 14.5, weight: .semibold))
                        ForEach(storage.policies) { policy in
                            HStack {
                                Text(policy.label).font(.system(size: 12.5))
                                Spacer()
                                Text(policy.value).font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(24)
    }

    private func usage(_ storage: StorageInfo) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(gigabytes(storage.totalGigabytes)).font(.system(size: 30, weight: .bold))
                    Text("used by Warren").foregroundStyle(.secondary)
                }
                GeometryReader { proxy in
                    HStack(spacing: 2) {
                        ForEach(Array(storage.categories.enumerated()), id: \.element.id) { index, category in
                            Self.barColors[index % Self.barColors.count]
                                .frame(width: proxy.size.width * category.gigabytes / storage.totalGigabytes)
                        }
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 12)
                HStack(spacing: 18) {
                    ForEach(Array(storage.categories.enumerated()), id: \.element.id) { index, category in
                        HStack(spacing: 6) {
                            Circle().fill(Self.barColors[index % Self.barColors.count]).frame(width: 8, height: 8)
                            Text(category.name)
                            Text(gigabytes(category.gigabytes)).foregroundStyle(.secondary)
                        }
                        .font(.system(size: 12.5))
                    }
                }
            }
        }
    }

    private func gigabytes(_ value: Double) -> String {
        String(format: "%.1f GB", value)
    }
}
