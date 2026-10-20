// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import WarrenCore

struct ProcessTests {
    private func home() throws -> WarrenPaths {
        try WarrenPaths(root: temporaryDirectory("proc"))
    }

    private func project(_ files: [String: String]) throws -> URL {
        let folder = try temporaryDirectory("site")
        for (name, text) in files {
            let url = folder.appendingPathComponent(name)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(text.utf8).write(to: url)
        }
        return folder
    }

    // MARK: Job

    @Test func theJobIsStartedOnceNotKeptAliveAndGivenItsFolderEnvironmentAndLog() throws {
        let job = ManagedJob(
            label: "dev.warren.site.shop", stem: "site-shop", program: "/bin/sh", arguments: ["-c", "npm run dev"],
            environment: ["PORT": "4100"], directory: "/tmp/shop", logFile: URL(fileURLWithPath: "/tmp/shop.log")
        )
        let plist = try #require(
            PropertyListSerialization.propertyList(from: job.plist(), format: nil) as? [String: Any]
        )
        #expect(plist["Label"] as? String == "dev.warren.site.shop")
        #expect(plist["ProgramArguments"] as? [String] == ["/bin/sh", "-c", "npm run dev"])
        #expect(plist["WorkingDirectory"] as? String == "/tmp/shop")
        #expect(plist["RunAtLoad"] as? Bool == true)
        #expect(plist["KeepAlive"] as? Bool == false)
        #expect(plist["ExitTimeOut"] as? Int == 5)
        #expect(plist["StandardOutPath"] as? String == "/tmp/shop.log")
        #expect(plist["StandardErrorPath"] as? String == "/tmp/shop.log")
        #expect((plist["EnvironmentVariables"] as? [String: String])?["PORT"] == "4100")
    }

    @Test func launchctlOutputIsReadForStateAndExitCode() {
        let running = "dev.warren.site.a = {\n\tstate = running\n\tpid = 4242\n\tlast exit code = (never exited)\n}"
        #expect(JobInfo.parse(running) == JobInfo(running: true, pid: 4242, lastExit: nil))
        let crashed = "dev.warren.site.a = {\n\tstate = not running\n\tlast exit code = 3\n}"
        #expect(JobInfo.parse(crashed) == JobInfo(running: false, pid: nil, lastExit: 3))
    }

    @Test func plistsLiveInTheRunFolderNotInLaunchAgents() throws {
        let paths = try home()
        let launch = FakeLaunch()
        let job = ManagedJob(
            label: "dev.warren.site.a", stem: "site-a", program: "/bin/sh", arguments: [], environment: [:],
            directory: "/tmp", logFile: paths.siteLog("a")
        )
        try JobHost(paths: paths, launch: launch).start(job)
        #expect(launch.calls == ["bootstrap site-a.plist"])
        #expect(FileManager.default.fileExists(atPath: paths.runDirectory.appendingPathComponent("site-a.plist").path))
        try JobHost(paths: paths, launch: launch).stop(label: job.label, stem: "site-a")
        #expect(launch.calls.last == "bootout dev.warren.site.a")
        #expect(!FileManager.default.fileExists(atPath: paths.runDirectory.appendingPathComponent("site-a.plist").path))
    }

    // MARK: Ports

    private func site(_ id: String, port: Int? = nil, path: String = "/nonexistent",
                      command: String? = nil) -> ResolvedSite
    {
        ResolvedSite(
            id: id, path: path, name: id, domains: ["\(id).test"], runtimes: [:], command: command, port: port,
            services: [:], problems: [], warnings: []
        )
    }

    @Test func aFreePortIsChosenKeptAndNotSharedWithAnotherSite() throws {
        let paths = try home()
        let ports = SitePorts(paths: paths, isFree: { _ in true })
        let first = try ports.resolve(for: site("a"))
        #expect(first == 4100)
        #expect(try ports.resolve(for: site("a")) == 4100)
        #expect(try ports.resolve(for: site("b")) == 4101)
        #expect(ports.assigned(for: "a") == 4100)
        ports.forget("a")
        #expect(ports.assigned(for: "a") == nil)
    }

    @Test func aKeptPortThatAnotherProgramNowHoldsIsReplaced() throws {
        let paths = try home()
        _ = try SitePorts(paths: paths, isFree: { _ in true }).resolve(for: site("a"))
        let busy = SitePorts(paths: paths, isFree: { $0 != 4100 })
        #expect(try busy.resolve(for: site("a")) == 4101)
        #expect(busy.assigned(for: "a") == 4101)
    }

    @Test func anExplicitPortIsUsedAsIsAndNeverReplaced() throws {
        let paths = try home()
        #expect(try SitePorts(paths: paths, isFree: { _ in true }).resolve(for: site("a", port: 3000)) == 3000)
        #expect(throws: SitePortError.self) {
            try SitePorts(paths: paths, isFree: { _ in false }).resolve(for: site("a", port: 3000))
        }
        #expect(SitePorts(paths: paths).assigned(for: "a") == nil)
    }

    // MARK: Command

    @Test func thePortGoesWhereTheFrameworkWantsIt() {
        var detection = FrameworkDetection.unknown
        detection.command = "npm run dev"
        detection.portHandling = .environment("PORT")
        let viaEnvironment = StartCommand.make(detection, port: 4100)
        #expect(viaEnvironment?.line == "npm run dev")
        #expect(viaEnvironment?.environment["PORT"] == "4100")
        #expect(viaEnvironment?.environment["HOST"] == "127.0.0.1")

        detection.portHandling = .flag("--port")
        #expect(StartCommand.make(detection, port: 4100)?.line == "npm run dev -- --port 4100")
        detection.command = "vite"
        #expect(StartCommand.make(detection, port: 4100)?.line == "vite --port 4100")

        detection.command = "python manage.py runserver 127.0.0.1:{port}"
        detection.portHandling = .placeholder
        #expect(StartCommand.make(detection, port: 4100)?.line == "python manage.py runserver 127.0.0.1:4100")
    }

    @Test func whatTheUserApprovesDoesNotChangeWithThePort() {
        var detection = FrameworkDetection.unknown
        detection.command = "npm run dev"
        detection.portHandling = .flag("--port")
        #expect(StartCommand.make(detection, port: 4100)?.shown == StartCommand.make(detection, port: 4777)?.shown)
        #expect(StartCommand.make(detection, port: 4100)?.shown == ["npm", "run", "dev"])
        #expect(StartCommand.make(.unknown, port: 4100) == nil)
    }

    // MARK: Proxy routes

    @Test func aServerSiteIsRoutedToItsAssignedPortOnlyOnceItHasOne() throws {
        let paths = try home()
        let folder = try project([".warren.toml": "[run]\ncommand = \"node server.js\"\n"])
        let shop = site("shop", path: folder.path, command: "node server.js")
        #expect(SiteServing.target(for: shop, paths: paths) == .failure(.notStarted))
        _ = try SitePorts(paths: paths, isFree: { _ in true }).resolve(for: shop)
        #expect(SiteServing.target(for: shop, paths: paths) == .success(.server(port: 4100)))
    }

    @Test func phpAndStaticSitesAreRoutedWhileTheirJobOrMarkerExists() throws {
        let paths = try home()
        let php = try project(["public/index.php": "<?php echo 1;"])
        let files = try project(["index.html": "<h1>hi</h1>"])
        let blog = site("blog", path: php.path)
        let docs = site("docs", path: files.path)
        #expect(SiteServing.target(for: blog, paths: paths) == .failure(.notStarted))
        #expect(SiteServing.target(for: docs, paths: paths) == .failure(.notStarted))

        try FileManager.default.createDirectory(at: paths.runDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: paths.runDirectory.appendingPathComponent("php-blog.plist").path,
            contents: Data()
        )
        FileManager.default.createFile(atPath: paths.staticMarker("docs").path, contents: nil)
        #expect(SiteServing.target(for: blog, paths: paths) == .success(.php(
            socket: paths.phpSocket("blog").path, root: php.appendingPathComponent("public").standardizedFileURL.path
        )))
        #expect(SiteServing
            .target(for: docs, paths: paths) == .success(.staticFiles(root: files.standardizedFileURL.path)))
    }

    @Test func caddyGetsAFastCGIHandlerForPHPAndAFileServerForStaticSites() throws {
        let php = CaddyConfig.handlers(for: .php(socket: "/run/a.sock", root: "/srv/a/public"))
        let text = try String(
            bytes: JSONSerialization.data(withJSONObject: php, options: .sortedKeys),
            encoding: .utf8
        ) ?? ""
        #expect(text.contains("\"protocol\":\"fastcgi\""))
        #expect(text.contains("unix\\/\\/run\\/a.sock"))
        #expect(text.contains("\"split_path\":[\".php\"]"))
        #expect(text.contains("{http.matchers.file.relative}"))
        let files = CaddyConfig.handlers(for: .staticFiles(root: "/srv/b"))
        #expect(files.first?["handler"] as? String == "file_server")
        #expect(files.first?["root"] as? String == "/srv/b")
    }

    // MARK: Starting and stopping

    private func processes(_ paths: WarrenPaths, _ launch: FakeLaunch) -> SiteProcesses {
        SiteProcesses(
            paths: paths, launch: launch, ports: SitePorts(paths: paths, isFree: { _ in true }), routesChanged: {}
        )
    }

    private func command(_ port: Int) throws -> ResolvedSite {
        let folder = try project([".warren.toml": "[run]\ncommand = \"sleep 100\"\nport = \(port)\n"])
        return site("app", port: port, path: folder.path, command: "sleep 100")
    }

    @Test func startingAsksFirstThenLoadsAJobAndWaitsForThePort() async throws {
        let paths = try home()
        let launch = FakeLaunch()
        let (descriptor, port) = try listeningSocket()
        defer { close(descriptor) }
        let app = try command(port)
        let asked = Box<[PlanStep]>([])
        try await processes(paths, launch).start(app, timeout: 5) { steps in
            asked.value = steps
            return .all(steps)
        }
        #expect(asked.value.first?.command == ["sleep", "100"])
        #expect(asked.value.first?.runsProjectCode == true)
        #expect(launch.calls == ["bootstrap site-app.plist"])
        let plist = try #require(PropertyListSerialization.propertyList(
            from: Data(contentsOf: paths.runDirectory.appendingPathComponent("site-app.plist")), format: nil
        ) as? [String: Any])
        #expect((plist["ProgramArguments"] as? [String])?.suffix(2) == ["-c", "sleep 100"])
        #expect((plist["EnvironmentVariables"] as? [String: String])?["PORT"] == String(port))
    }

    @Test func aDeclinedCommandStartsNothing() async throws {
        let paths = try home()
        let launch = FakeLaunch()
        let app = try command(4321)
        await #expect(throws: StartError.declined) {
            try await processes(paths, launch).start(app, timeout: 1) { _ in .none }
        }
        #expect(launch.calls.isEmpty)
    }

    @Test func aTrustedCommandIsNotAskedAboutAgain() async throws {
        let paths = try home()
        let launch = FakeLaunch()
        let (descriptor, port) = try listeningSocket()
        defer { close(descriptor) }
        let folder = try project([".warren.toml": "[run]\ncommand = \"sleep 100\"\nport = \(port)\n"])
        let registered = try SiteRegistry(paths: paths).add(path: folder.path)
        let pending = Box(0)
        try await processes(paths, launch).start(registered, timeout: 5) { steps in
            pending.value += 1
            return PlanApproval(approved: Set(steps.map(\.id)), trust: true)
        }
        try processes(paths, launch).stop(registered)
        try await processes(paths, launch).start(registered, timeout: 5) { _ in
            pending.value += 1
            return .none
        }
        #expect(pending.value == 1)
        #expect(launch.calls.filter { $0.hasPrefix("bootstrap") }.count == 2)
    }

    @Test func aServerThatExitsRightAwayIsReportedWithItsExitCode() async throws {
        let paths = try home()
        let launch = FakeLaunch()
        launch.setInfo("dev.warren.site.app", JobInfo(running: false, pid: nil, lastExit: 3))
        let app = try command(4322)
        await #expect(throws: StartError.exited(code: 3, lastLines: [])) {
            try await processes(paths, launch).start(app, timeout: 5) { .all($0) }
        }
        #expect(processes(paths, launch).state(of: app) == .crashed(exitCode: 3))
    }

    @Test func stoppingBootsTheJobOutAndRemovesItsFiles() async throws {
        let paths = try home()
        let launch = FakeLaunch()
        let (descriptor, port) = try listeningSocket()
        defer { close(descriptor) }
        let app = try command(port)
        let manager = processes(paths, launch)
        try await manager.start(app, timeout: 5) { .all($0) }
        #expect(manager.state(of: app) == .running(managed: true))
        try manager.stop(app)
        #expect(launch.calls.contains("bootout dev.warren.site.app"))
        // The test's own socket still holds the port, so what is left there is not Warren's.
        #expect(manager.state(of: app) == .running(managed: false))
        #expect(!manager.host.hasPlist(stem: "site-app"))
        // A second stop is harmless.
        try manager.stop(app)
    }

    @Test func aStaticSiteStartsByAddingARouteAndStopsByRemovingIt() async throws {
        let paths = try home()
        let files = try project(["index.html": "<h1>hi</h1>"])
        let docs = site("docs", path: files.path)
        let launch = FakeLaunch()
        let manager = processes(paths, launch)
        #expect(manager.state(of: docs) == .stopped)
        try await manager.start(docs) { _ in .none }
        #expect(manager.state(of: docs) == .running(managed: true))
        #expect(launch.calls.isEmpty)
        try manager.stop(docs)
        #expect(manager.state(of: docs) == .stopped)
    }

    @Test func aServerNotStartedByWarrenIsShownAsRunningButUnmanaged() throws {
        let paths = try home()
        let (descriptor, port) = try listeningSocket()
        defer { close(descriptor) }
        let app = site("app", port: port)
        #expect(processes(paths, FakeLaunch()).state(of: app) == .running(managed: false))
    }

    // MARK: Log

    @Test func familiarFailuresGetAPlainSentence() {
        #expect(SiteProcesses.cause(forLog: ["Error: listen EADDRINUSE: address already in use :::3000"], exitCode: 1)
            == "Another program is using the port.")
        #expect(SiteProcesses.cause(forLog: ["sh: next: command not found"], exitCode: 127)?
            .contains("Run setup") == true)
        #expect(SiteProcesses.cause(forLog: ["Error: Cannot find module 'express'"], exitCode: 1)?
            .contains("dependency") == true)
        #expect(SiteProcesses.cause(forLog: ["boom"], exitCode: 1) == nil)
    }

    @Test func theLastLinesOfTheLogAreRead() throws {
        let paths = try home()
        try FileManager.default.createDirectory(at: paths.logsDirectory, withIntermediateDirectories: true)
        try Data((1 ... 30).map { "line \($0)" }.joined(separator: "\n").utf8).write(to: paths.siteLog("a"))
        let lines = SiteProcesses(paths: paths, launch: FakeLaunch(), routesChanged: {}).lastLines("a", count: 3)
        #expect(lines == ["line 28", "line 29", "line 30"])
    }

    // MARK: Environment

    @Test func theStoreSettingIsOnlyForPnpmProjects() throws {
        let paths = try home()
        let manager = RuntimeManager(paths: paths)
        let folder = try project(["package.json": "{\"name\":\"a\",\"scripts\":{\"dev\":\"node a.js\"}}"])
        let npmSite = site("a", path: folder.path)
        let plan = SetupPlanner(paths: paths).plan(for: npmSite, registered: true, inventory: [])
        #expect(manager.siteEnvironment(plan: plan, base: [:])["npm_config_store_dir"] == nil)
        #expect(manager.siteEnvironment(plan: plan, base: [:])["PATH"]?
            .hasPrefix(folder.path + "/node_modules/.bin") == true)
        let pnpmFolder = try project([
            "package.json": "{\"name\":\"a\",\"packageManager\":\"pnpm@9.0.0\",\"scripts\":{\"dev\":\"node a.js\"}}",
        ])
        let pnpmPlan = SetupPlanner(paths: paths).plan(
            for: site("p", path: pnpmFolder.path),
            registered: true,
            inventory: []
        )
        #expect(manager.siteEnvironment(plan: pnpmPlan, base: [:])["npm_config_store_dir"] != nil)
    }
}

/// A value two closures can share in a test.
final class Box<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) {
        stored = value
    }

    var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
