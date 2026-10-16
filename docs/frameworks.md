# Frameworks

Warren looks at a project folder and says what it is and how it starts in development. The Sites page shows it as **Framework** and **Starts with**. Detection only reads a few files (`package.json`, `composer.json`, `pyproject.toml`, `requirements.txt`, lockfiles and a handful of well-known file names). It never runs anything from the project.

## Order

1. `[run] command` in `.warren.toml` always wins. The framework name is still shown.
2. The first framework below that matches, most specific first.
3. If a project has a `dev` or `start` script, that script is used instead of the framework's default command.

## What Warren recognises

| Framework | Identified by | Starts with |
|---|---|---|
| Laravel | `laravel/framework` and `artisan` | PHP-FPM from `public/` (installed with Composer even when a `package.json` is there for assets) |
| Symfony | `symfony/framework-bundle` | PHP-FPM from `public/` |
| WordPress | `wp-config.php` or `wp-content` | PHP-FPM from the project folder |
| Next.js | `next` | the `dev` script, else `next dev` |
| Nuxt | `nuxt` | the `dev` script, else `nuxt dev` |
| Astro | `astro` | the `dev` script, else `astro dev` |
| SvelteKit | `@sveltejs/kit` | the `dev` script, else `vite dev` |
| Remix, React Router | `@remix-run/dev`, `@react-router/dev` | the `dev` script |
| Angular | `angular.json` | the `start` script, else `ng serve` |
| Vite | `vite` | the `dev` script, else `vite` |
| Create React App | `react-scripts` | the `start` script |
| Node.js | a `dev` or `start` script | that script |
| PHP | `index.php` in `public`, `web` or the root | PHP-FPM |
| Django | `manage.py` | `python manage.py runserver` |
| FastAPI | `fastapi` | `uv run fastapi dev` or `python -m uvicorn` |
| Flask | `flask` | `python -m flask run` |
| Python | `main.py` or `app.py` | `python main.py` |
| Static site | `index.html` | served as files |

The package manager is the `packageManager` field in `package.json`, else the lockfile (`bun.lock`, `pnpm-lock.yaml`, `yarn.lock`), else npm.

## Host names

Vite and the frameworks built on it (Nuxt, Astro, SvelteKit, Remix) refuse requests for names they do not know, so `app.test` would show a blocked page. Warren sets `__VITE_ADDITIONAL_SERVER_ALLOWED_HOSTS` to the site's domain. Vite takes one value, so a site with several domains that share an ending gets that ending with a leading dot (`.test`).

## Command line

```sh
warren site detect <site or folder> [--json]
```
