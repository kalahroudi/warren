// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import WarrenCore

struct ToolInstallerTests {
    private let root: URL
    private let installer: ToolInstaller

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("warren-tool-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        installer = ToolInstaller(paths: WarrenPaths(root: root.appendingPathComponent("home")))
    }

    /// A tiny archive containing an executable named `demo`, served from a local file URL.
    private func makeArchive(containing name: String = "demo") throws -> URL {
        let source = root.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try "#!/bin/sh\necho hi\n".write(to: source.appendingPathComponent(name), atomically: true, encoding: .utf8)
        let archive = root.appendingPathComponent("demo.tar.gz")
        let result = try Shell.run("/usr/bin/tar", ["-czf", archive.path, "-C", source.path, name])
        try #require(result.status == 0)
        return archive
    }

    private func release(for archive: URL, checksum: ToolChecksum) -> ToolRelease {
        ToolRelease(
            name: "demo", version: "1.0.0", binaryName: "demo",
            assets: [.current: ToolAsset(url: archive, checksum: checksum)]
        )
    }

    @Test func installsAndMarksTheBinaryExecutable() async throws {
        let archive = try makeArchive()
        let release = try release(for: archive, checksum: .sha512(ToolInstaller.sha512Hex(of: archive)))
        let binary = try await installer.install(release)
        #expect(FileManager.default.isExecutableFile(atPath: binary.path))
        #expect(installer.isInstalled(release))
        #expect(binary.path.hasSuffix("bin/demo/1.0.0/demo"))
    }

    @Test func aWrongChecksumIsRejectedAndNothingIsInstalled() async throws {
        let archive = try makeArchive()
        let release = release(for: archive, checksum: .sha512(String(repeating: "0", count: 128)))
        await #expect(throws: ToolInstallError.self) { try await installer.install(release) }
        #expect(!installer.isInstalled(release))
    }

    @Test func anArchiveWithoutTheBinaryIsRejected() async throws {
        let archive = try makeArchive(containing: "other")
        let release = try release(for: archive, checksum: .sha512(ToolInstaller.sha512Hex(of: archive)))
        await #expect(throws: ToolInstallError.binaryMissing("demo")) { try await installer.install(release) }
    }

    @Test func hashMatchesTheShasumTool() throws {
        let archive = try makeArchive()
        let expected = try Shell.run("/usr/bin/shasum", ["-a", "512", archive.path]).output.split(separator: " ")[0]
        #expect(try ToolInstaller.sha512Hex(of: archive) == String(expected))
    }

    @Test func sha256ChecksumsAreVerifiedToo() async throws {
        let archive = try makeArchive()
        let good = try release(for: archive, checksum: .sha256(ToolInstaller.sha256Hex(of: archive)))
        _ = try await installer.install(good)
        let bad = release(for: archive, checksum: .sha256(String(repeating: "0", count: 64)))
        await #expect(throws: ToolInstallError.self) { try await installer.install(bad) }
    }

    @Test func theCorednsPinCoversBothArchitectures() throws {
        for architecture in [CPUArchitecture.arm64, .intel] {
            let asset = try ToolRelease.coredns.asset(for: architecture)
            guard case let .sha256(hash) = asset.checksum else { Issue.record("expected a SHA-256 pin"); continue }
            #expect(hash.count == 64)
            #expect(asset.url.absoluteString.hasPrefix("https://github.com/coredns/coredns/releases/download/v1.14.7/"))
        }
    }

    @Test func theCaddyPinCoversBothArchitectures() throws {
        for architecture in [CPUArchitecture.arm64, .intel] {
            let asset = try ToolRelease.caddy.asset(for: architecture)
            guard case let .sha512(hash) = asset.checksum else { Issue.record("expected a SHA-512 pin"); continue }
            #expect(hash.count == 128)
            #expect(asset.url.absoluteString
                .hasPrefix("https://github.com/caddyserver/caddy/releases/download/v2.11.7/"))
        }
    }
}
