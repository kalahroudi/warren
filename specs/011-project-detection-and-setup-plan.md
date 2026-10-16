# 011 · Project detection and setup-plan generation

Status: Draft · Phase 3 · Depends on: 004, 007, 008, 009, 010

## Goal

A user picks a project folder in the app and Warren shows, before changing anything, what the project is and what it takes to run it: which runtime to install, which dependencies to install, which env file to create, which services it wants, and which one-time commands (key generation, migrations) it needs. This is the **setup plan**: an ordered list of steps with plain titles, the exact commands, and what is already done. The user can add the site with the plan attached. Running the plan is spec 012.

This spec also builds the first working **Add site** window (the folder source), since the app has no way to add a site today except the CLI.

## Non-goals

- Running any step. 012 runs steps, streams progress and asks for approval of each command.
- Cloning from GitHub (014), starting from a template or blank project (013), and the catalog (045). They feed the same plan later.
- Creating or starting services. The plan names the services a project wants; the service manager (015 to 018) provides them. Until then those steps show as "arrives with the service manager".
- Prompting for secret values (014). The plan lists which variables the project expects to be filled in.
- Compose files. Services declared only in `docker-compose.yml` are noted, not parsed (019 shells out to Compose).

## App surface

- **Add site** window, opened from a "+ Add site" button on the Sites page and from the menu bar icon's right-click menu. For now one source, **Folder**: choose a folder in the standard macOS open panel (or drop one on the window). The mockup's other sources (GitHub, template, blank) appear as disabled entries labelled with the spec that enables them, so the window does not change shape later.
- After a folder is chosen the window shows, without running anything:
  - **What Warren found**: the framework and start command (010), runtimes and whether they are installed (007 to 009), the package manager, env files, and services wanted.
  - **Setup plan**: the steps, each with a title, a one-line detail, and a state: *done*, *to do*, or *waiting* (for example "PostgreSQL: arrives with the service manager"). Steps that run commands show the command, and those that run the project's own code carry the same mark as in the mockup: "runs code from this project".
  - **Name** and **Domain** fields, filled from the folder name (`shop` and `shop.test`). The domain is checked as you type against the registry and the domain rules from 006.
  - A note when the folder is under version control and has no `.warren.toml`: whether Warren needs to write one (see open question 1).
- **Add site** registers the site, and the plan appears on the site's page as a **Setup** card with the same states, re-checked against the machine each time the page opens. "Run setup" on that card is added by 012; until then the card says what is left.
- **Popover** and **wizard** unchanged. An unfinished plan is a state of the site, never a notice.
- **CLI** (additional): `warren site plan <site or folder> [--json]` prints the plan. `warren site add` is unchanged.
- **MCP** (specs 020 to 022): `plan_site` is a read tool returning the same plan. Running a plan is a write tool with approvals (012).

## Prior art

Surveyed 2026-10-16.

| Option | Verdict |
|---|---|
| **Dev Container `devcontainer.json`** (open specification): `postCreateCommand`, `forwardPorts`, `features`. | **Read as a hint.** If a project has one, its `postCreateCommand` is offered as an optional step, off by default. Warren does not run Dev Containers. |
| **`package.json` scripts**: `setup`, `bootstrap`, `db:migrate`, `prisma`-style scripts. | **Read as a hint**, the same way: shown as optional steps, never chosen automatically. |
| **Railpack / Nixpacks** install steps | **Consulted, not used** (see 010): they produce production images. Their choice of install command per package manager is the reference for the table below. |
| **Heroku `app.json`** (`env`, `addons`, `scripts.postdeploy`) | **Considered.** Uncommon outside Heroku templates, so not read in v1. |
| **`.env.example`** and its variants (`.env.sample`, `.env.dist`, `.env.template`) | **Read.** A dotenv file is `KEY=value` lines; Warren needs only the keys, which are empty, and a few values (`DB_CONNECTION=pgsql`). No stable Swift dotenv library exists to reuse, and the part needed is a few dozen lines; if one appears it replaces this. |
| **Procfile**, `Makefile`, `justfile` setup targets | Not read in v1. A project that needs them can say so in `.warren.toml`. |
| **Docker Compose files** | Noted only (019). |

## Behavior

**Input.** A folder, the installed runtimes and services as seen now, and the site's resolved config. Producing the plan reads files and the machine's state; it never runs a command from the project, so it is safe on repositories the user did not write.

**Output.** A `SetupPlan`: the detection (010), the runtime needs (007 to 009), the env summary, the services wanted, and ordered steps. Each `SetupStep` has: a stable id, a kind, a title and detail for people, the command as an argument list (or none, for steps Warren does itself), whether it **runs project code**, its state, and the ids of steps it waits for.

**Steps, in order.** A step appears only when it applies.

1. **Runtime** (one per missing runtime): "Install Node 22". Warren's own download; no project code.
2. **Dependencies**: from the package manager and lockfile.

   | Project | Command |
   |---|---|
   | npm, with `package-lock.json` | `npm ci` |
   | npm, without a lockfile | `npm install` |
   | pnpm | `pnpm install --frozen-lockfile` with a lockfile, else `pnpm install` |
   | Yarn | `yarn install` |
   | Bun | `bun install` |
   | Composer | `composer install` |
   | uv (`uv.lock` or `[tool.uv]`) | `uv sync` |
   | pip (`requirements.txt`) | `uv venv`, then `uv pip install -r requirements.txt` |

   Done when `node_modules`, `vendor` or `.venv` exists and is newer than the lockfile. Runs project code (install scripts), so it needs approval.
