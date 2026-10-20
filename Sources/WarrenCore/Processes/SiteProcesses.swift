// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum SiteRunState: Equatable, Sendable {
    case stopped
    case starting
    /// `managed` is false for a server Warren did not start, found on the site's `run.port`.
    case running(managed: Bool)
    /// The job ended without being stopped.
    case crashed(exitCode: Int32?)
}

public enum StartError: Error, Equatable, LocalizedError, Sendable {
    case nothingToStart
    case declined
    case runtimeMissing([String])
    case socketPathTooLong(String)
    case exited(code: Int32?, lastLines: [String])
    case notAnswering(seconds: Int)

    public var errorDescription: String? {
        switch self {
        case .nothingToStart: "Warren does not know how to start this site. Add a [run] command to .warren.toml."
        case .declined: "the command was not approved"
        case let .runtimeMissing(labels): "\(labels.joined(separator: ", ")) is not installed. Run setup first."
        case let .socketPathTooLong(path):
            "the socket path is too long for macOS (104 bytes at most): \(path). Use a shorter WARREN_HOME."
        case let .exited(code, lines):
            SiteProcesses.cause(forLog: lines, exitCode: code) ?? "it stopped right after starting"
                + (code.map { " (exit status \($0))" } ?? "") + (lines.last.map { ": \($0)" } ?? "")
        case let .notAnswering(seconds): "it did not answer within \(seconds) seconds. It may still be starting; see the log."
        }
    }
}

/// Starts, stops and reports on sites: servers on a port, PHP through PHP-FPM, and static files. Each runs as a
/// launchd job that Warren loads on request, so it keeps running when the app quits and is never started at login.
/// See spec 015.
public struct SiteProcesses: Sendable {
    public let paths: WarrenPaths
    public let host: JobHost
    public let ports: SitePorts
    private let manager: RuntimeManager
    private let routesChanged: @Sendable () -> Void

    /// `routesChanged` runs after a site starts or stops, so the proxy picks up its route.
    public init(
        paths: WarrenPaths,
        launch: any LaunchControlling = LaunchCtl(),
        ports: SitePorts? = nil,
        manager: RuntimeManager? = nil,
        routesChanged: (@Sendable () -> Void)? = nil
    ) {
        self.paths = paths
        host = JobHost(paths: paths, launch: launch)
        self.ports = ports ?? SitePorts(paths: paths)
        self.manager = manager ?? RuntimeManager(paths: paths)
        self.routesChanged = routesChanged ?? { _ = NetworkServices(paths: paths).applyRegistryChange() }
    }

    // MARK: Names

    static func label(_ id: String) -> String {
        "dev.warren.site.\(id)"
    }

    static func phpLabel(_ id: String) -> String {
        "dev.warren.php.\(id)"
    }

    public func logURL(_ siteID: String) -> URL {
        paths.siteLog(siteID)
    }

    // MARK: State

    public func state(of site: ResolvedSite, detection: FrameworkDetection? = nil) -> SiteRunState {
        let detection = detection ?? FrameworkDetector.detect(site: site)
        if site.port == nil, detection.kind == .staticFiles {
            return FileManager.default.fileExists(atPath: paths.staticMarker(site.id).path)
                ? .running(managed: true) : .stopped
        }
        let usesFPM = site.port == nil && detection.kind == .php
        let (stem, label) = usesFPM ? ("php-\(site.id)", Self.phpLabel(site.id)) : (
            "site-\(site.id)",
            Self.label(site.id)
        )
        guard host.hasPlist(stem: stem), let info = host.info(label: label) else {
            if let port = site.port, PortCheck.isListening(port) {
                return .running(managed: false)
            }
            return .stopped
        }
        guard info.running else { return .crashed(exitCode: info.lastExit) }
        let ready = usesFPM ? UnixSocket.canConnect(to: paths.phpSocket(site.id).path)
            : (site.port ?? ports.assigned(for: site.id)).map(PortCheck.isListening) ?? false
        return ready ? .running(managed: true) : .starting
    }

