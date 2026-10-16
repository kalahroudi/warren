# 009 · Python runtime via uv

Status: Draft · Phase 2 · Depends on: 004, 007

## Goal

A Python site gets the right Python without the user installing anything. Warren reads which version a project asks for, installs it into its own folder on demand, and gives the site an environment where `python` and `uv` are the ones Warren manages. The user sees installed Pythons on the Runtimes page beside Node, Bun and PHP, adds or removes versions, and sees their size. Python package downloads share the Warren package cache from 007.

## Non-goals

- Creating a project's virtual environment, installing its dependencies and starting it (specs 010 and 015). This spec answers "which binary, which version, which environment". `uv` is on the site's `PATH`, so `uv sync` works the moment those specs call it.
- Detecting Django, Flask or FastAPI (spec 010).
- Touching the user's own Python, pyenv, Homebrew Python or conda.
- Free-threaded builds, PyPy and pre-releases.

## App surface

- **Runtimes page**: a Python card beside the others: installed versions with size and the sites using each, **Remove** (asks first and names the sites), and **Install a version** (Latest, then the newest patch of each minor). Progress shows in the card and the install can be cancelled.
- **Per-site need** on the site's page: "Python 3.12 (installed)" or "(not installed). Install", one click, no password.
- **Packages cache** card counts uv's cache too.
- **Setup wizard and popover** unchanged.
- **CLI** (additional): the `warren runtime` commands from 007 accept `python`: `list`, `available python`, `install python@3.13`, `remove python@3.13.16`, `which python`, `env <site>`.
- **MCP** (specs 020 to 022): the same `list_runtimes` (read) and `install_runtime` / `remove_runtime` (approval) tools. Nothing new.

## Prior art

Surveyed 2026-10-16.

| Option | Verdict |
|---|---|
| **uv** (Astral; Apache-2.0 and MIT; 0.13.1, pushed the day of this survey; one binary of 14 MB for Apple silicon and 17 MB for Intel; SHA-256 published for every asset). Installs prebuilt CPython from python-build-standalone, lists installed and downloadable versions as JSON, and is also the package manager and environment tool Python projects increasingly use. | **Used**, as a managed binary like Caddy and mise. |
| mise's Python support | Rejected. It would work (it uses the same prebuilt Pythons), but projects still need a package manager, and uv is that and the installer in one 14 MB binary, where mise is 44 MB we would then also depend on for Python. |
| pyenv | Rejected. Compiles from source: needs a toolchain, takes minutes, fails on missing libraries. |
| Homebrew Python, python.org installers, conda | Rejected. Not relocatable or not scriptable without the user's involvement, or too heavy. |
| Building Python ourselves | Rejected. python-build-standalone already does this well. |

Measured while writing this spec, with uv 0.13.1 on Apple silicon and every uv folder inside a throwaway directory:

- `uv python list` answers in 0.14 s, including all downloadable versions.
- `uv python install 3.13` took 3.7 s, downloaded 24 MB and used 66 MB; the Python ran from that folder. Uninstall took 69 ms.
- A fake `HOME` stayed empty with `UV_PYTHON_INSTALL_DIR`, `UV_CACHE_DIR` and `UV_NO_CONFIG=1` set.
- With `UV_PYTHON_DOWNLOADS=never`, uv refuses to download and says so, so a project command can never trigger an install behind the user's back.
- `uv python list --only-installed --output-format json` gives version, path, implementation and variant for each install.

## Behavior

**Managed binary.** `ToolRelease.uv` pins uv 0.13.1 with a SHA-256 per architecture (arm64 `cfe45457…acd2`, Intel `bb7b805b…ff6b`), installed by `ToolInstaller` to `~/.warren/bin/uv/<version>/uv`. Updating the pin is a reviewed change.

**Isolation.** Every uv call sets, from `WarrenPaths`: `UV_PYTHON_INSTALL_DIR` = `data/python`, `UV_CACHE_DIR` = `cache/packages/uv`, `UV_NO_CONFIG=1` (a user's or project's `uv.toml` is not read), `UV_PYTHON_PREFERENCE=only-managed` (the system Python is never picked), `UV_PYTHON_INSTALL_BIN=0` (no `python` shims in `~/.local/bin`) and `UV_NO_PROGRESS=1`. Inherited `UV_*` variables are dropped. uv runs in a neutral folder, so no project file is read while installing or listing.

**Which version a site wants.** In order:

