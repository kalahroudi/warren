// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Works out what a project folder is and how to run it in development. Reads a few small files and never runs
/// anything, so it is safe on a repository the user did not write. See spec 010.
public enum FrameworkDetector {
    public static func detect(site: ResolvedSite) -> FrameworkDetection {
        detect(in: URL(fileURLWithPath: site.path, isDirectory: true), command: site.command, domains: site.domains)
    }

    /// `command` is the `[run] command` from `.warren.toml`, which always wins. `domains` are the site's names, used
    /// to allow them in dev servers that check the host.
    public static func detect(in directory: URL, command: String? = nil, domains: [String] = []) -> FrameworkDetection {
        let files = ProjectFiles(directory: directory)
        let manager = packageManager(files)
        var result = FrameworkDetection.unknown
        result.packageManager = manager

        if let rule = FrameworkRules.all.first(where: { $0.matches(files) }) {
            result.id = rule.id
            result.name = rule.name
            result.kind = rule.kind
            result.portHandling = rule.port
            result.documentRoot = rule.documentRoot(files)
            result.notes = rule.notes
            if let (text, source) = rule.command(files, manager) {
                result.command = text
                result.commandSource = source
            }
            if rule.allowsHostNames, let allowed = hostPattern(domains) {
                result.environment["__VITE_ADDITIONAL_SERVER_ALLOWED_HOSTS"] = allowed
                result.notes.append("Vite blocks unknown host names. Warren allows \(allowed) for this site.")
            }
        }
        if let command = command?.trimmingCharacters(in: .whitespacesAndNewlines), !command.isEmpty {
            result.command = command
            result.commandSource = .warrenConfig
            result.kind = .server
            if result.portHandling == .none {
                result.portHandling = .environment("PORT")
            }
        }
        return result
    }

    /// From the `packageManager` field, then the lockfile, for Node projects; Composer for PHP; uv or pip for Python.
    static func packageManager(_ files: ProjectFiles) -> PackageManager? {
        if files.hasPackageJSON {
            if let field = files.packageManagerField,
               let manager = PackageManager(rawValue: String(field.prefix { $0 != "@" }))
            {
                return manager
            }
            if files.exists("bun.lock") || files.exists("bun.lockb") {
                return .bun
            }
            if files.exists("pnpm-lock.yaml") {
                return .pnpm
            }
            if files.exists("yarn.lock") {
                return .yarn
            }
            return .npm
        }
        if files.exists("composer.json") {
            return .composer
        }
        if files.hasUvProject {
            return .uvCLI
        }
        if files.exists("requirements.txt") || files.exists("pyproject.toml") {
            return .pip
        }
        return nil
    }

    /// The value for Vite's `__VITE_ADDITIONAL_SERVER_ALLOWED_HOSTS`, which takes one name. A leading dot allows a
    /// name and everything under it (checked against Vite 7), so a site with several names sharing one ending gets
    /// that ending.
    static func hostPattern(_ domains: [String]) -> String? {
        guard let first = domains.first else { return nil }
        guard domains.count > 1 else { return first }
        let endings = Set(domains.map { $0.split(separator: ".").last.map(String.init) ?? $0 })
        return endings.count == 1 ? "." + endings[endings.startIndex] : first
    }
}