    // MARK: Start

    /// What approving a start shows: the command exactly as it will be run, apart from the port.
    public func approvalStep(for site: ResolvedSite, detection: FrameworkDetection) -> PlanStep? {
        guard let command = StartCommand.make(detection, port: site.port ?? 0) else { return nil }
        return PlanStep(
            id: "start", kind: .application, title: "Start \(site.name)",
            detail: "Runs in \(site.path). Warren passes the port.", command: command.shown, runsProjectCode: true,
            state: .todo, waitsFor: [], enabledByDefault: true
        )
    }

    /// Starts the site and returns once it answers. Does nothing if it is already running or starting.
    public func start(
        _ site: ResolvedSite, timeout: TimeInterval = 60, approve: PlanRunner.Approval
    ) async throws {
        let detection = FrameworkDetector.detect(site: site)
        switch state(of: site, detection: detection) {
        case .running(managed: true), .starting: return
        default: break
        }
        if site.port == nil, detection.kind == .staticFiles {
            try FileManager.default.createDirectory(at: paths.runDirectory, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: paths.staticMarker(site.id).path, contents: nil)
            routesChanged()
            return
        }
        let plan = SetupPlanner(paths: paths).plan(
            for: site, registered: true, inventory: (try? manager.inventory()) ?? [],
            tools: (try? manager.installedTools()) ?? []
        )
        let missing = manager.needs(for: plan).filter { !$0.isInstalled }.map(\.requirement.label)
        guard missing.isEmpty else { throw StartError.runtimeMissing(missing) }
        let environment = manager.siteEnvironment(plan: plan, base: Self.baseEnvironment)
        if site.port == nil, detection.kind == .php {
            try await startPHP(site, detection: detection, plan: plan, environment: environment, timeout: timeout)
        } else {
            try await startServer(
                site, detection: detection, environment: environment, timeout: timeout, approve: approve
            )
        }
    }

    private func startServer(
        _ site: ResolvedSite, detection: FrameworkDetection, environment: [String: String], timeout: TimeInterval,
        approve: PlanRunner.Approval
    ) async throws {
        guard let step = approvalStep(for: site, detection: detection), let command = step.command else {
            throw StartError.nothingToStart
        }
        try await confirm(step, command: command, site: site, approve: approve)
        let port = try ports.resolve(for: site)
        guard let start = StartCommand.make(detection, port: port) else { throw StartError.nothingToStart }
        var variables = environment
        variables.merge(start.environment) { _, new in new }
        let job = ManagedJob(
            label: Self.label(site.id), stem: "site-\(site.id)", program: "/bin/sh", arguments: ["-c", start.line],
            environment: variables, directory: site.path, logFile: logURL(site.id)
        )
        try host.start(job)
        routesChanged()
        try await waitUntil(timeout: timeout, label: job.label, site: site) { PortCheck.isListening(port) }
    }

    private func startPHP(
        _ site: ResolvedSite, detection: FrameworkDetection, plan: SetupPlan, environment: [String: String],
        timeout: TimeInterval
    ) async throws {
        guard let need = manager.needs(for: plan).first(where: { $0.requirement.kind == .php }),
              let install = need.installPath else { throw StartError.runtimeMissing(["PHP"]) }
        let socket = paths.phpSocket(site.id)
        guard socket.path.utf8.count < 104 else { throw StartError.socketPathTooLong(socket.path) }
        try FileManager.default.createDirectory(at: paths.runDirectory, withIntermediateDirectories: true)
        try Data(Self.fpmConfig(socket: socket.path).utf8).write(to: paths.phpConfig(site.id), options: .atomic)
        let job = ManagedJob(
            label: Self.phpLabel(site.id), stem: "php-\(site.id)",
            program: install.appendingPathComponent("bin/php-fpm").path,
            arguments: ["--nodaemonize", "--fpm-config", paths.phpConfig(site.id).path],
            environment: environment, directory: SiteServing.root(URL(fileURLWithPath: site.path), detection),
            logFile: logURL(site.id)
        )
        try? FileManager.default.removeItem(at: socket)
        try host.start(job)
        routesChanged()
        try await waitUntil(timeout: timeout, label: job.label, site: site) { UnixSocket.canConnect(to: socket.path) }
    }

