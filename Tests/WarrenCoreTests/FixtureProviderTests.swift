// SPDX-License-Identifier: Apache-2.0

import Testing
@testable import WarrenCore

@MainActor
struct FixtureProviderTests {
    @Test func startsWithDemoData() {
        let state = FixtureProvider().snapshot()
        #expect(!state.sites.isEmpty)
        #expect(!state.services.isEmpty)
        #expect(state.update != nil)
        #expect(state.paused == false)
    }

    @Test func togglingAServiceChangesTheSnapshot() {
        let provider = FixtureProvider()
        provider.setService("mysql", running: true)
        #expect(provider.snapshot().services.first { $0.id == "mysql" }?.running == true)
        provider.setService("mysql", running: false)
        #expect(provider.snapshot().services.first { $0.id == "mysql" }?.running == false)
    }

    @Test func pausingStopsEverythingAndResumingRestoresIt() {
        let provider = FixtureProvider()
        let sitesBefore = provider.snapshot().runningSiteCount
        let servicesBefore = provider.snapshot().runningServiceCount
        provider.setPaused(true)
        #expect(provider.snapshot().runningSiteCount == 0)
        #expect(provider.snapshot().runningServiceCount == 0)
        provider.setPaused(false)
        #expect(provider.snapshot().runningSiteCount == sitesBefore)
        #expect(provider.snapshot().runningServiceCount == servicesBefore)
    }

    @Test func applyingTheUpdateClearsTheBanner() {
        let provider = FixtureProvider()
        provider.applyUpdate()
        #expect(provider.snapshot().update == nil)
    }

    @Test func storageTotalsAddUp() {
        let storage = FixtureProvider().snapshot().storage
        #expect(abs(storage.totalGigabytes - 48.3) < 0.001)
        #expect(abs(storage.reclaimableGigabytes - 14.2) < 0.001)
    }
}