1. `[runtime]` in `.warren.toml` (`python = "3.12"`).
2. `.python-version`, then `.tool-versions` (`python 3.12.4`), read by Warren.
3. `requires-python` in `pyproject.toml`, a PEP 440 specifier: `>=3.10`, `>=3.10,<3.13`, `~=3.11`, `==3.12.*`. Warren picks the newest installed version that satisfies it. If none is, it asks uv to install the specifier as written, and uv picks the newest release that satisfies it. A specifier Warren cannot read (`!=`, pre-release markers, `===`) is ignored and the site is shown as having no Python requirement.
4. Nothing: no Python requirement, nothing installed.

A request like `3.12` matches the highest installed `3.12.x`. `latest` accepts the newest installed.

**Installing.** `uv python install <request>` with streamed progress; failures keep uv's message. A cancelled install leaves nothing listed (uv installs into a temporary name and renames, checked in the integration test). Installing a present version does nothing.

**Running a site.** `RuntimeManager.environment(for:)` (007) gains Python: `PATH` gets the Python's `bin` and uv's folder first. It sets `UV_PYTHON_INSTALL_DIR`, `UV_CACHE_DIR`, `UV_NO_CONFIG` and `UV_PYTHON_PREFERENCE` as above, plus `UV_PYTHON_DOWNLOADS=never`, so the project's own commands cannot fetch interpreters; only Warren's install action does. `PIP_CACHE_DIR` points at `cache/packages/pip`. A project's `.venv` is left alone.

**Removal.** `uv python uninstall <version>`. A version used by a registered site needs confirmation naming those sites. uv is kept; it is small and the package cache needs it.

**Footprint.** Idle: nothing runs. Disk: uv 14 MB download and about 40 MB unpacked; a Python measured 66 MB. Nothing is installed until a site needs it or the user asks.

## Acceptance criteria

- [ ] 1. Installing the managed uv verifies its SHA-256, and a wrong hash deletes the download and fails.
- [ ] 2. All uv folders are inside Warren's folder, and a fake `HOME` stays empty after install, list and uninstall (integration).
- [ ] 3. The wanted version resolves from `.warren.toml`, then `.python-version` / `.tool-versions`, then `pyproject.toml` (PEP 440 forms), including `==3.12.*` and `~=3.11` (unit).
- [ ] 4. A project's `uv.toml`, `pyproject.toml` `[tool.uv]` section or a `UV_*` variable in the environment does not change what Warren installs or lists (integration).
- [ ] 5. A cancelled or failed install lists nothing (unit with a fake uv; integration cancel).
- [ ] 6. `environment(for:)` for a Python site puts Python and uv first on `PATH`, sets the uv and pip variables and `UV_PYTHON_DOWNLOADS=never` (unit).
- [ ] 7. With that environment, `uv python find` cannot download, and finds the managed Python (integration).
- [ ] 8. The Runtimes page shows Python versions with sizes and using sites; Install, Cancel and Remove work, and Remove of an in-use version names the sites (running app).
- [ ] 9. The site's page shows "Python x (installed / not installed)" and its Install button installs it (running app).
- [ ] 10. `just check` passes, and `WARREN_DEMO=1` still shows demo content and writes nothing.

## Test plan

- **Unit**: release table shape; `pyproject.toml`, `.python-version` and PEP 440 resolution; environment building; uv JSON parsing from recorded output; argument and environment construction with a fake uv script; failure and cancel paths.
- **Integration, real uv** (`WARREN_INTEGRATION=1`, off in CI): download uv, install a Python, list it, run it, `uv python find` with downloads off, a hostile `uv.toml`, uninstall, cancel an install, fake `HOME` stays empty.
- **Manual in the running app** (8, 9): install from the Sites card and the Runtimes menu, cancel, remove an in-use version, relaunch.

## Rollout

New state under `data/python`, `cache/packages/uv`, `cache/packages/pip` and the uv binary. Nothing migrates. Deleting `~/.warren` removes everything.

## Open questions

1. **uv rather than mise for installing Python?** Recommendation: uv, as above. It adds a 14 MB binary and keeps one tool that is both installer and the package manager projects will use.
2. **Install a version for a site with no stated Python?** Recommendation: no, same rule as Node. The Add-site flow (011, 012) proposes one and the user confirms.
3. **Which versions to offer?** Recommendation: the newest patch of each stable CPython minor uv offers, newest first, without free-threaded builds, PyPy or pre-releases.
4. **Virtual environments.** Recommendation: not here. Spec 015 runs the project's own start command (for example `uv run`), with this environment.
