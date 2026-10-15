// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Loads `https://warren.test` the way a browser does: through the macOS resolver and the system trust store.
/// It passes only if DNS, the certificate and the proxy all work, and otherwise names the part that failed.
public enum SetupCheck {
    public static func run(httpsPort: Int = 443) async -> CheckResult {
        guard DNSService.systemResolves(CaddyConfig.selfCheckDomain) else {
            return CheckResult(
                passed: false,
                message: "macOS cannot resolve \(CaddyConfig.selfCheckDomain) yet. Finish the Local domains step."
            )
        }
        let port = httpsPort == 443 ? "" : ":\(httpsPort)"
        guard let url = URL(string: "https://\(CaddyConfig.selfCheckDomain)\(port)/") else {
            return CheckResult(passed: false, message: "The check address is invalid.")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 6
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await URLSession(configuration: configuration).data(from: url)
            let body = String(bytes: data, encoding: .utf8) ?? ""
            guard (response as? HTTPURLResponse)?.statusCode == 200, body.contains(CaddyConfig.selfCheckBody) else {
                return CheckResult(
                    passed: false,
                    message: "\(CaddyConfig.selfCheckDomain) answered, but not with Warren's page."
                )
            }
            return CheckResult(
                passed: true,
                message: "\(CaddyConfig.selfCheckDomain) loaded over a trusted connection."
            )
        } catch {
            return CheckResult(passed: false, message: describe(error))
        }
    }

    /// Turns a URL loading error into the step the user should go back to.
    static func describe(_ error: Error) -> String {
        switch (error as? URLError)?.code {
        case .serverCertificateUntrusted, .serverCertificateHasUnknownRoot, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .secureConnectionFailed, .clientCertificateRejected:
            "The connection works, but the certificate is not trusted yet. Finish the Trust step."
        case .cannotConnectToHost, .networkConnectionLost, .timedOut, .cannotFindHost:
            "Nothing answered. Make sure the local HTTPS proxy is running."
        default:
            "The check failed: \(error.localizedDescription)"
        }
    }
}
