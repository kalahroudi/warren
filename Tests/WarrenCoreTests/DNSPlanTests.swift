// SPDX-License-Identifier: Apache-2.0

import Testing
@testable import WarrenCore

struct DNSPlanTests {
    private func plan(_ domains: [String], port: Int = 5354) throws -> DNSPlan {
        try DNSPlanner.plan(domains: domains, port: port)
    }

    @Test func aReservedTLDGetsOneZoneForTheWholeTLD() throws {
        let result = try plan(["acme.test", "shop.test", "api.acme.test"])
        #expect(result.zones == ["test"])
    }

    @Test func anyOtherDomainGetsAnExactZone() throws {
        let result = try plan(["acme.dev", "shop.example.com"])
        #expect(result.zones == ["acme.dev", "shop.example.com"])
    }

    @Test func nestedZonesAreDropped() throws {
        let result = try plan(["acme.dev", "www.acme.dev", "api.www.acme.dev", "other.dev"])
        #expect(result.zones == ["acme.dev", "other.dev"])
    }

    @Test func aSimilarlyNamedZoneIsNotTreatedAsNested() throws {
        let result = try plan(["acme.dev", "myacme.dev"])
        #expect(result.zones == ["acme.dev", "myacme.dev"])
    }

    @Test func localhostNeedsNoDNS() throws {
        let result = try plan(["app.localhost", "acme.test"])
        #expect(result.zones == ["test"])
        #expect(result.native == ["app.localhost"])
    }

    @Test func dotLocalIsRejectedWithAReason() throws {
        let result = try plan(["printer.local", "acme.test"])
        #expect(result.zones == ["test"])
        #expect(result.rejected.map(\.domain) == ["printer.local"])
        #expect(result.rejected[0].reason.contains("Bonjour"))
    }

    @Test func outputIsSortedAndStable() throws {
        let first = try plan(["b.dev", "a.dev", "c.test"])
        let second = try plan(["c.test", "a.dev", "b.dev", "a.dev"])
        #expect(first.zones == ["a.dev", "b.dev", "test"])
        #expect(first.corefile == second.corefile)
    }

    @Test func theCorefileBindsLoopbackOnlyAndAnswersAAndAAAA() throws {
        let corefile = try plan(["acme.test"], port: 15354).corefile
        #expect(corefile.contains("test:15354 {"))
        #expect(corefile.contains("bind 127.0.0.1 ::1"))
        #expect(corefile.contains("IN A 127.0.0.1"))
        #expect(corefile.contains("IN AAAA ::1"))
        #expect(corefile.contains("reload 2s"))
    }

    @Test func theCorefileHasNoCatchAllZone() throws {
        let corefile = try plan(["acme.dev"]).corefile
        #expect(!corefile.contains(".:"))
        #expect(!corefile.contains("forward"))
    }

    @Test func reloadAppearsExactlyOnce() throws {
        let corefile = try plan(["a.dev", "b.dev", "c.dev"]).corefile
        #expect(corefile.components(separatedBy: "reload 2s").count == 2)
    }

    @Test func noZonesGivesNoServerBlocks() throws {
        let result = try plan(["app.localhost"])
        #expect(result.zones.isEmpty)
        #expect(!result.corefile.contains("{"))
    }

    @Test func rejectsBadPorts() {
        #expect(throws: DNSError.invalidPort(0)) { try DNSPlanner.plan(domains: [], port: 0) }
        #expect(throws: DNSError.invalidPort(70000)) { try DNSPlanner.plan(domains: [], port: 70000) }
    }
}
