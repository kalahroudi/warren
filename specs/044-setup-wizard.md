# 044 · Setup wizard

Status: Draft · Phase 1 · Depends on: 005, 006, 043

## Goal

A first-run wizard, reopenable later from settings, takes someone from a fresh install to `https://acme.test` working in a browser, with no terminal. Every step says what it changes and why, and can be undone.

## Non-goals

- No privileged helper (a later spec could remove the password prompts). The prompts are the standard macOS password dialog.
- No site creation. The wizard ends by handing over to Add site.
- No services, runtimes or sharing setup. Those have their own first-use moments.

## Prior art

| Need | Existing option | Verdict |
|---|---|---|
| Run a step as admin | The macOS password dialog through AppleScript (`do shell script ... with administrator privileges`). Touch ID works in it. | **Used.** No authorization code of our own. |
| Trust the local root certificate | `security add-trusted-cert` and `security remove-trusted-cert` | **Used**, instead of `caddy trust`, which runs `sudo` and needs a terminal. |
| Resolver files | The script spec 006 already generates | **Reused.** |
| Start the servers | The launch agents from spec 043 | **Reused.** |
| A privileged helper (`SMAppService` daemon) | Better UX, but needs signing and a helper | Later. |

## Behavior

**State comes from reality, not flags.** Each step decides whether it is done by inspecting the machine: Caddy installed and running, the root certificate trusted, CoreDNS installed and running, resolver files current. So the wizard can never disagree with the system, and it can be reopened to repair a half-finished setup.

**Steps.**

1. **Welcome.** What Warren will set up and which domain suffix to use (`.test` by default). Nothing changes yet.
2. **Local HTTPS.** Downloads Caddy (checksum verified) and starts it in the background (spec 043).
3. **Trust the certificate.** Explains that Warren has its own local certificate authority, that trusting it adds it to the system keychain so browsers accept `https://` for your sites, and that the certificate could issue certificates for any name, so its key stays private to your account. A macOS password dialog follows. Undo is `security remove-trusted-cert` from Settings.
4. **Local domains.** Downloads CoreDNS, starts it, and shows the exact resolver files it will write before a password dialog. Skippable if every domain is `*.localhost`.
5. **Check.** Warren serves a built-in page at `https://warren.test` (a static Caddy response). The step resolves the name through the real macOS resolver and loads the page over HTTPS, and reports which part failed if it does not work.
6. **Done.** Summary and a button into Add site.

**Each step has** a status (not started, done, needs attention), a plain-language description of what changes, an Undo, and a retry. A failed step explains the cause and the next action, never a raw error. The wizard can be quit and resumed.

**When it appears.** Automatically on first launch, and again when a user adds a site whose domain needs a step that is not done. From the popover, an incomplete setup shows a "Finish setup" banner. Settings has a Setup page with the same steps.

**Parity.** The CLI keeps doing everything the wizard does, for people and agents. Both call the same core code.

## Acceptance criteria

1. [ ] The wizard opens on first launch and its steps run in order.
2. [ ] Each step's state is derived from the machine and is correct after quitting and relaunching mid-way.
3. [ ] Local HTTPS installs and starts Caddy with no terminal.
4. [ ] Trust uses the macOS password dialog, adds Warren's root to the system keychain, and Undo removes it.
5. [ ] Local domains shows the exact resolver files before the dialog, writes only Warren's files, and Undo removes them.
6. [ ] The check step passes only if the name resolves through the macOS resolver and `https://warren.test` loads with a trusted certificate, and otherwise names the failing part.
7. [ ] Every step states what it changes before it asks for a password, and cancelling the dialog leaves nothing changed.
8. [ ] Re-running a completed step is harmless; a half-finished setup can be repaired from Settings.
9. [ ] Adding a site that needs an unfinished step offers to finish setup.
10. [ ] A fresh user reaches a working `https://<site>.test` from the app alone, with no terminal.

## Test plan

Unit tests for step-state derivation (against temporary directories) and the trust and resolver commands. The real flow verified on the running app through the accessibility tree where possible. The password dialogs and the browser check are the user's.

## Rollout

Changes the system only at steps 3 and 4, each behind a password dialog and each undoable. First-run detection is derived from the steps' state.

## Open questions

- Should the wizard offer a "set it all up" shortcut with one combined password dialog instead of two?
- Reserving `warren.test` for the self-check page means that name is unavailable to users. Acceptable?
- How should the wizard behave when Safari or Chrome has Secure DNS on and skips the resolver files?
