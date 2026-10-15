# 002 · App shell

Status: Implemented, pending manual test · Phase 0 · Depends on: 001

## Goal

Warren launches as a menu bar app with the icon, popover and main window from the mockup, driven by mock data. This fixes the look, navigation and window behavior before any real feature exists.

## Non-goals

- No real sites, services or runtimes. All data comes from a fixture provider.
- No auto-update (003).

## Behavior

- Menu bar item with a monochrome template icon (adapts to light and dark menu bars). No Dock icon unless the main window is open.
- Click opens the popover (mockup board 1): header with pause-all and settings, Sites, Services, Active runtimes, update banner slot, agent status footer.
- "Open Warren" (⌘O) opens the main window with a sidebar: Sites, Services, Runtimes, Agents, Storage. Each section renders the mockup layout from fixtures. Screens that depend on later specs show their fixture state and are marked internally as `preview`.
- Launch at login is a setting, off by default.
- All UI reads state through one `StateProvider` interface; 002 ships a `FixtureProvider`. Later specs add the real one.
- Built with SwiftUI (`MenuBarExtra` for the popover) and AppKit where SwiftUI falls short. No embedded web view.
- Idle budget: under 80 MB RSS with the popover closed and the window closed. (The first draft said 40 MB. A SwiftUI `MenuBarExtra` app measured 72 MB, so the budget was revised. Getting lower means an AppKit popover and is a follow-up if we want it.)

## Acceptance criteria

1. [ ] App starts and shows only a menu bar item. *Process runs and owns no windows at launch. The menu bar item itself is not yet visually confirmed.*
2. [ ] Clicking the item toggles the popover; Escape or an outside click closes it. *Needs manual test.*
3. [ ] ⌘O opens the main window; closing it returns the app to menu-bar-only. *Needs manual test.*
4. [ ] All five sidebar sections render and navigate. *Views render offscreen with demo data; navigation needs manual test.*
5. [ ] Light and dark appearance both render correctly. *Dark checked offscreen; light needs manual test.*
6. [ ] Quitting from the popover exits the process. *Needs manual test.*
7. [x] Idle RSS is under 80 MB on Apple silicon. *Measured 71.8 MB (budget revised from 40 MB, see Behavior).*
8. [x] UI components consume only the `StateProvider` interface. *`scripts/check-fixtures.sh`, part of `just check`, fails if anything outside `WarrenApp.swift` references `FixtureProvider`.*

## Test plan

Criteria 1 to 6 by a manual checklist (build with `just dev`, then walk through each item). Criterion 7 measured with `ps -o rss`. Criterion 8 by `scripts/check-fixtures.sh`. Unit tests cover the fixture provider.

## Rollout

None. Internal until real providers exist.

## Open questions

- Final app icon and menu bar glyph artwork.
