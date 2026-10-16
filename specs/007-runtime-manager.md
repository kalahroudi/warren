# 007 · Runtime manager: Node and Bun, plus shared package caches

Status: Implemented, pending the cancel button check · Phase 2 · Depends on: 004, 043, 044

## Goal

A site that needs Node or Bun gets the right version without the user installing anything. Warren reads which version a project asks for, installs it on demand into its own folder, and runs the project with it. The user sees installed runtimes, adds or removes versions, and sees how much space each takes, all in the app. Package downloads (npm, pnpm, Yarn, Bun) land in one Warren-owned cache, so the space they use is visible and reclaimable (spec 030).

## Non-goals

- PHP and Python (specs 008 and 009 reuse this design).
- Starting or supervising site processes (spec 015) and deciding the start command (spec 010). This spec only answers "which binary, which version, which environment".
- Changing the user's shell. Warren never edits shell profiles or touches existing nvm, fnm, Volta or mise installs.
- Deno and other runtimes. The design allows them; they are not built here.

## App surface

- **Runtimes page** (replaces the preview content). One card per runtime (Node, Bun). Each lists installed versions with size on disk, which sites use it, and a Remove action. A version used by a site says so, and removing it asks first.
- **Install** from the same card: pick from the versions available (latest of each major line first, a "More versions" list below). Progress shows in the card. The install can be cancelled.
- **Per-site need** shows on the site's row in the Sites page: "Node 22 (installed)" or "Node 22 (not installed). Install". Installing from there is one click and needs no password.
- **Packages cache** card on the same page: size on disk and a Clear action. Clearing is safe, since packages download again when needed.
- **Setup wizard** is unchanged. Runtimes install on demand, not at first run, so the wizard stays three steps.
- **Popover** is unchanged. A runtime that fails to install shows as a site problem, not a notice.
- **CLI** (additional): `warren runtime list`, `available <runtime>`, `install <runtime>[@version]`, `remove <runtime>@<version>`, `which <runtime>`, `env <site>` (prints the environment for a registered site), all with `--json`.
- **MCP** (specs 020 to 022, not here): `list_runtimes` is a read tool. `install_runtime` and `remove_runtime` are write tools and need approval, since they download and delete.

## Prior art

| Option | Verdict |
|---|---|
| **mise** (MIT, released 2026-10-11, pushed daily, single binary for macOS arm64 and Intel, SHA-256 and SHA-512 checksums and minisign signatures published with each release). Installs Node and Bun from their upstream releases, has JSON output (`mise ls --json`), and keeps all state in folders set by environment variables. | **Used**, as a managed helper binary, like Caddy. |
| fnm | Rejected. Node only, so PHP and Python would each need another tool. |
| Volta | Rejected. Node-centric and changes how binaries are shimmed. |
| asdf | Rejected. Shell-script based and slower than mise, which reads the same `.tool-versions`. |
| Downloading Node and Bun releases ourselves | Rejected under the reuse-before-build rule. Version lookup, checksum handling and archive layouts are what mise already does well. |
| Corepack and each package manager's own cache setting | **Used** for caches: Warren only sets the environment variables each tool already supports. It does not implement caching. |

Verified while writing this spec, against mise 2026.10.11 on Apple silicon, with all mise folders inside a throwaway directory:

- `mise ls-remote node` and `bun` answer in under half a second after the first call and list every release.
- mise can read `.nvmrc` and resolve it to Node 22.23.3, but Warren reads the version files itself (a few lines, in `RuntimeResolver`). That lets the Sites page show what a site needs without downloading mise first, and mise is only asked to install `node@22`.
- `mise install node@22 bun@latest` took 29 seconds, used 254 MB for installs and 78 MB of cache (Node 187 MB, Bun 67 MB), and `mise exec -- node -v` ran the installed version.
- The release archive matched the published SHA-256.

mise's own cache (downloads, version lists) is a separate folder from installs, so it is counted and clearable separately.

## Behavior

**Managed binary.** `ToolRelease.mise` pins version 2026.10.11 with a SHA-256 per architecture (arm64 `64592e29…6311`, Intel `6eaffe02…75f1`), installed by the existing `ToolInstaller` to `~/.warren/bin/mise/<version>/mise`. Updating the pin is a reviewed change.

**Isolation.** Every call to mise sets, from `WarrenPaths`:

- `MISE_DATA_DIR` = `data/mise` (installed runtimes), `MISE_CACHE_DIR` = `cache/mise`, `MISE_STATE_DIR` = `run/mise`, `MISE_CONFIG_DIR` and `MISE_GLOBAL_CONFIG_FILE` = `config/mise`, so a user's own `~/.config/mise` and `~/.local/share/mise` are never read or written.
- `MISE_YES=1` (no prompts) and `MISE_AUTO_INSTALL=0`, so nothing downloads except through Warren's own install action. Any `MISE_*` variable already in the environment is dropped.
- `MISE_NO_ENV=1` always. Found while prototyping: with mise's defaults, a repo's `mise.toml` ran an `exec()` template and a `_.source` script on a plain `mise exec`, with no trust prompt. With `MISE_NO_ENV=1` neither ran, and the tool version still resolved. Warren asks mise only "which version" and "install it", so a repo's `mise.toml` cannot run commands. This follows the consent rule in 000. Hooks only fire from a shell integration and tasks only from `mise run`; Warren uses neither.

**Which version a site wants.** In order:

