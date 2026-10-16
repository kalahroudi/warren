// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import WarrenCore

/// The Runtimes page with real data: installed versions, install and remove, and the shared packages cache.
struct InstalledRuntimesView: View {
    @ObservedObject var runtimes: RuntimesModel
    @State private var removing: InstalledRuntime?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let installing = runtimes.installing {
                installBanner(installing)
            }
            if let message = runtimes.message {
                Text(message).font(.system(size: 12.5)).foregroundStyle(.orange)
            }
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible())],
                alignment: .leading,
                spacing: 14
            ) {
                ForEach(RuntimeKind.allCases) { kind in card(kind) }
            }
            cacheCard
        }
        .confirmationDialog(
            removing.map { "Remove \($0.kind.displayName) \($0.version)?" } ?? "",
            isPresented: Binding(get: { removing != nil }, set: {
                if !$0 {
                    removing = nil
                }
            }),
            presenting: removing
        ) { runtime in
            Button("Remove", role: .destructive) { runtimes.remove(runtime) }
        } message: { runtime in
            let users = runtimes.sites(using: runtime)
            Text(users.isEmpty
                ? "This frees \(Size.text(runtime.bytes)). You can install it again any time."
                :
                "\(users.joined(separator: ", ")) use\(users.count == 1 ? "s" : "") it and will need it installed again.")
        }
    }

    private func installBanner(_ installing: RuntimesModel.Installing) -> some View {
        Card {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Installing \(installing.label)").font(.system(size: 13, weight: .medium))
                    Text(installing.progress).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button("Cancel") { runtimes.cancelInstall() }
            }
        }
    }

    private func card(_ kind: RuntimeKind) -> some View {
        let versions = runtimes.installed.filter { $0.kind == kind }
        return Card {
            VStack(alignment: .leading, spacing: 8) {
                Text(kind.displayName).font(.system(size: 14.5, weight: .semibold))
                if versions.isEmpty {
                    Text(runtimes.loaded ? "Nothing installed. Warren installs it when a site needs it." : "Loading…")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                ForEach(versions) { runtime in row(runtime) }
                installMenu(kind)
            }
        }
    }

    private func row(_ runtime: InstalledRuntime) -> some View {
        let users = runtimes.sites(using: runtime)
        return HStack {
            Text(runtime.version).font(.system(size: 13, design: .monospaced))
            Spacer()
            if !users.isEmpty {
                Text("used by \(users.joined(separator: ", "))")
                    .font(.system(size: 11.5)).foregroundStyle(Color.warrenAccent).lineLimit(1)
            }
            Text(Size.text(runtime.bytes)).font(.system(size: 11.5)).foregroundStyle(.secondary)
            Button("Remove") { removing = runtime }
                .buttonStyle(.plain).font(.system(size: 11.5)).foregroundStyle(.secondary)
                .accessibilityLabel("Remove \(runtime.kind.displayName) \(runtime.version)")
                .disabled(runtimes.installing != nil)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.warrenCard, in: RoundedRectangle(cornerRadius: 8))
    }

    private func installMenu(_ kind: RuntimeKind) -> some View {
        Menu("Install a version") {
            Button("Latest") { runtimes.install(kind, version: "latest") }
            if kind == .node {
                Button("Long-term support") { runtimes.install(kind, version: "lts") }
            }
            Divider()
            if let list = runtimes.releases[kind] {
                ForEach(list, id: \.self) { version in
                    Button(version) { runtimes.install(kind, version: version) }
                }
            } else {
                Button(runtimes.loadingReleases == kind ? "Loading versions…" : "Show other versions…") {
                    runtimes.loadReleases(for: kind)
                }
                .disabled(runtimes.loadingReleases != nil)
            }
        }
        .disabled(runtimes.installing != nil)
        .fixedSize()
    }

    private var cacheCard: some View {
        Card {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Packages cache").font(.system(size: 14.5, weight: .semibold))
                    Text(
                        "Downloads from npm, pnpm, Yarn, Bun and Composer for sites Warren runs. "
                            + "Safe to clear: packages download again when needed."
                    )
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
                Spacer()
                Text(Size.text(runtimes.cacheBytes)).font(.system(size: 13, weight: .medium))
                Button("Clear") { runtimes.clearPackagesCache() }
                    .accessibilityLabel("Clear the packages cache")
                    .disabled(runtimes.cacheBytes == 0)
            }
        }
    }
}
