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

    private func release(for archive: URL, sha512: String) -> ToolRelease {
        ToolRelease(
            name: "demo", version: "1.0.0", binaryName: "demo",
            assets: [.current: ToolAsset(url: archive, sha512: sha512)]
        )
    }

    @Test func installsAndMarksTheBinaryExecutable() async throws {
        let archive = try makeArchive()
        let release = try release(for: archive, sha512: ToolInstaller.sha512Hex(of: archive))
        let binary = try await installer.install(release)
        #expect(FileManager.default.isExecutableFile(atPath: binary.path))
        #expect(installer.isInstalled(release))
        #expect(binary.path.hasSuffix("bin/demo/1.0.0/demo"))
    }

    @Test func aWrongChecksumIsRejectedAndNothingIsInstalled() async throws {
        let archive = try makeArchive()
        let release = release(for: archive, sha512: String(repeating: "0", count: 128))
        await #expect(throws: ToolInstallError.self) { try await installer.install(release) }
        #expect(!installer.isInstalled(release))
    }

    @Test func anArchiveWithoutTheBinaryIsRejected() async throws {
        let archive = try makeArchive(containing: "other")
        let release = try release(for: archive, sha512: ToolInstaller.sha512Hex(of: archive))
        await #expect(throws: ToolInstallError.binaryMissing("demo")) { try await installer.install(release) }
    }

    @Test func hashMatchesTheShasumTool() throws {
        let archive = try makeArchive()
        let expected = try Shell.run("/usr/bin/shasum", ["-a", "512", archive.path]).output.split(separator: " ")[0]
        #expect(try ToolInstaller.sha512Hex(of: archive) == String(expected))
    }

    @Test func theCaddyPinCoversBothArchitectures() throws {
        for architecture in [CPUArchitecture.arm64, .intel] {
            let asset = try ToolRelease.caddy.asset(for: architecture)
            #expect(asset.sha512.count == 128)
            #expect(asset.url.absoluteString
                .hasPrefix("https://github.com/caddyserver/caddy/releases/download/v2.11.7/"))
        }
    }
}
