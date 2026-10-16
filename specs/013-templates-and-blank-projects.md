# 013 · Templates and blank projects

Status: Implemented, pending the failed-scaffold check · Phase 3 · Depends on: 007 to 012

## Goal

From the Add site window, a user can start a new project without a terminal in two ways:

- **From a template**: pick Next.js, Vite, Astro, SvelteKit, Laravel or Django from a short list, name it, and Warren runs the framework's own official scaffolder for them, after showing the command and asking.
- **A blank project**: pick a runtime (static site, Node, Bun, PHP, Python) and Warren writes a few small files of its own, with no network and no third-party code.

Either way the folder is created, registered as a site with its domain, and its setup plan runs, so the user ends with a project that is installed and ready to start. Starting it is the process manager (015).

## Non-goals

- Starting the site. Until 015, "created" means files, runtime and dependencies are in place.
- A browsable catalog, search across many starters, or fetching arbitrary repositories (045 and 014). The template list here is short and fixed in code; 045 turns it into data.
- Cloning from GitHub (014).
- Git: the new folder is not made a repository.
- Deleting anything. A failed scaffold leaves the folder for the user to inspect or remove.

## App surface

- **Add site window**, the two sources that are greyed out today become live:
  - **From a template**: a list with a search box (six entries, so the box mainly filters by name). Selecting one shows what it is, the runtime it needs, and exactly what Warren will run, with the line "Downloads and runs *create-next-app* from npm."
  - **Blank project**: a runtime picker, and below it the files you get, listed by name (the mockup's "You get" panel).
  - Both show **Name**, **Domain** (default `<name>.test`) and **Location** (default `~/Sites`, changeable with the open panel), checked as you type: the folder must not exist or be empty, the name must be a valid folder name, the domain must be free (006 rules).
  - Buttons: **Cancel** and **Create site**.
- **Create site** makes the folder, registers the site, closes the window and opens the site's page, where the Setup card runs the work with live progress. For a template that is two runs: first the scaffold (a runtime if one is missing, then the scaffolder, with the approval sheet from 012), then the normal setup plan (dependencies, `.env`, and so on), which asks again for its own commands. A blank project has only the second run, and for static sites nothing to install.
- **Location** `~/Sites` is created if missing. Nothing is written outside the chosen folder.
- **Popover** unchanged.
- **CLI** (additional): `warren template list [--json]`, `warren site new <template> <name> [--location <folder>] [--domain <name>] [--yes]` and `warren site new --blank <static|node|bun|php|python> <name> …`.
- **MCP** (specs 020 to 022): `create_site` is a write tool and goes through the same approval as running a plan.

## Prior art

Surveyed 2026-10-16.

| Option | Verdict |
|---|---|
| **The frameworks' own scaffolders**: `create-next-app`, `create-vite`, `sv create` (SvelteKit), `create-astro`, `composer create-project laravel/laravel`, `django-admin startproject`. | **Used**, run as they are. They are maintained by the framework authors, so Warren keeps no copy of their files and stays current by running the latest. Each runs non-interactively with flags, listed below. |
| **giget / degit** (download a template folder from a Git host) | Not used in this spec. They are for repository templates, which belong to the catalog (045), where they are the first choice to evaluate. |
| **Vercel's template gallery** | Catalog material (045). |
| **Yeoman, Plop, cookiecutter** | Rejected: a second templating system on top of the ones every framework already ships. |
| **Writing files ourselves** | Only for blank projects, where nothing existing does the job: a handful of files per runtime, each under thirty lines. |

Commands, each confirmed by running it with Warren's own runtimes in `TemplateIntegrationTests` (flags change between versions, so each is a table row with a test). Two needed more than the first guess: `sv create` waits on an add-ons prompt and then exits 0 having created nothing unless given `--no-add-ons`, and `composer create-project --no-install` still runs the post-create script `php artisan key:generate`, which fails without `vendor/`, unless given `--no-scripts`. `uvx` is not in the uv archive Warren installs, so `uv tool run` stands in:

| Template | Runtime | Command, run in the new empty folder |
|---|---|---|
| Next.js | Node | `npx create-next-app@latest . --yes --skip-install` |
| Vite (React, TypeScript) | Node | `npm create vite@latest . -- --template react-ts` |
| Astro | Node | `npm create astro@latest . -- --template minimal --no-install --no-git --yes` |
| SvelteKit | Node | `npx sv create . --template minimal --types ts --no-add-ons --no-install` |
| Laravel | PHP, Composer | `composer create-project laravel/laravel . --no-install --no-scripts --no-interaction` |
| Django | Python, uv | `uv tool run --from django django-admin startproject config .` (with a `requirements.txt` containing `django` written beside it first) |

## Behavior

**Creating.** In order, stopping at the first failure:

1. Validate name, location and domain. Create the empty folder.
2. Register the site (`SiteRegistry.add` with the name and domain, 011).
3. Run the **scaffold plan**: a synthetic `SetupPlan` of a runtime step if needed and one command step whose working folder is the new folder and whose command is the template's. The command step is marked *runs project code* and *third party* (it fetches and runs a package), so the 012 approval sheet shows it with that wording and never runs it unasked. Trust applies only to commands the user has seen.
4. On success, build the normal plan for the folder (011), now that the project exists, and run it. The user sees the same approval sheet for its commands.

A blank project skips step 3 and instead writes its files in step 1.

**Blank projects.** Warren writes these files, each short and commented, plus a `.warren.toml` with `[runtime]` (the runtime, `lts` or `latest`) and `[run] command` where the project has a server. They read the port from `PORT` and listen on `127.0.0.1`.

| Kind | Files |
|---|---|
| Static site | `index.html` |
| Node | `server.js` (node:http "hello"), `package.json` with a `dev` script |
| Bun | `server.ts` (`Bun.serve`), `package.json` with a `dev` script |
| PHP | `public/index.php` |
| Python | `app.py` (stdlib http.server "hello"), no dependencies |

**Folder rules.** The name becomes the folder name: letters, digits, `-`, `_` and `.`, not starting with a dot, at most 64 characters. A folder that exists must be empty (a `.DS_Store` does not count). Creation never overwrites.

**Scaffold plan and the setup plan.** The scaffold plan is built by `TemplatePlanner`, a small function over the table above, and executed by the 012 runner unchanged. Because the folder exists and is registered first and the scaffolders take `.` as the target, the runner's working folder is already right; no per-step working folder was needed. No new execution path.

**Failure.** The step fails like any other: the card shows the last lines, the log is kept, and Run again retries. The registered site stays, so the user can retry or remove it; the folder is never deleted.

**Footprint.** Nothing runs in the background. Templates are a table in code; blank files are string literals.

## Acceptance criteria

Checked means verified. How is in each line.

- [x] 1. Name, location, domain and folder rules are enforced with a message for each failure (`NewProjectTests`: invalid and empty names, non-empty folder, `.DS_Store` allowed, location a file, location not writable, taken, invalid and reserved domains).
- [x] 2. Each blank kind writes exactly its listed files and a `.warren.toml` that resolves to the right runtime and is detected as the right framework (`NewProjectTests`), and the Node, Bun, Python and PHP servers answer `GET /` with Warren's own runtimes (`BlankProjectIntegrationTests`). The static site is a single HTML file and was not served.
- [x] 3. Each template's command runs to completion non-interactively with Warren's own runtimes and produces a project that detection names correctly (`TemplateIntegrationTests`: Next.js, Vite, Astro, SvelteKit, Laravel, Django; two commands needed extra flags, see Prior art).
- [x] 4. The scaffold step is marked as running project code and third-party, is never run without approval, and runs in the new folder (`NewProjectTests.theScaffoldPlanNeedsApprovalIsThirdPartyAndRunsInTheNewFolder`).
- [x] 5. After a successful scaffold the normal setup plan is built from the new project and run, with its own approval (running app: Next.js created, then `npm install` asked separately and ran).
- [ ] 6. A failed scaffold leaves the registered site and the folder, shows the failure, and Run again retries. Not exercised: the failure path is the same runner behaviour as a failed install (012), but I did not break a scaffold on purpose.
- [x] 7. The Add site window creates a blank project and a template project end to end (running app). A Next.js project from the template pane: name typed, domain filled in, approval sheet worded for third-party code, scaffold, second sheet, `npm install`, plan complete. A blank Node project from the blank pane: the files listed, created, `npm install` asked. Not exercised in the window: the search box, the location chooser, and a clashing or invalid name on screen.
- [x] 8. `warren template list` and `warren site new` work (CLI run by hand: a static project, a Node project with `--yes` that installed Node and ran `npm install`, and the unknown-template, bad-name and non-empty-folder errors).
- [x] 9. `just check` passes (253 tests). `WARREN_DEMO=1` was not run again for this spec.

## Test plan

- **Unit**: validation; blank file sets; `.warren.toml` round trip; `TemplatePlanner` output for each row; approval and working-folder behaviour with the fake executor; creation order and failure paths.
- **Integration** (`WARREN_INTEGRATION=1`, real downloads, off in CI): every template row against an empty folder with Warren's Node, PHP or Python, then detection; the blank servers answering on a port. About one to two minutes each; the Laravel and Next.js rows are the largest downloads.
- **Manual in the running app** (7): create one blank and two template projects, a clashing domain, a non-empty folder, a failing scaffold (offline).

## Rollout

New code and UI only. No state changes. Templates are fetched at run time, so they are never stale.

## Open questions

Decided with the reviewer when approving.

1. **Run `@latest`** and rely on the per-template integration test as the early warning.
2. **Two approval sheets** for a template.
3. **Scaffolders do not install dependencies**; Warren's plan does.
4. **The template list is a Swift table** until the catalog (045).
5. **No `git init`** for new projects.
