# UI audit: light, dark, narrow, wide

This document records the final pass over the task-oriented shell that
replaced the old module-oriented navigation. The goal was parity between
light and dark appearance at both the minimum window size (860 × 560) and
a comfortable working size (1180 × 720).

## Method

- Build the Debug app and launch it with the QA switches below.
- Capture real window images with `screencapture -x -l <window-id>`.
- Repeat each screen in light and dark, narrow and wide where the screen
  can meaningfully change.
- Audit accessibility in code for icon-only controls, status rows, and
  card-level grouping.

| Screen | Light narrow | Light wide | Dark narrow |
| --- | --- | --- | --- |
| Library | yes | yes | yes |
| Bottle / Overview | yes | — | yes |
| Bottle / Games | yes | — | yes |
| Bottle / Settings | yes | — | — |
| Bottle / Activity (processes) | yes | — | — |
| Bottle / Activity (logs) | yes | yes | — |
| Global Activity | yes | — | — |
| Settings window | yes | — | — |
| Sidebar | yes | yes | yes |

Screens not covered by this pass: Winetricks sheet, Setup, bottle
creation/rename sheets, and program detail. They share the same tokens
and semantic colors but still need a visual pass.

## QA launch switches

All switches are `#if DEBUG` only.

| Switch | Effect |
| --- | --- |
| `--ui-light` | Force `NSAppearance(named: .aqua)` |
| `--ui-dark` | Force `NSAppearance(named: .darkAqua)` |
| `--ui-narrow` | Resize the main window to 860 × 560 |
| `--ui-wide` | Resize the main window to 1180 × 720 |
| `--ui-route=library` | Open the Library |
| `--ui-route=activity` | Open global Activity |
| `--ui-settings` | Open the Settings window |
| `--ui-tab=overview\|games\|settings\|activity` | Select a bottle tab |
| `--ui-activity=processes\|logs` | Select a bottle Activity pane |

Example:

```sh
open -n "$APP" --args --ui-light --ui-narrow --ui-tab=games
```

## Fixes from the pass

### Navigation and headings

- Removed `PageHeader` from global Activity and Settings. Both duplicated
  the toolbar title and, in Settings, the first Form section title.
- Renamed the Settings window title from “General” to “Settings”.
- Settings now has a minimum height of 560 so the engine and update
  sections are not clipped on first open.

### Bottle toolbar

- Hid the global engine picker and recipe-sync button inside a bottle.
  The bottle has its own engine binding in Settings, and the global
  controls made the narrow toolbar ambiguous.
- Hid the bottle-level Play button on the Games tab. The program-level
  Run button is the correct primary action there, so only one play
  control is visible at a time.
- Consolidated the log toolbar (sort, export, copy, delete, clean,
  verbose) into one actions menu.

### Programs

- Hid the pane Picker label that produced a duplicated “程序库” heading.
- Moved layout, sort, and “hide system noise” into one View menu, freeing
  the filter row at 860 pt.
- Added a visible “Browse other programs…” action to the header and the
  empty state. The old empty-state copy referenced a control that did
  not exist.
- Limited the View menu to controls that apply to the current pane.

### Logs

- Replaced the fixed three-column `HSplitView` with a responsive layout.
  Below 800 pt the program sidebar collapses into a program Picker above
  the run list; the run list and log detail remain side by side.
- This fixes the app sidebar collapsing to zero width and the log text
  being clipped at the minimum window size.
- Stopped overriding the window title with “Run logs”; the bottle name
  remains stable while the Activity tab and pane picker identify the
  screen.

### Processes

- Distinguish loading from an empty process list. The old view showed a
  spinner forever when `tasklist` returned no rows.
- Disable “End process” when nothing is selected.
- Disable alternating row backgrounds so empty table space no longer
  looks like a column of placeholder rows.

### Bottle overview

- Replaced the raw container path with a “Show in Finder” action. The
  full path remains in the tooltip.
- Hide the pin count pill when the count is zero.
- Sidebar engine labels now use a small engine-colored dot plus secondary
  text, so “Modern” no longer looks like a blue link.
- The Library grid uses a 230 pt minimum card width: two columns at
  860 pt, four at 1180 pt.

### Activity

- The global Activity page refreshes running bottles every two seconds,
  so the separate refresh toolbar button is gone. This also removes the
  pair of nearly identical circular-arrow icons at the top right.

### Accessibility

- Icon-only controls gained explicit labels: sidebar refresh, recipe
  sync, program pin/run, environment-row remove, and log actions.
- `StatusPill` is a single accessibility element.
- The bottle hero icon is hidden from VoiceOver, and the name, reveal
  button, and status pills are separate elements.
- The active activity card is combined into one announcement.