    /// A master with no workers until a request arrives, and workers that leave soon after.
    static func fpmConfig(socket: String) -> String {
        """
        ; Written by Warren for one site.
        [global]
        daemonize = no
        error_log = /dev/stderr

        [www]
        listen = \(socket)
        listen.mode = 0600
        pm = ondemand
        pm.max_children = 8
        pm.process_idle_timeout = 10s
        catch_workers_output = yes
        clear_env = no

        """
    }

    /// Asks unless the command is already trusted for the site. Throws `declined` if the answer is no.
    private func confirm(
        _ step: PlanStep, command: [String], site: ResolvedSite, approve: PlanRunner.Approval
    ) async throws {
        let registry = SiteRegistry(paths: paths)
        let trusted = (try? registry.trustedCommands(id: site.id)) ?? []
        guard !trusted.contains(command) else { return }
        let decision = await approve([step])
        guard decision.approved.contains(step.id) else { throw StartError.declined }
        if decision.trust {
            try? registry.setTrustedCommands(id: site.id, trusted + [command])
        }
    }

    private func waitUntil(
        timeout: TimeInterval, label: String, site: ResolvedSite, ready: @Sendable () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if ready() {
                return
            }
            if let info = host.info(label: label), !info.running {
                throw StartError.exited(code: info.lastExit, lastLines: lastLines(site.id, count: 12))
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        throw StartError.notAnswering(seconds: Int(timeout))
    }

    /// What launchd gives a job: little. Warren adds a usual search path, and the runtime folders go in front.
    static var baseEnvironment: [String: String] {
        [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin",
            "HOME": NSHomeDirectory(), "LANG": "en_US.UTF-8", "NO_COLOR": "1",
        ]
    }

    // MARK: Stop

    /// Stops the site and everything it started. Safe to call when it is not running.
    public func stop(_ site: ResolvedSite) throws {
        try host.stop(label: Self.label(site.id), stem: "site-\(site.id)")
        try host.stop(label: Self.phpLabel(site.id), stem: "php-\(site.id)")
        try? FileManager.default.removeItem(at: paths.staticMarker(site.id))
        try? FileManager.default.removeItem(at: paths.phpSocket(site.id))
        try? FileManager.default.removeItem(at: paths.phpConfig(site.id))
        routesChanged()
    }

    // MARK: Logs

    public func lastLines(_ siteID: String, count: Int) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: logURL(siteID)) else { return [] }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 65536 ? size - 65536 : 0)
        let text = String(bytes: (try? handle.readToEnd()) ?? Data(), encoding: .utf8) ?? ""
        return Array(text.split(separator: "\n", omittingEmptySubsequences: true).suffix(count).map(String.init))
    }

    /// A plain sentence for failures that look familiar.
    public static func cause(forLog lines: [String], exitCode: Int32?) -> String? {
        let text = lines.joined(separator: "\n").lowercased()
        if text.contains("eaddrinuse") || text.contains("address already in use") {
            return "Another program is using the port."
        }
        if exitCode == 127 || text.contains("command not found") {
            return "A tool the command needs was not found. Run setup to install it."
        }
        if text.contains("cannot find module") || text.contains("modulenotfounderror")
            || text.contains("no module named") || text.contains("failed to open stream")
        {
            return "A dependency is missing. Run setup to install the project's dependencies."
        }
        return PlanRunner.advice(forFailureLines: lines, exitCode: exitCode ?? 1)
    }
}

public extension SiteRunState {
    /// One word for scripts and `--json`.
    var word: String {
        switch self {
        case .stopped: "stopped"
        case .starting: "starting"
        case .running: "running"
        case .crashed: "crashed"
        }
    }
}
