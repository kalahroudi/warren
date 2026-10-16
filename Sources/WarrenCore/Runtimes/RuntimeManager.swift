// SPDX-License-Identifier: Apache-2.0

import Foundation

/// What one site needs from one runtime, and whether it is installed.
public struct RuntimeNeed: Equatable, Sendable {
    public let requirement: RuntimeRequirement
    /// The installed version that satisfies the requirement. Nil when it is not installed.
    public let installedVersion: String?
    public let installPath: URL?

    public var isInstalled: Bool {
        installedVersion != nil
    }
}

public struct SiteRuntimePlan: Equatable, Sendable {
    public let siteID: String
    public let needs: [RuntimeNeed]

    public var missing: [RuntimeNeed] {
        needs.filter { !$0.isInstalled }
    }
}

/// Installed runtimes, what sites need, and the environment to run a site in.
public struct RuntimeManager: Sendable {
    public let paths: WarrenPaths
    public let mise: MiseTool
    public let php: PHPTool
    public let uvTool: UvTool

    public init(paths: WarrenPaths, mise: MiseTool? = nil, php: PHPTool? = nil, uvTool: UvTool? = nil) {
        self.paths = paths
        self.mise = mise ?? MiseTool(paths: paths)
        self.php = php ?? PHPTool(paths: paths)
        self.uvTool = uvTool ?? UvTool(paths: paths)
    }

    public func inventory() throws -> [InstalledRuntime] {
        try mise.installed() + php.installed() + uvTool.installed()
    }

    /// Stable releases, newest last.
    public func available(_ kind: RuntimeKind) async throws -> [String] {
        if kind == .php {
            return php.available()
        }
        if kind == .python {
            return try await uvTool.availableVersions()
        }
        try await mise.ensureInstalled()
        return try mise.availableVersions(kind)
    }

    /// The newest release of each major line, newest first, for a short list to pick from.
    public static func latestPerMajor(_ versions: [String]) -> [String] {
        var newest: [Int: (SemanticVersion, String)] = [:]
        for text in versions {
            guard let version = SemanticVersion(text) else { continue }
            if newest[version.major].map({ $0.0 < version }) ?? true {
                newest[version.major] = (version, text)
            }
        }
        return newest.values.sorted { $0.0 > $1.0 }.map(\.1)
    }

    public func install(
        _ kind: RuntimeKind,
        version: String,
        onProgress: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws {
        if kind == .php {
            try await php.install(version: version, onProgress: onProgress)
        } else if kind == .python {
            try await uvTool.install(version: version, onProgress: onProgress)
        } else {
            try await mise.install(kind, version: version, onProgress: onProgress)
        }
    }

    /// Installs what a requirement asks for, resolving ranges against the releases that exist.
    public func install(_ requirement: RuntimeRequirement, onProgress: @escaping @Sendable (String) -> Void = { _ in })
        async throws
    {
        var version = requirement.requested
        if requirement.range != nil {
            let releases = try await available(requirement.kind)
            guard let chosen = RuntimeResolver.versionToInstall(for: requirement, available: releases) else {
                throw RuntimeError.noSuchVersion(requirement.label)
            }
            version = chosen
        }
        try await install(requirement.kind, version: version, onProgress: onProgress)
    }

    public func remove(_ runtime: InstalledRuntime) throws {
        if runtime.kind == .php {
            try php.uninstall(runtime)
        } else if runtime.kind == .python {
            try uvTool.uninstall(runtime)
        } else {
            try mise.uninstall(runtime)
        }
    }

    public func plan(for site: ResolvedSite, installed: [InstalledRuntime]) -> SiteRuntimePlan {
        let needs = RuntimeResolver.requirements(for: site).map { requirement -> RuntimeNeed in
            let candidates = installed.filter { $0.kind == requirement.kind }
            let version = RuntimeResolver.match(requirement, among: candidates.map(\.version))
            let path = candidates.first { $0.version == version }?.path
            return RuntimeNeed(requirement: requirement, installedVersion: version, installPath: path)
        }
        return SiteRuntimePlan(siteID: site.id, needs: needs)
    }

    /// The sites that currently resolve to an installed version, so removing it can name them.
    public static func sites(using runtime: InstalledRuntime, in plans: [SiteRuntimePlan]) -> [String] {
        plans.filter { plan in
            plan.needs.contains { $0.requirement.kind == runtime.kind && $0.installedVersion == runtime.version }
        }.map(\.siteID)
    }

    /// The variables to run a site with: its runtimes first on `PATH`, and the shared package caches.
    public func environment(
        for plan: SiteRuntimePlan,
        base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var environment = base
        var binaries = plan.needs.compactMap { $0.installPath?.appendingPathComponent("bin").path }
        if let need = plan.needs.first(where: { $0.requirement.kind == .php }), let path = need.installPath,
           let version = need.installedVersion
        {
            let runtime = InstalledRuntime(kind: .php, version: version, path: path, bytes: 0)
            environment.merge(php.environment(for: runtime)) { _, new in new }
            binaries += [php.composerBin?.path].compactMap(\.self)
        }
        if plan.needs.contains(where: { $0.requirement.kind == .python && $0.isInstalled }) {
            environment.merge(uvTool.siteEnvironment()) { _, new in new }
            binaries += [uvTool.binDirectory?.path].compactMap(\.self)
        }
        if !binaries.isEmpty {
            environment["PATH"] = (binaries + [base["PATH"]].compactMap(\.self)).joined(separator: ":")
        }
        environment.merge(PackageCaches.environment(paths)) { _, new in new }
        return environment
    }
}
