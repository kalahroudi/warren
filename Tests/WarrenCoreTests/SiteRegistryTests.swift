// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import WarrenCore

struct SiteRegistryTests {
    private let root: URL
    private let registry: SiteRegistry

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("warren-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        registry = SiteRegistry(paths: WarrenPaths(root: root.appendingPathComponent("home")))
    }

    private func folder(_ path: String, config: String? = nil) throws -> String {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        if let config {
            try config.write(
                to: url.appendingPathComponent(".warren.toml"),
                atomically: true,
                encoding: .utf8
            )
        }
        return url.path
    }

    @Test func addsAndListsASite() throws {
        let site = try registry.add(path: folder("a/shop"))
        #expect(site.id == "shop")
        #expect(site.domains == ["shop.test"])
        #expect(site.name == "shop")
        #expect(try registry.list().map(\.id) == ["shop"])
    }

    @Test func rejectsMissingPathsAndFiles() throws {
        #expect(throws: RegistryError.self) { try registry.add(path: root.appendingPathComponent("nope").path) }
        let file = root.appendingPathComponent("file.txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        #expect(throws: RegistryError.self) { try registry.add(path: file.path) }
    }

    @Test func sameFolderNameGetsASuffix() throws {
        try registry.add(path: folder("a/shop"))
        let second = try registry.add(path: folder("b/shop"))
        #expect(second.id == "shop-2")
    }

    @Test func registeringTheSamePathTwiceFails() throws {
        let path = try folder("a/shop")
        try registry.add(path: path)
        #expect(throws: RegistryError.alreadyRegistered(id: "shop")) { try registry.add(path: path) }
    }

    @Test func slugsAreSafe() {
        #expect(SiteRegistry.slug("My App!") == "my-app")
        #expect(SiteRegistry.slug("***") == "site")
        #expect(SiteRegistry.slug("Ärger_v2") == "rger-v2")
    }

    @Test func configOverridesDefaults() throws {
        let path = try folder("a/shop", config: "name = \"Acme\"\ndomains = [\"acme.test\"]\n[run]\nport = 3000")
        let site = try registry.add(path: path)
        #expect(site.name == "Acme")
        #expect(site.domains == ["acme.test"])
        #expect(site.port == 3000)
    }

    @Test func invalidConfigStillListsWithAProblem() throws {
        let path = try folder("a/shop", config: "port = = 3")
        let site = try registry.add(path: path)
        #expect(site.domains == ["shop.test"])
        #expect(site.problems.count == 1)
        #expect(site.problems[0].contains("Line 1"))
    }

    @Test func duplicateDomainsAreRejected() throws {
        try registry.add(path: folder("a/shop", config: "domains = [\"acme.test\"]"))
        let other = try folder("b/other", config: "domains = [\"acme.test\"]")
        #expect(throws: RegistryError.domainConflict(domain: "acme.test", otherSite: "shop")) {
            try registry.add(path: other)
        }
        #expect(try registry.list().count == 1)
    }

    @Test func removeLeavesProjectFiles() throws {
        let path = try folder("a/shop", config: "name = \"x\"")
        try registry.add(path: path)
        try registry.remove(id: "shop")
        #expect(try registry.list().isEmpty)
        #expect(FileManager.default.fileExists(atPath: path + "/.warren.toml"))
        #expect(throws: RegistryError.unknownSite("shop")) { try registry.remove(id: "shop") }
    }

    @Test func corruptRegistryIsBackedUpAndReported() throws {
        let file = registry.paths.sitesFile
        try FileManager.default.createDirectory(at: registry.paths.configDirectory, withIntermediateDirectories: true)
        try "{not json".write(to: file, atomically: true, encoding: .utf8)
        #expect(throws: RegistryError.self) { try registry.list() }
        #expect(!FileManager.default.fileExists(atPath: file.path))
        let backups = try FileManager.default.contentsOfDirectory(atPath: registry.paths.configDirectory.path)
        #expect(backups.contains { $0.hasPrefix("sites.json.corrupt-") })
    }

    @Test func newerRegistryVersionIsRejectedAndKept() throws {
        let file = registry.paths.sitesFile
        try FileManager.default.createDirectory(at: registry.paths.configDirectory, withIntermediateDirectories: true)
        try #"{"version":2,"sites":[]}"#.write(to: file, atomically: true, encoding: .utf8)
        #expect(throws: RegistryError.unsupportedVersion(2)) { try registry.list() }
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func warrenHomeRelocatesState() {
        let paths = WarrenPaths.fromEnvironment(["WARREN_HOME": "/tmp/elsewhere"])
        #expect(paths.sitesFile.path == "/tmp/elsewhere/config/sites.json")
    }

    @Test func stateDefaultsToWarrenInTheHomeFolder() throws {
        let home = try temporaryDirectory("home")
        #expect(WarrenPaths.fromEnvironment([:], home: home).root.lastPathComponent == "Warren")
    }

    @Test func stateStaysOutOfASourceCheckoutThatSharesTheName() throws {
        let home = try temporaryDirectory("home")
        let checkout = home.appendingPathComponent("Warren")
        try FileManager.default.createDirectory(at: checkout, withIntermediateDirectories: true)
        try "// swift-tools-version: 6.0".write(
            to: checkout.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )
        #expect(WarrenPaths.fromEnvironment([:], home: home).root.lastPathComponent == ".warren")
    }

    @Test func warrenHomeStillWinsOverTheCheckoutRule() throws {
        let home = try temporaryDirectory("home")
        let paths = WarrenPaths.fromEnvironment(["WARREN_HOME": "/tmp/elsewhere"], home: home)
        #expect(paths.root.path == "/tmp/elsewhere")
    }
}
