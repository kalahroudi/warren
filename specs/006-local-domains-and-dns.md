# 006 · Custom local domains and DNS

Status: Implemented, pending the resolver check · Phase 1 · Depends on: 004, 005

## Goal

Any domain a site claims in `.warren.toml` (`acme.test`, `shop.dev`, `hello.example.com`) resolves to this Mac, so the HTTPS proxy from spec 005 can serve it. Adding a site under `.test` needs no admin password after a one-time setup.

## Non-goals

- No certificates or proxying (spec 005) and no sharing a site beyond this Mac (specs 023 to 028). The DNS server listens on loopback only.
- No privileged helper that avoids the one-time admin prompts (spec 015).
- No supervision at login (spec 015). `warren dns run` is a foreground command, like `warren proxy run`.

## Prior art

| Option | Verdict |
|---|---|
| **CoreDNS** (Apache-2.0, 1.14.7 released 2026-08-19, actively maintained, official macOS arm64 and Intel binaries with published SHA-256). Per-zone answers from a template, live config reload, runs unprivileged on a high port. | **Used**, through the same pinned, checksum-verified managed-binary mechanism as Caddy. |
| **macOS per-domain resolver files** (`/etc/resolver/<domain>`, built in, can name a port) | **Used** to send only Warren's domains to Warren's DNS. Everything else keeps using the normal resolvers. |
| dnsmasq (GPL-2.0, source only, no official macOS binary, Homebrew bottles only) | Rejected. It cannot be shipped through the managed-binary mechanism without a compiler or a Homebrew dependency. |
| Unbound (BSD-3-Clause, source only) | Rejected. A recursive resolver, source only, and a poor fit for static answers. |
| A managed `/etc/hosts` block | Considered as the alternative below. No daemon, but every new site needs an admin password, and wildcards do not exist. |
| Public wildcard DNS (nip.io, sslip.io) | Rejected. Needs the internet and does not give custom names. |
| Our own DNS server | Rejected under the reuse-before-build rule. |

**The cost, stated plainly.** CoreDNS idles at about 46 MB of memory and its binary is about 70 MB on disk, measured on Apple silicon. That is the price of "add a `.test` site and it just works with no password". The alternative, a managed hosts-file block, costs nothing at idle but prompts for an admin password on every site change. This spec proposes CoreDNS, and the proxy does not need DNS running when no site uses a domain.

## Behavior

**Which domains need DNS.** Derived from the registry (spec 004):

| Domain | What Warren does |
|---|---|
| `*.localhost` | Nothing. macOS already resolves it to loopback. |
| Under a reserved TLD (`.test`, `.internal`) | One zone for the whole TLD, so every current and future site under it works. |
| Any other domain (`acme.dev`, `app.example.com`) | A zone for exactly that domain and its subdomains. Other names under the same TLD are untouched. |
| `*.local` | Rejected with a message. macOS reserves it for Bonjour, and it is slow and unreliable for this. |

Zones nested inside another claimed zone are dropped, and the list is sorted, so the same sites always give the same result.

**Names outside the zones are REFUSED by default.** CoreDNS answers REFUSED for any name that no server block covers, so the Corefile needs no catch-all block (an early draft tried a `refuse` directive, which this build does not have).

**The DNS server.** `warren dns run` generates a Corefile and runs CoreDNS on `127.0.0.1` and `::1`, port 5354 by default (`--port` to change), TCP and UDP, as the current user. Each zone answers `A` with `127.0.0.1` and `AAAA` with `::1`, for the zone and all its subdomains. Anything outside the zones is REFUSED, so Warren can never answer for a real domain it was not asked about. CoreDNS reloads its Corefile on change, so `warren dns sync` applies a changed registry without a restart.

**Resolver files.** Each zone needs `/etc/resolver/<zone>` containing:

```
# Managed by Warren
nameserver 127.0.0.1
port 5354
```

