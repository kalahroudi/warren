# 000 · Spec-driven development process

Status: Proposed · Phase 0

## Rule

**One spec is one PR.** The PR adds or updates the spec file and the code that satisfies it, together. Reviewers approve the spec first; the code is judged against it.

## Lifecycle

1. **Draft:** spec PR opened as a draft, with the code not yet written, to agree on behavior.
2. **Accepted:** reviewers approve the spec text. Status becomes `Accepted`.
3. **Implemented:** code lands in the same PR. Every acceptance criterion is checked off with a link to its test.
4. **Merged:** status becomes `Shipped`. A shipped spec is only changed by a later spec that says `Amends NNN`.

Small bug fixes and refactors do not need a spec. Anything that changes behavior users or agents can observe does.

## Template

Every spec in `specs/NNN-short-name.md` has these sections, in order:

- **Status / Phase / Depends on / Amends**
- **Goal:** one paragraph, the user-visible outcome.
- **Non-goals:** what this spec deliberately does not do.
- **App surface:** how a user does this in the app, with no terminal. The CLI and MCP are additional, never the only way. A spec with no app surface says why.
- **Prior art:** existing stable tools and libraries considered, which one we use and why. Building our own needs a stated reason. Start from `docs/prior-art.md`.
- **Behavior:** precise description, with examples and the UI states from the mockup where relevant.
- **Acceptance criteria:** numbered, each independently testable.
- **Test plan:** how each criterion is verified (unit, integration, manual).
- **Rollout:** flags, migrations, and anything affecting updates.
- **Open questions:** decisions still needed; must be empty before `Accepted`.

## Principles every spec must respect

- **App first:** every user-facing capability must be reachable from the app, including its one-time setup. The CLI is for developers and agents, and shares the same core code.
- **Reuse before build:** do not reinvent anything that already exists and is stable. Prefer proven tools and libraries, checked for license, maintenance, macOS support and size. Custom code needs a reason written in the spec.
- **Light:** idle footprint is a feature. Specs state their memory and disk impact.
- **Easy to update:** no spec may require manual user steps on upgrade. Data migrations are versioned and reversible.
- **Native first:** services and runtimes run natively; containers are an optional driver.
- **Disposable dependencies:** anything regenerable must be reproducible from files in the repo (lockfile, `.warren.toml`).
- **Agent-parity:** if a user can do it in the UI, a spec must say whether and how an agent can do it through MCP, and which actions need approval.
- **Safe by default:** running code from a repo the user did not write needs explicit consent per command.

## Open source model

- The desktop app, the core library, the service catalog, **and the Relay server** are open source.
- Licenses (proposed): app, core and catalog under Apache-2.0; Relay server under AGPL-3.0, so the code stays open even when run as a hosted service.
- The hosted service is the same code, operated by us. Self-hosting must never be a degraded mode: any feature available in hosted mode is available when self-hosting, except the operator's own billing and domain infrastructure.
- Contributions use a DCO sign-off. The Warren name and logo are covered by a trademark policy.

## Numbering

Specs are numbered in the order they are written, not the order they ship. The phase and dependency fields give the real order. See `ROADMAP.md`.
