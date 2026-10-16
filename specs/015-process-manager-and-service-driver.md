# 015 · Process manager: starting sites, and the `ServiceDriver` interface

Status: Draft · Phase 4 · Depends on: 005, 007, 008, 010, 012, 043

## Goal

A site that was added, installed and set up can be **started** from the app, and then it loads at its `.test` address over HTTPS. Start, Stop, Restart and the live log are on the site's page and in the popover. This works for all four kinds of site: a server on a port (Node, Bun, Python), PHP through PHP-FPM, and static files.

The same supervisor is the base for databases and other services (016 to 018), through a small `ServiceDriver` interface that this spec defines and the native driver implements.

## Non-goals

- Databases, Redis and the other services themselves (016 to 018). This spec ships the interface and a native driver tested with a stand-in program.
- Containers (019).
- Hibernation and idle shutdown (031). Sites run until stopped.
- The full Logs window with search and history (034). Here: the last lines, live, and a file.
- Starting sites at login. Sites start when asked.
- Build or production modes. A site runs its development command.

## App surface

- **Site page:** the disabled Start button (043) becomes live. Its state is one of *Stopped*, *Starting*, *Running*, *Stopped unexpectedly*. Buttons: **Start**, **Stop**, **Restart**, **Open** (the site's address in the browser). A **Logs** card shows the last lines live and a "Show in Finder" for the file. When a start fails, the card shows the last lines and a plain one-line cause where Warren recognises it (port taken, command not found, missing dependency), with **Run setup** when the plan has open steps.
- **Popover:** a Start/Stop control on each site row, the only new control. No setup notices (they stay in the wizard).
- **First start of a command Warren has not seen approved** shows the 012 approval sheet with the exact command ("Start `npm run dev`"). Approving can remember the command for that site, as in 012. Commands already approved during setup do not ask again.
- **Port:** nothing to choose. A site whose `.warren.toml` has `run.port` uses it; otherwise Warren picks a free port and keeps it for that site (see Behavior). The site page shows the port as a detail.
- **CLI** (additional): `warren site start|stop|restart <id> [--yes]`, `warren site status [id] [--json]`, `warren site logs <id> [-n N] [--follow]`.
- **MCP** (specs 020 to 022): `list_sites` shows state; `start_site`, `stop_site` and `restart_site` are write tools, approved like plan runs when the command is new. `get_logs` is a read tool. Nothing new is built here for it.

## Prior art

Surveyed 2026-10-16. Record any change after the survey in the PR.

| Option | Verdict |
|---|---|
| **launchd** (already supervises the proxy and DNS in 043): a job per site with `launchctl bootstrap` and `bootout`, working folder, environment and log paths in the plist, and the whole process group stopped on `bootout`. | **Used.** The supervisor exists in the OS, survives the app quitting or crashing, and costs nothing when no site runs. Jobs are bootstrapped from `~/Warren/run/` and are **not** installed in `~/Library/LaunchAgents`, so nothing comes back at the next login. |
| **A process supervisor of our own inside `warrend`** (what 012's executor already does for setup commands) | Rejected for running sites: it would have to outlive the app, restart, and relaunch at login, which is launchd's job. `warrend` stays reserved for what launchd cannot do. 012's executor remains the way to run finite setup commands. |
| **foreman, overmind, honcho, pm2, process-compose** | Rejected: they run a Procfile or a config the project would have to carry, and each needs its own install. Warren already knows each project's command from 010. |
| **PHP-FPM behind Caddy's `php_fastcgi`** | **Used.** Caddy is already the proxy, the FPM binary ships with Warren's PHP (008), and `php_fastcgi` is the documented way to serve PHP from Caddy. Replaces the idea of PHP's built-in server, which is single-process and not what production runs. |
| **Caddy `file_server`** for static sites | **Used.** One more handler in the config Warren already generates. |
| **Port allocation** | Probe with `bind` on a loopback port; no library. A few lines, and the only correct check. |

## Behavior

**Starting.** In order, stopping at the first failure:

1. Resolve the runtime from the site's version files (007 to 009) and build the environment (managed runtimes first on `PATH`, package-cache variables, `.env` untouched). The command comes from `.warren.toml` `[run] command`, else the detected one (010).
2. If the command has not been approved for this site, show the approval sheet.
3. Choose the port (below) and pass it as 010's `PortHandling` says (`PORT`, a flag, or `{port}`). Loopback only: servers are told to listen on `127.0.0.1` where the framework allows it.
4. Write the job plist under `~/Warren/run/site-<id>.plist`: program, arguments, working folder, environment, `StandardOutPath` and `StandardErrorPath` to `~/Warren/logs/site-<id>.log`, `RunAtLoad` on, `KeepAlive` **off** (a dev server that exits because of a syntax error should show the error, not restart in a loop). `bootstrap` it.
5. Update the proxy so the route exists (the proxy skips sites with no port today; it now uses the assigned one), then wait until the port accepts connections, up to 60 seconds (configurable per command later), polling every 250 ms. The state is *Starting* until then.
6. *Running* is derived, not stored: the job is loaded **and** the port accepts connections. The app reads this the same way 043 already does.

**Stopping.** `bootout` the job: launchd stops the whole process group (so `npm run dev`'s child dies with it), with SIGTERM and then SIGKILL after launchd's exit timeout, which is lowered to 5 seconds in the plist. The plist is deleted. Stop is also done when a site is removed from Warren.

**Crashes.** A job that exits on its own moves to *Stopped unexpectedly* with the exit code and last log lines. It is not restarted. **Restart** is Stop then Start.

**Port assignment.** Order: `.warren.toml` `run.port`, else the port kept in `~/Warren/state/ports.json` for this site, else the first free port in 4100 to 4999, remembered. If a kept port is taken by another program, a new one is chosen and remembered. If an explicit `run.port` is taken, the start fails with who holds it (reuse `PortCheck.holder`) and does not pick another, because the user asked for that one. Ports are not reserved while a site is stopped.

**Vite and similar hosts check.** The `.test` host must be allowed: Vite gets `__VITE_ADDITIONAL_SERVER_ALLOWED_HOSTS` with the site's domains (from 010), and Next.js, SvelteKit and Astro get the equivalent where their detection rows say so.

**PHP sites.** One FPM master per started PHP site, bound to a Unix socket in `~/Warren/run/`, run as the user, using the site's PHP version and the ini from 008. The proxy route for the site is `php_fastcgi unix//…/site-<id>.sock` with the detected document root (`public/` for Laravel, the folder otherwise) and `try_files` the way Caddy documents it. FPM runs as a launchd job like any other command, with `pm = ondemand` and a short `process_idle_timeout`, so an idle PHP site holds one master process and no workers.

**Static sites.** No job. The route is `file_server` on the document root with the site's domains. Start and Stop for a static site mean "add the route" and "remove the route": the status is *Running* while the route exists.

**The `ServiceDriver` interface.** For services (016 and later), not for sites:

```swift
protocol ServiceDriver {
    var kind: String { get }                       // "native", later "container"
    func status(of service: ServiceInstance) async -> ServiceStatus
    func start(_ service: ServiceInstance) async throws
    func stop(_ service: ServiceInstance) async throws
    func logs(of service: ServiceInstance) -> URL
    func connection(of service: ServiceInstance) -> ServiceConnection?   // host, port, user, URL template
}
```

`NativeDriver` implements it on the same launchd job code as sites: a service is a program, arguments, a data folder under `~/Warren/data/`, a port, a log file, and a readiness check (a port accepting connections, or a command that exits 0). The catalog (018) supplies those facts as data. The interface carries nothing PostgreSQL-specific. Tests drive it with a stand-in program (a tiny TCP listener written in Python and run with Warren's own uv), since the real servers arrive in 016.

**Fix carried along.** `npm_config_store_dir` is a pnpm setting, and npm warns about it. It is set only when the site's package manager is pnpm.

**Footprint.** Nothing runs in the background of Warren itself. A running site costs what its own process costs; a stopped site costs a few hundred bytes of state. Warren does not poll while no site is starting.

## Acceptance criteria

Each is verified before it is ticked, and the PR says how.

1. [ ] A Node, a Bun and a Python site (blank projects from 013) start from the site page and load at `https://<name>.test` with the trusted certificate.
2. [ ] A Next.js site (real template, 013) starts and loads, including its first page compile and the host check for `.test`.
3. [ ] A Laravel site starts through FPM and shows its welcome page; a plain PHP folder works as well.
4. [ ] A static site loads, and Stop removes its route.
5. [ ] Stop kills the whole process tree (`npm run dev`'s node child included) within 5 seconds, and leaves no job, plist or listener.
6. [ ] A crash (the server exits with an error) shows *Stopped unexpectedly* with the last log lines and is not restarted.
7. [ ] Ports: `run.port` is honoured and a clash names the holder; an unset port gets a free one that is kept across restarts of the site and of Warren.
8. [ ] The first start of an unapproved command asks with the exact command; Skip or Cancel does not start it; an approved one does not ask again.
9. [ ] Quitting Warren leaves running sites running; opening it again shows them as Running.
10. [ ] Nothing starts at login: after a log-out and log-in the sites are stopped and no plist for a site is in `~/Library/LaunchAgents`. (The log-out check is the user's, like 043.)
11. [ ] The popover control, the site page buttons and the Logs card work in the running app, and the popover keeps no setup notices.
12. [ ] `warren site start|stop|restart|status|logs` work, with `--json` for status.
13. [ ] `NativeDriver` starts and stops the stand-in service, reports readiness and a connection, and a second start of a running service is a no-op.
14. [ ] `just check` passes; `WARREN_DEMO=1` still shows demo data.

## Test plan

- **Unit:** plist generation (environment, working folder, log paths, no `KeepAlive`); port selection (explicit, kept, free, taken); the state derivation; Caddy route output for server, PHP and static; the log-line cause matcher; the `ServiceDriver` contract against a fake launch controller.
- **Integration** (`WARREN_INTEGRATION=1`, real launchd and real runtimes): the blank servers and a real Next.js, Laravel and static site, each curled over HTTPS through Caddy; kill-tree timing; crash handling; the stand-in service through `NativeDriver`.
- **Manual in the running app** (1 to 4, 8, 9, 11): the buttons, the popover, the approval sheet, quit and reopen. The log-out/log-in check (10) is the user's.

## Rollout

New code and UI; new folders `~/Warren/run/` and `~/Warren/state/ports.json`. The registry is unchanged. When signing arrives (003) the jobs keep their labels (`dev.warren.site.<id>`). The roadmap row for 015 is renamed to match this spec.

## Open questions

Recommendations first. Decided with the reviewer when approving.

1. **Supervise sites with launchd jobs bootstrapped from `~/Warren/run/`**, not a Warren daemon.
2. **No automatic restart after a crash.** Show the log instead.
3. **PHP and static sites are in this spec**, so that every site kind actually loads. This is the largest part of the PR. The alternative is to split them into a 015b, which delays PHP sites by one spec.
4. **Assign ports in 4100 to 4999** and keep them per site.
5. **Ask once per command** on first Start, using 012's approval and trust. Commands already approved during setup do not ask again.
6. **Sites do not start at login.** A "Start with Warren" setting can come with Settings (035).
