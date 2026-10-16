# Warren roadmap

One row is one spec is one PR. Mockup: https://claude.ai/artifact/QdJZC1qARd8SbcRDY5g9Lj

| # | Spec | Phase |
|---|------|-------|
| 000 | Spec-driven process, licensing model | 0 Foundation |
| 001 | Repo, CI, licenses, contribution rules | 0 Foundation |
| 002 | App shell: menu bar item, popover, main window (mock data) | 0 Foundation |
| 003 | Release pipeline: signing, notarization, delta auto-update | 0 Foundation |
| 004 | Site registry and config store, `.warren.toml` | 1 Core |
| 005 | Local reverse proxy and trusted local CA | 1 Core |
| 006 | Custom local domains and aliases (DNS resolver) | 1 Core |
| 007 | Runtime manager: Node and Bun, plus shared package caches | 2 Runtimes |
| 008 | PHP runtime with FPM and Composer | 2 Runtimes |
| 009 | Python runtime via uv | 2 Runtimes |
| 010 | Framework detection and start commands | 2 Runtimes |
| 011 | Project detection and setup-plan generation | 3 Add site |
| 012 | Plan executor, progress events, command approvals | 3 Add site |
| 013 | Templates and blank projects | 3 Add site |
| 014 | GitHub import and env/secret prompts | 3 Add site |
| 015 | Service manager and `ServiceDriver` interface (native) | 4 Services |
| 016 | PostgreSQL and MySQL | 4 Services |
| 017 | Redis, Mailpit, MinIO | 4 Services |
| 018 | Service catalog as data | 4 Services |
| 019 | Container driver and docker-compose mapping | 4 Services |
| 020 | MCP server: read tools | 5 Agents |
| 021 | MCP write tools and approvals | 5 Agents |
| 022 | MCP client auto-setup | 5 Agents |
| 023 | `ShareProvider` interface and Share UI | 6 Sharing |
| 024 | Tailscale provider | 6 Sharing |
| 025 | Relay server (open source, self-hostable) and accounts | 6 Sharing |
| 026 | Cloudflare provider: shared domain, hosted or self-hosted | 6 Sharing |
| 027 | Free-tier limits and abuse controls | 6 Sharing |
| 028 | Custom domains and billing for hosted Relay | 6 Sharing |
| 029 | Storage accounting (measure only) | 7 Storage |
| 030 | Runtime garbage collection | 7 Storage |
| 031 | Site hibernation | 7 Storage |
| 032 | Storage UI and policies | 7 Storage |
| 033 | MCP storage tools | 7 Storage |
| 034 | Logs UI | 8 Polish |
| 035 | Settings and optional shell shim | 8 Polish |
| 036 | Onboarding and import from other local dev tools | 8 Polish |
| 037 | Database browser: auto-connect to Warren services, schema tree, read-only table viewer | 9 Database tools |
| 038 | Query editor with history, saved queries and a result grid | 9 Database tools |
| 039 | Row editing with safe, reviewable changes (insert, update, delete in a transaction) | 9 Database tools |
| 040 | Structure view and schema editing (tables, columns, indexes, foreign keys) | 9 Database tools |
| 041 | Import and export (CSV, JSON, SQL dump) and one-click snapshot and restore | 9 Database tools |
| 042 | MCP database tools: schema and read queries open, writes ask first | 9 Database tools |
| 043 | Background proxy and DNS (launchd) and real state in the app | 1 Core |
| 044 | Setup wizard: first-run setup from the app, no terminal | 1 Core |
| 045 | App catalog: browse and start from ready-made apps (Next.js and other starters), as data | 3 Add site |

## Notes

- **App catalog (045).** A browsable catalog of starter apps (for example the Next.js starters and templates Vercel publishes, Laravel and Vite starters, WordPress) shown in the Add-site flow, with search and categories. Entries are data in the repo, like the service catalog (018), not code: each names the source repo or template, the runtime it needs, the services it wants and the commands to set it up. It builds on 011 and 012, and replaces the fixed template list in 013, which then covers only blank projects. Before writing the spec, survey existing sources (Vercel's template gallery, `create-next-app`, `giget` and `degit` for fetching a template, framework starter lists) and reuse them instead of keeping our own copies. Starters come from repos the user did not write, so running their setup commands needs the per-command consent from 000.

- **Build order change.** 043 and 044 come right after 006 and before 007. Specs 004 to 006 built the engine and a CLI. Until 043 and 044 land, a user cannot actually use them from the app. Everything after that should arrive with its app surface (see the *App first* principle in 000).
- 025 and 026 implement the same `ShareProvider` in two modes: **hosted** (uses the Warren API) and **self-hosted** (user's own Relay server, or their own Cloudflare account directly). The app has one setting: *Relay endpoint*.
- 024 (Tailscale) needs no backend and can ship before 025.
- 029 should land before 031 so hibernation decisions are based on real numbers.
- Phase 9 builds on the service manager (015, 016, 017). A site's `[services]` entry in `.warren.toml` becomes a ready-made connection, so a database is one click from the site that uses it. It also reaches databases outside Warren (any host, with credentials in the Keychain) after 037.
- 042 follows the agent-parity rule in 000: reads are open, anything that changes data asks first, and the user sees the exact SQL before approving.