1. `[runtime]` in `.warren.toml` (`node = "22"`, `bun = "latest"`).
2. The project's own version files, read by Warren: `.nvmrc`, `.node-version`, `.bun-version` and `.tool-versions` (`nodejs` counts as `node`). `v22.1.0` is read as `22.1.0`, `lts/*` as `lts`.
3. `engines.node` in `package.json`, as a range (`>=18 <23`, `^20`, `20.x`, `18 || 20`). Warren picks the newest installed version that satisfies it. If none is installed it installs the newest release that satisfies it, preferring long-term-support lines (even majors). Ranges with pre-release tags or hyphens are ignored. This is a small range matcher in `VersionRange`, because no stable Swift package for it exists; it is tested against npm's behaviour for the common forms.
4. Nothing: the site has no Node requirement. Warren does not install anything for it.

A version like `22` is matched to the highest installed `22.x.y`. `latest` and `lts` accept the newest installed version, since whether a newer release exists is only known on the network.

**Installing.** An install runs `mise install <runtime>@<version>` and streams progress. Failures keep mise's message, shortened. A cancelled install leaves nothing listed (checked in the integration test). Installing a version that is already present does nothing.

**Running a site.** `RuntimeManager.environment(for:)` returns the variables to run the project: `PATH` with the runtime's `bin` first, plus the cache variables below. Spec 015 passes this to the process. Nothing is put on the user's global `PATH`.

**Shared package caches.** The environment points every package manager at one place, `cache/packages`:

| Variable | Used by |
|---|---|
| `npm_config_cache` | npm |
| `npm_config_store_dir` | pnpm |
| `YARN_CACHE_FOLDER` | Yarn 1 |
| `YARN_ENABLE_GLOBAL_CACHE=1` and `YARN_GLOBAL_FOLDER` | Yarn Berry |
| `BUN_INSTALL_CACHE_DIR` | Bun |

This is only for processes Warren starts. A terminal the user opens keeps its own caches. The cache is disposable: deleting it only costs a re-download.

**Removal.** Removing a version deletes its folder. A version used by a registered site needs confirmation that names those sites. The Packages cache can be cleared at any time.

**Footprint.** Idle: nothing runs. Disk: mise is about 130 MB on disk once unpacked (44 MB download); a Node 22 install measured 187 MB and Bun 1.4 measured 67 MB. Nothing is installed until a site needs it or the user asks.

## Acceptance criteria

Checked means verified. How is in each line.

- [x] 1. Installing the managed mise verifies its SHA-256, and a wrong hash deletes the download and fails. The real pinned download verifies in the integration test; the wrong-hash case is `ToolInstallerTests`.
- [x] 2. All mise folders are inside Warren's state folder, and a user's existing mise folders are untouched. Unit test on the environment; the integration test runs with a fake `HOME` and finds nothing written in it.
- [x] 3. The wanted version resolves from `.warren.toml`, then version files, then `engines.node`. `RuntimeTests`, including the range forms.
- [x] 4. A project's `mise.toml` with an `[env]` template, a `_.source` script or a task runs none of them. The integration test runs real mise inside such a project with Warren's environment and finds no side effects. (Hooks only fire from a shell integration, which Warren does not use, so they were not tested separately.)
- [x] 5. `warren runtime install bun@1.4`, `list`, `which` and `env` work, and installing again does nothing. Run by hand on the CLI, and the integration test installs twice. Node was installed through the app. The criterion originally said `node@22`.
- [ ] 6. A cancelled or failed install leaves nothing listed as installed. Cancelled: verified in the integration test (cancel two seconds into a Node download, inventory unchanged). Failed install is not tested yet.
- [x] 7. `environment(for:)` puts the runtime first on `PATH` and sets the cache variables. Unit test, and `warren runtime env` run on a real site.
- [x] 8. The Runtimes page shows real installed versions, sizes and the sites that use each one, and no demo content. Read from the running app through accessibility.
- [ ] 9. Install and Remove work from the Runtimes page without a terminal, and Remove of an in-use version names the sites. Verified in the running app: Remove named the site and removed the version from disk. Not exercised: the "Install a version" menu items and the Cancel button. Installs were started from the Sites card.
- [x] 10. The Sites page shows "installed" or "not installed" for a site's runtime, and its Install button installs it. Clicked in the running app for Bun and Node, with live progress.
- [x] 11. Clearing the Packages cache frees its space. A 3 MB cache cleared from the page. "The next install still works" was not tested.
- [x] 12. `just check` passes (136 tests), and `WARREN_DEMO=1` still shows the demo content and writes nothing to disk. Both run.

## Test plan

- **Unit:** version resolution order (3), engines range selection, environment building (7), mise JSON parsing from recorded output, mise argument and environment construction with a fake runner (2, 4), checksum failure (1).
- **Integration against real mise** (1, 2, 4, 5, 6): `RuntimeIntegrationTests`, off unless `WARREN_INTEGRATION=1`. Downloads mise and Bun into a throwaway home with a fake `HOME`, then runs a hostile `mise.toml`, installs twice, cancels a Node install and removes Bun. It does not run in CI, since it downloads about 75 MB.
- **Manual in the running app** (8 to 11): install, remove an in-use version, clear the cache, relaunch.

## Rollout

New state under `data/mise`, `cache/mise` and `cache/packages`. Nothing migrates. Existing users get the page on update, with no steps. If the app is later removed, deleting `~/.warren` removes everything.

## Open questions

Decided with the reviewer when approving.

1. **Include `engines.node` (step 3)?** It makes more projects work with no setup, but ranges are ambiguous. Recommendation: include, and show the chosen version so it is never a surprise.
2. **Install Node LTS when a site has no version?** Recommendation: no. A site with no stated need installs nothing, and the Add-site flow (011 and 012) proposes a version the user confirms.
3. **Where mise's own Node build comes from.** mise downloads upstream Node releases from nodejs.org and verifies them. Recommendation: accept this, and note it in the docs, since we do not rebuild Node.
