// SPDX-License-Identifier: Apache-2.0

import Foundation

/// One pinned PHP build: the `php` and `php-fpm` binaries in one archive per architecture, built by Warren's
/// `php-build` workflow with static-php-cli and published as a release of this repository (spec 008).
public struct PHPRelease: Equatable, Sendable {
    public let version: String
    let assets: [CPUArchitecture: ToolAsset]

    /// `8.3` for `8.3.31`.
    public var minor: String {
        version.split(separator: ".").prefix(2).joined(separator: ".")
    }

    func asset(for architecture: CPUArchitecture) throws -> ToolAsset {
        guard let asset = assets[architecture]
        else { throw ToolInstallError.unsupportedArchitecture(architecture.rawValue) }
        return asset
    }

    /// Pins one build. Updating a patch version is a reviewed change to `offered`.
    static func pinned(_ version: String, arm64: String, intel: String) -> PHPRelease {
        func asset(_ arch: String, _ hash: String) -> ToolAsset {
            let url = "https://github.com/kalahroudi/warren/releases/download/php-\(version)/"
                + "warren-php-\(version)-macos-\(arch).tar.gz"
            return ToolAsset(url: URL(string: url)!, checksum: .sha256(hash))
        }
        return PHPRelease(version: version, assets: [
            .arm64: asset("aarch64", arm64),
            .intel: asset("x86_64", intel),
        ])
    }
}

/// Composer's own phar, pinned by hash and run by the PHP Warren installs.
public struct ComposerRelease: Equatable, Sendable {
    public let version: String
    let asset: ToolAsset

    static let current = ComposerRelease(
        version: "2.10.3",
        asset: ToolAsset(
            url: URL(string: "https://getcomposer.org/download/2.10.3/composer.phar")!,
            checksum: .sha256("7a2d379d5b8ffdaa028580ef26494c36d2feef4b178d3dd1473a4dbc5e17c8d6")
        )
    )
}

public extension PHPRelease {
    /// The PHP lines Warren offers, newest patch of each minor. PHP 8.1 no longer receives security fixes.
    static let offered: [PHPRelease] = []
}
