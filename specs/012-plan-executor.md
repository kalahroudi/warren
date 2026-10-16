# 012 · Plan executor, progress events, command approvals

Status: Implemented, pending the UI choices below · Phase 3 · Depends on: 007 to 011

## Goal

The Setup card on a site (and the Add site window) gets a **Run setup** button. Warren works through the plan: installs the runtimes, creates `.env`, installs dependencies, generates the key, runs migrations, with live progress, a log for each step, and a stop button. Anything that runs code that came with the project asks first, showing the exact command. A failed step says what failed and what to do, and running again continues where it stopped.

## Non-goals

- Starting the site or services, picking ports, routing the domain (spec 015 and the services specs). Steps waiting on a service stay *waiting*.
- Prompting for secret values in `.env` (014). The executor copies the example and reports the variables still empty.
- Cloning, templates, the catalog (013, 014, 045). They end by handing a folder to this executor.
- Sandboxing project code. The approval is the control; the commands run with the user's privileges, like running them in a terminal.

## App surface

- **Run setup** on the Setup card, and on the Add site window after "Add site" (add, then run in one flow). While running, each step shows a spinner, a one-line live status, and a **Log** disclosure with the last lines of its output. **Stop** ends the run; the running command and the processes it started are stopped.
- **Approval sheet**: before the first step that runs project code, a sheet lists those steps with their exact commands and working folder, and the words "These run code that came with this project." The buttons are **Run these commands**, **Skip these steps** and **Cancel**. Approval holds for this run only. Choosing a step's checkbox off skips just that step.
- **Trust this project** (a checkbox on the sheet, off by default): for a folder the user wrote. A trusted site runs its plan commands without the sheet next time. It is stored per site, shown on the site page with a **Stop trusting** button, and never applies to a command that is not in the plan (for example one added after a `git pull` changes `devcontainer.json`: such a step asks again, since its command text is new).
- **Results**: a finished step shows a check, a failed one shows the last lines of output and a **Run again** button. The summary at the end says what is done and what is waiting.
- **Optional steps** from the project (`postCreateCommand`, `setup` scripts) show as unchecked rows on the sheet.
- **Popover** unchanged apart from a spinner on a site that is being set up.
- **CLI** (additional): `warren site setup <site>` runs the plan in the terminal and asks `[y/N]` for each command that runs project code; `--yes` approves them all (the flag is the user's own explicit consent). `--dry-run` prints what would run.
- **MCP** (specs 020 to 022): `run_setup` is a write tool. It never carries its own approval: the app shows the sheet and the tool waits for the user's decision, as every write tool will.

## Prior art

Surveyed 2026-10-16.

| Option | Verdict |
|---|---|
| **VS Code Workspace Trust**: a folder opens in a restricted mode until trusted; trust is per folder and remembered. | **Adopted as the model for "Trust this project"**, but narrowed: trust covers only the plan's commands as they were shown, never a command whose text changed. |
| **Dev Containers lifecycle commands** (`postCreateCommand` and friends). | Already read as optional steps (011); run through the same sheet. |
| **GitHub Actions / CI runners** | No: they assume a disposable machine. This runs on the user's own Mac. |
| **Task runners** (`just`, `mise run`, `make`) | Not used. Plan steps are an argument list Warren already knows, so no task runner adds anything, and a project's `mise.toml` tasks must not run (007). |
| **Foundation `Process`**, with a new process group per step | **Used**. Warren already wraps it (`Shell.stream`); the executor adds a process group so stopping a step also stops what `npm` or `composer` started. |
| **pnpm and Yarn availability**: Corepack ships with Node up to 24 only; mise installs both as tools (verified: `mise install pnpm@9.15.0` took 20 s and 61 MB, ran `pnpm --version` with no Node installed; `ls-remote` lists `yarn` 4.18). | **mise**, the tool Warren already manages for Node and Bun, honouring the version in `packageManager` when present. |
| Pseudo-terminals for pretty output | Not used. Piped output is what logs need, and tools print plain progress when not on a terminal. |

## Behavior

**What runs.** The plan's steps, in order, each only when it is on by default (or ticked), not *done*, and not *waiting*. A step waits for the steps in `waitsFor`; if one fails, the steps that depend on it are skipped and shown as such.

**Warren's own steps** run in-process and never need approval:

- *Install a runtime*: `RuntimeManager.install`, with its progress lines.
- *Install pnpm / Yarn* (new step before dependencies when the project uses them and they are not installed): `mise install pnpm@<version>`, the version from `packageManager` or the latest. Installed into Warren's folder, put on the step's `PATH`.
- *Create `.env`*: copies the example, never overwrites an existing file, and reports which variables are empty.
- *Create the SQLite file*: creates the empty file and its folder.
- *Add the site*: registers it if it is not yet (in the Add site flow).

**Project-code steps** run the plan's argument list as a process, not through a shell (except a `devcontainer.json` string, which is `/bin/sh -c` as the project wrote it):

- Working folder: the project.
- Environment: the site's runtime environment (007 to 009: runtimes first on `PATH`, shared package caches, uv and PHP settings), plus `CI=1` (tools do not prompt), `NO_COLOR=1`, `COMPOSER_NO_INTERACTION=1`, `npm_config_yes=true`, `DEBIAN_FRONTEND=noninteractive`. Warren's own secrets, if any ever exist, are never passed.
- Standard input is closed, so a command that asks a question fails instead of hanging.
- New process group; **Stop** sends `SIGTERM` to the group, then `SIGKILL` after five seconds.
- Output is read as lines, kept in memory for the live view (last 200 lines per step) and appended to `logs/setup/<site>/<step>.log`. A log is replaced by the next run of that step.
- No time limit by default (installs are slow). The user stops it.

**Events.** The executor reports `PlanRunEvent`s to a callback (the app hops them to the main thread): `awaitingApproval(steps)`, `stepStarted`, `output(step, line)`, `stepFinished(step, result)` where the result is *done*, *failed(exit code, last lines)*, *skipped(reason)* or *cancelled*, and `finished(summary)`. The app, the CLI and (later) MCP all consume the same stream.

**Completion memory.** Some steps cannot be checked from files (migrations). After such a step succeeds, Warren records it in `config/setup-runs.json` (site id, step id, the exact command, date), and the planner treats it as *done* while the recorded command matches. The Setup card has **Run again** on any step. Deleting the site's record or changing the command makes it *to do* again.

**Failure.** The step stops, its dependents are skipped, and the card shows: the step, the exit code, the last 20 lines, the log path, and a plain next action when the failure matches a known pattern (command not found: the runtime is missing; permission denied; `EADDRINUSE`; network unreachable). Running again re-plans from the machine's real state, so completed steps are not repeated.

**Trust record.** A site's trust is `trustedCommands`, the exact argument lists the user saw, in the registry's per-site fields (additive, like name and domain in 011). A run asks again when the plan contains a project-code command that is not in that list.

**Footprint.** No background work: the executor exists only while a run is in progress.

## Acceptance criteria

Checked means verified. How is in each line.

- [x] 1. Steps run in plan order, skip *done*, *waiting*, unticked, site and service steps, and respect `waitsFor`; a failure skips dependents and continues independent steps (`PlanRunnerTests`, fake executor).
- [x] 2. No project-code step runs without approval; Warren's own steps run without it (`PlanRunnerTests`: the approval callback is asked exactly for the marked steps; declining runs nothing).
- [x] 3. Approval holds for one run unless the site is trusted, and a trusted site asks again for a command whose text is not in its trust record (`PlanRunnerTests.trustedCommandsAreNotAskedAboutAgainButAChangedCommandIs`).
- [x] 4. A command runs as an argument list in the project folder, with the given environment, stdin closed, and `CI=1` (`ProcessGroupTests` with real processes; `PlanRunnerTests.commandsGetTheNonInteractiveEnvironment`). Found while testing: a parent that ignores SIGTERM or SIGPIPE passes that on to the command, so the executor resets every signal to its default.
- [x] 5. Stop ends the command and the processes it started (`ProcessGroupTests.stoppingEndsTheCommandAndTheProcessesItStarted`, and in the running app: Stop during a 77-second `postinstall` left no `sleep` behind).
- [x] 6. Output reaches the event stream line by line and is written to the step's log (`ProcessGroupTests`, `PlanRunnerTests.eachStepWritesItsLog`).
- [x] 7. `.env` is copied without overwriting, and the SQLite file is created (`PlanRunnerTests`).
- [x] 8. A successful migration is *done* in the next plan, and *to do* again if its command changes (`PlanRunnerTests.aSuccessfulMigrationIsRememberedUntilItsCommandChanges`).
- [x] 9. pnpm is installed through mise and found by the next step (`PlanIntegrationTests`, real mise, `WARREN_INTEGRATION=1`). Yarn uses the same code path and was not run separately.
- [ ] 10. The Setup card shows Run setup, the approval sheet, live progress, a failure, Run again, and Stop (running app). Verified: Add and run setup opened the approval sheet with the exact command; approving ran a real Node install and `npm ci` to "Done."; a failing `postinstall` ended with "1 step failed"; Stop ended a long step and left no process. Not exercised: the sheet's Skip and Cancel buttons, the trust checkbox and Stop trusting, the Run setup button on an existing site's card (only the Add-and-run path), and what the step rows look like (my accessibility scripts cannot read their text).
- [x] 11. `warren site setup` asks per command, honours `--yes` and `--dry-run`, and exits non-zero on failure or when steps were skipped (run by hand against real Node and a failing project).
- [x] 12. `just check` passes (230 tests). `WARREN_DEMO=1` was not run again for this spec.

## Test plan

- **Unit** (fake runner): ordering, skipping, dependents on failure, approval calls, trust record, completion memory, `.env` and SQLite steps, event sequence.
- **Integration** (real processes, no network): commands through `/bin/sh` fixtures for environment, working folder, stdin, output, log file, stop with children. A real `mise install pnpm` under `WARREN_INTEGRATION=1`.
- **Manual in the running app** (10): a throwaway Node project with a dependency-free `package.json` (so `npm install` needs no network beyond npm itself), a project whose `postinstall` fails, Stop during a long step, the approval sheet's three choices, trust and un-trust.

## Rollout

New state: `config/setup-runs.json`, `logs/setup/`, and an optional `trustedCommands` list per site in `sites.json` (additive, version stays 1). Nothing migrates.

## Open questions

Decided with the reviewer when approving.

1. **Trust this project** is included, off by default, narrowed to the commands shown.
2. **pnpm and Yarn** come through mise.
3. **Output** is piped lines, not a terminal.
4. **No time limit** per step; Stop is always available.
5. **`--yes`** on the CLI approves every command, after printing them.

## Notes from the build

- A run counts as succeeded only if nothing failed, was stopped or was skipped, so declining the approval is not reported as success.
- `npm ci` on a project with no dependencies creates no `node_modules`, so the dependency step stays *to do* for such a project.
- Every site gets `npm_config_store_dir` (pnpm's setting) from 007, and npm prints a warning about it. Harmless; to be tidied by setting it only for pnpm sites.
