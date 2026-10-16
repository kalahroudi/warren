// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import WarrenCore

struct SetupPlanTests {
    private let root: URL
    private let paths: WarrenPaths

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("wsp-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        paths = WarrenPaths(root: root.appendingPathComponent("home"))
    }

    private func project(_ files: [String: String]) throws -> URL {
        let directory = root.appendingPathComponent("shop-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, text) in files {
            let file = directory.appendingPathComponent(name)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try text.write(to: file, atomically: true, encoding: .utf8)
        }
        return directory
    }

    private func plan(
        _ files: [String: String], installed: [InstalledRuntime] = [], register: Bool = false
    ) throws -> SetupPlan {
        let directory = try project(files)
        let registry = SiteRegistry(paths: paths)
        let site = register ? try registry.add(path: directory.path) : try registry.preview(path: directory.path)
        return SetupPlanner(paths: paths).plan(for: site, registered: register, inventory: installed)
    }

    @Test func aNodeProjectWithNoPackagesHasNothingToInstall() throws {
        let bare = try plan(["package.json": #"{"name":"a","scripts":{"dev":"node server.js"}}"#])
        #expect(step(bare, "dependencies")?.state == .done)
        let needy = try plan(["package.json": #"{"name":"a","dependencies":{"express":"^4"}}"#])
        #expect(step(needy, "dependencies")?.state == .todo)
    }

    private func step(_ plan: SetupPlan, _ id: String) -> PlanStep? {
        plan.steps.first { $0.id == id }
    }

    private func runtime(_ kind: RuntimeKind, _ version: String) -> InstalledRuntime {
        InstalledRuntime(kind: kind, version: version, path: root, bytes: 0)
    }

    private let nextPackage = #"{"dependencies":{"next":"15"},"scripts":{"dev":"next dev"}}"#

    // MARK: Dependencies

    @Test func eachPackageManagerGetsItsInstallCommand() throws {
        struct Case {
            let files: [String: String]
            let command: [String]
        }
        let cases = [
            Case(files: ["package.json": nextPackage, "package-lock.json": "{}"], command: ["npm", "ci"]),
            Case(files: ["package.json": nextPackage], command: ["npm", "install"]),
            Case(
                files: ["package.json": nextPackage, "pnpm-lock.yaml": ""],
                command: ["pnpm", "install", "--frozen-lockfile"]
            ),
            Case(files: ["package.json": nextPackage, "yarn.lock": ""], command: ["yarn", "install"]),
            Case(files: ["package.json": nextPackage, "bun.lock": ""], command: ["bun", "install"]),
            Case(files: ["composer.json": "{}", "index.php": "<?php"], command: ["composer", "install"]),
            Case(
                files: ["pyproject.toml": "[project]\nname=\"x\"\ndependencies=[\"flask\"]\n", "uv.lock": ""],
                command: ["uv", "sync"]
            ),
        ]
        for item in cases {
            let found = try #require(step(plan(item.files), "dependencies"), "no step for \(item.command)")
            #expect(found.command == item.command)
            #expect(found.runsProjectCode && found.state == .todo)
        }
        let pip = try #require(step(plan(["requirements.txt": "flask\n"]), "dependencies"))
        #expect(pip.commandLine?.hasSuffix("uv pip install -r requirements.txt") == true)
    }

    @Test func dependenciesAreDoneOnceTheFolderExists() throws {
        let done = try plan(["package.json": nextPackage, "node_modules/.keep": ""])
        #expect(step(done, "dependencies")?.state == .done)
        let composer = try plan(["composer.json": "{}", "vendor/autoload.php": "<?php", "index.php": "<?php"])
        #expect(step(composer, "dependencies")?.state == .done)
        let none = try plan(["index.html": "<h1>x</h1>"])
        #expect(step(none, "dependencies") == nil)
    }

    @Test func aFolderOlderThanTheLockfileNeedsInstallingAgain() throws {
        let directory = try project(["package.json": nextPackage, "package-lock.json": "{}", "node_modules/.keep": ""])
        let old = Date(timeIntervalSinceNow: -3600)
        try FileManager.default.setAttributes(
            [.modificationDate: old],
            ofItemAtPath: directory.appendingPathComponent("node_modules").path
        )
        let site = try SiteRegistry(paths: paths).preview(path: directory.path)
        let result = SetupPlanner(paths: paths).plan(for: site, registered: false, inventory: [])
        #expect(step(result, "dependencies")?.state == .todo)
    }

    // MARK: Runtimes

    @Test func aRuntimeIsSuggestedWhenTheProjectNamesNoVersion() throws {
        let result = try plan(["package.json": nextPackage])
        let node = try #require(result.runtimes.first)
        #expect(node.proposed && node.label == "Node lts" && node.installedVersion == nil)
        #expect(step(result, "runtime-node")?.state == .todo)
        #expect(step(result, "dependencies")?.waitsFor == ["runtime-node"])
        #expect(step(result, "runtime-node")?.runsProjectCode == false)
    }

    @Test func anInstalledRuntimeMakesItsStepDone() throws {
        let result = try plan(["package.json": nextPackage, ".nvmrc": "22\n"], installed: [runtime(.node, "22.4.0")])
        #expect(result.runtimes.first?.proposed == false)
        #expect(step(result, "runtime-node")?.state == .done)
        #expect(step(result, "dependencies")?.waitsFor.isEmpty == true)
    }

    @Test func phpAndPythonProjectsImplyTheirRuntimes() throws {
        #expect(try plan(["composer.json": "{}", "index.php": "x"]).runtimes.map(\.label) == ["PHP latest"])
        #expect(try plan(["requirements.txt": "flask\n"]).runtimes.map(\.label) == ["Python latest"])
        #expect(try plan(["index.html": "x"]).runtimes.isEmpty)
    }

    // MARK: Env file and services

    @Test func theEnvStepIsTodoUntilEnvExistsAndListsWhatIsEmpty() throws {
        let example = "APP_NAME=Shop\nSTRIPE_KEY=\nSTRIPE_SECRET=\"\"\nDB_PASSWORD=\n"
        let todo = try plan(["package.json": nextPackage, ".env.example": example])
        #expect(step(todo, "env")?.state == .todo)
        #expect(todo.env.emptyVariables == ["STRIPE_KEY", "STRIPE_SECRET", "DB_PASSWORD"])
        #expect(step(todo, "env")?.detail.contains("STRIPE_KEY") == true)
        let done = try plan(["package.json": nextPackage, ".env.example": example, ".env": "A=1"])
        #expect(step(done, "env")?.state == .done)
        #expect(try step(plan(["package.json": nextPackage]), "env") == nil)
    }

    @Test func envFilesAreReadWithQuotesCommentsAndExport() {
        let env = EnvFile("# c\nexport A=1\nB=\"two words\" # note\nC='x'\nD=\nbad line\nE=a#b\n")
        #expect(env["A"] == "1" && env["B"] == "two words" && env["C"] == "x" && env["E"] == "a#b")
        #expect(env.emptyKeys == ["D"])
        #expect(env["bad line"] == nil)
    }

    @Test func eachServiceHintProducesItsStepWithEvidence() throws {
        struct Case {
            let env: String
            let id: String
        }
        let cases = [
            Case(env: "DB_CONNECTION=pgsql\n", id: "postgres"),
            Case(env: "DATABASE_URL=postgresql://u:p@localhost/db\n", id: "postgres"),
            Case(env: "DB_CONNECTION=mysql\n", id: "mysql"),
            Case(env: "DATABASE_URL=mysql://u@h/db\n", id: "mysql"),
            Case(env: "REDIS_HOST=127.0.0.1\n", id: "redis"),
            Case(env: "CACHE_STORE=redis\n", id: "redis"),
            Case(env: "MAIL_MAILER=smtp\nMAIL_HOST=mailpit\n", id: "mailpit"),
            Case(env: "MINIO_ROOT_USER=x\n", id: "minio"),
            Case(env: "AWS_ENDPOINT=http://localhost:9000\n", id: "minio"),
        ]
        for item in cases {
            let result = try plan(["package.json": nextPackage, ".env.example": item.env])
            #expect(result.services.map(\.id) == [item.id], "\(item.env)")
            let service = try #require(step(result, "service-\(item.id)"))
            #expect(service.detail.contains(".env.example"))
            #expect(service.state == .waiting("arrives with the service manager"))
        }
        let none = try plan([
            "package.json": nextPackage,
            ".env.example": "APP_NAME=x\nDB_CONNECTION=sqlite\nMAIL_HOST=smtp.example.com\n"
        ])
        #expect(none.services.isEmpty)
    }

    // MARK: Application setup

    private let laravel = [
        "composer.json": #"{"require":{"php":"^8.2","laravel/framework":"^11"}}"#, "artisan": "",
        ".env.example": "APP_KEY=\nDB_CONNECTION=pgsql\n",
    ]

    @Test func laravelGetsKeyAndMigrationsInOrder() throws {
        let result = try plan(laravel)
        let ids = result.steps.map(\.id)
        let order = ["dependencies", "env", "service-postgres", "app-key", "migrate", "site"]
        #expect(order.allSatisfy(ids.contains))
        #expect(order.compactMap(ids.firstIndex(of:)) == order.compactMap(ids.firstIndex(of:)).sorted())
        #expect(step(result, "app-key")?.command == ["php", "artisan", "key:generate"])
        #expect(step(result, "migrate")?.command == ["php", "artisan", "migrate", "--no-interaction"])
        #expect(step(result, "migrate")?.state == .waiting("after PostgreSQL"))
        #expect(step(result, "migrate")?.waitsFor.contains("service-postgres") == true)
    }

    @Test func anExistingAppKeyMakesThatStepDone() throws {
        var files = laravel
        files[".env"] = "APP_KEY=base64:abc\n"
        #expect(try step(plan(files), "app-key")?.state == .done)
    }

    @Test func laravelWithSQLiteCreatesTheDatabaseFileItself() throws {
        var files = laravel
        files[".env.example"] = "APP_KEY=\nDB_CONNECTION=sqlite\n"
        let result = try plan(files)
        let sqlite = try #require(step(result, "sqlite"))
        #expect(sqlite.runsProjectCode == false && sqlite.command == nil && sqlite.state == .todo)
        #expect(step(result, "migrate")?.state == .todo)
        #expect(result.services.isEmpty)
    }

    @Test func djangoGetsMigrations() throws {
        let result = try plan(["manage.py": "", "requirements.txt": "Django\n"])
        #expect(step(result, "migrate")?.command == ["python", "manage.py", "migrate", "--no-input"])
    }

    // MARK: Which steps run project code

    @Test func onlyStepsThatRunTheProjectsCodeAreMarked() throws {
        var files = laravel
        files["package.json"] = nextPackage
        let result = try plan(files)
        for found in result.steps {
            let expected = ["dependencies", "app-key", "migrate"].contains(found.id)
            #expect(found.runsProjectCode == expected, "\(found.id)")
        }
    }

    // MARK: Optional steps

    @Test func stepsTheProjectSuggestsAreOffByDefault() throws {
        let devcontainer = """
        // comment
        {
          /* block */
          "name": "x",
          "postCreateCommand": "npm run seed"
        }
        """
        let result = try plan([
            "package.json": #"{"dependencies":{"next":"15"},"scripts":{"dev":"next dev","setup":"node setup.js"}}"#,
            ".devcontainer/devcontainer.json": devcontainer.replacingOccurrences(of: "/* block */", with: ""),
        ])
        let container = try #require(step(result, "optional-devcontainer"))
        #expect(container.command == ["/bin/sh", "-c", "npm run seed"])
        #expect(container.enabledByDefault == false && container.runsProjectCode)
        let script = try #require(step(result, "optional-script-setup"))
        #expect(script.command == ["npm", "run", "setup"] && script.enabledByDefault == false)
        let remainingFlags = result.remaining.map(\.enabledByDefault)
        #expect(!remainingFlags.contains(false))
    }

    // MARK: Site step

    @Test func theSiteStepIsDoneOnceRegistered() throws {
        #expect(try step(plan(["index.html": "x"]), "site")?.state == .todo)
        #expect(try step(plan(["index.html": "x"], register: true), "site")?.state == .done)
    }

    @Test func aPlanIsCompleteWhenNothingRemains() throws {
        let result = try plan(["index.html": "x"], register: true)
        #expect(result.isComplete)
        #expect(try plan(["package.json": nextPackage]).isComplete == false)
    }

    // MARK: Safety

    @Test func buildingAPlanRunsNothingFromTheProject() throws {
        let marker = root.appendingPathComponent("pwned")
        _ = try plan([
            "package.json": """
            {"dependencies":{"next":"15"},"scripts":{"dev":"touch \(marker.path)-dev",
            "setup":"touch \(marker.path)-setup","postinstall":"touch \(marker.path)-post"}}
            """,
            "mise.toml": "[env]\nA = \"{{ exec(command='touch \(marker.path)-mise') }}\"\n",
            ".devcontainer/devcontainer.json": #"{"postCreateCommand":"touch \#(marker.path)-dev-container"}"#,
            ".env.example": "DB_CONNECTION=pgsql\nAPP_KEY=\n",
            "artisan": "touch \(marker.path)-artisan",
        ])
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix("pwned") }
        #expect(leftovers.isEmpty)
    }

    // MARK: Registry: name, domain, preview

    @Test func aChosenNameAndDomainAreStoredWithTheSiteNotInTheProject() throws {
        let directory = try project(["index.html": "x"])
        let registry = SiteRegistry(paths: paths)
        let site = try registry.add(path: directory.path, name: "My Shop", domains: ["Store.Test"])
        #expect(site.name == "My Shop" && site.domains == ["store.test"])
        #expect(try registry.show(id: site.id).domains == ["store.test"])
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(".warren.toml").path))
    }

    @Test func warrenTomlWinsOverTheChosenDomain() throws {
        let directory = try project(["index.html": "x", ".warren.toml": "domains = [\"fromfile.test\"]\n"])
        let site = try SiteRegistry(paths: paths).add(path: directory.path, domains: ["chosen.test"])
        #expect(site.domains == ["fromfile.test"])
    }

    @Test func aClashingOrInvalidDomainIsRefusedAndPreviewDoesNotRegister() throws {
        let registry = SiteRegistry(paths: paths)
        try registry.add(path: project(["index.html": "x"]).path, domains: ["taken.test"])
        let other = try project(["index.html": "x"])
        #expect(throws: RegistryError.self) { try registry.preview(path: other.path, domains: ["taken.test"]) }
        #expect(throws: ConfigError.self) { try registry.preview(path: other.path, domains: ["not a domain"]) }
        _ = try registry.preview(path: other.path, domains: ["free.test"])
        #expect(try registry.list().count == 1)
    }

    @Test func theSuggestedIDFollowsTheFolderNameAndSkipsTakenOnes() throws {
        let registry = SiteRegistry(paths: paths)
        #expect(try registry.suggestedID(forFolder: "My Shop") == "my-shop")
        let directory = root.appendingPathComponent("My Shop")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try registry.add(path: directory.path)
        #expect(try registry.suggestedID(forFolder: "My Shop") == "my-shop-2")
    }
}
