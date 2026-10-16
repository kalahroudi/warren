// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A framework starter made by running the framework's own scaffolder in a new empty folder. Warren keeps no copy
/// of the files; flags are the non-interactive ones, and installing is left to Warren's setup plan.
public struct ProjectTemplate: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let summary: String
    public let runtime: RuntimeKind
    /// The version to ask for when the project has none yet.
    public let runtimeRequest: String
    /// What is downloaded and run, for the approval sheet.
    public let source: String
    public let command: [String]
    /// Files Warren writes before the scaffolder runs, which the scaffolder needs or builds on.
    public let seedFiles: [String: String]

    public var commandLine: String {
        command.joined(separator: " ")
    }

    public static let all: [ProjectTemplate] = [
        ProjectTemplate(
            id: "next", name: "Next.js", summary: "React framework with routing and server rendering.",
            runtime: .node, runtimeRequest: "lts", source: "create-next-app from npm",
            command: ["npx", "create-next-app@latest", ".", "--yes", "--skip-install"], seedFiles: [:]
        ),
        ProjectTemplate(
            id: "vite-react", name: "Vite + React", summary: "Fast React and TypeScript starter.",
            runtime: .node, runtimeRequest: "lts", source: "create-vite from npm",
            command: ["npm", "create", "vite@latest", ".", "--", "--template", "react-ts"], seedFiles: [:]
        ),
        ProjectTemplate(
            id: "astro", name: "Astro", summary: "Content sites with little JavaScript.",
            runtime: .node, runtimeRequest: "lts", source: "create-astro from npm",
            command: [
                "npm", "create", "astro@latest", ".", "--", "--template", "minimal", "--no-install", "--no-git",
                "--yes",
            ], seedFiles: [:]
        ),
        ProjectTemplate(
            id: "sveltekit", name: "SvelteKit", summary: "Svelte application framework.",
            runtime: .node, runtimeRequest: "lts", source: "sv from npm",
            command: [
                "npx",
                "sv",
                "create",
                ".",
                "--template",
                "minimal",
                "--types",
                "ts",
                "--no-add-ons",
                "--no-install"
            ],
            seedFiles: [:]
        ),
        ProjectTemplate(
            id: "laravel", name: "Laravel", summary: "PHP framework with batteries included.",
            runtime: .php, runtimeRequest: "latest", source: "laravel/laravel from Packagist",
            command: [
                "composer",
                "create-project",
                "laravel/laravel",
                ".",
                "--no-install",
                "--no-scripts",
                "--no-interaction"
            ],
            seedFiles: [:]
        ),
        ProjectTemplate(
            id: "django", name: "Django", summary: "Python web framework.",
            runtime: .python, runtimeRequest: "latest", source: "Django from PyPI",
            command: ["uv", "tool", "run", "--from", "django", "django-admin", "startproject", "config", "."],
            seedFiles: ["requirements.txt": "django\n"]
        ),
    ]

    public static func named(_ id: String) -> ProjectTemplate? {
        all.first { $0.id == id }
    }
}

/// A project Warren writes itself: a few short files and no network.
public enum BlankKind: String, CaseIterable, Identifiable, Sendable {
    case staticSite = "static"
    case node
    case bun
    case php
    case python

    public var id: String {
        rawValue
    }

    public var name: String {
        switch self {
        case .staticSite: "Static site"
        case .node: "Node"
        case .bun: "Bun"
        case .php: "PHP"
        case .python: "Python"
        }
    }

    public var runtime: RuntimeKind? {
        switch self {
        case .staticSite: nil
        case .node: .node
        case .bun: .bun
        case .php: .php
        case .python: .python
        }
    }

    /// File name to contents. `.warren.toml` pins the runtime where there is one.
    public func files(name: String) -> [String: String] {
        var files: [String: String] = switch self {
        case .staticSite:
            ["index.html": Self.html(name)]
        case .node:
            ["server.js": Self.nodeServer, "package.json": Self.packageJSON(name, run: "node server.js")]
        case .bun:
            [
                "server.ts": Self.bunServer,
                "package.json": Self.packageJSON(name, run: "bun server.ts", manager: "bun@1"),
            ]
        case .php:
            ["public/index.php": Self.phpSource]
        case .python:
            ["app.py": Self.pythonSource]
        }
        if let runtime {
            files[".warren.toml"] = "[runtime]\n\(runtime.rawValue) = \"\(runtime == .node ? "lts" : "latest")\"\n"
        }
        return files
    }

    private static func html(_ name: String) -> String {
        """
        <!doctype html>
        <meta charset="utf-8">
        <title>\(name)</title>
        <h1>\(name)</h1>
        <p>Edit index.html and reload.</p>

        """
    }

    private static func packageJSON(_ name: String, run: String, manager: String? = nil) -> String {
        let field = manager.map { ",\n  \"packageManager\": \"\($0)\"" } ?? ""
        return """
        {
          "name": "\(name.lowercased())",
          "private": true,
          "scripts": { "dev": "\(run)" }\(field)
        }

        """
    }

    private static let nodeServer = """
    // A small web server. Warren passes the port in PORT.
    const http = require("node:http");
    const port = process.env.PORT || 3000;

    http
      .createServer((request, response) => {
        response.setHeader("content-type", "text/plain");
        response.end("Hello from Node\\n");
      })
      .listen(port, "127.0.0.1", () => console.log(`listening on http://127.0.0.1:${port}`));

    """

    private static let bunServer = """
    // A small web server. Warren passes the port in PORT.
    const port = Number(process.env.PORT ?? 3000);

    Bun.serve({
      hostname: "127.0.0.1",
      port,
      fetch: () => new Response("Hello from Bun\\n"),
    });

    console.log(`listening on http://127.0.0.1:${port}`);

    """

    private static let phpSource = """
    <?php
    // Served by PHP-FPM from this folder.
    echo "Hello from PHP " . PHP_VERSION . "\\n";

    """

    private static let pythonSource = """
    # A small web server. Warren passes the port in PORT.
    import os
    from http.server import BaseHTTPRequestHandler, HTTPServer


    class Hello(BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(200)
            self.send_header("content-type", "text/plain")
            self.end_headers()
            self.wfile.write(b"Hello from Python\\n")


    port = int(os.environ.get("PORT", "3000"))
    print(f"listening on http://127.0.0.1:{port}", flush=True)
    HTTPServer(("127.0.0.1", port), Hello).serve_forever()

    """
}
