# 014 · GitHub import and env/secret prompts

Status: Implemented, pending the window checks (screen was locked) · Phase 3 · Depends on: 011, 012, 013

## Goal

A user pastes a repository address (or picks one of their own), Warren clones it, registers it as a site, and runs its setup plan. When the project needs values in `.env` that only the user knows, Warren asks for exactly those, once, in a plain form, and writes them into the project's `.env`. A skipped value is fine: the project keeps a placeholder and the plan does not nag.

## Non-goals

- Starting the site (015).
- Pull requests, pushing, branches beyond choosing one to clone, or any Git client features. After the clone, Git is the user's.
- Signing in to GitHub from Warren. Warren stores no GitHub credentials (see Prior art).
- Managing secrets beyond the project's `.env`: no vault, no sync, no Keychain in this spec (see open questions).
- Submodules and Git LFS (a clone with them works as `git` does it, but Warren does not add flags for them).

## App surface

- **Add site window, "From GitHub"** (the entry that is greyed out today):
  - **Repository** field accepting `acme/shop`, `github.com/acme/shop`, `https://github.com/acme/shop` (including a `/tree/<branch>` address), `git@github.com:acme/shop.git`, or another host's `https://` or `ssh://` Git address. Addresses that could run a command or reach the disk (`ext::`, `file:`, local paths, anything starting with `-`) are refused with a message.
  - **Branch** menu, filled from the repository once the address is valid (`git ls-remote`, no download). The default branch is preselected.
  - **Pick from my repos**: a searchable list of the user's repositories, shown when the GitHub CLI (`gh`) is installed and signed in, and hidden with a one-line note ("Install the GitHub CLI to list your repositories") when it is not.
  - **Name**, **Domain** and **Location** as in 013 (default `~/Sites/<repo>`), checked as you type.
  - Private repositories use the credentials the user's Git already has: the macOS Keychain helper, the GitHub CLI's helper, or an SSH key in the agent. If access fails the window says so in plain words and how to fix it (sign in with `gh auth login`, or use an SSH address), and never hangs on a hidden prompt.
  - Buttons: **Cancel** and **Clone & set up**. A note says "Warren shows each command from this repository and asks before it runs."