3. **Env file**: copy `.env.example` (or a variant) to `.env` when `.env` is missing. Warren itself; no project code. The detail lists the variables left empty, which 014 will prompt for.
4. **Services**: one step per wanted service, from the env file's hints (table below). *Waiting* until the service manager can provide it.
5. **Application setup**: Laravel with an empty `APP_KEY`: `php artisan key:generate`. SQLite projects: create the database file. Runs project code for the first.
6. **Database**: Laravel `php artisan migrate`; Django `python manage.py migrate`. Waits for the database service. Runs project code.
7. **Optional steps found in the project**: `postCreateCommand` from `devcontainer.json`, a `setup` or `bootstrap` script in `package.json`. Off by default, clearly labelled, runs project code.
8. **Site**: register the domain. Done once added.

**Service hints.** From the env file's keys and values (`DB_CONNECTION=pgsql`, `DATABASE_URL=postgres://…`, `REDIS_HOST`, `CACHE_STORE=redis`, `MAIL_HOST`, `AWS_ENDPOINT` or `MINIO_*`):

| Wanted | Evidence |
|---|---|
| PostgreSQL | `DB_CONNECTION` of `pgsql`/`postgres`, or a `postgres://` / `postgresql://` URL |
| MySQL | `DB_CONNECTION` of `mysql`/`mariadb`, or a `mysql://` URL |
| Redis | `REDIS_HOST`, `REDIS_URL`, or a cache, queue or session setting of `redis` |
| Mailpit | `MAIL_MAILER=smtp` with a `MAIL_HOST` that is `mailpit`, `mailhog`, `localhost` or `127.0.0.1` |
| MinIO | `AWS_ENDPOINT`/`AWS_URL` containing a local host, or `MINIO_*` keys |

The table is data in one file with a test per row. Evidence is always shown with the step ("because `.env.example` sets `DB_CONNECTION=pgsql`"), so a wrong guess is visible and can be dismissed.

**State is derived, not remembered.** *Done* comes from the machine each time the plan is built (is the runtime installed, does `node_modules` exist, does `.env` exist), so the plan is right after a manual `npm install` or a half-run setup, and needs no stored progress.

**Name and domain.** Defaults from the folder name. A name that is already a site gets the next free id, as today. The domain must pass the 006 rules and not clash with another site; both are checked live.

**Footprint.** Reading a few files; no process, nothing stored for the plan itself.

## Acceptance criteria

- [ ] 1. A fixture project per row of the dependency table gets the listed command, and `done` once its folder exists (unit).
- [ ] 2. The env step is *to do* when `.env` is missing and an example exists, and *done* otherwise (copying is 012's job); the variables the example leaves empty are listed (unit).
- [ ] 3. Each service hint row produces its step with the evidence text (unit), and a project with no hints produces none.
- [ ] 4. Laravel and Django fixtures get the key and migrate steps, ordered after dependencies and services (unit).
- [ ] 5. Steps that run project code are marked, and Warren's own steps (runtime install, env copy, site registration) are not (unit).
- [ ] 6. Optional steps from `devcontainer.json` and `package.json` appear off by default (unit).
- [ ] 7. Producing a plan runs nothing from the project: a fixture with hostile scripts, a hostile `mise.toml` and a `devcontainer.json` creates no marker files (test).
- [ ] 8. The Add site window opens from the Sites page and the menu bar icon, takes a folder from the open panel, shows detection and the plan, validates name and domain as you type, and adds the site (running app).
- [ ] 9. After adding, the site's page shows the Setup card, and its states change when a dependency folder is created by hand and the page is reopened (running app).
- [ ] 10. `warren site plan` prints the same plan, with `--json` (CLI).
- [ ] 11. `just check` passes, and `WARREN_DEMO=1` still shows demo content and writes nothing.

## Test plan

- **Unit**: planner over fixture folders for each row (dependencies, env, services, application setup, database, optional steps); ordering and `waitsFor`; state derivation against a fake runtime inventory.
- **Safety**: marker-file test for criterion 7.
- **Manual in the running app** (8, 9): add a Next.js-like folder, a Laravel-like folder and a folder with nothing; change the domain; try a clashing domain; create `node_modules` and reopen the page.

## Rollout

New code and one new window. If open question 1 is answered with registry overrides, `sites.json` gains optional `name` and `domains` fields per site, read by older versions as absent (additive, version stays 1).

## Open questions

1. **Where does a custom name or domain chosen in the window live?** Writing `.warren.toml` into the project changes someone's repository, which is wrong for a project they do not own. Recommendation: store overrides in the registry (`config/sites.json`), have `.warren.toml` win when it sets the same field, and only write `.warren.toml` when the user asks ("Save settings to the project"). This amends 004.
2. **Install command for npm without a lockfile.** `npm install` creates a lockfile in the user's repo. Recommendation: accept it and say so in the step's detail.
3. **Optional steps from the project's own scripts.** Recommendation: show them off by default, as above. They are the author's own idea of setup.
4. **Which services does 011 name before 015 to 018 exist?** Recommendation: name them and mark *waiting*; the plan is the contract those specs fill in.
