# Handover

Written 2026-10-21 at the end of a session. Read `AGENTS.md` and `specs/000-process.md` first.

## Where things stand

- `main` is at spec 015 (#29, merged). Specs 001 to 015, 043 and 044 are shipped.
- **Spec 016 (PostgreSQL and MySQL) is a draft: PR #30, branch `spec/016-postgresql-mysql`.** Spec text only, no code. It waits for the user's "approved" (six open questions, each with a recommendation; approving accepts all six).
- Next after 016, in roadmap order: 017 Redis/Mailpit/MinIO, 018 service catalog, 019 container driver, 020 to 022 MCP, 023 to 028 sharing, 029 to 033 storage, 034 to 036 polish, 037 to 042 database tools, 045 app catalog. See `specs/ROADMAP.md`.

## How the user works (keep doing this)

- One spec is one PR. Draft the spec as a draft PR, get "approved", build, get CI green, ask for approval again, then merge.
- Do not merge without approval. Merge with `gh pr merge N --squash --delete-branch --admin`.
- Commits: `git commit -s`, ending with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`. PR bodies end with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
- The gate is `./scripts/check.sh` (format lint, SwiftLint strict, SPDX headers, fixture check, build, tests). swiftformat can rewrite code, so re-check edits after it runs.
- Verify by running the real app and keep the local app on the latest build: `pkill -x Warren; scripts/build-app.sh; open build/Warren.app`.
- Tick acceptance criteria only for what was verified, and say what was not.
- Never reinvent stable tools; record prior art in each spec. App first; CLI and MCP are additional. The popover stays clean and setup notices go in the wizard. No references to other products in code or comments.

## Things to know about this machine

- `~/Warren` is the source checkout (case-insensitive disk), so real state lives in `~/.warren`. `WARREN_HOME` points the app at another state folder.
- `WARREN_OPEN=main|add|setup|popover` opens a window at launch; `WARREN_DEMO=1` shows demo data.
- The screen was locked or off during testing: screenshots fail and synthetic clicks do not register. Accessibility `AXPress` through System Events works for windows and sheets. The popover and status item could not be seen.
- Node 24 is left installed on purpose (the user's `mcpmaster` site is Next.js). Bun, PHP and Python test runtimes were removed.

## Not verified yet (unticked in the specs)

- Spec 015, criteria 10 and 11: the popover Start/Stop control, the Open button, the "Stopped unexpectedly" card for a server that dies after running, the Skip button on the approval sheet, `logs --follow`, `WARREN_DEMO=1`, and the user's own log-out/log-in check (sites should be stopped afterwards; a static site's route stays).
- Spec 014, criteria 8 and 9: the GitHub window UI.
- Also open: trust Undo, README screenshots, and the open questions on a name-constrained CA, the firewall prompt, browser Secure DNS, SMAppService and the bundle id.

## Known gaps handed forward

- The app's 3-second poll shows a site as Running only once its port answers.
- A static site's route persists across reboot through a marker file.
- The first TLS request for a new domain can be slow, because certificates are issued on demand.

## Where the process manager lives (spec 015)

- `Sources/WarrenCore/Processes/`: `ManagedJob` (launchd plists and `JobHost`), `SitePorts`, `StartCommand`, `SiteServing`, `SiteEnvironment`, `SiteProcesses`, `ServiceDriver` (+ `NativeDriver`, which spec 016 builds on).
- Jobs are plists in `<root>/run/`, loaded with `launchctl bootstrap`, not in `~/Library/LaunchAgents`. Labels: `dev.warren.site.<id>`, `dev.warren.php.<id>`, `dev.warren.service.<id>`. `KeepAlive` is off, so a crash stays visible.
- Logs go to `~/.warren/logs/site-<id>.log`. Docs: `docs/running-sites.md`.
- Opt-in real-launchd tests: `WARREN_INTEGRATION=1`.

## Next step

Wait for the user's answer on PR #30. On "approved": do the prior-art survey for the PostgreSQL and MySQL binaries first (license, relocatable, checksums, size, arm64 and x86_64), record it in the spec, then build, using `NativeDriver`. If the user changes an answer, update the spec before any code.
