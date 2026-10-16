# Adding a site and the setup plan

**Add site** (the button on the Sites page, `⌘N`, or the menu bar icon's right-click menu) takes a project folder. Warren shows what it found and what it takes to run the project, and changes nothing until you press **Add site**.

## What Warren shows

- **What Warren found**: the framework and how it starts (see [frameworks](frameworks.md)), the runtimes the project needs and whether they are installed, the package manager, and the services the project seems to want.
- **Setup plan**: ordered steps, each *done*, *to do* or *waiting*. Steps that run code that came with the project (install scripts, `artisan`, a project's own setup script) are marked **Runs code from this project**. Running the plan, with approval of each command, arrives with spec 012.
- **Name and domain**: filled from the folder name (`shop` and `shop.test`) and checked as you type. They are stored with the site in Warren. Nothing is written into the project. A `.warren.toml` that sets the same field wins.

After the site is added, the plan stays on its page as a **Setup** card, re-checked against the machine each time the page is opened.

## The steps

| Step | When | Runs project code |
|---|---|---|
| Install a runtime | the project needs one that is not installed. When it names no version, Warren suggests the newest | no |
| Install dependencies | `npm ci` or `npm install`, `pnpm install`, `yarn install`, `bun install`, `composer install`, `uv sync`, or `uv pip install -r requirements.txt` | yes |
| Create `.env` | `.env` is missing and `.env.example` (or `.sample`, `.dist`, `.template`) exists | no |
| Start a service | the env file points at PostgreSQL, MySQL, Redis, Mailpit or MinIO | no |
| Generate the application key | Laravel with an empty `APP_KEY` | yes |
| Create the SQLite database | Laravel with `DB_CONNECTION=sqlite` | no |
| Set up the database tables | Laravel `artisan migrate`, Django `manage.py migrate` | yes |
| Steps the project suggests | `postCreateCommand` in `devcontainer.json`, or a `setup` or `bootstrap` script in `package.json`. Off by default | yes |

*Done* is worked out from the machine each time (is the runtime installed, does `node_modules` or `vendor` exist and is it newer than the lockfile, does `.env` exist), so the plan is right after you run something by hand. Services show *waiting* until the service manager arrives.

## Command line

```sh
warren site plan <site or folder> [--json]
```