Creating files in `/etc/resolver` needs an admin password. `warren dns enable` prints exactly which files it will write, asks for confirmation, then does all of them in one privileged step and flushes the macOS DNS cache. `.test` is one file, once. Warren only ever creates or removes files that carry its marker comment. If a file for a zone already exists without the marker, Warren refuses to touch it and says so. `warren dns disable` removes Warren's files.

**CLI.**

- `warren dns install` downloads and verifies CoreDNS.
- `warren dns config [--port N]` prints the Corefile.
- `warren dns run [--port N]` runs it in the foreground; Ctrl-C stops it.
- `warren dns sync` rewrites the Corefile from the registry.
- `warren dns enable` and `warren dns disable` manage the resolver files.
- `WARREN_RESOLVER_DIR` points the resolver-file commands at another directory, which then needs no admin password. It exists so the full flow can be exercised without touching `/etc/resolver`.
- `warren dns status` shows zones, whether CoreDNS is installed and running, which resolver files are present or missing, and **an end-to-end check through the real macOS resolver** for each domain.

## Acceptance criteria

1. [x] `dns install` downloads the pinned CoreDNS and verifies its SHA-256; a corrupted archive is rejected and removed.
2. [x] Zone planning is unit tested: reserved TLD gives a TLD zone, other domains give an exact zone, `*.localhost` is skipped, `*.local` is rejected, nested zones are dropped, output is sorted and stable.
3. [x] Corefile generation is unit tested: loopback bind only, A and AAAA templates per zone, no catch-all.
4. [x] With the real CoreDNS, a registered name gets `127.0.0.1` and `::1`, a subdomain works, and an unregistered name gets REFUSED.
5. [x] `dns sync` adds a new domain to the running server without a restart.
6. [x] The resolver file plan is unit tested. `enable` shows the exact files and asks first, only writes Warren-marked files, refuses to overwrite a foreign file, and `disable` removes only Warren's.
7. [x] CoreDNS runs unprivileged, listens on loopback only, and Ctrl-C leaves no process behind.
8. [ ] After `enable`, the macOS resolver answers for a registered domain (`dns status` end-to-end check), and a browser reaches `https://acme.test` through the proxy with the trusted certificate.

*Verified with the real CoreDNS 1.14.7 download through the `warren` CLI: install with SHA-256, a TLD zone and exact zones, A and AAAA answers, REFUSED for `other.dev` and `google.com`, a domain added with `dns sync` and answered with no restart, a busy port naming the process holding it, loopback-only unprivileged listeners (TCP and UDP), and a clean Ctrl-C. For criterion 6 the full `enable` and `disable` flow ran against a temporary directory: it asked first, wrote the exact files, was idempotent, refused a foreign file without changing anything, rewrote a stale file, and removed only Warren's files. **What was not run is the write to `/etc/resolver` itself and criterion 8**, which need your admin password and a browser. See below.*

## Test plan

Unit tests for zone planning, Corefile generation, and the resolver file plan. Criteria 4, 5 and 7 verified against the real CoreDNS on a high port, recorded in the PR. Criteria 6 (writing) and 8 need an admin password, so they are verified by the user on their own machine.

## Rollout

New files under `~/Warren/bin`, `data` and `run`. The system is touched only by `dns enable` (files in `/etc/resolver`), and `dns disable` undoes it.

## Open questions

- **Do browsers honor the system resolver?** Chrome and Firefox with built-in "Secure DNS" may bypass `/etc/resolver`. Verify with it on and decide whether Warren needs a note or a workaround.
- **VPN and security software** that rewrites DNS can override per-domain resolvers. Check how often, and whether `status` should detect it.
- **Is a zone-per-domain resolver file acceptable** for non-reserved domains, given each one needs a password? A privileged helper (spec 015) would remove that.
- **Footprint.** If 46 MB idle is too much, the hosts-file alternative is the fallback. Decide before accepting.
