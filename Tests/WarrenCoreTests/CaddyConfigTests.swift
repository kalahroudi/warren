// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import WarrenCore

struct CaddyConfigTests {
    private let paths = WarrenPaths(root: URL(fileURLWithPath: "/tmp/wh"))

    private func site(_ id: String, domains: [String], port: Int?) -> ResolvedSite {
        ResolvedSite(
            id: id, path: "/x/\(id)", name: id, domains: domains, runtimes: [:],
            command: nil, port: port, services: [:], problems: [], warnings: []
        )
    }

    private func decode(_ plan: ProxyPlan) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(plan.configJSON.utf8)) as? [String: Any])
    }

    @Test func routesSitesWithAPortAndReportsTheRest() throws {
        let plan = try CaddyConfig.plan(
            sites: [
                site("b", domains: ["b.test"], port: 3001),
                site("a", domains: ["a.test", "alias.test"], port: 3000),
                site("c", domains: ["c.test"], port: nil)
            ],
            ports: ProxyPorts(), paths: paths
        )
        #expect(plan.routes.map(\.siteID) == ["a", "b"])
        #expect(plan.routes[0].domains == ["a.test", "alias.test"])
        #expect(plan.skipped == [ProxySkippedSite(siteID: "c", reason: "no run.port in .warren.toml")])
    }

    @Test func outputIsStable() throws {
        let sites = [site("a", domains: ["a.test"], port: 3000), site("b", domains: ["b.test"], port: 3001)]
        let first = try CaddyConfig.plan(sites: sites, ports: ProxyPorts(), paths: paths).configJSON
        let second = try CaddyConfig.plan(sites: sites.reversed(), ports: ProxyPorts(), paths: paths).configJSON
        #expect(first == second)
    }

    @Test func routesOnlyAnswerLoopbackAndNeverInstallTrust() throws {
        let plan = try CaddyConfig.plan(
            sites: [site("a", domains: ["a.test"], port: 3000)],
            ports: ProxyPorts(),
            paths: paths
        )
        let json = plan.configJSON
        #expect(json.contains("127.0.0.1/32"))
        #expect(json.contains("::1/128"))
        #expect(json.contains("Warren: local access only"))
        #expect(json.contains("\"install_trust\" : false"))
        #expect(json.contains("unix//tmp/wh/run/caddy.sock|0600"))
        _ = try decode(plan)
    }

    @Test func usesTheRequestedPortsAndProxiesToTheSitePort() throws {
        let plan = try CaddyConfig.plan(
            sites: [site("a", domains: ["a.test"], port: 3000)], ports: ProxyPorts(http: 8080, https: 8443),
            paths: paths
        )
        #expect(plan.configJSON.contains("\":8443\""))
        #expect(plan.configJSON.contains("\"http_port\" : 8080"))
        #expect(plan.configJSON.contains("localhost:3000"))
    }

    @Test func noSitesStillProducesAValidConfig() throws {
        let plan = try CaddyConfig.plan(sites: [], ports: ProxyPorts(), paths: paths)
        #expect(plan.routes.isEmpty)
        #expect(!plan.configJSON.contains("\"tls\""))
        _ = try decode(plan)
    }

    @Test func rejectsBadPorts() {
        #expect(throws: ProxyError.invalidPort(0)) { try CaddyConfig.plan(
            sites: [],
            ports: ProxyPorts(http: 0),
            paths: paths
        ) }
        #expect(throws: ProxyError.invalidPort(70000)) { try CaddyConfig.plan(
            sites: [],
            ports: ProxyPorts(https: 70000),
            paths: paths
        ) }
        #expect(throws: ProxyError.samePorts(8080)) { try CaddyConfig.plan(
            sites: [],
            ports: ProxyPorts(http: 8080, https: 8080),
            paths: paths
        ) }
    }

    @Test func rejectsAnAdminSocketPathThatIsTooLongForMacOS() {
        let deep = WarrenPaths(root: URL(fileURLWithPath: "/" + String(repeating: "a", count: 120)))
        #expect(throws: ProxyError.self) { try CaddyConfig.plan(sites: [], ports: ProxyPorts(), paths: deep) }
    }
}
