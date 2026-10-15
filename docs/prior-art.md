# Prior art

Warren should be built from stable, existing parts. This list is a starting point for each spec's **Prior art** section. The entries are candidates from a quick survey, not decisions: the spec that builds the feature confirms current facts (license, maintenance, macOS and Apple silicon support, size, how it is distributed) and records the choice.

| Area | Existing options | Leaning | Spec |
|---|---|---|---|
| Parsing `.warren.toml` | TOMLDecoder (pure Swift, Codable), TOMLKit and swift-toml (both wrap the C++ toml++ parser) | TOMLDecoder (decided in 004) | 004 |
| Node, Bun, Deno and other runtimes | mise (polyglot, reads `.nvmrc`, `.tool-versions`), fnm (Node only), Volta | mise | 007 |
| Python | uv (versions, venvs, packages) | uv | 009 |
| PHP | Prebuilt static PHP binaries, mise plugins, Homebrew builds | Needs investigation: prebuilt FPM binaries are the key question | 008 |
| Package caches | pnpm, uv, Bun and Composer shared stores, pointed at one location by environment variables | Their own caches | 007 |
| Framework and project detection | Nixpacks and Railpack detectors, buildpacks, `package.json` and lockfile heuristics | Evaluate Railpack and Nixpacks before writing detectors | 010, 011 |
| Reverse proxy and local HTTPS | Caddy (automatic HTTPS, internal CA, admin API for live config), mkcert plus a proxy | Caddy as a managed helper binary (decided in 005) | 005 |
| Local DNS for custom domains | dnsmasq, macOS per-domain resolver files, `/etc/hosts` | dnsmasq with a resolver file | 006 |
| Database and service binaries | Upstream release binaries, Homebrew bottles, Postgres.app-style builds, embedded-postgres binaries | Evaluate; prefer upstream binaries we verify by checksum | 015 to 018 |
| Compose files from imported repos | `docker compose config` (normalizes and validates), the Compose specification | Shell out to Compose, do not parse YAML ourselves | 019 |
| Containers | Docker, OrbStack, Podman, Apple's `container` | Drive whichever is installed through its CLI | 019 |
| MCP server | Official Swift MCP SDK | The SDK | 020 |
| Updates | Sparkle | Sparkle (decided in 003) | 003 |
| Tailscale sharing | The `tailscale` CLI and LocalAPI (`serve`, `funnel`) | The user's own Tailscale client | 024 |
| Cloudflare sharing | `cloudflared`, the Cloudflare Tunnel and DNS APIs | Do not invent a tunnel protocol | 026 |
| Database browser | libpq and the MySQL client library for drivers, existing open-source clients for UX reference and possible embedding | Evaluate before building a grid and query editor from scratch | 037 to 040 |
| Import and export | `pg_dump`, `mysqldump`, CSV libraries | The vendors' own tools | 041 |
| Repo hygiene in CI | The DCO GitHub app or action, the REUSE tool for license headers | Replace our small scripts if the existing tools fit | 001 |

## Rules of thumb

- If a mature command-line tool does the job, Warren drives it and ships or downloads it, rather than reimplementing it.
- Prefer one managed binary per job over a pile of libraries.
- Pin versions and verify checksums for anything Warren downloads.
- A dependency must be easy to update. If updating it is hard, that counts against it.
