// SPDX-License-Identifier: Apache-2.0

import Foundation

/// One framework Warren recognises: how to identify it, and how to run it in development. Rows are checked in
/// order, most specific first, so a framework built on another one (SvelteKit on Vite) comes before it.
struct FrameworkRule: Sendable {
    let id: String
    let name: String
    let kind: ServeKind
    let matches: @Sendable (ProjectFiles) -> Bool
    /// The command and where it came from, for `server` kinds.
    var command: @Sendable (ProjectFiles, PackageManager?) -> (String, CommandSource)? = { _, _ in nil }
    var port: PortHandling = .none
    var documentRoot: @Sendable (ProjectFiles) -> String? = { _ in nil }
    /// Vite-based dev servers refuse unknown host names unless they are allowed.
    var allowsHostNames = false
    var notes: [String] = []
}

enum FrameworkRules {
    /// `<pm> run <script>` when the project has that script, else the framework's own command run through the
    /// package manager's executor (`npx next dev`).
    private static func script(_ names: [String],
                               fallback: String?)
        -> @Sendable (ProjectFiles, PackageManager?) -> (String, CommandSource)?
    {
        { files, manager in
            let manager = manager ?? .npm
            if let name = names.first(where: { files.scripts[$0] != nil }) {
                return ("\(manager.rawValue) run \(name)", .script)
            }
            return fallback.map { ("\(executor(manager)) \($0)", .framework) }
        }
    }

    private static func executor(_ manager: PackageManager) -> String {
        switch manager {
        case .pnpm: "pnpm exec"
        case .yarn: "yarn"
        case .bun: "bunx"
        default: "npx"
        }
    }

    private static func fixed(_ command: String)
        -> @Sendable (ProjectFiles, PackageManager?) -> (String, CommandSource)?
    {
        { _, _ in (command, .framework) }
    }

    private static func firstFolder(_ candidates: [String]) -> @Sendable (ProjectFiles) -> String? {
        { files in candidates.first { files.exists($0 + "/index.php") } ?? "." }
    }

    /// Most specific first.
    static let all: [FrameworkRule] = [
        FrameworkRule(
            id: "laravel", name: "Laravel", kind: .php,
            matches: { $0.composerPackages.contains("laravel/framework") && $0.exists("artisan") },
            documentRoot: { _ in "public" }
        ),
        FrameworkRule(
            id: "symfony", name: "Symfony", kind: .php,
            matches: { $0.composerPackages.contains("symfony/framework-bundle") },
            documentRoot: { _ in "public" }
        ),
        FrameworkRule(
            id: "wordpress", name: "WordPress", kind: .php,
            matches: { $0.exists("wp-config.php") || $0.exists("wp-content") || $0.exists("wp-config-sample.php") },
            documentRoot: { _ in "." }
        ),
        FrameworkRule(
            id: "next", name: "Next.js", kind: .server, matches: { $0.hasNode("next") },
            command: script(["dev"], fallback: "next dev"), port: .environment("PORT")
        ),
        FrameworkRule(
            id: "nuxt", name: "Nuxt", kind: .server, matches: { $0.hasNode("nuxt") || $0.hasNode("nuxt-nightly") },
            command: script(["dev"], fallback: "nuxt dev"), port: .environment("PORT"), allowsHostNames: true
        ),
        FrameworkRule(
            id: "astro", name: "Astro", kind: .server, matches: { $0.hasNode("astro") },
            command: script(["dev", "start"], fallback: "astro dev"), port: .flag("--port"), allowsHostNames: true
        ),
        FrameworkRule(
            id: "sveltekit", name: "SvelteKit", kind: .server, matches: { $0.hasNode("@sveltejs/kit") },
            command: script(["dev"], fallback: "vite dev"), port: .flag("--port"), allowsHostNames: true
        ),
        FrameworkRule(
            id: "remix", name: "Remix", kind: .server,
            matches: { $0.hasNode("@remix-run/dev") || $0.hasNode("@react-router/dev") },
            command: script(["dev"], fallback: nil), port: .flag("--port"), allowsHostNames: true
        ),
        FrameworkRule(
            id: "angular", name: "Angular", kind: .server,
            matches: { $0.exists("angular.json") || $0.hasNode("@angular/cli") },
            command: script(["start", "dev"], fallback: "ng serve"), port: .flag("--port"),
            notes: ["Angular blocks unknown host names. Add --allowed-hosts for this site's domain."]
        ),
        FrameworkRule(
            id: "vite", name: "Vite", kind: .server, matches: { $0.hasNode("vite") },
            command: script(["dev"], fallback: "vite"), port: .flag("--port"), allowsHostNames: true
        ),
        FrameworkRule(
            id: "react-scripts", name: "Create React App", kind: .server, matches: { $0.hasNode("react-scripts") },
            command: script(["start"], fallback: "react-scripts start"), port: .environment("PORT")
        ),
        FrameworkRule(
            id: "django", name: "Django", kind: .server,
            matches: { $0.exists("manage.py") && ($0.pythonPackages.contains("django") || $0.pythonPackages.isEmpty) },
            command: fixed("python manage.py runserver 127.0.0.1:{port}"), port: .placeholder
        ),
        FrameworkRule(
            id: "fastapi", name: "FastAPI", kind: .server, matches: { $0.pythonPackages.contains("fastapi") },
            command: { files, _ in
                files.hasUvProject
                    ? ("uv run fastapi dev --port {port}", .framework)
                    : (
                        "python -m uvicorn \(files.exists("app/main.py") ? "app.main" : "main"):app --reload --port {port}",
                        .framework
                    )
            },
            port: .placeholder
        ),
        FrameworkRule(
            id: "flask", name: "Flask", kind: .server, matches: { $0.pythonPackages.contains("flask") },
            command: fixed("python -m flask run --port {port}"), port: .placeholder
        ),
        FrameworkRule(
            id: "node", name: "Node.js", kind: .server,
            matches: { $0.hasPackageJSON && ($0.scripts["dev"] != nil || $0.scripts["start"] != nil) },
            command: script(["dev", "start"], fallback: nil), port: .environment("PORT"),
            notes: ["Warren passes the port in PORT. The app has to listen on it."]
        ),
        FrameworkRule(
            id: "php", name: "PHP", kind: .php,
            matches: { files in ["public", "web", "."].contains { files.exists($0 + "/index.php") } },
            documentRoot: firstFolder(["public", "web"])
        ),
        FrameworkRule(
            id: "python", name: "Python", kind: .server,
            matches: { $0.exists("main.py") || $0.exists("app.py") },
            command: { files, _ in (files.exists("app.py") ? "python app.py" : "python main.py", .framework) },
            port: .environment("PORT"), notes: ["Warren passes the port in PORT. The app has to listen on it."]
        ),
        FrameworkRule(
            id: "static", name: "Static site", kind: .staticFiles,
            matches: { $0.exists("index.html") || $0.exists("public/index.html") },
            documentRoot: { $0.exists("index.html") ? "." : "public" }
        ),
    ]
}
