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
    private let launch = FakeLaunch()

    init() throws {
        root = try temporaryDirectory("live")
        paths = WarrenPaths(root: root.appendingPathComponent("home"))
        let background = BackgroundServices(
            paths: paths,
            agentsDirectory: root.appendingPathComponent("agents"),
            launch: launch
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

    // MARK: Pause

    private func installTool(_ release: ToolRelease) throws {
        let binary = ToolInstaller(paths: paths).binaryURL(for: release)
        try FileManager.default.createDirectory(
            at: binary.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\n".write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
    }

    @Test func thereIsNothingToPauseUntilSomethingIsSetUp() {
        #expect(!provider.snapshot().capabilities.canPause)
    }

    @Test func pauseAppearsOnceLocalHTTPSIsInstalled() throws {
        try installTool(.caddy)
        #expect(provider.snapshot().capabilities.canPause)
    }

    @Test func pausingStopsBothServicesAndRemembersIt() throws {
        try installTool(.caddy)
        launch.setLoaded("dev.warren.proxy")
        launch.setLoaded("dev.warren.dns")
        provider.setPaused(true)
        #expect(launch.calls.contains("bootout dev.warren.proxy"))
        #expect(launch.calls.contains("bootout dev.warren.dns"))
        #expect(UserState.load(paths).paused)
        let snapshot = provider.snapshot()
        #expect(snapshot.paused)
        #expect(snapshot.capabilities.canPause)
    }

    @Test func aPausedWarrenIsNotNaggedAboutSetup() throws {
        try installTool(.caddy)
        provider.setPaused(true)
        #expect(provider.snapshot().setupComplete)
    }

    @Test func aFailedStartKeepsThePause() throws {
        var user = UserState()
        user.paused = true
        try user.save(paths)
        let background = BackgroundServices(
            paths: paths,
            agentsDirectory: root.appendingPathComponent("agents"),
            launch: launch
        )
        _ = try? NetworkServices(paths: paths, background: background).startProxy(ports: ProxyPorts())
        // The start fails (no binary installed) before it can clear the flag, so the pause is kept.
        #expect(UserState.load(paths).paused)
    }

    @Test func aFailedResumeKeepsItPausedAndSaysWhy() throws {
        try installTool(.caddy)
        var user = UserState()
        user.paused = true
        try user.save(paths)
        provider.setPaused(false)
        let snapshot = provider.snapshot()
        #expect(snapshot.notice?.hasPrefix("Could not resume") == true)
        #expect(snapshot.paused)
    }

    @Test func oldStateFilesWithoutNewKeysStillLoad() throws {
        try FileManager.default.createDirectory(at: paths.configDirectory, withIntermediateDirectories: true)
        try Data(#"{"setupDismissed":true,"domainsSkipped":false}"#.utf8).write(to: paths.userStateFile)
        let state = UserState.load(paths)
        #expect(state.setupDismissed)
        #expect(!state.paused)
    }
}
