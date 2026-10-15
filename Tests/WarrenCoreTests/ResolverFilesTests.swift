// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import WarrenCore

struct ResolverFilesTests {
    private let directory: URL
    private let manager: ResolverManager

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("warren-resolver-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        manager = ResolverManager(directory: directory)
    }

    private func write(_ name: String, _ text: String) throws {
        try text.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    @Test func fileContentsCarryTheMarkerAndThePort() {
        let text = ResolverManager.contents(port: 5354)
        #expect(text == "# Managed by Warren\nnameserver 127.0.0.1\nport 5354\n")
    }

    @Test func inspectReportsEachState() throws {
        try write("current.dev", ResolverManager.contents(port: 5354))
        try write("stale.dev", ResolverManager.contents(port: 9999))
        try write("foreign.dev", "nameserver 10.0.0.1\n")
        let states = manager.inspect(zones: ["current.dev", "foreign.dev", "missing.dev", "stale.dev"], port: 5354)
        #expect(states.map(\.state) == [.current, .foreign, .missing, .stale])
    }

    @Test func theInstallScriptWritesOnlyMissingAndStaleFiles() throws {
        try write("current.dev", ResolverManager.contents(port: 5354))
        try write("stale.dev", ResolverManager.contents(port: 9999))
        let entries = manager.inspect(zones: ["current.dev", "missing.dev", "stale.dev"], port: 5354)
        let script = try #require(try manager.installScript(entries: entries, port: 5354))
        #expect(script.contains("missing.dev"))
        #expect(script.contains("stale.dev"))
        #expect(!script.contains("current.dev"))
        #expect(script.contains("port 5354"))
        #expect(script.contains("set -e"))
    }

    @Test func nothingToDoGivesNoScript() throws {
        try write("a.dev", ResolverManager.contents(port: 5354))
        let entries = manager.inspect(zones: ["a.dev"], port: 5354)
        #expect(try manager.installScript(entries: entries, port: 5354) == nil)
    }

    @Test func aForeignFileIsNeverOverwritten() throws {
        try write("foreign.dev", "nameserver 10.0.0.1\n")
        let entries = manager.inspect(zones: ["foreign.dev", "other.dev"], port: 5354)
        #expect(throws: DNSError.foreignResolverFile(directory.appendingPathComponent("foreign.dev").path)) {
            try manager.installScript(entries: entries, port: 5354)
        }
        #expect(try String(contentsOf: directory.appendingPathComponent("foreign.dev"), encoding: .utf8) ==
            "nameserver 10.0.0.1\n")
    }

    @Test func theRemovalScriptNamesOnlyManagedFiles() throws {
        try write("mine.dev", ResolverManager.contents(port: 5354))
        try write("theirs.dev", "nameserver 10.0.0.1\n")
        let script = try #require(manager.removalScript())
        #expect(script.contains("mine.dev"))
        #expect(!script.contains("theirs.dev"))
    }

    @Test func noManagedFilesGivesNoRemovalScript() throws {
        try write("theirs.dev", "nameserver 10.0.0.1\n")
        #expect(manager.removalScript() == nil)
    }

    @Test func pathsWithQuotesAreEscaped() throws {
        let tricky = ResolverManager(directory: directory.appendingPathComponent("it's here"))
        let entries = [ResolverEntry(
            zone: "a.dev",
            path: tricky.directory.appendingPathComponent("a.dev").path,
            state: .missing
        )]
        let script = try #require(try tricky.installScript(entries: entries, port: 5354))
        #expect(script.contains("'\\''"))
    }

    @Test func onlyTheSystemDirectoryNeedsPrivilege() {
        #expect(ResolverManager().needsPrivilege)
        #expect(!manager.needsPrivilege)
    }

    @Test func aScriptForATestDirectoryDoesNotFlushTheSystemCache() throws {
        let entries = manager.inspect(zones: ["a.dev"], port: 5354)
        let script = try #require(try manager.installScript(entries: entries, port: 5354))
        #expect(!script.contains("mDNSResponder"))
    }
}
