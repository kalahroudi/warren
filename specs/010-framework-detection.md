# 010 · Framework detection and start commands

Status: Draft · Phase 2 · Depends on: 004, 007, 008, 009

## Goal

Warren looks at a project folder and says what it is and how to run it: "Next.js, starts with `npm run dev`", "Laravel, served by PHP-FPM from `public/`", "Django, `python manage.py runserver`". The Sites page shows this instead of "Unknown". The answer is a plain data structure that later specs use: the service manager (015) runs the command, and the Add-site flow (011 and 012) builds a setup plan from it.

## Non-goals

- Starting, stopping or supervising anything (spec 015).
- Installing dependencies or running setup commands (011 and 012, with consent).
- Proposing services or environment variables for a project (011).
- Choosing or installing runtimes. 007 to 009 already read the version a project names; detection does not add runtime requirements.
- Production build plans. Warren runs development servers.

## App surface

- **Sites page**: the "Framework" line shows the detected framework ("Next.js", "Laravel", "Static site") instead of "Unknown", and a new "Starts with" line shows the command, or "Served by PHP-FPM from `public/`" for PHP, or "Served as static files". When a site's `.warren.toml` sets `[run] command`, the line shows that command and says "from .warren.toml".
- **Nothing to configure.** A wrong guess is fixed by a `[run]` command in `.warren.toml`, which always wins. The site page offers no editor for it in this spec; an editor belongs with the Add-site flow.
- **Popover and wizard** unchanged.
- **CLI** (additional): `warren site detect <site or folder> [--json]` prints what Warren sees. `site show` includes it.
- **MCP** (specs 020 to 022): `get_site` includes the detection. It is read only.

## Prior art

Surveyed 2026-10-16.

| Option | Verdict |
|---|---|
| **Railpack** (Railway; MIT; 0.42.0, pushed the day of this survey; 8 MB macOS binary). `railpack info --format json` detects the provider and some frameworks (`phpFramework: laravel`) and resolves runtime versions. | **Not used**, after trying it on Next.js, Vite, Laravel and Django fixtures. Its output is a production container plan: start commands are `npm run start`, `/start-container.sh` and `caddy run` for a static build, with apt packages and Docker base images. It has no development command, no port handling and no notion of a dev server. Its detection rules are still a useful reference for what to recognise. |
| **Nixpacks** (MIT; pushed 2026-10-02) | Rejected for the same reason: production image plans. |
| Cloud Native Buildpacks | Rejected: container images again, and they need Docker. |
| `package.json` `scripts`, `composer.json` `scripts`, lockfiles | **Used directly.** A project's own `dev` script is the best statement of how to run it, and no tool can know better. |
| Each framework's own CLI (`next dev`, `vite`, `php artisan serve`, `manage.py runserver`) | **Used** as the commands Warren runs; Warren does not wrap or reimplement them. |

So Warren keeps a small detector. What it keeps is deliberately little: a table of frameworks (data, in one file), each with the files and dependencies that identify it, the command for a development server, and how to tell that server which port to use. The table is new code because no existing tool answers "how do I start this in development", and it is regenerable from Railpack's and the frameworks' documentation.

## Behavior

**Input.** A folder (and its resolved `.warren.toml`). Nothing outside the folder is read. Detection only reads a few small files and never runs anything, so it is safe on repositories the user did not write.

**Output** (`FrameworkDetection`):

