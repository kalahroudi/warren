// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct MainWindowView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var runtimes: RuntimesModel
    @ObservedObject var setupRun: SetupRunModel
    let addSite: () -> Void

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
        .sheet(item: $setupRun.pendingApproval) { approval in
            ApprovalSheet(approval: approval) { approved, trust in
                setupRun.resolve(approval, approved: approved, trust: trust)
            }
            .interactiveDismissDisabled()
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.section {
        case .sites: SitesView(model: model, runtimes: runtimes, setupRun: setupRun, addSite: addSite)
        case .services: ServicesView(model: model)
        case .runtimes: RuntimesView(model: model, runtimes: runtimes)
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
