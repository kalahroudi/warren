// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A service a project appears to want, and the evidence for it.
public struct ServiceNeed: Equatable, Codable, Sendable {
    public let id: String
    public let name: String
    /// What in the project suggested it, for example `DB_CONNECTION=pgsql`.
    public let evidence: String
}

/// Reads an env file for signs that a project wants a database, cache, mail catcher or object store.
enum ServiceHints {
    private struct Rule: Sendable {
        let id: String
        let name: String
        let evidence: @Sendable (EnvFile) -> String?
    }

    private static func connection(_ env: EnvFile, _ values: Set<String>) -> String? {
        for key in ["DB_CONNECTION", "DATABASE_CONNECTION"] {
            if let value = env[key]?.lowercased(), values.contains(value) {
                return "\(key)=\(env[key] ?? "")"
            }
        }
        return nil
    }

    private static func url(_ env: EnvFile, schemes: [String]) -> String? {
        for key in env.keys where key.hasSuffix("DATABASE_URL") || key == "DB_URL" || key == "DATABASE_DSN" {
            let value = env[key] ?? ""
            if schemes.contains(where: { value.lowercased().hasPrefix($0 + "://") }) {
                return "\(key) is a \(value.prefix { $0 != ":" }) URL"
            }
        }
        return nil
    }

    private static let redisSettings = ["CACHE_DRIVER", "CACHE_STORE", "QUEUE_CONNECTION", "SESSION_DRIVER"]
    private static let localHosts: Set = ["mailpit", "mailhog", "localhost", "127.0.0.1"]

    private static let rules: [Rule] = [
        Rule(id: "postgres", name: "PostgreSQL") {
            connection($0, ["pgsql", "postgres", "postgresql"]) ?? url($0, schemes: ["postgres", "postgresql"])
        },
        Rule(id: "mysql", name: "MySQL") {
            connection($0, ["mysql", "mariadb"]) ?? url($0, schemes: ["mysql"])
        },
        Rule(id: "redis", name: "Redis") { env in
            if let key = ["REDIS_HOST", "REDIS_URL"].first(where: { env[$0] != nil }) {
                return "\(key) is set"
            }
            return redisSettings.first { env[$0]?.lowercased() == "redis" }.map { "\($0)=redis" }
        },
        Rule(id: "mailpit", name: "Mailpit") { env in
            guard env["MAIL_MAILER"]?.lowercased() == "smtp" || env["MAIL_MAILER"] == nil,
                  let host = env["MAIL_HOST"]?.lowercased(), localHosts.contains(host) else { return nil }
            return "MAIL_HOST=\(host)"
        },
        Rule(id: "minio", name: "MinIO") { env in
            if let key = env.keys.first(where: { $0.hasPrefix("MINIO_") }) {
                return "\(key) is set"
            }
            for key in ["AWS_ENDPOINT", "AWS_URL"] {
                if let value = env[key]?.lowercased(),
                   localHosts.contains(where: value.contains)
                {
                    return "\(key)=\(value)"
                }
            }
            return nil
        },
    ]

    static func needs(in env: EnvFile, file: String) -> [ServiceNeed] {
        rules.compactMap { rule in
            rule.evidence(env).map { ServiceNeed(id: rule.id, name: rule.name, evidence: "\(file): \($0)") }
        }
    }
}
