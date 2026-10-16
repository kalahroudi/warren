// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import WarrenCore

/// Runs each template's real scaffolder with Warren's own runtimes (hundreds of MB in total) and checks that
/// detection names the result. Off by default.
/// Run with `WARREN_INTEGRATION=1 swift test --filter TemplateIntegrationTests`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["WARREN_INTEGRATION"] == "1"), .serialized)
struct TemplateIntegrationTests {
    private static let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("wti-\(UUID().uuidString.prefix(8))")
    private static let paths = WarrenPaths(root: root.appendingPathComponent("warren"))
    private static let home = root.appendingPathComponent("home")

    private final class Lines: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [String] = []
        var tail: [String] {
            lock.withLock { Array(stored.suffix(15)) }
        }

        func add(_ line: String) {
            lock.withLock { stored.append(line) }
        }
    }

    private func scaffold(_ id: String, expecting framework: String) async throws {
        let template = try #require(ProjectTemplate.named(id))
        try FileManager.default.createDirectory(at: Self.home, withIntermediateDirectories: true)
        let creator = ProjectCreator(paths: Self.paths)
        let site = try creator.create(NewProjectRequest(
            name: "t-\(id)", location: Self.root.appendingPathComponent("Sites"), source: .template(template)
        ))
        var base = ProcessInfo.processInfo.environment
        base["HOME"] = Self.home.path
        let runner = PlanRunner(paths: Self.paths, site: site, baseEnvironment: base)
        let inventory = (try? runner.inventoryForTesting()) ?? []
        let plan = TemplatePlanner.plan(template, site: site, inventory: inventory)
        let lines = Lines()
        let summary = await runner.run(plan: plan, approve: { .all($0) }, onEvent: { event in
            if case let .output(_, line) = event {
                lines.add(line)
            }
        })
        #expect(summary.succeeded, "\(id): \(summary.results) \(lines.tail.joined(separator: "\n"))")
        let found = FrameworkDetector.detect(in: URL(fileURLWithPath: site.path))
        #expect(found.id == framework, "\(id) detected as \(found.id ?? "nothing")")
        #expect(!FileManager.default
            .fileExists(atPath: URL(fileURLWithPath: site.path).appendingPathComponent("node_modules").path))
    }

    @Test func next() async throws {
        try await scaffold("next", expecting: "next")
    }

    @Test func viteReact() async throws {
        try await scaffold("vite-react", expecting: "vite")
    }

    @Test func astro() async throws {
        try await scaffold("astro", expecting: "astro")
    }

    @Test func sveltekit() async throws {
        try await scaffold("sveltekit", expecting: "sveltekit")
    }

    @Test func laravel() async throws {
        try await scaffold("laravel", expecting: "laravel")
    }

    @Test func django() async throws {
        try await scaffold("django", expecting: "django")
    }
}

extension PlanRunner {
    func inventoryForTesting() throws -> [InstalledRuntime] {
        try RuntimeManager(paths: paths).inventory()
    }
}

/// Starts each blank project's server with Warren's own runtime and asks it for `/`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["WARREN_INTEGRATION"] == "1"), .serialized)
struct BlankProjectIntegrationTests {
    private static let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("wbi-\(UUID().uuidString.prefix(8))")
    private static let paths = WarrenPaths(root: root.appendingPathComponent("warren"))

    private static func freePort() -> Int {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        _ = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(
                descriptor,
                $0,
                socklen_t(MemoryLayout<sockaddr_in>.size)
            ) }
        }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
        }
        return Int(UInt16(bigEndian: address.sin_port))
    }

    private func serve(_ kind: BlankKind, command: [String], expecting text: String) async throws {
        let creator = ProjectCreator(paths: Self.paths)
        let site = try creator.create(NewProjectRequest(
            name: "b-\(kind.rawValue)", location: Self.root.appendingPathComponent("Sites"), source: .blank(kind)
        ))
        let manager = RuntimeManager(paths: Self.paths)
        let requirement = try #require(RuntimeResolver.requirements(for: site).first)
        try await manager.install(requirement)
        let plan = try manager.plan(for: site, installed: manager.inventory())
        let port = Self.freePort()
        var environment = manager.environment(for: plan)
        environment["PORT"] = String(port)
        let server = Task {
            try await ProcessGroupExecutor().run(
                command.map { $0.replacingOccurrences(of: "{port}", with: String(port)) },
                directory: URL(fileURLWithPath: site.path), environment: environment, onLine: { _ in }
            )
        }
        defer { server.cancel() }
        var body = ""
        for _ in 0 ..< 60 where !body.contains(text) {
            try await Task.sleep(for: .milliseconds(250))
            if let (data, _) = try? await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/")!) {
                body = String(bytes: data, encoding: .utf8) ?? ""
            }
        }
        #expect(body.contains(text), "\(kind): got '\(body)'")
    }

    @Test func nodeAnswers() async throws {
        try await serve(.node, command: ["node", "server.js"], expecting: "Hello from Node")
    }

    @Test func bunAnswers() async throws {
        try await serve(.bun, command: ["bun", "server.ts"], expecting: "Hello from Bun")
    }

    @Test func pythonAnswers() async throws {
        try await serve(.python, command: ["python", "app.py"], expecting: "Hello from Python")
    }

    @Test func phpAnswers() async throws {
        try await serve(.php, command: ["php", "-S", "127.0.0.1:{port}", "-t", "public"], expecting: "Hello from PHP")
    }
}
