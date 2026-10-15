# 001 · Repo, CI, licenses

Status: Implemented, pending CI run · Phase 0 · Depends on: 000

## Goal

A new contributor can clone the repo, run one command, and have the app building and tests passing. Every later spec lands on a repo that already enforces formatting, linting, tests and license hygiene.

## Non-goals

- No app features. No release or signing (that is 003).

## Behavior

Monorepo layout:

```
Package.swift        SwiftPM manifest (macOS 14+, Swift 6)
Sources/WarrenApp/   Menu bar app (SwiftUI + AppKit), product WarrenApp
Sources/WarrenCore/  Library: registry, supervisor, drivers (grows over time)
Sources/WarrenDaemon/  Background helper, product `warrend` (supervises sites and services)
Sources/WarrenCLI/   CLI, product `warren` (talks to warrend over a Unix socket)
Tests/               Swift Testing targets
App/Info.plist       Bundle metadata; scripts/bundle-app.sh assembles a dev Warren.app
scripts/             The real logic behind `just` (CI and humans run the same scripts)
services/relay/    Relay server (added in 025)
catalog/           Service and runtime manifests (data)
specs/             This directory
docs/
```

- Stack decision recorded here: **native Swift (SwiftUI + AppKit), Swift Package Manager for the core, Sparkle for updates.** Reason: smallest footprint, native menu bar and system integration, Mac-only product. Alternatives considered: Tauri (Rust + web UI), rejected for a larger footprint and non-native feel.
- `just setup` checks for Xcode command line tools and installs SwiftLint and SwiftFormat; `just check` runs format, lint and tests; `just dev` builds and starts the app.
- Licenses: `LICENSE` Apache-2.0 at the root; `services/relay/LICENSE` AGPL-3.0 once it exists (still to be confirmed). SPDX headers are enforced by a CI check.
- `CONTRIBUTING.md` explains the spec process and DCO sign-off. `SECURITY.md` explains private vulnerability reporting.
- PR template links the spec and lists its acceptance criteria.

## Acceptance criteria

1. [ ] Fresh clone on macOS: `just setup && just check` succeeds. *Not yet verified: the author's machine has a broken Swift toolchain (SDK 27.0 vs compiler 6.3.3). First real run is CI.*
2. [ ] CI runs `just check` on every PR and blocks merge on failure. *Workflow added in `.github/workflows/ci.yml`; needs a GitHub remote and branch protection.*
3. [x] CI fails a PR with a source file missing an SPDX header. *`scripts/check-spdx.sh` verified locally against a headerless file.*
4. [x] CI fails a commit missing a DCO sign-off. *`scripts/check-dco.sh` verified locally with signed and unsigned commits.*
5. [x] PR template exists and references `specs/`.
6. [x] `README.md` states the project goal, status and how to contribute.

## Test plan

Criteria 1 to 2 verified by the CI run on this PR. Criteria 3 to 4 verified by deliberately failing branches, referenced in the PR description.

## Rollout

None. Repo-only.

## Open questions

- Confirm AGPL-3.0 for the Relay server (Apache-2.0 for the app is confirmed).
- Relay server language (TypeScript on Cloudflare Workers is the current leaning).
