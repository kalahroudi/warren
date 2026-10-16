// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum CPUArchitecture: String, Sendable {
    case arm64
    case intel = "x86_64"

    public static var current: CPUArchitecture {
        #if arch(arm64)
            .arm64
        #else
            .intel
        #endif
    }
}

public enum ToolChecksum: Equatable, Sendable {
    case sha256(String)
    case sha512(String)
}

public struct ToolAsset: Equatable, Sendable {
    public let url: URL
    public let checksum: ToolChecksum
}

/// A third-party tool Warren downloads and manages: pinned version, one archive per architecture.
public struct ToolRelease: Sendable {
    public let name: String
    public let version: String
    public let binaryName: String
    /// Where the binary sits inside the archive, when it is not at the top.
    public var pathInArchive: String?
    public let assets: [CPUArchitecture: ToolAsset]

    public func asset(for architecture: CPUArchitecture) throws -> ToolAsset {
        guard let asset = assets[architecture]
        else { throw ToolInstallError.unsupportedArchitecture(architecture.rawValue) }
        return asset
    }
}

public extension ToolRelease {
    /// Caddy, used as the reverse proxy and local certificate authority (spec 005).
    /// Updating the pin means editing the version and hashes here, in a reviewed change.
    static let caddy = ToolRelease(
        name: "caddy",
        version: "2.11.7",
        binaryName: "caddy",
        assets: [
            .arm64: ToolAsset(
                url: caddyURL("caddy_2.11.7_mac_arm64.tar.gz"),
                checksum: .sha512(
                    "68f592df8f0ec058fbdb9b137b64e9a0aa792d28c06e1e3b9ec12d0e7fb37168"
                        + "3a54e73ef6d8e6d0dd70dc6b941a5b5d5b73faedd3f89de119ad2eb78bdc668e"
                )
            ),
            .intel: ToolAsset(
                url: caddyURL("caddy_2.11.7_mac_amd64.tar.gz"),
                checksum: .sha512(
                    "147886811fa2320a8881c6116dc8cc3f0562e2f686509ccc60f55cf85dfd5ea7"
                        + "8e9f5f770c75da13bf124a2536b72e887b975fefd58706de3dafb57483610e70"
                )
            ),
        ]
    )

    private static func caddyURL(_ file: String) -> URL {
        URL(string: "https://github.com/caddyserver/caddy/releases/download/v2.11.7/\(file)")!
    }
}

public extension ToolRelease {
    /// CoreDNS, used as the local DNS server (spec 006).
    static let coredns = ToolRelease(
        name: "coredns",
        version: "1.14.7",
        binaryName: "coredns",
        assets: [
            .arm64: ToolAsset(
                url: corednsURL("coredns_1.14.7_darwin_arm64.tgz"),
                checksum: .sha256("0005d154d49c73a88b2c56f429f35106e46c4ca37ee6de4e4d482d7de5c4b8ba")
            ),
            .intel: ToolAsset(
                url: corednsURL("coredns_1.14.7_darwin_amd64.tgz"),
                checksum: .sha256("49c2155e48a53c710eedcf8c6709bf5aee395e372bdca77ae978f042bf86c580")
            ),
        ]
    )

    private static func corednsURL(_ file: String) -> URL {
        URL(string: "https://github.com/coredns/coredns/releases/download/v1.14.7/\(file)")!
    }
}

public extension ToolRelease {
    /// mise, used to install and remove Node and Bun (spec 007).
    static let mise = ToolRelease(
        name: "mise",
        version: "2026.10.11",
        binaryName: "mise",
        pathInArchive: "mise/bin/mise",
        assets: [
            .arm64: ToolAsset(
                url: miseURL("mise-v2026.10.11-macos-arm64.tar.gz"),
                checksum: .sha256("64592e2978459d91b9dc690352c97d59a8c2b327f586fd201468fa56afe66311")
            ),
            .intel: ToolAsset(
                url: miseURL("mise-v2026.10.11-macos-x64.tar.gz"),
                checksum: .sha256("6eaffe02521c700b420ba6930dfbc528951f27c1c9896c827ab6aab7248c75f1")
            ),
        ]
    )

    private static func miseURL(_ file: String) -> URL {
        URL(string: "https://github.com/jdx/mise/releases/download/v2026.10.11/\(file)")!
    }
}
