// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum ResolverState: Equatable, Sendable {
    case missing
    case current
    /// Warren's file, but for a different port.
    case stale
    /// A file Warren did not create. Never touched.
    case foreign
}

public struct ResolverEntry: Equatable, Sendable {
    public let zone: String
    public let path: String
    public let state: ResolverState
}

/// Plans and scripts the per-domain resolver files macOS reads from `/etc/resolver`.
/// Warren only ever creates or removes files carrying its marker line.
public struct ResolverManager: Sendable {
    public static let marker = "# Managed by Warren"
    public static let systemDirectory = URL(fileURLWithPath: "/etc/resolver", isDirectory: true)

    public let directory: URL

    public init(directory: URL = ResolverManager.systemDirectory) {
        self.directory = directory
    }

    /// Writing to the system directory needs an admin password. A test directory does not.
    public var needsPrivilege: Bool {
        directory.path == Self.systemDirectory.path
    }

    public static func contents(port: Int) -> String {
        "\(marker)\nnameserver 127.0.0.1\nport \(port)\n"
    }

    public func inspect(zones: [String], port: Int) -> [ResolverEntry] {
        zones.map { zone in
            let file = directory.appendingPathComponent(zone)
            guard let existing = try? String(contentsOf: file, encoding: .utf8) else {
                return ResolverEntry(zone: zone, path: file.path, state: .missing)
            }
            let state: ResolverState = if !existing.hasPrefix(Self.marker) {
                .foreign
            } else if existing == Self.contents(port: port) {
                .current
            } else {
                .stale
            }
            return ResolverEntry(zone: zone, path: file.path, state: state)
        }
    }

    /// A shell script that writes the missing or outdated files. Nil if nothing needs doing.
    /// Throws, changing nothing, if a zone's file exists and is not Warren's.
    public func installScript(entries: [ResolverEntry], port: Int) throws -> String? {
        if let foreign = entries.first(where: { $0.state == .foreign }) {
            throw DNSError.foreignResolverFile(foreign.path)
        }
        let pending = entries.filter { $0.state == .missing || $0.state == .stale }
        guard !pending.isEmpty else { return nil }

        var lines = ["#!/bin/sh", "set -e", "mkdir -p \(quoted(directory.path))"]
        for entry in pending {
            lines.append("cat > \(quoted(entry.path)) <<'WARREN_EOF'")
            lines.append(Self.contents(port: port).trimmingCharacters(in: .newlines))
            lines.append("WARREN_EOF")
        }
        lines += flushCommands
        return lines.joined(separator: "\n") + "\n"
    }

    /// A shell script that removes every file in the directory that carries Warren's marker. Nil if none.
    public func removalScript() -> String? {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let managed = files.sorted().filter { name in
            let text = try? String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
            return text?.hasPrefix(Self.marker) == true
        }
        guard !managed.isEmpty else { return nil }
        let removals = managed.map { "rm -f \(quoted(directory.appendingPathComponent($0).path))" }
        return (["#!/bin/sh", "set -e"] + removals + flushCommands).joined(separator: "\n") + "\n"
    }

    private var flushCommands: [String] {
        needsPrivilege ? ["dscacheutil -flushcache", "killall -HUP mDNSResponder 2>/dev/null || true"] : []
    }

    private func quoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
