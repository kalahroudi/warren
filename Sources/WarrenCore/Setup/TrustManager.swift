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

    /// Trusts the certificate from the app. Writing the System keychain needs root, but changing trust settings
    /// needs macOS's own authorization dialog, which root running behind a password prompt cannot show. So root adds
    /// the certificate and the user then sets the trust, which asks for the password (or Touch ID) once more.
    public func trust(prompt: String) throws {
        guard FileManager.default.fileExists(atPath: certificate.path) else { throw ProxyError.rootCertificateMissing }
        // Already present from an earlier attempt is fine; the trust step below fails if the certificate is missing.
        let add = "#!/bin/sh\n/usr/bin/security add-certificates -k /Library/Keychains/System.keychain "
            + quoted(certificate.path) + " || true\n"
        try AdminRunner.run(script: add, prompt: prompt)
        try runAsUser(["add-trusted-cert", "-d", "-r", "trustRoot", certificate.path])
    }

    /// The reverse of `trust(prompt:)`: the user removes the trust setting, then root removes the certificate.
    public func untrust(prompt: String) throws {
        guard FileManager.default.fileExists(atPath: certificate.path) else { throw ProxyError.rootCertificateMissing }
        try runAsUser(["remove-trusted-cert", "-d", certificate.path])
        if let fingerprint = try? Self.sha1Fingerprint(ofPEM: certificate) {
            let remove = "#!/bin/sh\n/usr/bin/security delete-certificate -Z \(fingerprint) "
                + "/Library/Keychains/System.keychain || true\n"
            try AdminRunner.run(script: remove, prompt: prompt)
        }
    }

    private func runAsUser(_ arguments: [String]) throws {
        let result = try Shell.run("/usr/bin/security", arguments)
        guard result.status == 0 else {
            let text = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            // The dialog reports a cancel as "User canceled the authorization".
            if text.localizedCaseInsensitiveContains("cancel") {
                throw AdminError.cancelled
            }
            throw AdminError.failed(text)
        }
    }

    /// The same steps as one script, for the command line, where `sudo` runs in a terminal and can show its prompt.
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
