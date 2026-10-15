// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation
import Testing
@testable import WarrenCore

@MainActor
struct LiveProviderTests {
    private let root: URL
    private let paths: WarrenPaths
    private let provider: LiveProvider

    init() throws {
        root = try temporaryDirectory("live")
        paths = WarrenPaths(root: root.appendingPathComponent("home"))
        let background = BackgroundServices(
            paths: paths,
            agentsDirectory: root.appendingPathComponent("agents"),
            launch: FakeLaunch()
        )
        provider = LiveProvider(paths: paths, network: NetworkServices(paths: paths, background: background))
    }

    private func addSite(_ folder: String, config: String? = nil) throws {
        let directory = root.appendingPathComponent(folder)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let config {
            try config.write(
                to: directory.appendingPathComponent(".warren.toml"),
                atomically: true,
                encoding: .utf8
            )
        }
        try SiteRegistry(paths: paths).add(path: directory.path)
    }

    @Test func anEmptyRegistryGivesNoSitesAndNoFakeData() {
        let snapshot = provider.snapshot()
        #expect(snapshot.sites.isEmpty)
        #expect(snapshot.isLive)
        #expect(snapshot.update == nil)
        #expect(snapshot.activeRuntimes.isEmpty)
    }

    @Test func registeredSitesAppearWithTheirDomainAndRuntime() throws {
        try addSite("shop", config: "domains = [\"shop.test\"]\n[runtime]\nnode = \"22\"\n[run]\nport = 3000")
        let site = try #require(provider.snapshot().sites.first)
        #expect(site.domain == "shop.test")
        #expect(site.runtime == "Node 22")
        #expect(site.detail == ":3000")
        #expect(provider.snapshot().activeRuntimes == ["Node 22"])
    }

    @Test func aSiteWithoutAPortOrRuntimeSaysSo() throws {
        try addSite("plain")
        let site = try #require(provider.snapshot().sites.first)
        #expect(site.detail == "no port set")
        #expect(site.runtime == "No runtime")
        #expect(site.state == .stopped)
    }

    @Test func aSiteIsRunningOnlyWhileSomethingListensOnItsPort() throws {
        let listener = try listeningSocket()
        try addSite("live", config: "[run]\nport = \(listener.port)")
        #expect(provider.snapshot().sites.first?.state == .running)
        close(listener.descriptor)
        #expect(provider.snapshot().sites.first?.state == .stopped)
    }

    @Test func demoOnlySectionsAreFlaggedAsPreviews() {
        #expect(provider.snapshot().previewSections == ["Services", "Runtimes", "Agents", "Storage"])
    }

    @Test func controlsThatDoNothingYetAreOff() {
        let capabilities = provider.snapshot().capabilities
        #expect(!capabilities.canControlSites)
        #expect(!capabilities.canPause)
    }

    @Test func theNetworkStatusIsReal() {
        let network = provider.snapshot().network
        #expect(network.proxy == ServiceStatus(installed: false, running: false))
        #expect(network.dns == ServiceStatus(installed: false, running: false))
    }

    @Test func registryChangesShowUpOnTheNextSnapshot() throws {
        #expect(provider.snapshot().sites.isEmpty)
        try addSite("later")
        #expect(provider.snapshot().sites.count == 1)
    }

    @Test func snapshotsCompareEqualUnlessSomethingChanged() {
        let demo = FixtureProvider()
        let before = demo.snapshot()
        #expect(before == demo.snapshot())
        demo.setService("mysql", running: true)
        #expect(before != demo.snapshot())
    }

    @Test func listeningIsDetectedOnLoopback() throws {
        let listener = try listeningSocket()
        #expect(PortCheck.isListening(listener.port))
        close(listener.descriptor)
        #expect(!PortCheck.isListening(listener.port))
    }
}
