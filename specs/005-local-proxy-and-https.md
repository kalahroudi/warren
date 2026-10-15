# 005 · Local reverse proxy and trusted HTTPS

Status: Draft · Phase 1 · Depends on: 004

## Goal

A registered site is reachable at `https://<domain>` with a certificate the browser trusts, forwarded to the port in its `.warren.toml`. Warren does this by managing an existing proxy, not by writing one.

## Non-goals

- No DNS. Names like `acme.test` resolve through spec 006. Until then, tests use `curl --resolve` or `/etc/hosts`.
- No starting or supervising site processes or the proxy at login (spec 015). In this spec the proxy runs in the foreground from the CLI.
- No sharing over the internet (specs 023 to 028) and no UI.

## Prior art

| Option | Verdict |
|---|---|
| **Caddy** (Apache-2.0, 2.11.7 released 2026-10-03, actively maintained, macOS arm64 and Intel builds with published checksums). Automatic HTTPS, a built-in local certificate authority, live reconfiguration through an admin API. | **Used**, as a managed helper binary. |
| mkcert plus our own proxy | Rejected. Last updated August 2024, and we would still have to write and maintain the proxy. |
| Traefik (MIT, active) | Rejected. No built-in local CA, and its model is built around containers and service discovery. |
| nginx or Apache | Rejected. No automatic local CA, and reconfiguration means rewriting files and reloading. |
| A proxy and CA written with SwiftNIO and Security.framework | Rejected under the reuse-before-build rule. |

Warren writes Caddy's JSON configuration and drives its admin API. It does not fork, patch or wrap Caddy's code.

## Behavior

**Managed binary.** `catalog/tools/caddy.json` pins a version and, per architecture, a download URL and SHA-512. `warren proxy install` downloads the archive over HTTPS, verifies the pinned hash, and unpacks to `~/Warren/bin/caddy/<version>/caddy`. A hash mismatch deletes the download and fails. Updating the pin is a reviewed change in the repo, so Warren updates Caddy by shipping a new pin.

**Configuration.** A pure function turns the resolved sites (spec 004) and the chosen ports into Caddy JSON:

- One route per site domain, forwarding to `localhost:<run.port>`. Sites without a `run.port` are listed as "no port" and skipped.
- TLS from Caddy's `internal` issuer. HTTP redirects to HTTPS.
- Output is sorted and stable, so the same sites always give the same config.
- The admin API listens on a Unix socket at `~/Warren/run/caddy.sock`, mode 0600. No TCP port 2019.
- Caddy's data directory is `~/Warren/data/caddy`, so Warren's CA is separate from any other Caddy on the machine. That directory is mode 0700.

**Ports.** Defaults are 80 and 443. `--http-port` and `--https-port` override them, which also lets tests run unprivileged. If a port is taken, the error names the process holding it.

**Who may connect.** On macOS, an unprivileged process can bind ports 80 and 443 only on the wildcard address, not on loopback alone, so Caddy would otherwise answer other machines on the network. Every route therefore matches only loopback clients (`remote_ip` of `127.0.0.1` and `::1`) and refuses all others.

**CLI.**

- `warren proxy install` downloads and verifies Caddy.
- `warren proxy config` prints the generated JSON.
- `warren proxy run [--http-port N] [--https-port N]` runs Caddy in the foreground. Ctrl-C stops it cleanly.
- `warren proxy reload` regenerates the config from the registry and applies it through the admin API without a restart.
- `warren proxy trust` explains what it will change, asks for confirmation, then runs `caddy trust` so Warren's local root CA is trusted by the system. This prompts for the user's admin password.
- `warren proxy untrust` removes it. `warren proxy status` reports installed version, whether it is running, which sites are routed, and whether the root is trusted.

**Trust is explicit and reversible.** Warren never trusts its CA silently. The root certificate can issue certificates for any name, so its private key stays in the 0700 data directory, and `status` and the docs say so plainly.

## Acceptance criteria

1. [ ] `proxy install` downloads the pinned Caddy and verifies its SHA-512; a corrupted archive is rejected and removed.
2. [ ] Config generation is covered by unit tests: one route per site with a port, sites without a port reported, stable sorted output, loopback-only matcher present.
3. [ ] `proxy run` on high ports serves `https://acme.test:<port>` to the site's backend, and the certificate chains to Warren's root, checked with `curl --cacert` without changing the keychain.
4. [ ] Plain HTTP redirects to HTTPS.
5. [ ] A request arriving from a non-loopback address (the machine's LAN IP) is refused.
6. [ ] A busy port fails with a message naming the process that holds it.
7. [ ] `proxy trust` asks for confirmation before changing anything, and after it the system trusts the root; `proxy untrust` reverses it; `status` reports both states.
8. [ ] `proxy reload` picks up an added or removed site without restarting Caddy.
9. [ ] The admin API is a Unix socket with mode 0600, and nothing listens on TCP 2019.
10. [ ] Ctrl-C leaves no Caddy process running.

## Test plan

Unit tests for config generation and checksum verification. Criteria 3 to 6, 8 to 10 verified by running the real binary on high ports against a throwaway backend, recorded in the PR. Criterion 7 needs an admin password prompt, so it is verified by the user on their own machine.

## Rollout

New files under `~/Warren/bin`, `data` and `run`. The system is touched only by `proxy trust`, and `proxy untrust` undoes it. No migration.

## Open questions

- Can the local CA be constrained to `.test` and `.localhost`-style names (name constraints), to limit the damage if its key leaks? Check what Caddy supports before accepting.
- Does binding the wildcard address trigger the macOS firewall prompt for the Caddy binary? Verify on a machine with the firewall on.
- How do we keep the pinned hashes current? A scheduled job that opens a PR bumping the pin is likely.
- Whether `caddy trust` can use the Unix-socket admin address, or whether Warren should hand it the root certificate file instead. Confirm when building.