## Verification

```sh
swiftlint lint --strict
xcodebuild -project MacBottle.xcodeproj -scheme MacBottle -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
cd MacBottleKit && swift test
```

Result at the time of writing: 0 SwiftLint violations, Debug build
succeeds, 209 tests pass.

## Follow-up: appearance, settings entry, and the toolbar band

The first pass left two visible gaps that users hit immediately:

- **No way to choose dark mode.** The app followed the system, but Settings
  did not expose an override, and the Settings window was easy to miss.
- **The first card row could sit half-cut under the toolbar glass.**
  Scrolling the Library and coming back restored an offset that tucked the
  cards under the toolbar. A temporary top inset fixed the cut but added
  a visibly empty band; the inset was removed once the real cause (the
  restored scroll offset) was fixed.

Changes:

- Added an **Appearance** section to Settings with System / Light / Dark.
  The choice is stored in `appearanceMode`, applied at launch in
  `applicationWillFinishLaunching`, and applied immediately on change.
- Added an always-visible gear to the sidebar bottom bar. The Settings
  window is still available from the app menu and `⌘,`.
- Removed the extra top inset entirely. The window already lays the
  detail view below the titlebar/toolbar, and the native bottle `TabView`
  places its tab strip directly under the toolbar. No manual 52/80 pt
  padding is needed.
- The Library `ScrollView` gets a fresh identity on launch and whenever
  the user returns to Library, so it opens at the top instead of restoring
  a scrolled offset. The welcome card moved inside the scroll content.
- The sidebar bottom bar keeps “创建容器” on one line and uses an
  icon-only gear for Settings, so Chinese labels no longer wrap into
  vertical columns at the minimum sidebar width.

## Remaining limitations

- Automated VoiceOver traversal was not possible in the QA environment
  because Accessibility permission was not granted. The audit is
  code-level; a manual VoiceOver pass over Library, a bottle, Settings,
  and Activity is still recommended before release.
- The new strings are translated for English, Simplified Chinese, and
  Traditional Chinese. Other locales fall back to English until they are
  translated.

## 2026-11 visual polish pass

The first pass fixed clipping, navigation, and accessibility. This second
pass gives the main screens a clearer hierarchy without leaving the
native macOS vocabulary.

### Library

- Added a page subtitle with the game/installed counts and a row of
  compatibility filter chips with per-tier counts. The filtered-empty
  state now explains the filter and offers a reset.
- Added a Continue-playing rail for installed games that still exist in
  the recipe catalog; each card opens its bottle.
- Rebuilt the recipe card: 14 pt radius, hover lift and shadow, cover
  gradient, a green installed check, and shared compatibility/renderer
  badges with icons. Context menu adds details, open bottle, and copy ID.
- The welcome card is now a tinted banner with the brand gradient icon,
  so a first run has a clear primary action.

### Bottle

- Replaced the native `TabView` strip with a custom icon tab bar using a
  matched-geometry selection capsule and `⌘1`–`⌘4` shortcuts.
- The hero is a branded gradient card with a large gradient icon, status
  pills, and the decorative shipping-box watermark. Repeated program/pin
  numbers were removed from the hero; the metric grid below is the single
  source for those numbers.
- Added the metric grid: programs, pinned programs, Windows version, and
  active engine.
- Replaced the full-screen empty state with a three-step onboarding card
  (install → pin → play) and both install/browse actions.

### Programs

- Reduced the toolbar to the primary Run action plus one Actions menu;
  pin, config, block, reveal, history, expand/collapse, and refresh now
  live inside it.
- Rows use an accent-tinted icon well, a hover background, and a clearer
  metadata line (architecture, last run, folder) instead of three pills.
  The play button fills with the accent color on hover; pin fades in for
  unpinned rows.
- Disabled alternating row backgrounds so the list reads as cards rather
  than a spreadsheet.

### Sidebar and Activity

- Sidebar bottles now have deterministic colored avatars, a green running
  dot with process count, and a program count next to the engine label.
- Activity adds a three-metric strip (active bottles, running processes,
  current engine) and a proper empty card that links to the Library.

### Verification

- Debug build, `swift test` (260 tests), and `swiftlint lint --strict`
  all pass.
- Captured Library, Bottle overview, Games, Activity, and Settings in
  light and dark at 1180 × 720, plus Library and Bottle at the 860 × 560
  minimum. No clipping or duplicate headings found.

### Known trade-off

The custom bottle tab bar recreates the Games view when switching away
from it, so the local program filter/search resets. Bottle data, pins,
and launch state are unaffected. Keeping every tab alive would either
keep hidden `searchable` fields in the toolbar or run Activity polling
in the background, so the reset is the safer default for now.
