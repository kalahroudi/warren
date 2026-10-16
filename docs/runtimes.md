# Runtimes

Warren installs Node and Bun for the sites that need them, into its own folder. It does not touch nvm, fnm, Volta or your own mise.

Warren uses [mise](https://mise.jdx.dev) to install and remove versions. It downloads a pinned, checksum-verified copy the first time you install a runtime (about 44 MB).

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
2. `.nvmrc`, `.node-version`, `.bun-version`, `.tool-versions`.
3. `engines.node` in `package.json`, for example `>=18 <23`.

A site that names nothing gets nothing installed.

## Command line

```sh
warren runtime list [--json]
warren runtime available node
warren runtime install node@22      # or bun@latest, node@lts
warren runtime remove node@22.23.3
warren runtime which node
warren runtime env <site>           # PATH and cache variables to run a site with
```

## Where things live

| What | Where |
|---|---|
| Installed runtimes | `data/mise` |
| Downloads and version lists | `cache/mise` |
| npm, pnpm, Yarn and Bun packages | `cache/packages` |

Everything under `cache` can be deleted at any time.

## Safety

A project's own `mise.toml` is never run. Warren turns off mise's environment, template and script features (`MISE_NO_ENV`), because with mise's defaults a repo's `mise.toml` can run commands the moment mise reads it.
