# Contributing to Warren

## The one rule

**One spec is one PR.** Behavior that users or agents can observe starts as a file in `specs/`. Read [`specs/000-process.md`](specs/000-process.md) first; it is short.

1. Pick a spec from [`specs/ROADMAP.md`](specs/ROADMAP.md), or propose a new one with the template.
2. Open a draft PR with the spec text. Reviewers agree on behavior and acceptance criteria.
3. Implement against the spec in the same PR. Check each acceptance criterion off with a link to its test.
4. Bug fixes and refactors do not need a spec.

## Sign your commits (DCO)

Every commit needs a `Signed-off-by` line, certifying the [Developer Certificate of Origin](https://developercertificate.org/):

```sh
git commit -s -m "Add site registry"
```

CI rejects pull requests with unsigned commits.

## Before you push

```sh
just check
```

Every Swift and shell source file starts with an SPDX header:

```swift
// SPDX-License-Identifier: Apache-2.0
```

## Code of conduct

Be kind, assume good faith, and keep review comments about the code.