- `framework`: id and display name (`next`, "Next.js"), or `nil`.
- `kind`: `server` (a process listens on a port), `php` (served by PHP-FPM, spec 015), `static` (files served directly), or `unknown`.
- `command`: the development command, such as `npm run dev`, and where it came from (`.warren.toml`, the `dev` script, or the framework's default).
- `packageManager`: npm, pnpm, Yarn, Bun, Composer or uv/pip, from the lockfile or `packageManager` in `package.json`.
- `portHandling`: how the server is told its port: an environment variable (`PORT`), a flag appended to the command (`--port 5173`), or fixed (the framework ignores both, and the proxy follows the port it reports).
- `documentRoot` for `php` and `static` kinds (`public`, `web`, `.`).
- `notes`: things to tell the user, for example "Vite blocks unknown host names; Warren allows this site's domain".

**Order.** `[run] command` in `.warren.toml` first (kind `server`, framework still detected for display). Then the first framework in the table that matches, checked most specific first. Then generic fallbacks: a Node project with a `dev` or `start` script, a PHP project with `index.php`, a Python project with `manage.py`, `app.py` or `main.py`, a folder with `index.html`. Then `unknown`.

**Frameworks in this spec.**

| Framework | Identified by | Command | Port |
|---|---|---|---|
| Next.js | `next` dependency | `<pm> run dev` (script) else `next dev` | `PORT` |
| Nuxt | `nuxt` dependency | `dev` script | `PORT` |
| Astro | `astro` dependency | `dev` script | `--port` |
| SvelteKit | `@sveltejs/kit` | `dev` script | `--port` |
| Remix and React Router | `@remix-run/dev` or `@react-router/dev` | `dev` script | `--port` |
| Angular | `angular.json` | `ng serve` through the `start` script | `--port` |
| Vite (React, Vue, Svelte, plain) | `vite` dependency | `dev` script | `--port` |
| Create React App and similar | `react-scripts` | `start` script | `PORT` |
| Express, Fastify, Hono, Koa (generic Node) | a `dev` or `start` script | that script | `PORT` |
| Laravel | `laravel/framework` and `artisan` | PHP-FPM, root `public` | none |
| Symfony | `symfony/framework-bundle` | PHP-FPM, root `public` | none |
| WordPress | `wp-config.php` or `wp-content` | PHP-FPM, root `.` | none |
| Generic PHP | `index.php` (in `public`, `web` or the root) | PHP-FPM | none |
| Django | `manage.py` and `django` dependency | `python manage.py runserver 127.0.0.1:<port>` | argument |
| FastAPI | `fastapi` dependency | `uv run fastapi dev --port <port>` (or `python -m uvicorn`) | `--port` |
| Flask | `flask` dependency | `flask run --port <port>` | `--port` |
| Static site | `index.html` | files served directly | none |

Rows are data in one Swift file with a test per row, so adding a framework is a table entry and a fixture.

**Dev-server host checks.** Vite 5.4.12 and later reject requests whose `Host` is not `localhost` unless the name is allowed, so a site at `app.test` would show a blocked page. For Vite-based frameworks the detection records an environment variable (checked against a real Vite in the build) that allows the site's domains, and a note. Other servers that do host checking (Angular's `--allowed-hosts`, Next.js `allowedDevOrigins`) are listed in `notes` with the setting, and are the known cases this spec handles by environment or flag where one exists.

**Performance.** Reading a handful of files, under a millisecond. The result is computed when the Sites page loads, not stored, so it is never stale.

**Footprint.** No process, no disk beyond the code.

## Acceptance criteria

- [ ] 1. Each framework row identifies a fixture project, and a project matching none is `unknown` (unit, one fixture per row).
- [ ] 2. `[run] command` in `.warren.toml` overrides the command and leaves the framework name (unit).
- [ ] 3. The package manager comes from the lockfile or `packageManager` (unit).
- [ ] 4. A project's own `dev` script is used in preference to the framework default (unit).
- [ ] 5. Detection reads files only: a fixture containing scripts, `postinstall` hooks and a hostile `mise.toml` runs none of them (test that creates marker files).
- [ ] 6. The Sites page shows the framework and the "Starts with" line for registered sites, and "Unknown" only when nothing matched (running app).
- [ ] 7. `warren site detect` prints the same result, with `--json` (CLI run by hand).
- [ ] 8. The Vite host allowance works: a real Vite dev server started by hand with the variable answers a request for `app.test` (manual, recorded in the PR).
- [ ] 9. `just check` passes, and `WARREN_DEMO=1` still shows demo content.

## Test plan

- **Unit**: a fixture folder per framework row and per fallback; ordering conflicts (Next.js with `vite` in devDependencies, Laravel with a `package.json`, WordPress with a root `index.php`); package manager precedence; `.warren.toml` override.
- **Safety**: marker-file test for criterion 5.
- **Manual with a real dev server** (8): install Vite with Warren's Node, start it with the variable, request it with a custom `Host`.
- **Manual in the running app** (6): register a Next.js-like and a Laravel-like folder and read the Sites page.

## Rollout

No state, no migration. The line appears on update.

## Open questions

1. **Own table or Railpack's detection as a hint?** Recommendation: own table, as the prior art shows. Railpack could be revisited if it grows a development mode.
2. **Where does the table live?** Recommendation: a Swift file now, moved to repo data when the service catalog (018) sets the format, so both catalogs share a loader.
3. **Frameworks beyond the list** (Rails, Go, Rust, .NET, Java). Recommendation: out for now; Ruby and Go arrive with their runtimes. They fall back to `[run] command`.
4. **Should detection suggest a runtime?** Recommendation: no here; the Add-site flow (011) reads the detection and the version files together and proposes.
