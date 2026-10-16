# Starting a new project

**Add site** has two sources for projects that do not exist yet. Both create a folder, register it as a site, and run its setup plan.

## From a template

Pick a starter, give it a name, and Warren runs the framework's own scaffolder in the new empty folder. Warren keeps no copy of the files, so you always get the current version.

| Starter | Needs | Runs |
|---|---|---|
| Next.js | Node | `npx create-next-app@latest . --yes --skip-install` |
| Vite + React | Node | `npm create vite@latest . -- --template react-ts` |
| Astro | Node | `npm create astro@latest . -- --template minimal --no-install --no-git --yes` |
| SvelteKit | Node | `npx sv create . --template minimal --types ts --no-add-ons --no-install` |
| Laravel | PHP, Composer | `composer create-project laravel/laravel . --no-install --no-scripts --no-interaction` |
| Django | Python, uv | `uv tool run --from django django-admin startproject config .` |

The scaffolder downloads and runs a package from the internet, so Warren shows the command first, marked as such, and asks before it runs. Scaffolders are told not to install dependencies or run their own post-install scripts; Warren's setup plan does that next, with its own approval, so it uses the shared package cache.

## Blank project

A few short files Warren writes itself, with no network: a static site (`index.html`), Node (`server.js`), Bun (`server.ts`), PHP (`public/index.php`) or Python (`app.py`). The servers read their port from `PORT` and listen on `127.0.0.1`. A `.warren.toml` pins the runtime.

## Name, domain and location

The name becomes the folder name (letters, digits, `-`, `_` and `.`, not starting with a dot, up to 64 characters). The domain defaults to `<name>.test`. The location defaults to `~/Sites` and is created if missing. The folder must not exist or be empty, and Warren never overwrites anything. If the scaffolder fails, the folder and the site stay so you can look at the log and run it again.

## Command line

```sh
warren template list [--json]
warren site new <template> <name> [--location <folder>] [--domain <name>] [--yes]
warren site new --blank <static|node|bun|php|python> <name> [--location <folder>] [--domain <name>] [--yes]
```

`--yes` approves the commands after printing them. `WARREN_SITES` changes the default location (for tests).
