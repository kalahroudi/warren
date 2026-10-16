// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import WarrenCore

struct ServiceDriverTests {
    private func home() throws -> WarrenPaths {
        try WarrenPaths(root: temporaryDirectory("svc"))
    }

    private func service(_ paths: WarrenPaths, port: Int) -> ServiceInstance {
        ServiceInstance(
            id: "standin", name: "Stand-in", program: "/usr/bin/true",
            dataDirectory: paths.dataDirectory.appendingPathComponent("standin"),
            readiness: .port(port), connection: ServiceConnection(
                port: port,
                user: "dev",
                url: "standin://127.0.0.1:\(port)"
            )
        )
    }

    @Test func theNativeDriverStartsAServiceWaitsForItAndStopsIt() async throws {
        let paths = try home()
        let launch = FakeLaunch()
        let (descriptor, port) = try listeningSocket()
        defer { close(descriptor) }
        let driver = NativeDriver(paths: paths, launch: launch, timeout: 5)
        let standin = service(paths, port: port)
        #expect(await driver.status(of: standin) == .stopped)
        try await driver.start(standin)
        #expect(await driver.status(of: standin) == .running)
        #expect(FileManager.default.fileExists(atPath: standin.dataDirectory.path))
        // Starting a running service changes nothing.
        try await driver.start(standin)
        #expect(launch.calls.filter { $0.hasPrefix("bootstrap") }.count == 1)
        #expect(driver.connection(of: standin)?.url == "standin://127.0.0.1:\(port)")
        #expect(driver.logs(of: standin).lastPathComponent == "service-standin.log")
        #expect(driver.kind == "native")
        try await driver.stop(standin)
        #expect(await driver.status(of: standin) == .stopped)
    }

    @Test func aServiceThatDiesIsReported() async throws {
        let paths = try home()
        let launch = FakeLaunch()
        launch.setInfo("dev.warren.service.standin", JobInfo(running: false, pid: nil, lastExit: 1))
        let driver = NativeDriver(paths: paths, launch: launch, timeout: 5)
        let standin = service(paths, port: 1)
        await #expect(throws: ServiceStartError.exited(code: 1, lastLines: [])) { try await driver.start(standin) }
        #expect(await driver.status(of: standin) == .crashed(exitCode: 1))
    }
}
