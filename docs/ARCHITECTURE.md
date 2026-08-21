# MacBottle Architecture

This document describes how MacBottle is organized, what each module owns,
and where a contributor should start reading.

## Origins

MacBottle is a fork of [Whisky](https://github.com/Whisky-App/Whisky), an
archived SwiftUI-based Wine wrapper for macOS. The core bottle management,
Wine invocation, and PE parsing code are inherited from Whisky with minimal
changes. The visible differences are:

- The **Recipe** subsystem — new to MacBottle, and the reason this project
  exists as a distinct fork.
- Branding — bundle identifiers, update feed, product name.
- A GPL-3.0 compliance package — `NOTICE`, this document, `LICENSE` unchanged.

## Module map

| Path | Role |
| --- | --- |
| `Whisky/` | Top-level macOS app target — AppDelegate, Views, Assets, localization |
| `WhiskyKit/` | Core library consumed by app and CLI (SwiftPM package) |
| `WhiskyKit/Recipe/` | MacBottle-only: recipe types, loader, applier, remote sync |
| `WhiskyKit/Recipes/` | MacBottle-only: shipped recipe JSON files |
| `WhiskyKit/WineEngine/` | MacBottle-only: `WineEngine` protocol, `CrossOverEngine`, catalog, launch policy |
| `WhiskyKit/Whisky/` | Bottle / Program / BottleSettings models |
| `WhiskyKit/Wine/` | Wine command invocation (uses WineEngine), launch coordinator, run logs |
| `WhiskyKit/NativeBridge/` | MacBottle-only: native Steam install path — `SteamCMDEngine` (login, app_update, validate, progress), `ChunkedDownloader`, `DepotStore`/`ContentStore`, `SteamClientSeeder`, VDF parser. Drives `Views/Recipe/GameInstaller`. |
| `WhiskyKit/WhiskyWine/` | Legacy shim. Forwards to `WineEngineRegistry`. |
| `WhiskyKit/PE/` | Windows PE file parser (imports, architecture, graphics API) |
| `WhiskyKit/Extensions/` | Foundation extensions |
| `WhiskyCmd/` | CLI companion |
| `WhiskyThumbnail/` | Finder thumbnail extension for PE files |
| `docs/` | This directory and recipe authoring guide |

Do not rename the Swift modules yet. A project-wide rename from `Whisky`
to `MacBottle` is planned but deferred until v0.1 is verified to compile
and run (tracked in `MIGRATION.md`).

## Runtime flow of a game launch

1. **User picks a bottle** in the macOS app UI.
2. **User selects a `Program`** inside that bottle (a `.exe` path).
3. (MacBottle addition) **User optionally attaches a `Recipe`** matching
   the program. Recipes are discovered via `RecipeStore.shared.loadAll()`.
4. Launch pipeline builds the environment dictionary:
   - Start with `Program.generateEnvironment()`.
   - Merge `BottleSettings.environmentVariables(wineEnv:)`.
   - (MacBottle addition) Merge recipe overrides via
     `RecipeApplier.apply(recipe, to:)`. **Recipe wins on conflict.**
5. `Wine.runProgram(...)` spawns `wine <exe>` with that environment,
   through the engine selected by `LaunchEnginePolicy`.

The recipe layer is intentionally additive. If no recipe is attached, the
code path is identical to upstream Whisky.

## Recipe subsystem

See `docs/RECIPE_AUTHORING.md` for the file format. The Swift side spans
two layers.

**Data layer (WhiskyKit):**

| Type | Responsibility |
| --- | --- |
| `Recipe.swift` | `Codable` data model. No behaviour. |
| `RecipeStore.swift` | Merges bundled recipes (shipped inside the app) with remote recipes (cached under Application Support). Remote wins on conflict because it's the most recently accepted source of truth. |
| `RecipeApplier.swift` | Pure-function environment merger. Side-effect free so it is trivially testable. |
| `RemoteRecipeSource.swift` | Fetches the manifest (`_index.json`) and individual recipes from raw.githubusercontent.com with ETag conditional GET. Network is abstracted via a closure so tests inject canned responses. |
| `RecipeCache.swift` | On-disk snapshot of the last accepted remote manifest plus every cached recipe file. NSLock-guarded, atomic writes. |
| `RecipeSyncDiff.swift` | Pure function turning (newRemote, lastAccepted, knownRecipes) into a sorted list of `RecipeChange` values. No I/O. |
| `RecipeSyncService.swift` | Orchestrator: `check()` returns a diff, `apply()` downloads additions/updates and removes deletions, updates meta only after at least one change has landed on disk. |

**UI layer (Whisky app):**

| Type | Responsibility |
| --- | --- |
| `Views/Recipe/RecipeSyncController.swift` | `@MainActor ObservableObject` wrapping `RecipeSyncService` for SwiftUI. Checks run only on explicit user action from the toolbar button; re-entrant clicks while a check or apply is in flight are ignored. |
| `Views/Recipe/RecipeSyncView.swift` | Modal sheet with per-row checkboxes, a summary header, and a "Sync selected" footer button. Presented from `RecipeSyncToolbarButton` (the global toolbar item) only when the diff is non-empty — nothing interrupts the user if there are no changes. |

Design choices worth knowing:

- **JSON, not YAML.** Foundation ships `JSONDecoder`; adding a YAML
  dependency would couple every build to a third-party parser.
- **Resources ship via SwiftPM `.copy("Recipes")`.** At build time, SwiftPM
  copies the whole `Recipes/` tree into `WhiskyKit_WhiskyKit.bundle` so
  `Bundle.module.url(forResource: "Recipes", ...)` finds it.
- **Strict on decode, lenient on missing directory.** A malformed recipe is
  logged and skipped so a single bad file does not break the rest of the
  set. The generated `_index.json` is filtered from the scan so the manifest
  never gets mistaken for a recipe.
- **Recipe wins on env conflict.** A recipe is a narrower, community-vetted
  source of truth than bottle defaults. Users who disagree can detach the
  recipe.
- **No GitHub Contents API.** Unauthenticated requests are rate-limited to
  60/hour. Instead the client reads a single `_index.json` manifest
  (regenerated by CI on every merge to `main`) and fetches recipe files
  directly from the raw.githubusercontent CDN, where rate limits are
  effectively unbounded for public repositories.
- **The accepted baseline is incremental.** Only changes that actually
  landed on disk enter `meta.index` — upserting the remote entry for
  successful added/updated outcomes and deleting the entry for successful
  removals. Rejected, unselected, or failed changes stay out of the
  baseline, so the next check re-surfaces them. The ETag is only saved
  when the baseline covers the full remote index; while outstanding
  changes remain, the ETag is cleared so the next check re-fetches and
  re-presents the diff. A fully-failed apply leaves the previous state
  intact.
- **Apply-time side effects (winetricks, registry) are out of scope for
  `RecipeApplier`.** They belong in a future `RecipeProvisioner` that runs
  once per bottle-recipe pairing at mount time, not on every launch.

## Wine engine abstraction

The `WineEngine` protocol under `WhiskyKit/Sources/WhiskyKit/WineEngine/`
isolates everything about "which Wine build this install uses" into a single
type. Today two concrete implementations ship — `CrossOverEngine` (the
Whisky/CrossOver-derived packaging) and `LocalPathEngine` (a locally
installed engine root, used for the D3DMetal path) — and the reason to keep
the abstraction is that:

- It turns a future engine swap into a one-line change
  (`WineEngineRegistry.shared.setCurrent(...)`) rather than a repo-wide
  find-and-replace.
- Tests substitute a `FakeEngine` pointing at the system temp directory,
  which makes it safe to exercise the engine-dependent paths without
  touching the user's real install.
- It separates the GPL-clean, MacBottle-authored interface from the
  CrossOver-derived binary distribution, which is useful if the project ever
  ships a pure upstream Wine variant with different licensing.

`LaunchEnginePolicy` sits on top and decides which engine a given launch
should use, in priority order: bottle-pinned engine → recipe `renderer` →
PE import profile + runtime profile (`classic32` and friends) → bottle DXVK
toggle → keep current engine. The decision is derived from real executable
scans (`PEImportScanner`, `RuntimeLaunchOptimizer`), not from guesses, and
auto-selected engines are applied for the launch only, with the user's
saved selection restored afterwards.

`WhiskyWineInstaller` is preserved as a thin shim forwarding to
`WineEngineRegistry.shared.current`, so every existing call site keeps
working. New code should call the registry directly.

## Launch experience layer

The `WhiskyKit/Wine/` folder hosts the pieces that make launches reliable
on real hardware, each independently testable:

- `ProgramLaunchCoordinator` — owns the launch lifecycle and status flow.
- `RuntimeLaunchOptimizer` — profiles the executable to detect legacy
  32-bit binaries and other launch-affecting traits.
- `D3DMetalCapability` — detects whether a local GPTK/D3DMetal bridge is
  available before offering the D3DMetal path.
- `DisplayPolicy` — decides display-related launch behavior.
- `ProgramRunLogStore` — persists per-run logs surfaced in the UI.
- `BottleForceStop` — host-side force stop for frozen Wine runtimes.

## Testing

Unit tests live under `WhiskyKit/Tests/WhiskyKitTests/`. MacBottle-added
tests use the `Recipe*` prefix (recipes, sync, cache, diff) or descriptive
suffixes for the launch layer (launch coordinator, runtime optimizer, engine
policy, display policy, run log store). `RecipeApplier` should have 100%
line coverage because every game launch goes through it.

## Current state and what's next

- v0.5 (remote recipe sync) shipped: the data layer (`RecipeCache`,
  `RemoteRecipeSource`), the sync engine (`RecipeSyncService`), and the
  diff UI (`RecipeSyncView` + `RecipeSyncToolbarButton`) are all live.
  See `PROJECT_PLAN.md` for the v0.5.1–v0.5.3 sub-phase breakdown.
- v0.7 added the native install-and-play flow: `NativeBridge/` (SteamCMD
  engine, chunked downloader, depot/content stores) plus
  `Views/Recipe/GameInstaller` and `GameDetailSheet`. This is the largest
  undocumented-in-README subsystem; this module map is its canonical entry
  point for contributors.
- The engine layer (`WineEngine` protocol, `CrossOverEngine`,
  `LocalPathEngine`, `LaunchEnginePolicy`) is in place. v0.6's goal of a
  second concrete engine (pure upstream Wine or GPTK2) is still open.
- The CI RecipeLint workflow validates the entire `Recipes/` tree through
  the real `Recipe` Swift type, so schema evolution only requires editing
  `Recipe.swift` and migrating existing recipes. The `installer` and
  `main_exe` fields (added for the install flow) are optional and
  documented in `docs/RECIPE_AUTHORING.md`.
