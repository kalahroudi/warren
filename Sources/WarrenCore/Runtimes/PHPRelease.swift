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
    static let offered: [PHPRelease] = [
        .pinned(
            "8.2.34",
            arm64: "0dea9a5afebb7747fff7f6076c720dbee21e161210cd3c9af05353157191cead",
            intel: "086618d7ace4444ce79699d721410325e2b8b09de8452b21f24fa4edbacea350"
        ),
        .pinned(
            "8.3.35",
            arm64: "dbd69aaf5c73aa2ed5c2c10e30a94f82575f2a37d3c2b78c2cc3c5cad3177e0d",
            intel: "cd32de5b0d6c3e0c906ae719f27d7fb32e9acadd7955bbadb2662037ed2a3533"
        ),
        .pinned(
            "8.4.26",
            arm64: "8ec44e3b8e2b72b17e4c1310932a053e13d3e7ecfe50ac80b9f219fafea24703",
            intel: "7994aacc35f133cf55b08c0a00085d3e4b84bf48424d62adfc69824384ba1832"
        ),
        .pinned(
            "8.5.11",
            arm64: "fab6ca5e1a7f5de111372863a740696f61b9874cac55efe778db56b9405a2371",
            intel: "dfbad901dbe6aae6fab96b190ca3481e8e83f3436fed1a44ca157e04350dd1fa"
        ),
    ]
}
