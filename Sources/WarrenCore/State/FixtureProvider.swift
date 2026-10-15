// SPDX-License-Identifier: Apache-2.0

/// In-memory demo data. Toggles work, but nothing real starts or stops.
@MainActor
public final class FixtureProvider: StateProvider {
    private var state: StateSnapshot
    private var pausedSites: Set<String> = []
    private var pausedServices: Set<String> = []

    public init() {
        state = FixtureProvider.demoState
    }

    public func snapshot() -> StateSnapshot {
        state
    }

    public func setSite(_ id: String, running: Bool) {
        guard let index = state.sites.firstIndex(where: { $0.id == id }) else { return }
        state.sites[index].state = running ? .running : .stopped
    }

    public func setService(_ id: String, running: Bool) {
        guard let index = state.services.firstIndex(where: { $0.id == id }) else { return }
        state.services[index].running = running
    }

    public func setPaused(_ paused: Bool) {
        guard paused != state.paused else { return }
        state.paused = paused
        if paused {
            pausedSites = Set(state.sites.filter { $0.state == .running }.map(\.id))
            pausedServices = Set(state.services.filter(\.running).map(\.id))
            pausedSites.forEach { setSite($0, running: false) }
            pausedServices.forEach { setService($0, running: false) }
        } else {
            pausedSites.forEach { setSite($0, running: true) }
            pausedServices.forEach { setService($0, running: true) }
        }
    }

    public func applyUpdate() {
        state.update = nil
    }
}
