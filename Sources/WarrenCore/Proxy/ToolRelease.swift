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

public struct ToolAsset: Equatable, Sendable {
    public let url: URL
    public let sha512: String
}

/// A third-party tool Warren downloads and manages: pinned version, one archive per architecture.
public struct ToolRelease: Sendable {
    public let name: String
    public let version: String
    public let binaryName: String
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
                sha512: "68f592df8f0ec058fbdb9b137b64e9a0aa792d28c06e1e3b9ec12d0e7fb37168"
                    + "3a54e73ef6d8e6d0dd70dc6b941a5b5d5b73faedd3f89de119ad2eb78bdc668e"
            ),
            .intel: ToolAsset(
                url: caddyURL("caddy_2.11.7_mac_amd64.tar.gz"),
                sha512: "147886811fa2320a8881c6116dc8cc3f0562e2f686509ccc60f55cf85dfd5ea7"
                    + "8e9f5f770c75da13bf124a2536b72e887b975fefd58706de3dafb57483610e70"
            ),
        ]
    )

    private static func caddyURL(_ file: String) -> URL {
        URL(string: "https://github.com/caddyserver/caddy/releases/download/v2.11.7/\(file)")!
    }
}
