// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import WarrenCore

enum SidebarSection: String, CaseIterable, Identifiable {
    case sites = "Sites"
    case services = "Services"
    case runtimes = "Runtimes"
    case agents = "Agents"
    case storage = "Storage"

    var id: String {
        rawValue
    }

    var symbol: String {
        switch self {
        case .sites: "house"
        case .services: "cylinder.split.1x2"
        case .runtimes: "shippingbox"
        case .agents: "cpu"
        case .storage: "internaldrive"
        }
    }
}

/// The single object views observe. It talks to Warren only through a `StateProvider`.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot: StateSnapshot
    @Published var section: SidebarSection = .sites
    @Published var selectedSiteID: String?

    private let provider: any StateProvider
    private var timer: Timer?

    init(provider: any StateProvider) {
        self.provider = provider
        snapshot = provider.snapshot()
        selectedSiteID = snapshot.sites.first?.id
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    var selectedSite: Site? {
        snapshot.sites.first { $0.id == selectedSiteID }
    }

    func setSite(_ id: String, running: Bool) {
        provider.setSite(id, running: running)
        refresh()
    }

    func setService(_ id: String, running: Bool) {
        provider.setService(id, running: running)
        refresh()
    }

    func togglePaused() {
        provider.setPaused(!snapshot.paused)
        refresh()
    }

    func applyUpdate() {
        provider.applyUpdate()
        refresh()
    }

    /// Re-reads the state. The UI only updates when something actually changed.
    func refresh() {
        let latest = provider.snapshot()
        if latest != snapshot {
            snapshot = latest
        }
        if !latest.sites.contains(where: { $0.id == selectedSiteID }) {
            selectedSiteID = latest.sites.first?.id
        }
    }
}
