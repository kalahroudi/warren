# Setup

The first time Warren runs, the setup wizard opens by itself and takes you from nothing to `https://<your-site>.test` working in a browser, with no terminal. If you close it unfinished it stays closed, and you can reopen it from the gear menu (**Set up Warren…**) or by right-clicking the menu bar icon.

| Step | What it does | Password? |
|---|---|---|
| Local HTTPS | Downloads Caddy (checked against a published checksum) and runs it as a background service that starts at login | No |
| Trust the certificate | Adds Warren's local certificate authority to your System keychain, so browsers accept `https://` for your sites | Yes (macOS dialog, Touch ID works) |
| Local domains | Runs a tiny DNS server on this Mac and writes `/etc/resolver` files so macOS asks it about your domains | Yes (macOS dialog) |
| Check | Loads Warren's own page, `https://warren.test`, the way a browser would, and names the step to redo if it fails | No |

Every step says what it will change before it asks, and has an Undo. Each step's state is read from the machine, not remembered, so you can quit and resume, and reopening the wizard repairs a half-finished setup. `.localhost` sites need no DNS step.

## Where Warren keeps its files

`~/Warren` (downloads, settings, logs). If `~/Warren` is the Warren source checkout, as it is on a case-insensitive disk when the repo is cloned to `~/warren`, Warren uses `~/.warren` instead, so nothing lands in your working tree. `WARREN_HOME` overrides both.

## Pause and resume

The pause button in the menu bar popover stops the local HTTPS proxy and DNS server and keeps them off, including after you log in again, until you resume. It appears once there is something to pause.

## For scripts and agents

```sh
just warren setup status     # each step's state, read from this machine
```

The wizard and the CLI call the same code (`proxy`, `dns` and `setup` commands), so anything the wizard does can be done from a terminal.

## Testing hooks

Environment variables let the whole flow run without touching ports 80 and 443 or `/etc/resolver`: `WARREN_HOME`, `WARREN_HTTP_PORT`, `WARREN_HTTPS_PORT`, `WARREN_DNS_PORT` and `WARREN_RESOLVER_DIR`. `WARREN_DEMO=1` shows the demo data instead of real state.
