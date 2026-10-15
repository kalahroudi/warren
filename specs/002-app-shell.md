# 002 · App shell

Status: Draft · Phase 0 · Depends on: 001

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
- Idle budget: under 40 MB RSS with the popover closed and the window closed.

## Acceptance criteria

1. App starts and shows only a menu bar item.
2. Clicking the item toggles the popover; Escape or an outside click closes it.
3. ⌘O opens the main window; closing it returns the app to menu-bar-only.
4. All five sidebar sections render and navigate.
5. Light and dark appearance both render correctly.
6. Quitting from the popover exits the process.
7. Idle RSS is under 40 MB on Apple silicon (recorded in the PR).
8. UI components consume only the `StateProvider` interface.

## Test plan

Criteria 1 to 6 by a scripted UI test plus a manual checklist in the PR. Criterion 7 measured and pasted. Criterion 8 by a lint rule banning direct fixture imports from UI code.

## Rollout

None. Internal until real providers exist.

## Open questions

- Final app icon and menu bar glyph artwork.
