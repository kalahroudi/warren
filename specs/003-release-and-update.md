# 003 · Release pipeline and auto-update

Status: Draft · Phase 0 · Depends on: 002

## Goal

Every tagged release produces a signed, notarized macOS build, and installed apps update themselves with small downloads and no manual steps. Updating must be easy from day one.

## Non-goals

- No Windows or Linux builds yet.
- No in-app changelog beyond a link.

## Behavior

- Release workflow on a version tag builds universal binaries (Apple silicon and Intel), signs, notarizes, and publishes a `.dmg` and an update manifest.
- Update channels: `stable` and `beta`. Default `stable`.
- The app checks for updates on launch and daily. The popover shows the "Warren x.y.z is ready" banner from the mockup with a delta size.
- Updates use Sparkle: an EdDSA-signed appcast, binary delta updates, and signature verification before install. Unsigned or mismatched payloads are rejected.
- Applying an update stops managed processes cleanly, replaces the app, and relaunches. Managed services come back to their previous state.
- User data under `~/Warren/` is never touched by an update. Data migrations are versioned, run on first launch of a new version, and a backup is taken first.
- A failed update leaves the previous version runnable.

## Acceptance criteria

1. A tag push produces a notarized `.dmg` that passes Gatekeeper on a clean Mac.
2. The manifest lists the version, signature, delta and full-download URLs.
3. App on version N sees N+1 and shows the update banner.
4. Applying the update installs N+1 and relaunches without user action beyond one click.
5. A tampered payload is rejected and the app keeps running version N.
6. Data directory contents are unchanged by an update unless a versioned migration ran, which took a backup first.
7. The beta channel can be selected in settings and receives pre-releases only.

## Test plan

Release workflow exercised on a test tag. Criteria 3 to 6 verified with two consecutive test releases on a clean VM. Criterion 5 by a signature-mismatch fixture.

## Rollout

Needs Apple Developer credentials and the update signing key stored as CI secrets. Key rotation procedure documented in `docs/releasing.md`.

## Open questions

- Hosting for update artifacts (GitHub Releases versus object storage with a CDN).
- Whether the hosted service (025) should also serve update manifests for self-hosters.