- **Clone & set up** creates the folder, registers the site, shows the clone's progress, then builds the project's setup plan (011) and runs it (012) with its approval sheet. The site page's Setup card shows all of it.
- **Values needed** (the mockup's "One value needed" card): after `.env` is created from the example, a sheet lists the variables the example leaves empty, one field each, with the reason Warren asks. A field is plain text, or hidden text for names that look secret (`KEY`, `SECRET`, `TOKEN`, `PASSWORD`, `DSN`). Where Warren can answer, it offers to: **Use https://shop.test** for `APP_URL`-style variables, **Generate** a random value for auth and session secrets (`AUTH_SECRET`, `NEXTAUTH_SECRET`, `BETTER_AUTH_SECRET`, `SESSION_SECRET`, `JWT_SECRET`, `COOKIE_SECRET`, `ENCRYPTION_KEY`). Third-party keys (`STRIPE_SECRET_KEY`) are never generated. **Save** writes the filled fields; **Skip** keeps the placeholders. A note appears if `.env` is not covered by the project's `.gitignore`.
- **Popover** unchanged.
- **CLI** (additional): `warren repo list` (via `gh`), `warren site clone <repo> [name] [--branch <b>] [--location <folder>] [--domain <name>] [--yes]`. In the terminal the values are asked one by one (secret ones without echo); Enter skips; `--yes` approves commands and skips every value.
- **MCP** (specs 020 to 022): `import_repo` is a write tool, approved like any plan run. Secret values never pass through an agent: the tool asks the app to show the sheet.

## Prior art

Surveyed 2026-10-16.

| Option | Verdict |
|---|---|
| **`git`** (Apple's `/usr/bin/git`, Git 2.54 here, from the Xcode Command Line Tools) | **Used** for `ls-remote` and `clone`. It already knows the user's credentials. If the Command Line Tools are missing, `git` offers to install them; Warren detects that first (`xcode-select -p`) and explains instead of letting a system dialog appear unannounced. |
| **GitHub CLI `gh`** (MIT; `gh repo list --json …`, `gh auth status`) | **Used when present**, for the repository picker only. Not installed by Warren. |
| **A GitHub OAuth app or token in Warren** | Rejected for now. It would make Warren hold a credential for the user's code, and Git's own helpers already do the job. |
| **Archive download** (`codeload.github.com/<owner>/<repo>/tar.gz/<branch>`) | Not used: public repositories only, no history. A possible fallback if Git is unavailable (open question). |
| **libgit2 / SwiftGit2** | Rejected: a large dependency to redo what `git` does, with credential handling to reimplement. |
| **Dotenv libraries** | None stable for Swift (see 011). The part needed here edits `KEY=` lines in place and is a few dozen lines. |
| **macOS Keychain, 1Password CLI, `direnv`** for secrets | Out of scope; the convention for local development is the project's own `.env`, which this spec writes and keeps out of Warren's hands. |

Safety facts that shape the design: Git's `ext::` transport runs a command from the address; `GIT_ALLOW_PROTOCOL` restricts the transports a clone may use; `GIT_TERMINAL_PROMPT=0` and `ssh -o BatchMode=yes` make a credential failure an error instead of a prompt nobody can see. Warren sets all three on every Git call. A clone itself does not run code from the repository (hooks are not cloned), so the clone step needs no project-code approval; anything that does run repository code is a later plan step with the approval sheet from 012.

## Behavior

**Parsing.** `RepositoryReference` turns the field into a clone address and a default name, or an error. Accepted forms are listed above; GitHub shorthand becomes `https://github.com/<owner>/<repo>.git`. The branch from a `/tree/` address pre-selects that branch.

**Inspecting.** Once the address parses, `git ls-remote --heads --symref <address>` (with the safety settings) fills the branch list and the default branch. Failure messages are mapped from Git's output: not found or no access, authentication failed, network unreachable, host not trusted.

**Cloning.** Same shape as 013: validate name, location and domain; create the empty folder; register the site; run a **clone plan** with the 012 runner: one step, `git clone --progress --branch <branch> -- <address> .`, working folder the new folder. Progress lines (`Receiving objects: 45%`) stream into the step. Then the normal setup plan is built and run.

**Values.** A variable counts as unset when it is empty or a placeholder (`YOUR_KEY`, `your-…`, `<…>`, `changeme`, `replace_me`, `xxxxxxxx`); real defaults like `password` or `localhost` do not. (Found by cloning a real repository whose example holds `FIRECRAWL_KEY="YOUR_KEY"`, which the first design, empty only, would have missed.) The plan gains a step *Fill in .env values* after *Create .env*: *to do* while the example leaves variables unset and the choice has not been made, *done* once saved or skipped (remembered in the run store with the list of variable names, so a new empty variable in a later example asks again). Warren edits only the lines of the chosen variables, keeps the rest of the file byte for byte, and quotes a value that contains spaces or `#`. It never writes a value anywhere else, never logs one, and passes none to the process environment.

**Footprint.** Nothing runs in the background. `gh` is run only when the picker is opened.

## Acceptance criteria

Checked means verified. How is in each line.

- [x] 1. Every accepted address form parses to the right clone address, name and branch, and each refused form is refused with a message (`ImportTests`: ten accepted forms, eleven unsafe, six unsupported).
- [x] 2. Every Git call carries `GIT_ALLOW_PROTOCOL`, `GIT_TERMINAL_PROMPT=0` and `ssh -o BatchMode=yes`, and an `ext::` address cannot run a command even if it reaches Git (`ImportTests.theExtTransportCannotRunACommandEvenIfItReachesGit`, real `git`, marker file).
- [x] 3. `ls-remote` fills the branch list and default branch (`ImportTests` against a local bare repository with two branches; the CLI against the real public repository `dzhng/deep-research`), and a missing or private repository gives the plain "not found / cannot see it" message (CLI by hand against a repository that does not exist).
- [x] 4. A clone runs as a plan step in the new folder with progress lines, registers the site first, and a failed clone leaves the site and files (`ImportTests`, local bare repository, real `git`; the second clone into a filled folder fails and the site stays).
- [x] 5. After the clone, the project's normal plan is built and run with the 012 approval (CLI against `dzhng/deep-research`: cloned, Node 22 installed from `.nvmrc`, `npm ci` asked and declined, `.env` created). In the window: not checked.
- [x] 6. The values step lists unset variables, fills URL-style and generated secrets only where offered, never generates third-party keys, writes only chosen lines and leaves the rest of `.env` unchanged, quotes when needed, and a skip is remembered (`EnvValuesTests`; a new variable in the example asks again).
- [x] 7. A secret value is never written to a log, the run store, the event stream or a process environment (`EnvValuesTests.aSecretValueIsWrittenToEnvAndNowhereElse`, sentinel search; and by hand: after a real clone, the sentinel was in `.env` only).
- [ ] 8. The Add site window clones and sets up a repository end to end, shows the values sheet, and writes `.env` (running app). **Not checked:** the Mac's screen was locked while I was testing, so no window could be opened. The pane, the values sheet and the picker are built and compile, and the CLI path above runs the same core code.
- [ ] 9. The picker lists repositories when `gh` is signed in and explains itself when it is not. The list comes from the same code as `warren repo list`, which listed this account's repositories (also with a minimal `PATH`); the picker sheet itself was not seen.
- [x] 10. `warren repo list` and `warren site clone` work: a real clone with values asked and saved, an unsafe address refused, a missing repository explained. Hidden entry on a real terminal (`getpass`) was not exercised; piped input is read as it comes.
- [x] 11. `just check` passes (270 tests). `WARREN_DEMO=1` was not run again for this spec.

## Test plan

- **Unit**: address parsing table; env editing (quoting, preserving, only chosen lines); value classification and the generate/fill rules; the plan step's states; secret-not-leaked sentinel test; clone plan with the fake executor.
- **Integration** (`WARREN_INTEGRATION=1`): clone a local bare repository (branches, default branch, failure messages), run the `ext::` marker test, clone one small real public repository.
- **Manual in the running app** (5, 8, 9): a public repository, a private one (to see the access message), the picker with and without `gh`, the values sheet with a secret, a generated secret and a skip.

## Rollout

New code and UI only. The run store gains a record for the values step. No migration.

## Open questions

Decided with the reviewer when approving.

1. **No GitHub sign-in in Warren.** Git's and `gh`'s own credentials.
2. **Pasted secrets live only in the project's `.env`.**
3. **Generate only for the named list**, as a button.
4. **If Git is missing**, explain and point to `xcode-select --install`.
5. **Submodules and Git LFS** follow Git's defaults.
