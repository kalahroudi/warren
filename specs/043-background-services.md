# 043 · Background proxy and DNS, and real state in the app

Status: Draft · Phase 1 · Depends on: 004, 005, 006

## Goal

The local HTTPS proxy and DNS server start at login and stay running without a terminal, and the app shows the real site list and the real state of both, instead of demo data. This is the base the setup wizard (spec 044) stands on.

## Non-goals

- No starting or stopping of each site's own dev server (later specs). A site counts as running when something is listening on its `run.port`.
- No services (databases), runtimes, agents or storage in the app. Those screens keep their demo data and say so (see Behavior).
- No privileged helper. Admin actions arrive with the wizard (spec 044).

## Prior art

| Option | Verdict |
|---|---|
| **launchd** (built into macOS): per-user LaunchAgents with `RunAtLoad` and `KeepAlive` give start at login and restart on crash. Driven with `launchctl bootstrap`, `bootout` and `print`. | **Used.** The supervisor already exists, so Warren does not write one. |
| `SMAppService` (Apple's API for registering bundled agents) | The proper route for a signed release. It needs a signed bundle with the plist inside it, so it waits for spec 003. Until then plists live in `~/Library/LaunchAgents`. Revisit when signing lands. |
| A Warren supervisor daemon (`warrend`) for these two tools | Rejected. launchd does the job. `warrend` stays for what launchd cannot do. |
| Homebrew services | Rejected. Requires Homebrew. |

## Behavior

**Launch agents.** Two per-user agents, `dev.warren.proxy` and `dev.warren.dns`, each running the managed binary with the same arguments as the foreground commands, `RunAtLoad` and `KeepAlive` on, output to `~/Warren/logs/<name>.log`. The plist is generated from the same code that builds the foreground command, so the two cannot drift.

**CLI.** `warren proxy start|stop|restart|logs` and `warren dns start|stop|restart|logs`. `start` says exactly what it installs, then writes the plist and starts the agent. `stop` stops it and removes the plist, so nothing starts at the next login. `run` stays as the foreground command for debugging.

**Staying in step with the registry.** Adding or removing a site (CLI or app) applies to the running proxy and DNS server automatically: the proxy reloads and the Corefile is rewritten. A failure is reported, never silent.

**Real state in the app.** A `LiveProvider` implements `StateProvider` (spec 002):

- Sites come from the registry, with their domains, runtime and port. A site shows Running when its port is listening, otherwise Stopped.
- The popover and main window show whether the proxy and DNS server are running.
- Screens whose data does not exist yet (Services, Runtimes, Agents, Storage) keep demo data and carry a visible "Preview" label on the section, so demo numbers are never mistaken for real ones.
- The app picks up registry changes made from the CLI without a restart.

## Acceptance criteria

1. [ ] `proxy start` installs the agent and the proxy runs with no terminal open; `dns start` likewise.
2. [ ] Killing the Caddy or CoreDNS process makes launchd restart it.
3. [ ] The plists set `RunAtLoad`, so both start at login (checked in the plist and with `launchctl print`; the log-out and log-in test is the user's).
4. [ ] `stop` stops the agent and removes the plist, leaving no files and no loaded job.
5. [ ] Output is written to `~/Warren/logs`, and `logs` shows it.
6. [ ] `site add` and `site remove` update the running proxy and DNS server without a manual reload.
7. [ ] The app lists the real registered sites and updates when the registry changes, with no restart.
8. [ ] The app shows the real running state of the proxy and DNS server, and a site's state follows its port.
9. [ ] Preview sections are visibly labelled and the demo data is not shown as real.
10. [ ] Nothing is installed without an explicit `start`.

## Test plan

Unit tests for plist generation and the `LiveProvider`. Criteria 1, 2, 4 to 6 verified against real launchd with the real binaries, recorded in the PR. Criterion 3's reboot check is for the user. Criteria 7 to 9 verified on the running app through the accessibility tree.

## Rollout

Plists under `~/Library/LaunchAgents` and logs under `~/Warren/logs`. `stop` removes them. When signing arrives (spec 003) the agents move to `SMAppService` and the label and arguments stay the same.

## Open questions

- Does `SMAppService` work for an ad-hoc signed development build, or only a properly signed one?
- The bundle identifier and launchd label prefix (`dev.warren`) are placeholders until Warren owns a domain.
- What should the proxy do at login if port 80 or 443 is already taken?
