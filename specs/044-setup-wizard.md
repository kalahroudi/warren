# 044 · Setup wizard

Status: Implemented, pending the password steps · Phase 1 · Depends on: 005, 006, 043

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

**When it appears.** Automatically on first launch, and not again once the user closes it unfinished. It can be reopened any time from the gear menu (Set up Warren…) and from the right-click menu on the menu bar icon. Clicking a site in the popover while setup is unfinished opens it too, since the site's address would not work yet.

**The popover stays clean.** It never shows setup notices or banners. Setup lives only in the wizard. Once something that was working stops (for example the proxy), the popover shows one quiet line, never anything about setup that was not done.

**Menu bar.** The popover is a real `NSPopover` anchored to the status item with an arrow, closed by clicking elsewhere, sized to its content. Right-clicking the icon shows Open Warren, Set up Warren and Quit. The main window and the wizard are AppKit windows, so nothing depends on SwiftUI scenes.

**Pause and resume.** The pause button stops the background proxy and DNS server and keeps them off, including across logins, until resumed. It appears once there is something to pause. A paused Warren is complete but off, so it is not nagged about setup.

**Parity.** The CLI keeps doing everything the wizard does, for people and agents. Both call the same core code.

## Acceptance criteria

1. [x] The wizard opens on first launch and its steps run in order.
2. [x] Each step's state is derived from the machine and is correct after quitting and relaunching mid-way.
3. [x] Local HTTPS installs and starts Caddy with no terminal.
4. [ ] Trust uses the macOS password dialog, adds Warren's root to the system keychain, and Undo removes it. *The scripts and dialog wiring are unit tested; the real keychain change needs your password.*
5. [ ] Local domains shows the exact resolver files before the dialog, writes only Warren's files, and Undo removes them. *Run end to end against a temporary resolver folder, including Undo. The write to the real `/etc/resolver` needs your password.*
6. [ ] The check step passes only if the name resolves through the macOS resolver and `https://warren.test` loads with a trusted certificate, and otherwise names the failing part. *The failure path is verified in the app (it said exactly which step to redo). The pass path needs steps 4 and 5 done for real.*
7. [x] Every step states what it changes before it asks for a password. *A dismissed password dialog is reported as "cancelled, nothing was changed"; that is unit tested, the dialog itself is yours.*
8. [x] Re-running a completed step is harmless; a half-finished setup can be repaired by reopening the wizard.
9. [x] Clicking a site while setup is unfinished opens the wizard.
10. [ ] A fresh user reaches a working `https://<site>.test` from the app alone, with no terminal. *Needs 4, 5 and 6.*

*Verified in the running app through the accessibility tree and real launchd: the wizard opened by itself at first launch and stayed closed once dismissed, resumed on the first unfinished step after a relaunch, installed and started Caddy and CoreDNS, showed the Done state, undid each step, and the popover stayed clean. Pause and resume were clicked for real inside the anchored popover.*

## Test plan

Unit tests for step-state derivation (against temporary directories) and the trust and resolver commands. The real flow verified on the running app through the accessibility tree where possible. The password dialogs, the real keychain and `/etc/resolver` changes, and the browser check are the user's.

## Rollout

Changes the system only at steps 3 and 4, each behind a password dialog and each undoable. First-run detection is derived from the steps' state.

## Open questions

- Should the wizard offer a "set it all up" shortcut with one combined password dialog instead of two?
- Reserving `warren.test` for the self-check page means that name is unavailable to users. Acceptable?
- How should the wizard behave when Safari or Chrome has Secure DNS on and skips the resolver files?
