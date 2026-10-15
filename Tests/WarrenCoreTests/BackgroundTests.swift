// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import WarrenCore

struct BackgroundTests {
    private let root: URL
    private let paths: WarrenPaths
    private let agents: URL
    private let launch = FakeLaunch()

    init() throws {
        root = try temporaryDirectory("background")
        paths = WarrenPaths(root: root.appendingPathComponent("home"))
        agents = root.appendingPathComponent("LaunchAgents")
    }

    private func services() -> BackgroundServices {
        BackgroundServices(paths: paths, agentsDirectory: agents, launch: launch)
    }

    private func agent(_ kind: BackgroundKind = .proxy, environment: [String: String] = [:]) -> LaunchAgent {
        LaunchAgent(
            kind: kind, program: URL(fileURLWithPath: "/opt/tool"), arguments: ["run", "--config", "/x.json"],
            environment: environment, logFile: paths.logsDirectory.appendingPathComponent("\(kind.rawValue).log")
        )
    }

    private func decode(_ data: Data) throws -> [String: Any] {
        try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    @Test func thePlistStartsAtLoginAndRestartsOnExit() throws {
        let plist = try decode(agent(environment: ["XDG_DATA_HOME": "/d"]).plist())
        #expect(plist["Label"] as? String == "dev.warren.proxy")
        #expect(plist["ProgramArguments"] as? [String] == ["/opt/tool", "run", "--config", "/x.json"])
        #expect(plist["RunAtLoad"] as? Bool == true)
        #expect(plist["KeepAlive"] as? Bool == true)
        #expect(plist["StandardOutPath"] as? String == paths.logsDirectory.appendingPathComponent("proxy.log").path)
        #expect(plist["EnvironmentVariables"] as? [String: String] == ["XDG_DATA_HOME": "/d"])
    }

    @Test func noEnvironmentMeansNoEnvironmentKey() throws {
        #expect(try decode(agent(.dns).plist())["EnvironmentVariables"] == nil)
    }

    @Test func labelsAreStablePerKind() {
        #expect(BackgroundKind.proxy.label == "dev.warren.proxy")
        #expect(BackgroundKind.dns.label == "dev.warren.dns")
    }

    @Test func startWritesThePlistAndBootstrapsIt() throws {
        let background = services()
        try background.start(agent())
        #expect(FileManager.default.fileExists(atPath: background.plistURL(.proxy).path))
        #expect(launch.calls == ["bootstrap dev.warren.proxy.plist"])
        #expect(background.isLoaded(.proxy))
        #expect(FileManager.default.fileExists(atPath: paths.logsDirectory.path))
    }

    @Test func startingAgainReplacesTheRunningJob() throws {
        let background = services()
        try background.start(agent())
        try background.start(agent())
        #expect(launch.calls == [
            "bootstrap dev.warren.proxy.plist",
            "bootout dev.warren.proxy",
            "bootstrap dev.warren.proxy.plist"
        ])
    }

    @Test func stopBootsOutAndRemovesThePlist() throws {
        let background = services()
        try background.start(agent())
        try background.stop(.proxy)
        #expect(!FileManager.default.fileExists(atPath: background.plistURL(.proxy).path))
        #expect(!background.isLoaded(.proxy))
        #expect(launch.calls.last == "bootout dev.warren.proxy")
    }

    @Test func stoppingSomethingNotRunningIsHarmless() throws {
        try services().stop(.dns)
        #expect(launch.calls.isEmpty)
    }

    @Test func networkSettingsRoundTripAndFallBackToDefaults() throws {
        #expect(NetworkSettings.load(paths) == NetworkSettings())
        try NetworkSettings(httpPort: 8080, httpsPort: 8443, dnsPort: 15354).save(paths)
        #expect(NetworkSettings.load(paths) == NetworkSettings(httpPort: 8080, httpsPort: 8443, dnsPort: 15354))
        try Data("not json".utf8).write(to: paths.networkSettingsFile)
        #expect(NetworkSettings.load(paths) == NetworkSettings())
    }

    @Test func aRegistryChangeWithNothingRunningDoesNothing() {
        let network = NetworkServices(paths: paths, background: services())
        #expect(network.applyRegistryChange().isEmpty)
        #expect(launch.calls.isEmpty)
    }

    @Test func aRegistryChangeReportsAProblemForARunningJobItCannotUpdate() {
        launch.setLoaded("dev.warren.proxy")
        let problems = NetworkServices(paths: paths, background: services()).applyRegistryChange()
        #expect(problems.count == 1)
        #expect(problems[0].hasPrefix("proxy:"))
    }

    @Test func statusReflectsNotInstalledAndNotRunning() {
        let status = NetworkServices(paths: paths, background: services()).status()
        #expect(status.proxy == ServiceStatus(installed: false, running: false))
        #expect(status.dns == ServiceStatus(installed: false, running: false))
    }
}
