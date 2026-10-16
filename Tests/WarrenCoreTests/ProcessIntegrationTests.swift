// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import WarrenCore

/// Uses the real launchd with a small Python web server as the stand-in service. Off by default.
/// Run with `WARREN_INTEGRATION=1 swift test --filter ProcessIntegrationTests`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["WARREN_INTEGRATION"] == "1"))
struct ProcessIntegrationTests {
    @Test func theNativeDriverRunsAServiceThroughRealLaunchd() async throws {
        let paths = try WarrenPaths(root: temporaryDirectory("drv"))
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let (descriptor, port) = try listeningSocket()
        close(descriptor)
        let id = "standin-\(UUID().uuidString.prefix(6).lowercased())"
        let service = ServiceInstance(
            id: id, name: "Stand-in", program: "/usr/bin/python3",
            arguments: ["-m", "http.server", String(port), "--bind", "127.0.0.1"],
            dataDirectory: paths.dataDirectory.appendingPathComponent(id), readiness: .port(port),
            connection: ServiceConnection(port: port)
        )
        let driver = NativeDriver(paths: paths, timeout: 30)
        try await driver.start(service)
        defer { Task { try? await driver.stop(service) } }
        #expect(await driver.status(of: service) == .running)
        #expect(PortCheck.isListening(port))
        try await driver.start(service)
        #expect(await driver.status(of: service) == .running)
        try await driver.stop(service)
        #expect(await driver.status(of: service) == .stopped)
        // launchd stops the process; give the port a moment to close.
        for _ in 0 ..< 20 where PortCheck.isListening(port) {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        #expect(!PortCheck.isListening(port))
    }
}
