# MacBottle Architecture

This document describes how MacBottle is organized, what each module owns,
and where a contributor should start reading.

## Origins

MacBottle is a fork of [Whisky](https://github.com/Whisky-App/Whisky), an
archived SwiftUI-based Wine wrapper for macOS. The core bottle management,
Wine invocation, and PE parsing code are inherited from Whisky with minimal
changes. The visible differences are:

- The **Recipe** subsystem, which is new to MacBottle and is the reason
  this project exists as a distinct fork.
- Branding (bundle identifiers, update feed, product name).
- A GPL-3.0 compliance package (`NOTICE`, this document, `LICENSE` unchanged).

## Module map

```
.
├── Whisky/                  Top-level macOS app target
│   └── AppDelegate, Views, Assets, localization
├── WhiskyKit/               Core library consumed by app and CLI
│   ├── Recipe/              MacBottle-only: recipe types, loader, applier
│   ├── Recipes/             MacBottle-only: shipped recipe JSON files
│   ├── WineEngine/          MacBottle-only: WineEngine protocol, CrossOverEngine, registry
│   ├── Whisky/              Bottle / Program / BottleSettings
│   ├── Wine/                Wine command invocation (uses WineEngine)
│   ├── WhiskyWine/          Legacy shim. Forwards to WineEngineRegistry.
│   ├── PE/                  Windows PE file parser
│   └── Extensions/          Foundation extensions
├── WhiskyCmd/               CLI companion
├── WhiskyThumbnail/         Finder thumbnail extension for PE files
└── docs/                    This directory
```

Do not rename these Swift modules yet. A project-wide rename from `Whisky`
to `MacBottle` is planned but deferred until v0.1 is verified to compile
and run.

## Runtime flow of a game launch

1. **User picks a bottle** in the macOS app UI.
2. **User selects a `Program`** inside that bottle (a `.exe` path).
3. (MacBottle addition) **User optionally attaches a `Recipe`** matching
   the program. Recipes are discovered via
   `RecipeStore.shared.loadAll()`.
4. Launch pipeline builds the environment dictionary:
   - Start with `Program.generateEnvironment()`.
   - Merge `BottleSettings.environmentVariables(wineEnv:)`.
   - (MacBottle addition) Merge recipe overrides via
     `RecipeApplier.apply(recipe, to:)`. Recipe wins on conflict.
5. `Wine.runProgram(...)` spawns `wine <exe>` with that environment.

The recipe layer is intentionally additive. If no recipe is attached, the
code path is identical to upstream Whisky.

## Recipe subsystem

See `docs/RECIPE_AUTHORING.md` for the file format. The Swift side spans
two layers:

**Data layer (WhiskyKit):**

- `Recipe.swift` — `Codable` data model. No behaviour.
- `RecipeStore.swift` — Merges bundled recipes (shipped inside the app)
  with remote recipes (cached under Application Support). Remote wins
  on conflict because it's the most recently accepted source of truth.
- `RecipeApplier.swift` — Pure-function environment merger. Side-effect
  free so it is trivially testable.
- `RemoteRecipeSource.swift` — Fetches the manifest (`_index.json`) and
  individual recipes from raw.githubusercontent.com with ETag
  conditional GET. Network is abstracted via a closure so tests inject
  canned responses.
- `RecipeCache.swift` — On-disk snapshot of the last accepted remote
  manifest plus every cached recipe file. NSLock-guarded, atomic writes.
- `RecipeSyncDiff.swift` — Pure function turning (newRemote,
  lastAccepted, knownRecipes) into a sorted list of `RecipeChange`
  values. No I/O.
- `RecipeSyncService.swift` — Orchestrator: `check()` returns a diff,
  `apply()` downloads additions/updates and removes deletions, updates
  meta only after at least one change has landed on disk.

**UI layer (Whisky app):**

- `Views/Recipe/RecipeSyncController.swift` — `@MainActor
  ObservableObject` that wraps `RecipeSyncService` for SwiftUI. Throttles
  checks to once per 10 seconds per process so `onAppear` navigation
  does not hammer the network.
- `Views/Recipe/RecipeSyncView.swift` — Modal sheet with per-row
  checkboxes, a summary header, and a "Sync selected" footer button.
  Presented from `BottleView` via `.sheet(item:)` only when the diff
  is non-empty — nothing interrupts the user if there are no changes.

Design choices worth knowing:

- **JSON, not YAML.** Foundation ships `JSONDecoder`; adding a YAML
  dependency would couple every build to a third-party parser.
- **Resources ship via SwiftPM `.copy("Recipes")`.** At build time,
  SwiftPM copies the whole `Recipes/` tree into `WhiskyKit_WhiskyKit.bundle`
  so `Bundle.module.url(forResource: "Recipes", ...)` finds it.
- **Strict on decode, lenient on missing directory.** A malformed recipe
  is logged and skipped so a single bad file does not break the rest of
  the set. The generated `_index.json` is filtered from the scan so the
  manifest never gets mistaken for a recipe.
- **Recipe wins on env conflict.** A recipe is a narrower, community-vetted
  source of truth than bottle defaults. Users who disagree can detach the
  recipe.
- **No GitHub Contents API.** Unauthenticated requests are rate-limited
  to 60/hour. Instead the client reads a single `_index.json` manifest
  (regenerated by CI on every merge to `main`) and fetches recipe files
  directly from the raw.githubusercontent CDN, where rate limits are
  effectively unbounded for public repositories.
- **Meta updates only on partial success.** If the user selects 5
  changes and 3 download but 2 fail, the 3 are cached and the meta
  records the full new index so the remaining 2 reappear on the next
  check. Fully-failed applies leave the previous state intact.
- **Apply-time side effects (winetricks, registry) are out of scope for
  `RecipeApplier`.** They belong in a future `RecipeProvisioner` that
  runs once per bottle-recipe pairing at mount time, not on every launch.

## Testing

Unit tests live under `WhiskyKit/Tests/WhiskyKitTests/`. MacBottle-added
tests use the `Recipe*` prefix. `RecipeApplier` should have 100% line
coverage because every game launch goes through it.

## Wine engine abstraction

The `WineEngine` protocol under `WhiskyKit/Sources/WhiskyKit/WineEngine/`
isolates everything about "which Wine build this install uses" into a
single type. The reason to have this layer even with only one concrete
implementation (`CrossOverEngine`) is that:

- It turns a future engine swap into a one-line change
  (`WineEngineRegistry.shared.setCurrent(...)`) rather than a repo-wide
  find-and-replace.
- Tests substitute a `FakeEngine` pointing at the system temp directory,
  which makes it safe to exercise the engine-dependent paths without
  touching the user's real install.
- It separates the GPL-clean, MacBottle-authored interface from the
  CrossOver-derived binary distribution, which is useful if the project
  ever ships a pure upstream Wine variant with different licensing.

`WhiskyWineInstaller` is preserved as a thin shim forwarding to
`WineEngineRegistry.shared.current`, so every existing call site keeps
working. New code should call the registry directly.

## Continuing beyond v0.4

- v0.5 introduces a user-facing engine selector once a second concrete
  engine (pure upstream Wine) ships. The Recipe schema will grow a
  `min_wine` field at that point.
- The CI RecipeLint workflow already validates the entire `Recipes/`
  tree through the real `Recipe` Swift type, so schema evolution only
  requires editing `Recipe.swift` and migrating existing recipes.
