# Agent guide

Warren is a native macOS menu bar app for running local web projects. This file is for AI agents working in this repo. Humans: see [`README.md`](README.md) and [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Orientation

- **Stack:** Swift 6, SwiftUI + AppKit, Swift Package Manager, macOS 14+. Updates via Sparkle (spec 003).
- **Layout:** `Sources/WarrenApp` (menu bar app), `Sources/WarrenCore` (library), `Sources/WarrenDaemon` (`warrend` helper), `Sources/WarrenCLI` (`warren`), `Tests/`, `scripts/`, `specs/`, `design/`.
- **Design:** `design/mockup/*.dc.html` are the approved UI mockups. `node design/render.mjs` re-renders the README screenshots (needs Google Chrome).
- **Status:** pre-release scaffold. Most features exist only as specs.

## Workflow rules

1. **One spec is one PR.** Find the spec in `specs/`. If behavior is not covered, write or amend a spec in the same PR and say so. Read `specs/000-process.md`.
2. **Reuse before build.** Do not write what already exists and is stable. Check `docs/prior-art.md`, survey current options, and record the choice in the spec's Prior art section before writing code.
3. **Branch and PR. Never commit to the default branch directly.** Do not merge until a human approves.
4. **Run `just check` before pushing.** It runs SwiftFormat (lint mode), SwiftLint (strict), the SPDX header check, the fixture-provider check, `swift build` and `swift test`.
5. **Sign off every commit:** `git commit -s`. CI rejects unsigned commits.
6. **SPDX header** on every `.swift` and `.sh` file: `// SPDX-License-Identifier: Apache-2.0` (or `#` for shell). The Relay server under `services/relay/` will be AGPL-3.0.
7. **Tick acceptance criteria honestly.** Only check a criterion off if you verified it, and link or describe how. If you could not run something, say so in the spec and the PR.

## Design principles to respect

Light idle footprint, native-first (containers optional), no manual steps on update, regenerable dependencies are disposable, agent parity (anything in the UI has an MCP story and approvals for risky actions), and consent before running code from repos the user did not write.

## Using Warren from an agent

The MCP server is planned (specs 020 to 022) and is **not built yet**. Planned tools include listing sites, start/stop, logs, adding services, installing runtimes, enabling sharing, and storage reports, with write actions gated by user approval. Do not assume any of it exists. Check `specs/ROADMAP.md` and the code before relying on it.

## Common commands

```sh
just setup   # verify/install toolchain
just check   # the single gate
just dev     # build and launch a dev Warren.app
just warren site list --json   # build and run the CLI; see docs/warren-toml.md
just warren proxy status       # local HTTPS proxy; see docs/proxy.md
just warren dns status         # local DNS for your domains; see docs/dns.md
```

The app shows real state. `WARREN_DEMO=1` shows demo data instead (screenshots, design work), and `WARREN_HOME` points it at another state folder.

`just check` is the single gate and needs a matching Xcode toolchain (accept the Xcode license first: `sudo xcodebuild -license accept`). `just dev` builds with SwiftPM and launches the app.
