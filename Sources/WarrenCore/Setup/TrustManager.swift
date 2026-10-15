// SPDX-License-Identifier: Apache-2.0

import CryptoKit
import Foundation

/// The scripts that trust and untrust Warren's local root certificate. Uses the system `security` tool, so it works
/// without a terminal (unlike `caddy trust`, which runs `sudo`).
public struct TrustManager: Sendable {
    public let paths: WarrenPaths

    public init(paths: WarrenPaths) {
        self.paths = paths
    }

    private var certificate: URL {
        paths.caddyRootCertificate
    }

    /// Adds the root certificate to the System keychain as a trusted root.
    public func trustScript() throws -> String {
        guard FileManager.default.fileExists(atPath: certificate.path) else { throw ProxyError.rootCertificateMissing }
        return [
            "#!/bin/sh",
            "set -e",
            "/usr/bin/security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain \(quoted(certificate.path))",
        ].joined(separator: "\n") + "\n"
    }

    /// Removes the trust setting and the certificate itself from the System keychain.
    public func untrustScript() throws -> String {
        guard FileManager.default.fileExists(atPath: certificate.path) else { throw ProxyError.rootCertificateMissing }
        var lines = ["#!/bin/sh", "set -e", "/usr/bin/security remove-trusted-cert -d \(quoted(certificate.path))"]
        if let fingerprint = try? Self.sha1Fingerprint(ofPEM: certificate) {
            lines
                .append(
                    "/usr/bin/security delete-certificate -Z \(fingerprint) /Library/Keychains/System.keychain || true"
                )
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// The SHA-1 fingerprint of a PEM certificate, in the form `security` expects.
    static func sha1Fingerprint(ofPEM file: URL) throws -> String {
        let pem = try String(contentsOf: file, encoding: .utf8)
        let body = pem.split(separator: "\n").filter { !$0.hasPrefix("-----") }.joined()
        guard let der = Data(base64Encoded: body) else { throw ProxyError.rootCertificateMissing }
        return Insecure.SHA1.hash(data: der).map { String(format: "%02X", $0) }.joined()
    }

    private func quoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
