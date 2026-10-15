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

## Notes

- 025 and 026 implement the same `ShareProvider` in two modes: **hosted** (uses the Warren API) and **self-hosted** (user's own Relay server, or their own Cloudflare account directly). The app has one setting: *Relay endpoint*.
- 024 (Tailscale) needs no backend and can ship before 025.
- 029 should land before 031 so hibernation decisions are based on real numbers.
