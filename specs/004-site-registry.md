# 004 · Site registry and `.warren.toml`

Status: Implemented · Phase 1 · Depends on: 001

## Goal

Warren knows which sites exist and how each is configured. A persistent registry lists the sites on this Mac, and an optional `.warren.toml` in a project describes how Warren should run it. Both are usable from the `warren` CLI, so people and agents can register and inspect sites today, before any process management exists.

## Non-goals

- No starting or stopping processes, no proxy, no DNS or certificates (specs 005, 006, 012).
- No framework or runtime detection (spec 010). Config values are stored and validated, not acted on.
- No UI wiring. The app keeps its demo data until a real `StateProvider` exists.
- Single writer. Cross-process locking arrives with the helper (spec 015).

## Behavior

**Locations.** Warren's home is `~/Warren`, overridable with `WARREN_HOME`. The registry is `config/sites.json` under it.

**Registry file.** `{"version": 1, "sites": [{"id", "path", "addedAt"}]}`. Writes are atomic (temp file, then rename). A file with a newer `version` is rejected, not rewritten. A corrupt file is moved to `sites.json.corrupt-<unix time>` and the command fails with the backup path; it is never silently overwritten.

**Registering a site.** The path must exist and be a directory. The id is the folder name as a slug (lowercase, runs of other characters become `-`, trimmed, `site` if empty), with `-2`, `-3` added if taken. Registering the same path twice is an error. Removing a site never touches project files.

**Effective configuration.** Defaults plus `.warren.toml` overrides:

| Field | Default |
|---|---|
| `name` | folder name |
| `domains` | `["<id>.test"]` |
| `runtime` | none |
| `run.command`, `run.port` | none |
| `services` | none |

**`.warren.toml` (schema v1).**

```toml
name = "acme-store"
domains = ["acme.test", "shop.localhost"]

[runtime]
node = "22"

[run]
command = "pnpm dev"
port = 3000

[services]
postgres = "17"
```

Supported TOML subset: comments, `[tables]`, strings (basic and literal), integers, booleans, and single-line arrays of strings. Anything else is a clear error with a line number. Unknown keys are warnings, so newer files still load. Wrong types are errors.

**Domains.** Lowercase labels of `a-z`, `0-9` and `-`, no leading or trailing hyphen, at most 253 characters, and at least two labels (`acme.test`, not `acme`). Two sites may not claim the same domain; adding a conflicting site fails and names the other site.

**Problems never hide a site.** If a project's `.warren.toml` is invalid, the site still lists, with default domains and the problem recorded in `problems`.

**CLI.**

- `warren site add <path>` registers and prints the resolved site.
- `warren site list [--json]`, `warren site show <id> [--json]`.
- `warren site remove <id>`.
- Exit code 0 on success, 1 on any error, with the message on stderr. `--json` output is stable and meant for agents.

## Acceptance criteria

1. [x] `site add` registers a directory, prints its id, and the site appears in `site list`.
2. [x] Adding a missing path or a file fails with a clear message and exit code 1.
3. [x] Two folders with the same name get ids `name` and `name-2`.
4. [x] Adding the same path twice fails.
5. [x] With no `.warren.toml`, the domain is `<id>.test` and the name is the folder name.
6. [x] A valid `.warren.toml` overrides name, domains, runtime, command, port and services.
7. [x] A syntax or type error in `.warren.toml` reports the line number; the site still lists with a problem recorded.
8. [x] Unknown keys are warnings, not errors.
9. [x] Adding a site whose domain another site already claims is rejected, naming the other site. An invalid domain in `.warren.toml` is recorded as a problem (see criterion 7), not a rejection.
10. [x] A corrupt `sites.json` is backed up and reported, never overwritten; a newer `version` is rejected.
11. [x] `site remove` unregisters the site and leaves the project directory untouched.
12. [x] `WARREN_HOME` relocates all state.

*All twelve were exercised against the real `warren` binary with a throwaway `WARREN_HOME` (see the PR). The unit tests mirror them and run in CI; they could not be run on the author's machine because the Command Line Tools' Testing macros are out of step with the compiler.*

## Test plan

Unit tests (Swift Testing) for the TOML subset, config validation, domain rules, and the registry against a temporary `WARREN_HOME`. A manual CLI walkthrough of criteria 1 to 4 and 11 on the author's machine, recorded in the PR.

## Rollout

New files under `~/Warren/config` only. No migration. `version: 1` is the format every later spec must keep reading.

## Open questions

- Should `.warren.toml` also accept `[env]` values? Deferred to the setup specs (011 to 014), which own `.env` handling.
