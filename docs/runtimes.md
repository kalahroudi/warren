# Runtimes

Warren installs Node, Bun, PHP and Python for the sites that need them, into its own folder. It does not touch nvm, fnm, Volta or your own mise.

Warren uses [mise](https://mise.jdx.dev) to install and remove Node and Bun. It downloads a pinned, checksum-verified copy the first time you install one (about 44 MB).

PHP does not come from mise, which would compile it. Warren downloads its own static PHP builds (`php` and `php-fpm` in one archive), made by the `PHP build` workflow with [static-php-cli](https://github.com/crazywhalecc/static-php-cli) and published as releases of this repository. Each is pinned by SHA-256. Composer is its own pinned download and installs with the first PHP.

Python comes from [uv](https://docs.astral.sh/uv/), a pinned, checksum-verified download of about 14 MB that installs prebuilt Pythons. Warren sets `UV_PYTHON_DOWNLOADS=never` for the sites it runs, so a project's own commands cannot fetch interpreters; only the install action does.

## In the app

Open **Runtimes** in the main window.

- Each runtime lists its installed versions with size and the sites that use each one.
- **Install a version** offers Latest, Long-term support (Node) and a list of other versions.
- **Remove** asks first, and names the sites that use that version.
- **Packages cache** shows the space npm, pnpm, Yarn and Bun downloads use for sites Warren runs. **Clear** is always safe.

A site's page shows what it needs, for example "Node 22, not installed, from .nvmrc", with an **Install** button.

## Which version a site wants

In order, the first that names a runtime wins:

1. `[runtime]` in `.warren.toml`: `node = "22"`.
2. `.nvmrc`, `.node-version`, `.bun-version`, `.php-version`, `.python-version`, `.tool-versions`.
3. `engines.node` in `package.json`, for example `>=18 <23`, or `require.php` in `composer.json`, for example `^8.2`. `config.platform.php` in `composer.json` wins over `require.php`. For Python, `requires-python` in `pyproject.toml`, for example `>=3.10,<3.13`.

A site that names nothing gets nothing installed.

## Command line

```sh
warren runtime list [--json]
warren runtime available node
warren runtime install node@22      # or bun@latest, node@lts
warren runtime remove node@22.23.3
warren runtime which node
warren runtime env <site>           # PATH and cache variables to run a site with
warren runtime install php@8.3      # PHP, php-fpm and Composer
warren runtime composer <site> -- install   # Composer with the site's PHP
warren runtime install python@3.13  # Python, with uv beside it
```

## Where things live

| What | Where |
|---|---|
| Node and Bun | `data/mise` |
| Python | `data/python/<version>` (uv itself in `bin/uv`) |
| PHP and `php-fpm` | `data/php/<version>` |
| Composer | `data/composer` (state in `config/composer`) |
| `php.ini` per PHP minor | `config/php/<minor>`, written once and never overwritten; extra settings go in `conf.d` |
| Downloads and version lists | `cache/mise` |
| npm, pnpm, Yarn, Bun, Composer, uv and pip packages | `cache/packages` |

Everything under `cache` can be deleted at any time.

## Safety

A project's own `mise.toml` is never run. Warren turns off mise's environment, template and script features (`MISE_NO_ENV`), because with mise's defaults a repo's `mise.toml` can run commands the moment mise reads it.

## PHP extensions

The builds include: `apcu bcmath bz2 calendar ctype curl dom exif fileinfo filter ftp gd gmp iconv intl mbstring mysqli mysqlnd opcache openssl pcntl pdo pdo_mysql pdo_pgsql pdo_sqlite pgsql phar posix readline redis session simplexml soap sockets sodium sqlite3 tokenizer xml xmlreader xmlwriter xsl zip zlib`. They are static, so extra extensions cannot be loaded at run time, and Xdebug is not available.
