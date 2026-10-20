// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import WarrenCore

struct FrameworkTests {
    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("wf-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// A project folder with the given files; a path with slashes makes its folders.
    private func project(_ files: [String: String]) throws -> URL {
        let directory = root.appendingPathComponent("p-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, text) in files {
            let file = directory.appendingPathComponent(name)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try text.write(to: file, atomically: true, encoding: .utf8)
        }
        return directory
    }

    private func detect(_ files: [String: String], command: String? = nil, domains: [String] = []) throws
        -> FrameworkDetection
    {
        try FrameworkDetector.detect(in: project(files), command: command, domains: domains)
    }

    private func package(
        dependencies: [String] = [], dev: [String] = [], scripts: [String: String] = [:], manager: String? = nil
    ) -> String {
        func object(_ names: [String]) -> String {
            "{" + names.map { "\"\($0)\":\"1\"" }.joined(separator: ",") + "}"
        }
        let scriptText = "{" + scripts.map { "\"\($0.key)\":\"\($0.value)\"" }.joined(separator: ",") + "}"
        let field = manager.map { ",\"packageManager\":\"\($0)\"" } ?? ""
        return "{\"name\":\"x\",\"dependencies\":\(object(dependencies)),\"devDependencies\":\(object(dev)),"
            + "\"scripts\":\(scriptText)\(field)}"
    }

    // MARK: One fixture per framework

    @Test func nextRunsItsDevScriptAndGetsThePortInTheEnvironment() throws {
        let found = try detect(["package.json": package(dependencies: ["next", "react"], scripts: ["dev": "next dev"])])
        #expect(found.id == "next" && found.kind == .server)
        #expect(found.command == "npm run dev" && found.commandSource == .script)
        #expect(found.portHandling == .environment("PORT"))
    }

    @Test func nextWithoutADevScriptUsesTheFrameworkCommand() throws {
        let found = try detect(["package.json": package(dependencies: ["next"]), "pnpm-lock.yaml": ""])
        #expect(found.command == "pnpm exec next dev" && found.commandSource == .framework)
    }

    @Test func nodeFrameworksAreRecognised() throws {
        struct Case {
            let id: String
            let dependencies: [String]
            let scripts: [String: String]
        }
        let cases = [
            Case(id: "nuxt", dependencies: ["nuxt"], scripts: ["dev": "nuxt dev"]),
            Case(id: "astro", dependencies: ["astro"], scripts: ["dev": "astro dev"]),
            Case(id: "sveltekit", dependencies: ["@sveltejs/kit", "vite"], scripts: ["dev": "vite dev"]),
            Case(id: "remix", dependencies: ["@remix-run/dev"], scripts: ["dev": "remix vite:dev"]),
            Case(id: "vite", dependencies: ["vite"], scripts: ["dev": "vite"]),
            Case(id: "react-scripts", dependencies: ["react-scripts"], scripts: ["start": "react-scripts start"]),
            Case(id: "node", dependencies: ["express"], scripts: ["start": "node server.js"]),
        ]
        for item in cases {
            let found = try detect(["package.json": package(dependencies: item.dependencies, scripts: item.scripts)])
            #expect(found.id == item.id, "expected \(item.id), got \(found.id ?? "nil")")
            #expect(found.kind == .server)
            #expect(found.command?.hasPrefix("npm run ") == true)
        }
    }

    @Test func angularIsFoundByItsConfigFile() throws {
        let found = try detect(["angular.json": "{}", "package.json": package(scripts: ["start": "ng serve"])])
        #expect(found.id == "angular" && found.command == "npm run start" && found.portHandling == .flag("--port"))
    }

    @Test func laravelIsServedByPHPFromPublic() throws {
        let found = try detect([
            "composer.json": #"{"require":{"php":"^8.2","laravel/framework":"^11"}}"#, "artisan": "",
            "package.json": package(dev: ["vite"], scripts: ["dev": "vite"]),
        ])
        #expect(found.id == "laravel" && found.kind == .php && found.documentRoot == "public")
        // The package.json is for assets; the project is still installed with Composer.
        #expect(found.command == nil && found.packageManager == .composer)
        #expect(found.startLine == "Served by PHP-FPM from public/")
    }

    @Test func symfonyWordPressAndPlainPHP() throws {
        let symfony = try detect(["composer.json": #"{"require":{"symfony/framework-bundle":"^7"}}"#])
        #expect(symfony.id == "symfony" && symfony.documentRoot == "public" && symfony.packageManager == .composer)
        let wordpress = try detect(["wp-config.php": "<?php", "index.php": "<?php"])
        #expect(wordpress.id == "wordpress" && wordpress.documentRoot == ".")
        let nested = try detect(["web/index.php": "<?php"])
        #expect(nested.id == "php" && nested.documentRoot == "web")
        let flat = try detect(["index.php": "<?php"])
        #expect(flat.documentRoot == "." && flat.startLine == "Served by PHP-FPM from the project folder")
    }

    @Test func pythonFrameworksPassThePortInTheCommand() throws {
        let django = try detect(["manage.py": "", "requirements.txt": "Django==5.0\n"])
        #expect(django.id == "django" && django.command == "python manage.py runserver 127.0.0.1:{port}")
        #expect(django.portHandling == .placeholder && django.packageManager == .pip)
        let flask = try detect(["pyproject.toml": "[project]\nname=\"x\"\ndependencies=[\"flask>=3\"]\n"])
        #expect(flask.id == "flask" && flask.command == "python -m flask run --port {port}")
        let fastapi = try detect([
            "pyproject.toml": "[project]\nname=\"x\"\ndependencies=[\"fastapi[standard]\"]\n",
            "uv.lock": ""
        ])
        #expect(fastapi.id == "fastapi" && fastapi.command == "uv run fastapi dev --port {port}")
        #expect(fastapi.packageManager == .uvCLI)
        let plain = try detect(["requirements.txt": "fastapi\n", "app/main.py": ""])
        #expect(plain.command == "python -m uvicorn app.main:app --reload --port {port}")
    }

    @Test func genericPythonAndStaticFallbacks() throws {
        let script = try detect(["main.py": "print(1)"])
        #expect(script.id == "python" && script.command == "python main.py" && script
            .portHandling == .environment("PORT"))
        let site = try detect(["index.html": "<h1>x</h1>"])
        #expect(site.id == "static" && site.kind == .staticFiles && site.documentRoot == ".")
        #expect(site.startLine == "Served as static files")
        let built = try detect(["public/index.html": "<h1>x</h1>"])
        #expect(built.documentRoot == "public")
    }

    @Test func aFolderThatMatchesNothingIsUnknown() throws {
        let found = try detect(["README.md": "hello"])
        #expect(found == FrameworkDetection.unknown)
        #expect(found.displayName == "Unknown" && found.startLine == "No start command found")
    }

    // MARK: Order and overrides

    @Test func theMoreSpecificFrameworkWins() throws {
        let nextWithVite = try detect(["package.json": package(
            dependencies: ["next"],
            dev: ["vite"],
            scripts: ["dev": "next dev"]
        )])
        #expect(nextWithVite.id == "next")
        let wordpressTheme = try detect([
            "wp-config.php": "",
            "package.json": package(dev: ["vite"], scripts: ["dev": "vite"])
        ])
        #expect(wordpressTheme.id == "wordpress")
    }

    @Test func warrenTomlCommandWinsAndKeepsTheFrameworkName() throws {
        let found = try detect(
            ["package.json": package(dependencies: ["next"], scripts: ["dev": "next dev"])], command: "node custom.js"
        )
        #expect(found.id == "next" && found.command == "node custom.js" && found.commandSource == .warrenConfig)
        #expect(found.startLine == "node custom.js (from .warren.toml)")
        let onlyCommand = try detect(["README.md": "x"], command: "./run.sh")
        #expect(onlyCommand.kind == .server && onlyCommand.id == nil && onlyCommand
            .portHandling == .environment("PORT"))
    }

    @Test func aProjectsOwnDevScriptBeatsTheFrameworkDefault() throws {
        let found = try detect(["package.json": package(dependencies: ["vite"], scripts: ["dev": "vite --open"])])
        #expect(found.command == "npm run dev")
    }

    @Test func thePackageManagerComesFromTheFieldThenTheLockfile() throws {
        let deps = package(dependencies: ["vite"], scripts: ["dev": "vite"])
        #expect(try detect(["package.json": deps, "yarn.lock": ""]).packageManager == .yarn)
        #expect(try detect(["package.json": deps, "bun.lock": ""]).packageManager == .bun)
        #expect(try detect(["package.json": deps, "package-lock.json": ""]).packageManager == .npm)
        let field = package(dependencies: ["vite"], scripts: ["dev": "vite"], manager: "pnpm@9.1.0")
        let found = try detect(["package.json": field, "yarn.lock": ""])
        #expect(found.packageManager == .pnpm && found.command == "pnpm run dev")
    }

    // MARK: Host names

    @Test func viteBasedServersAllowTheSitesDomains() throws {
        let files = ["package.json": package(dependencies: ["vite"], scripts: ["dev": "vite"])]
        let one = try detect(files, domains: ["app.test"])
        #expect(one.environment["__VITE_ADDITIONAL_SERVER_ALLOWED_HOSTS"] == "app.test")
        let several = try detect(files, domains: ["app.test", "api.test"])
        #expect(several.environment["__VITE_ADDITIONAL_SERVER_ALLOWED_HOSTS"] == ".test")
        let mixed = try detect(files, domains: ["app.test", "app.local"])
        #expect(mixed.environment["__VITE_ADDITIONAL_SERVER_ALLOWED_HOSTS"] == "app.test")
        #expect(try detect(files).environment.isEmpty)
        let next = try detect(["package.json": package(dependencies: ["next"])], domains: ["app.test"])
        #expect(next.environment.isEmpty)
    }

    // MARK: Safety

    @Test func detectionRunsNothingInTheProject() throws {
        let marker = root.appendingPathComponent("pwned")
        let hostile = package(
            dependencies: ["next"],
            scripts: ["dev": "touch \(marker.path)-dev", "postinstall": "touch \(marker.path)-post"]
        )
        let directory = try project([
            "package.json": hostile,
            "mise.toml": "[env]\nA = \"{{ exec(command='touch \(marker.path)-mise') }}\"\n",
            "artisan": "touch \(marker.path)-artisan",
            "manage.py": "import os; os.system('touch \(marker.path)-py')",
        ])
        _ = FrameworkDetector.detect(in: directory, command: "touch \(marker.path)-run")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix("pwned") }
        #expect(leftovers.isEmpty)
    }
}
