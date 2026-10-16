// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import WarrenCore

private final class RecordingExecutor: CommandExecuting, @unchecked Sendable {
    private let lock = NSLock()
    private var runs: [(command: [String], directory: String)] = []

    var recorded: [(command: [String], directory: String)] {
        lock.withLock { runs }
    }

    func run(
        _ command: [String], directory: URL, environment _: [String: String],
        onLine _: @escaping @Sendable (String) -> Void
    ) async throws -> Int32 {
        lock.withLock { runs.append((command, directory.path)) }
        return 0
    }
}

struct NewProjectTests {
    private let root: URL
    private let paths: WarrenPaths
    private let creator: ProjectCreator
    private let sites: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("wnp-\(UUID().uuidString.prefix(8))")
        paths = WarrenPaths(root: root.appendingPathComponent("home"))
        creator = ProjectCreator(paths: paths)
        sites = root.appendingPathComponent("Sites")
    }

    private func request(
        _ name: String = "shop", source: NewProjectSource = .blank(.node), domain: String? = nil, location: URL? = nil
    ) -> NewProjectRequest {
        NewProjectRequest(name: name, location: location ?? sites, domain: domain, source: source)
    }

    // MARK: Rules

    @Test func folderNamesAreCheckedAndEachFailureHasItsOwnMessage() {
        for bad in ["", "   "] {
            #expect(throws: NewProjectError.noName) { try creator.validate(request(bad)) }
        }
        for bad in [".hidden", "a/b", "has space", "ünï", String(repeating: "a", count: 65)] {
            #expect(throws: NewProjectError.invalidName(bad)) { try creator.validate(request(bad)) }
        }
        #expect(throws: Never.self) { try creator.validate(request("my-shop_2.0")) }
        #expect(NewProjectError.invalidName("x").errorDescription?.contains("folder name") == true)
    }

    @Test func aFolderThatExistsMustBeEmpty() throws {
        let folder = sites.appendingPathComponent("shop")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try creator.validate(request())
        FileManager.default.createFile(atPath: folder.appendingPathComponent(".DS_Store").path, contents: nil)
        try creator.validate(request())
        FileManager.default.createFile(atPath: folder.appendingPathComponent("file").path, contents: nil)
        #expect(throws: NewProjectError.folderNotEmpty(folder.path)) { try creator.validate(request()) }
    }

    @Test func theLocationMustBeAFolderYouCanWriteTo() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("plain-file")
        FileManager.default.createFile(atPath: file.path, contents: nil)
        #expect(throws: NewProjectError.locationNotAFolder(file.path)) { try creator.validate(request(location: file)) }
        let locked = root.appendingPathComponent("locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: locked.path) }
        #expect(throws: NewProjectError.locationNotWritable(locked.path)) {
            try creator.validate(request(location: locked))
        }
    }

    @Test func aTakenOrInvalidDomainIsRefusedBeforeAnythingIsCreated() throws {
        try creator.create(request("one", domain: "shop.test"))
        #expect(throws: RegistryError.self) { try creator.validate(request("two", domain: "shop.test")) }
        #expect(throws: ConfigError.self) { try creator.validate(request("two", domain: "not a domain")) }
        #expect(throws: RegistryError.self) { try creator.validate(request("two", domain: CaddyConfig.selfCheckDomain))
        }
        #expect(!FileManager.default.fileExists(atPath: sites.appendingPathComponent("two").path))
    }

    @Test func theDefaultDomainFollowsTheName() {
        #expect(ProjectCreator.defaultDomain(forName: "My Shop") == "my-shop.test")
        #expect(ProjectCreator.defaultDomain(forName: "api_v2") == "api-v2.test")
    }

    // MARK: Blank projects

    @Test func eachBlankKindWritesExactlyItsFiles() throws {
        let expected: [BlankKind: Set<String>] = [
            .staticSite: ["index.html"], .node: ["server.js", "package.json", ".warren.toml"],
            .bun: ["server.ts", "package.json", ".warren.toml"], .php: ["public/index.php", ".warren.toml"],
            .python: ["app.py", ".warren.toml"],
        ]
        for kind in BlankKind.allCases {
            let site = try creator.create(request("p-\(kind.rawValue)", source: .blank(kind)))
            let folder = URL(fileURLWithPath: site.path)
            let relative = (FileManager.default.enumerator(atPath: folder.path)?.allObjects as? [String]) ?? []
            let found = relative.filter { path in
                var isDirectory: ObjCBool = false
                FileManager.default.fileExists(
                    atPath: folder.appendingPathComponent(path).path,
                    isDirectory: &isDirectory
                )
                return !isDirectory.boolValue
            }
            #expect(Set(found) == expected[kind], "\(kind)")
        }
    }

    @Test func aBlankProjectIsRegisteredAndDetectedAndPinsItsRuntime() throws {
        let expected: [BlankKind: (framework: String, runtime: String?)] = [
            .staticSite: ("static", nil), .node: ("node", "Node lts"), .bun: ("node", "Bun latest"),
            .php: ("php", "PHP latest"), .python: ("python", "Python latest"),
        ]
        for kind in BlankKind.allCases {
            let site = try creator.create(request(
                "q-\(kind.rawValue)",
                source: .blank(kind),
                domain: "q-\(kind.rawValue).test"
            ))
            #expect(site.domains == ["q-\(kind.rawValue).test"] && site.name == "q-\(kind.rawValue)")
            #expect(FrameworkDetector.detect(site: site).id == expected[kind]?.framework, "\(kind)")
            #expect(RuntimeResolver.requirements(for: site).first?.label == expected[kind]?.runtime, "\(kind)")
        }
    }

    @Test func bunProjectsRunTheirScriptWithBun() throws {
        let site = try creator.create(request("bunny", source: .blank(.bun)))
        #expect(FrameworkDetector.detect(site: site).command == "bun run dev")
    }

    @Test func creatingNeverOverwritesAndAFailureUndoesOnlyItsOwnWork() throws {
        let site = try creator.create(request("keep"))
        let marker = URL(fileURLWithPath: site.path).appendingPathComponent("mine.txt")
        try "mine".write(to: marker, atomically: true, encoding: .utf8)
        #expect(throws: NewProjectError.self) { try creator.create(request("keep")) }
        #expect(try String(contentsOf: marker, encoding: .utf8) == "mine")
        // A registration that fails after the files were written removes them again.
        let clash = request("other", domain: "keep.test")
        #expect(throws: RegistryError.self) { try creator.create(clash) }
        #expect(!FileManager.default.fileExists(atPath: sites.appendingPathComponent("other").path))
    }

    // MARK: Templates

    @Test func everyTemplateHasANonInteractiveCommandThatTargetsTheCurrentFolder() {
        #expect(ProjectTemplate.all.map(\.id) == ["next", "vite-react", "astro", "sveltekit", "laravel", "django"])
        for template in ProjectTemplate.all {
            #expect(template.command.contains("."), "\(template.id) must target the empty folder")
            #expect(template.command.contains { $0.hasPrefix("--") || $0 == "--" || $0 == "." }, "\(template.id)")
            #expect(!template.source.isEmpty && !template.summary.isEmpty)
        }
        #expect(ProjectTemplate.named("laravel")?.command.contains("--no-scripts") == true)
        #expect(ProjectTemplate.named("sveltekit")?.command.contains("--no-add-ons") == true)
        #expect(ProjectTemplate.named("nope") == nil)
    }

    @Test func aTemplateProjectStartsWithItsSeedFiles() throws {
        let site = try creator.create(request("dj", source: .template(#require(ProjectTemplate.named("django")))))
        let folder = URL(fileURLWithPath: site.path)
        #expect(try String(contentsOf: folder.appendingPathComponent("requirements.txt"), encoding: .utf8) ==
            "django\n")
        let next = try creator.create(request("nx", source: .template(#require(ProjectTemplate.named("next")))))
        #expect(try FileManager.default.contentsOfDirectory(atPath: next.path).isEmpty)
    }

    @Test func theScaffoldPlanNeedsApprovalIsThirdPartyAndRunsInTheNewFolder() async throws {
        let template = try #require(ProjectTemplate.named("next"))
        let site = try creator.create(request("nx", source: .template(template)))
        let installed = [InstalledRuntime(kind: .node, version: "24.1.0", path: root, bytes: 0)]
        let plan = TemplatePlanner.plan(template, site: site, inventory: installed)
        #expect(plan.steps.map(\.id) == ["scaffold"])
        let step = try #require(plan.steps.first)
        #expect(step.runsProjectCode && step.payload["thirdParty"] == "create-next-app from npm")
        #expect(step.command == template.command && step.kind == .scaffold)

        let executor = RecordingExecutor()
        let runner = PlanRunner(paths: paths, site: site, executor: executor, baseEnvironment: ["PATH": "/usr/bin"])
        let declined = await runner.run(plan: plan, approve: { _ in .none }, onEvent: { _ in })
        #expect(executor.recorded.isEmpty && !declined.succeeded)
        let approved = await runner.run(plan: plan, approve: { .all($0) }, onEvent: { _ in })
        #expect(approved.succeeded)
        #expect(executor.recorded.map(\.command) == [template.command])
        #expect(executor.recorded.first?.directory == URL(fileURLWithPath: site.path).path)
    }

    @Test func aMissingRuntimeComesFirstAndTheScaffolderWaitsForIt() throws {
        let template = try #require(ProjectTemplate.named("laravel"))
        let site = try creator.create(request("lv", source: .template(template)))
        let plan = TemplatePlanner.plan(template, site: site, inventory: [])
        #expect(plan.steps.map(\.id) == ["runtime-php", "scaffold"])
        #expect(plan.steps[1].waitsFor == ["runtime-php"])
        #expect(plan.steps[0].runsProjectCode == false)
        #expect(plan.runtimes.first?.requirement.kind == .php)
    }
}
