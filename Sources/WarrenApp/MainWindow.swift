// SPDX-License-Identifier: Apache-2.0

import SwiftUI

enum MainWindow {
    static let id = "main"

    /// Shows the Dock icon while the window is open, then hides it again when it closes.
    @MainActor
    static func open(_ openWindow: OpenWindowAction) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        openWindow(id: id)
    }
}

struct MainWindowView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $model.section) { section in
                HStack {
                    Label(section.rawValue, systemImage: section.symbol)
                    if model.snapshot.previewSections.contains(section.rawValue) {
                        Spacer()
                        Text("Preview").font(.system(size: 10.5)).foregroundStyle(.secondary)
                    }
                }
                .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 240)
            .safeAreaInset(edge: .bottom) {
                Text(model.snapshot.isLive ? "Sites and network are live" : "Preview · demo data")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .padding(12)
            }
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 960, minHeight: 620)
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.section {
        case .sites: SitesView(model: model)
        case .services: ServicesView(model: model)
        case .runtimes: RuntimesView(model: model)
        case .agents: AgentsView(model: model)
        case .storage: StorageView(model: model)
        }
    }
}

struct PageHeader: View {
    let title: String
    let subtitle: String
    var preview = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                Text(title).font(.system(size: 22, weight: .semibold))
                if preview {
                    Chip(text: "Preview · demo data", tint: .orange)
                }
            }
            Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }
}
