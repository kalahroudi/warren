// SPDX-License-Identifier: Apache-2.0

import CryptoKit
import Foundation

public enum ToolInstallError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedArchitecture(String)
    case downloadFailed(String)
    case checksumMismatch(expected: String, actual: String)
    case extractionFailed(String)
    case binaryMissing(String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedArchitecture(name): "no download is pinned for \(name)"
        case let .downloadFailed(message): "download failed: \(message)"
        case let .checksumMismatch(expected, actual): "checksum mismatch (expected \(expected.prefix(16))..., got \(actual.prefix(16))...)"
        case let .extractionFailed(message): "could not unpack the download: \(message)"
        case let .binaryMissing(name): "the download did not contain '\(name)'"
        }
    }
}

/// Downloads a pinned tool, verifies its SHA-512, and unpacks it under `~/Warren/bin/<name>/<version>/`.
public struct ToolInstaller: Sendable {
    public let paths: WarrenPaths

    public init(paths: WarrenPaths) {
        self.paths = paths
    }

    public func binaryURL(for release: ToolRelease) -> URL {
        paths.binDirectory
            .appendingPathComponent(release.name, isDirectory: true)
            .appendingPathComponent(release.version, isDirectory: true)
            .appendingPathComponent(release.binaryName)
    }

    public func isInstalled(_ release: ToolRelease) -> Bool {
        FileManager.default.isExecutableFile(atPath: binaryURL(for: release).path)
    }

    @discardableResult
    public func install(_ release: ToolRelease, architecture: CPUArchitecture = .current) async throws -> URL {
        let asset = try release.asset(for: architecture)
        let archive = try await download(asset.url)
        defer { try? FileManager.default.removeItem(at: archive) }

        let (expected, actual) = try Self.compare(archive, against: asset.checksum)
        guard actual == expected else {
            throw ToolInstallError.checksumMismatch(expected: expected, actual: actual)
        }
        return try unpack(archive, release: release)
    }

    public static func sha512Hex(of file: URL) throws -> String {
        try digest(of: file, using: SHA512())
    }

    public static func sha256Hex(of file: URL) throws -> String {
        try digest(of: file, using: SHA256())
    }

    /// The pinned checksum and the one computed from the file, using the pinned algorithm.
    static func compare(_ file: URL, against checksum: ToolChecksum) throws -> (expected: String, actual: String) {
        switch checksum {
        case let .sha256(expected): try (expected, sha256Hex(of: file))
        case let .sha512(expected): try (expected, sha512Hex(of: file))
        }
    }

    private static func digest(of file: URL, using initial: some HashFunction) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = initial
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func download(_ url: URL) async throws -> URL {
        do {
            let (temporary, response) = try await URLSession.shared.download(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw ToolInstallError.downloadFailed("HTTP \(http.statusCode) from \(url.host ?? "server")")
            }
            let kept = FileManager.default.temporaryDirectory
                .appendingPathComponent("warren-\(UUID().uuidString).tar.gz")
            try FileManager.default.moveItem(at: temporary, to: kept)
            return kept
        } catch let error as ToolInstallError {
            throw error
        } catch {
            throw ToolInstallError.downloadFailed(error.localizedDescription)
        }
    }

    private func unpack(_ archive: URL, release: ToolRelease) throws -> URL {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(
            "warren-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let result = try Shell.run("/usr/bin/tar", ["-xzf", archive.path, "-C", scratch.path])
        guard result.status == 0 else { throw ToolInstallError.extractionFailed(result.output) }

        let extracted = scratch.appendingPathComponent(release.pathInArchive ?? release.binaryName)
        guard FileManager.default.fileExists(atPath: extracted.path) else {
            throw ToolInstallError.binaryMissing(release.binaryName)
        }
        let destination = binaryURL(for: release)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: extracted, to: destination)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        return destination
    }
}
