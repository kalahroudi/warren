// SPDX-License-Identifier: Apache-2.0

extension FixtureProvider {
    static let demoState = StateSnapshot(
        sites: demoSites,
        services: demoServices,
        runtimeGroups: demoRuntimeGroups,
        activeRuntimes: ["Node 22.11", "PHP 8.4", "Python 3.13", "Bun 1.2"],
        agents: demoAgents,
        storage: demoStorage,
        update: UpdateInfo(version: "0.4.2", deltaMB: 12),
        paused: false,
        network: NetworkStatus(
            proxy: ServiceStatus(installed: true, running: true),
            dns: ServiceStatus(installed: true, running: true),
            rootTrusted: true
        ),
        capabilities: Capabilities(canControlSites: true, canPause: true),
        isLive: false,
        setupComplete: true,
        previewSections: [],
        notice: nil
    )

    private static let demoSites = [
        Site(id: "acme", domain: "acme.test", stack: "Next.js", runtime: "Node 22", detail: ":3000",
             path: "~/Sites/acme-store", state: .running, relayURL: "https://acme-store.warren.run"),
        Site(id: "api", domain: "api.acme.test", stack: "Hono", runtime: "Bun 1.2", detail: ":8787",
             path: "~/Sites/acme-api", state: .running, relayURL: nil),
        Site(id: "docs", domain: "docs.dev", stack: "SvelteKit", runtime: "Node 22", detail: "hibernated",
             path: "~/Sites/docs", state: .hibernated, relayURL: nil),
        Site(id: "billing", domain: "billing.test", stack: "Laravel", runtime: "PHP 8.4", detail: "php-fpm",
             path: "~/Sites/billing", state: .running, relayURL: nil),
        Site(id: "scraper", domain: "scraper.local", stack: "FastAPI", runtime: "Python 3.13", detail: ":8000",
             path: "~/Sites/scraper", state: .running, relayURL: nil),
    ]

    private static let demoServices = [
        Service(id: "postgres", name: "PostgreSQL 17", kind: "Database", port: 5432, running: true, memoryMB: 142),
        Service(id: "redis", name: "Redis 7", kind: "Cache and queues", port: 6379, running: true, memoryMB: 18),
        Service(id: "mysql", name: "MySQL 8.4", kind: "Database", port: 3306, running: false, memoryMB: 0),
        Service(id: "mailpit", name: "Mailpit", kind: "Mail catcher", port: 8025, running: true, memoryMB: 12),
        Service(id: "minio", name: "MinIO", kind: "S3 storage", port: 9000, running: false, memoryMB: 0),
        Service(id: "meilisearch", name: "Meilisearch", kind: "Search", port: 7700, running: false, memoryMB: 0),
    ]

    private static func version(_ label: String, _ note: String, _ size: Int,
                                isDefault: Bool = false, update: Bool = false) -> RuntimeVersion
    {
        RuntimeVersion(id: label, label: label, note: note, sizeMB: size,
                       isDefault: isDefault, updateAvailable: update)
    }

    private static let demoRuntimeGroups = [
        RuntimeGroup(id: "node", name: "Node.js", note: "pnpm, npm and yarn included", versions: [
            version("22.11.0", "default · 3 sites", 41, isDefault: true),
            version("20.18.1", "1 site", 39),
            version("24.0.0", "update available", 43, update: true),
        ]),
        RuntimeGroup(id: "php", name: "PHP", note: "FPM and CLI, Composer included", versions: [
            version("8.4.1", "default · 1 site", 58, isDefault: true),
            version("8.3.14", "not used", 56),
        ]),
        RuntimeGroup(id: "python", name: "Python", note: "via uv, one venv per site", versions: [
            version("3.13.0", "default · 1 site", 32, isDefault: true),
            version("3.12.7", "not used", 31),
        ]),
        RuntimeGroup(id: "bun", name: "Bun and Deno", note: "Single binaries", versions: [
            version("Bun 1.2.2", "default · 1 site", 52, isDefault: true),
            version("Deno 2.1.4", "not used", 38),
        ]),
    ]

    private static let demoAgents = AgentsInfo(
        endpoint: "http://127.0.0.1:7421/mcp",
        clients: [
            AgentClient(id: "claude", name: "Claude Code", connected: true),
            AgentClient(id: "cursor", name: "Cursor", connected: true),
            AgentClient(id: "codex", name: "Codex CLI", connected: false),
        ],
        permissions: [
            ToolPermission(
                id: "inspect",
                tool: "list_sites, tail_logs",
                summary: "Inspect what is running",
                asksFirst: false
            ),
            ToolPermission(
                id: "lifecycle",
                tool: "start_site, stop_service",
                summary: "Lifecycle control",
                asksFirst: false
            ),
            ToolPermission(
                id: "create",
                tool: "create_site, add_service",
                summary: "Scaffold new things",
                asksFirst: true
            ),
            ToolPermission(id: "runtime", tool: "install_runtime", summary: "Download a runtime", asksFirst: true),
            ToolPermission(id: "share", tool: "share_site", summary: "Expose a site to the internet", asksFirst: true),
        ],
        activity: [
            AgentActivity(
                id: "1",
                time: "09:41",
                client: "Claude Code",
                call: "add_service postgres@17",
                result: "approved"
            ),
            AgentActivity(id: "2", time: "09:40", client: "Claude Code", call: "tail_logs acme.test", result: "ok"),
            AgentActivity(
                id: "3",
                time: "09:32",
                client: "Cursor",
                call: "share_site acme.test",
                result: "waiting for you"
            ),
            AgentActivity(id: "4", time: "09:12", client: "Cursor", call: "list_sites", result: "ok"),
        ]
    )

    private static let demoStorage = StorageInfo(
        categories: [
            StorageCategory(id: "sites", name: "Sites", gigabytes: 21.4),
            StorageCategory(id: "runtimes", name: "Runtimes", gigabytes: 9.1),
            StorageCategory(id: "services", name: "Services", gigabytes: 8.6),
            StorageCategory(id: "caches", name: "Caches", gigabytes: 9.2),
        ],
        reclaim: [
            ReclaimItem(id: "hibernate", title: "Hibernate 3 inactive sites",
                        note: "Not opened in 30+ days. Lockfiles found.", gigabytes: 6.1),
            ReclaimItem(id: "cache", title: "Package cache over its 10 GB budget",
                        note: "Least recently used entries", gigabytes: 3.8),
            ReclaimItem(id: "runtimes", title: "3 unused runtimes",
                        note: "Re-downloaded when needed", gigabytes: 1.9),
            ReclaimItem(id: "build", title: "Build caches", note: "Idle sites only", gigabytes: 1.6),
            ReclaimItem(id: "orphans", title: "Orphaned database files",
                        note: "Left behind by a deleted site", gigabytes: 0.8),
        ],
        policies: [
            StoragePolicy(id: "hibernate", label: "Hibernate sites after", value: "30 days · ask first"),
            StoragePolicy(id: "runtimes", label: "Remove unused runtimes after", value: "30 days · automatic"),
            StoragePolicy(id: "cache", label: "Package cache budget", value: "10 GB"),
        ]
    )
}
