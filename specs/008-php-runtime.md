# 008 · PHP runtime with FPM and Composer

Status: Draft · Phase 2 · Depends on: 004, 007

## Goal

A PHP site gets a working PHP without the user installing anything. Warren reads which PHP a project asks for, downloads that version into its own folder, and gives the site everything it needs to run: `php`, `php-fpm` (so Caddy can serve it, spec 015) and Composer. The user sees installed PHP versions on the Runtimes page next to Node and Bun, adds or removes versions, and sees their size. Composer downloads share the Warren package cache from 007.

## Non-goals

- Starting `php-fpm` or wiring it to Caddy (spec 015 supervises processes; this spec answers "which binary, which version, which environment").
- Detecting that a folder is a Laravel, WordPress or Symfony project and choosing its start command (spec 010).
- Per-site `php.ini` editing in the UI and Xdebug (later; the design leaves room, see Behavior).
- Changing the user's shell or touching a Homebrew, MAMP or Valet PHP.
- Building PHP ourselves (see Prior art and open question 1).

## App surface

- **Runtimes page**: a PHP card beside Node and Bun, the same way: installed versions with size and the sites using each, a Remove action that names those sites, and an "Install a version" menu (latest patch of each supported minor first). Progress shows in the card, and the install can be cancelled.
- **Composer** is shown as a line on the PHP card ("Composer 2.10.3") and installed together with the first PHP. It is not a separate runtime to manage.
- **Per-site need** on the site's page and grid row: "PHP 8.3 (installed)" or "PHP 8.3 (not installed). Install", one click, no password.
- **Packages cache** card (from 007) now also counts Composer's cache.
- **Setup wizard and popover** unchanged.
- **CLI** (additional): the `warren runtime` commands from 007 accept `php`: `list`, `available php`, `install php@8.3`, `remove php@8.3.12`, `which php`, `env <site>`; plus `warren runtime composer <site> -- <args>` to run Composer with the site's PHP. All with `--json` where 007 has it.
- **MCP** (specs 020 to 022): the same `list_runtimes` (read) and `install_runtime` / `remove_runtime` (approval) tools; PHP needs no new tools.

## Prior art

Surveyed 2026-10-16.

| Option | Verdict |
|---|---|
| **static-php-cli** (MIT, active: last push the day of this survey) and its public builds at `dl.static-php.dev`: self-contained `php` and `php-fpm` binaries for macOS arm64 and Intel, every maintained minor (8.0 to 8.5), kept at the latest patch. Measured: a `cli` or `fpm` archive is 14 MB to download and 41 MB unpacked (`common` set) or 35 MB and 97 MB (`bulk` set); no dylibs, no Homebrew; `php-fpm -v` and `php composer.phar` ran from a throwaway folder. | **Used**, as downloaded binaries pinned by SHA-256, like Caddy. |
| mise `php` (builds from source with `php-build`) | Rejected. Needs a compiler, autoconf, bison and many libraries; a first install takes many minutes and fails on missing build dependencies, which breaks "no manual steps". |
| Homebrew `php` and `shivammathur/php` bottles | Rejected. Bottles are not relocatable: they expect `/opt/homebrew` and dozens of dependent formulae, and using Homebrew would make Warren need it. |
| Laravel Herd-style bundled builds, MAMP, XAMPP | Rejected. Not redistributable as a library; or heavy GUI bundles. |
| Docker `php` images | Rejected for the default path: containers are an optional driver (019). |
| Composer's own phar from `getcomposer.org` | **Used**, pinned by SHA-256, run by Warren's PHP. Composer is not reimplemented and updates by a reviewed pin change. |

Facts found that shape the design:

- The static builds publish no checksum files. Warren pins the hash of each archive it offers, so the offered list is a reviewed table, not a live index. That is the same trust model as Caddy and CoreDNS, and it means a compromised download host cannot change what Warren runs.
- A static `php` looks for its ini in `/usr/local/etc/php` and finds none. Warren passes its own ini folder (`PHPRC` and `PHP_INI_SCAN_DIR`) so nothing outside `~/.warren` is read.
- Neither published set has every extension. `common` has `pdo_sqlite`, `pdo_pgsql`, `pgsql`, `gd`, `zip`, `redis`, `mbstring`, `curl` but not `mysqli`, `intl`, `opcache` or `sodium`. `bulk` has `mysqli`, `intl`, `opcache`, `sodium`, `imagick`, `apcu` but not `pdo_sqlite` or `pdo_pgsql`. Laravel's default (SQLite via PDO) and WordPress (`mysqli`) need opposite sets, so neither build alone covers the popular stacks. See open question 1.

## Behavior

**Offered versions.** A table in `PHPRelease` lists, for each supported minor (8.1 to 8.5, the lines receiving at least security fixes at the time of release), the pinned patch version, the archive URLs and a SHA-256 for arm64 `php`, arm64 `php-fpm`, Intel `php`, Intel `php-fpm`. Older lines can be added by a reviewed change. Updating a patch version is a reviewed change that Warren ships in a normal app update; the user does nothing.

**Install.** Installing `php@8.3` downloads the `cli` and `fpm` archives, verifies each hash (a wrong hash deletes the download and fails), and unpacks to `data/php/<version>/bin/{php,php-fpm}`. Composer is downloaded once to `data/php/composer/<version>/composer.phar`, hash-verified. Installing a version already present does nothing; a cancelled or failed install leaves nothing listed (the folder is built in a temporary name and renamed last).

**Which version a site wants.** In order, extending 007:

1. `[runtime]` in `.warren.toml` (`php = "8.3"`).
2. `.php-version` and `.tool-versions` (`php 8.3.12`), read by Warren.
3. `composer.json`: `require.php` as a range (`^8.2`, `>=8.1 <8.4`, `8.2.*`), using the `VersionRange` matcher from 007 extended with `.*`; and `config.platform.php` when present (it wins, as Composer treats it as the target). Warren picks the newest installed minor that satisfies it, otherwise offers the newest offered minor that does.
4. Nothing: no PHP requirement, nothing installed.

**Running a site.** `RuntimeManager.environment(for:)` (007) gains PHP: `PATH` gets the version's `bin` and Composer's wrapper folder first; `PHPRC` and `PHP_INI_SCAN_DIR` point at `config/php/<minor>/`; `COMPOSER_HOME` and `COMPOSER_CACHE_DIR` point under `cache/packages` and `config/composer`, so nothing is written to `~/.composer`. `composer` on that `PATH` is a two-line wrapper script that runs `php composer.phar`.

**ini.** Warren writes a default `php.ini` on first use per minor (sensible development values: `memory_limit=512M`, `display_errors=On`, `error_reporting=E_ALL`, `date.timezone` from the system, `opcache` settings where the build has it) and never overwrites it, so a user edit survives updates. A `conf.d` folder next to it is scanned for additions (the hook for later per-site settings and Xdebug).

**Removal.** Deleting the version's folder. A version used by a registered site needs confirmation that names those sites. Composer stays until the last PHP is removed.

**Footprint.** Idle: nothing runs. Disk per PHP minor: about 28 MB download and 80 MB unpacked for the `common` set (cli plus fpm); `bulk` roughly 70 MB download and 195 MB unpacked. Composer is about 3 MB. Nothing downloads until a site needs it or the user asks.

## Acceptance criteria

- [ ] 1. Installing PHP verifies each archive's SHA-256; a wrong hash deletes the download and fails (unit test with a fake download).
- [ ] 2. The needed version resolves from `.warren.toml`, then `.php-version` / `.tool-versions`, then `composer.json` (`require.php`, `config.platform.php`), including range forms (unit).
- [ ] 3. `php`, `php-fpm` and `composer` run from the install, with `PHPRC` and `PHP_INI_SCAN_DIR` inside `~/.warren`, and a fake `HOME` stays empty (integration, `WARREN_INTEGRATION=1`).
- [ ] 4. A cancelled or failed install lists nothing as installed (unit with a fake installer; integration cancel).
- [ ] 5. `environment(for:)` for a PHP site has the PHP and Composer first on `PATH` and the ini and Composer variables set (unit).
- [ ] 6. The Runtimes page shows PHP versions with sizes and using sites; Install, Cancel and Remove work from it, and Remove of an in-use version names the sites (running app).
- [ ] 7. The site's page shows "PHP x (installed / not installed)" and its Install button installs it (running app).
- [ ] 8. `composer install` on a small project with a lockfile succeeds using only Warren's PHP, writes its cache under `cache/packages` and nothing under `~/.composer` (integration).
- [ ] 9. A user-edited `php.ini` is not overwritten by a later install or update (unit).
- [ ] 10. The extension set covers the decision in open question 1, checked by listing `php -m` in the integration test.
- [ ] 11. `just check` passes, and `WARREN_DEMO=1` still shows demo content and writes nothing.

## Test plan

- **Unit**: release table shape and hashes present for both architectures; `composer.json` and `.php-version` resolution; range matching for Composer forms; environment building; ini creation without overwrite; install failure paths with a fake downloader.
- **Integration, real downloads** (`WARREN_INTEGRATION=1`, off in CI because of the size): install one PHP, run `php -m`, `php-fpm -t` against Warren's ini, run Composer on a fixture project, cancel an install, fake `HOME` stays empty.
- **Manual in the running app** (6, 7): install from the Sites card and from the Runtimes menu, cancel, remove an in-use version, relaunch.

## Rollout

New state under `data/php`, `config/php`, `config/composer`. Nothing migrates, nothing needs steps on update. Deleting `~/.warren` removes everything.

## Open questions

1. **Which extension set?** The public builds are `common` or `bulk`, and each lacks something a popular stack needs (`pdo_sqlite` and `pdo_pgsql` in bulk; `mysqli`, `intl`, `opcache` in common). Options: (a) offer `bulk` and accept that SQLite-by-PDO projects (Laravel's default) fail until a build with it exists; (b) offer `common` and accept WordPress and Intl-heavy projects fail; (c) Warren builds its own set with static-php-cli in CI and publishes it on GitHub Releases next to the app, hashes pinned as usual. **Recommendation: (c).** static-php-cli is the tool and Warren only chooses the extension list and hosts the output; it makes the table reproducible and the set complete (`pdo_sqlite`, `pdo_pgsql`, `mysqli`, `intl`, `opcache`, `sodium`, `gd`, `zip`, `redis`, `imagick` is optional). The cost is a release workflow (about 20 minutes per build, 5 minors by 2 architectures) and being the party that rebuilds on PHP security releases. If you prefer not to take that on now: start with (a) or (b) and move to (c) before the Add-site flow (011).
2. **Which minors to offer?** Recommendation: 8.2 to 8.5 only (8.1 has no security support left by this release). Older projects can be added by a reviewed change.
3. **Install Composer with the first PHP, or on demand?** Recommendation: with PHP; it is 3 MB and nearly every PHP project uses it.
4. **Xdebug.** A static build cannot load it as a shared extension. Recommendation: out of scope, noted in the docs; revisit if (c) is chosen, since a custom build could include it.
