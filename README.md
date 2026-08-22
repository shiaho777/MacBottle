<div align="center">

<img src="Whisky/Assets.xcassets/AppIcon.appiconset/512@2x.png" width="96" alt="MacBottle icon" />

# MacBottle 🍾

### Play Windows games on your Mac. Simply.

**MacBottle is a modern Wine wrapper for Apple Silicon, maintained by its community. Pick a container, drop your Windows game in, hit play — no terminal, no hand-configured Wine prefixes, no guesswork. And when a game needs more than the defaults, a community recipe applies the right environment, winetricks, and registry settings for you.**

**English** · [简体中文](.github/docs/README_CN.md)

[![License](https://img.shields.io/badge/License-GPL--3.0-blue?style=for-the-badge)](LICENSE)
[![Platform](https://img.shields.io/badge/macOS-14%2B-black?style=for-the-badge&logo=apple&logoColor=white)](#system-requirements)
[![Chip](https://img.shields.io/badge/Apple%20Silicon-Only-red?style=for-the-badge)](#system-requirements)
[![Swift](https://img.shields.io/badge/Swift-6-orange?style=for-the-badge&logo=swift&logoColor=white)](#)

</div>

<p align="center">
  <a href="#why-macbottle">Why MacBottle</a> ·
  <a href="#capability-overview">Capability overview</a> ·
  <a href="#what-you-can-build">What you can build</a> ·
  <a href="#full-feature-map">Feature map</a> ·
  <a href="#recipes">Recipes</a> ·
  <a href="#architecture">Architecture</a> ·
  <a href="#roadmap">Roadmap</a> ·
  <a href="#contributing">Contributing</a>
</p>

---

## Why MacBottle

Running Windows games on Apple Silicon shouldn't require a command-line tutorial. MacBottle does that work for you, and keeps going where a default setup stops:

- **Actively maintained.** Open source and under continuous development — fixes, new recipes, and support for the latest Apple Silicon and macOS land as they arrive.
- **No terminal required.** There is no need to build wine prefixes by hand or memorize `WINEPREFIX`. MacBottle creates, configures, and launches every bottle from a native macOS window.
- **Free and open source.** Everything MacBottle does is GPL-3.0 and built in public — no license fees, no subscriptions, no locked-in features.
- **Recipes that know each game.** A recipe is one JSON file describing what a single game needs: environment variables, winetricks verbs, registry tweaks, and the right renderer. Community-verified, synced from a shared catalog, and applied automatically at launch. Most wrappers leave you to guess; a recipe hands MacBottle the answer.
- **The right engine, chosen automatically.** Every launch inspects the executable (PE imports and runtime profile) and, with any attached recipe, picks **D3DMetal**, **DXVK**, or **WineD3D** — then runs the matching Wine engine without asking.
- **Chinese and English, written together.** The UI, recipes, and documentation are authored in both languages from the first line, not translated in afterward.

---

## Capability overview

A quick scan of what's in the box.

| Area | Highlights |
| --- | --- |
| **Bottle management** | Create, configure, rename, and delete bottles; pins/shortcuts; per-bottle engine binding |
| **Game recipes** | Community JSON recipes (Steam / GOG / generic), bundled catalog + remote sync with ETag cache, diff UI with per-row selection |
| **Rendering** | Auto-selected **D3DMetal** (Apple GPTK), **DXVK** (+ async, HUD), or **WineD3D**; Metal HUD/trace; DXR toggle |
| **Wine engine layer** | CrossOver-based engine today; pluggable `WineEngine` protocol so pure upstream Wine can slot in later |
| **Launch experience** | Wineserver prewarm, launch-status feedback, per-program run logs, force-stop for frozen runtimes, stale-status reconciliation |
| **Bottle internals** | Winetricks catalog with categorized verbs, environment variables, Windows version & enhanced-sync (msync/esync) selection, AVX toggle |
| **Integration** | CLI companion (`WhiskyCmd`), Finder thumbnail previews for `.exe` files, shader-cache wiping |

---

## What you can build

| Source | What MacBottle does | Good for |
| --- | --- | --- |
| Steam library | Point at the game's `.exe`; recipe (if any) applies tweaks automatically | AAA and indie titles on Apple Silicon |
| GOG / DRM-free installers | Install once into a bottle, launch from the programs list | The games you actually own outright |
| Retail / other installers | Attach a `generic` recipe or configure manually | Origin, Battle.net, random installers |
| Legacy 32-bit titles | `classic32` runtime profile forces the WineD3D path | Old games that never got 64-bit ports |
| Non-game Windows apps | Works the same as games — bottles don't care | Office tools, utilities, old shareware |

---

## Full feature map

MacBottle has more switches than a casual glance suggests. The sections below group them by use case, kept collapsible so the top of the page stays scannable.

<details>
<summary><b>🍾 Bottle management</b></summary>

- **One-click creation** — name a bottle, pick a Windows version, go. No prefix path to type, no config file to edit.
- **Per-bottle settings** — environment variables, Windows version (win10/…), enhanced sync (**msync** default, or esync), AVX toggle, Retina mode, DXR.
- **Engine binding** — pin a bottle to a specific Wine engine, or leave it on auto-select (`LaunchEnginePolicy` decides per launch).
- **Pins** — pin any installed program to the bottle home screen as a launch shortcut, with its own environment arguments.
- **Winetricks catalog** — categorized verb table with one-click install (vcrun, dotnet, and friends).
- **Housekeeping** — rename, delete, force-stop every running process in a bottle from the menu bar.

</details>

<details>
<summary><b>🧪 Recipe system</b></summary>

- **Bundled catalog** — recipes ship inside the app and load at startup; zero configuration required.
- **Remote sync** — the catalog updates from a GitHub-backed manifest (`_index.json`, regenerated by CI on every merge) with ETag conditional GETs against the raw CDN — effectively unbounded rate limits, no API keys. Every download is verified against a SHA-256 digest from the manifest before it is accepted.
- **Diff UI** — entering the game list checks for changes and shows a sheet with `+ new / − removed / ~ updated`, per-row checkboxes, and a "sync selected" footer. Nothing interrupts you when there are no changes.
- **Game detail sheets & installer** — browse recipes as a library, read compatibility notes, and run a guided install that creates a bottle, applies winetricks/registry, and launches.
- **Recipe wins on conflict** — a recipe is a narrower, community-vetted source of truth than bottle defaults; detach it if you disagree.

</details>

<details>
<summary><b>⚙️ Wine engine layer</b></summary>

- **`WineEngine` protocol** — everything about "which Wine build this install uses" lives behind one interface; a future engine swap is a one-line registry change, not a repo-wide search-and-replace.
- **`CrossOverEngine`** — the first concrete engine, carrying the Whisky/CrossOver-derived packaging forward.
- **`LaunchEnginePolicy`** — per-launch decision engine: scans PE imports + runtime profile, honors bottle pinning and recipe `renderer`, and falls back gracefully when D3DMetal isn't installed.
- **Temporary engine switching** — auto-select swaps engines for the launch only; your saved selection is restored afterwards.

</details>

<details>
<summary><b>🚀 Launch experience</b></summary>

- **Wineserver prewarm** — the engine is warmed before the game launches, so first clicks aren't dead air.
- **Launch status feedback** — the UI reflects real state instead of silently sitting on a spinner.
- **Run logs** — every program run writes a log you can open from the UI (`⌘L` opens the logs folder); old logs are cleaned up automatically after 7 days.
- **Force-stop** — host-side force stop for frozen Wine runtimes, with `⌘⇧K` to kill all bottles; stale "running" status is reconciled when the game process actually dies.

</details>

<details>
<summary><b>🔌 Integration & tooling</b></summary>

- **CLI companion** — `WhiskyCmd` exposes bottle and launch workflows from the terminal, installed from the app menu.
- **Finder thumbnails** — a Quick Look–style extension renders previews for Windows executables in Finder.
- **Shader-cache management** — one menu item kills bottles and wipes D3DMetal shader caches when graphics misbehave.
- **Setup flow** — first-run assistant for Rosetta 2 and the Wine engine download/install, so a brand-new Mac goes from zero to gaming in one sitting.

</details>

---

## Recipes

Recipes are the reason this project exists as a distinct fork, and they are MacBottle's primary growth mechanism. A recipe is a single JSON file — no Swift knowledge required to contribute one:

```
WhiskyKit/Sources/WhiskyKit/Recipes/
  steam/<AppID>.json       # e.g. steam/2050650.json for Black Myth: Wukong
  gog/<ProductID>.json     # e.g. gog/1207658924.json for The Witcher 2
  generic/<slug>.json      # out-of-platform titles or retail installers
```

Each recipe declares the game's DirectX version, minimum macOS, recommended renderer, optional winetricks verbs, environment variables, registry tweaks, and an honest compatibility tier (platinum → broken, on the ProtonDB scale). CI validates every file against the real Swift `Recipe` type, so a recipe either decodes or it tells you exactly which field is wrong.

The full schema, examples, and review criteria live in [`docs/RECIPE_AUTHORING.md`](docs/RECIPE_AUTHORING.md).

---

## Architecture

```
Whisky/                  macOS app target — SwiftUI views, bottle/program UX
WhiskyKit/               Core library (SwiftPM) — models, Wine invocation, recipes
  ├─ Recipe/             Recipe types, loader, applier, remote sync, diff
  ├─ Recipes/            Shipped recipe JSON files
  ├─ WineEngine/         Engine protocol, CrossOverEngine, catalog, launch policy
  ├─ Whisky/             Bottle / Program / settings models
  ├─ Wine/               Launch coordinator, run logs, force-stop, optimizers
  └─ PE/                 Windows PE parser (imports, architecture, graphics API)
WhiskyCmd/               CLI companion
WhiskyThumbnail/         Finder thumbnail extension for PE files
```

A game launch merges environments in a strict order — program defaults → bottle settings → recipe overrides (recipe wins) — then spawns `wine <exe>` through the engine selected by `LaunchEnginePolicy`. If no recipe is attached, the path is identical to upstream Whisky; the recipe layer is purely additive.

The complete design rationale lives in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

---

## Roadmap

The plan runs as four parallel tracks — **engine & distribution**, **recipe ecosystem**, **release engineering**, and **platform & branding** — with version numbers as checkpoints:

| Version | Status | Core deliverable |
| -- | -- | -- |
| v0.1 – v0.5 | ✅ Done | Brand switch, runnable app, recipe system, CI + docs + Recipe UI, engine abstraction, remote recipe sync |
| v0.6 | 🚧 Wrapping up | User-switchable engines; a second engine implementation is evaluated separately on the engine track |
| v0.7 | Planned | Self-owned engine distribution (off archived upstream infrastructure); release engineering: real update feed, signed & notarized builds |
| v1.0 | Goal | Formal release, gated by an explicit definition of done |

The full plan — including the track breakdown and the explicit non-goals (no virtualization, no DRM/anti-cheat workarounds, no game content) — is in [`PROJECT_PLAN.md`](PROJECT_PLAN.md).

---

## System requirements

- **CPU:** Apple Silicon (M1 / M2 / M3 / M4 series)
- **OS:** macOS Sonoma 14.0 or later
- **Recommended:** 16 GB RAM or more, macOS 15 Sequoia or later

MacBottle does not ship game content. You obtain games through legitimate channels (Steam, Epic, GOG, Battle.net); MacBottle only concerns itself with running them well on your Mac.

---

## Contributing

| Lane | What you do | Effort |
| --- | --- | --- |
| **Recipes** | Get a game running, then add or update its JSON recipe — the highest-impact contribution there is | hours |
| **Issues** | Report a bug, request a feature, or file a recipe request for a game you can't run | minutes |
| **Code** | Fix a bug or build a feature in the Swift app / WhiskyKit | days |
| **Translation** | Help keep UI copy and docs bilingual (中文 / English) | varies |

All work follows one delivery loop — **Issue → PR → main → CI → merge** (issues close on merge via `Fixes #N` only). The full guide, including the required CI checks and code style, is in [`CONTRIBUTING.md`](CONTRIBUTING.md).

---

## Whisky heritage & credits

MacBottle is a derivative of [Whisky](https://github.com/Whisky-App/Whisky) (created by Isaac Marovitz, GPL-3.0, archived 2025-05-11), and stands on the shoulders of the projects that made Wine-on-Mac possible: CrossOver/WineHQ, Apple's D3DMetal (Game Porting Toolkit), DXVK-macOS, MoltenVK, wine-msync, Sparkle, and more. All original authorship and attribution are preserved in every inherited file and in [`NOTICE`](NOTICE).

## License

[GPL-3.0](LICENSE), consistent with upstream Whisky.

Note: Apple's D3DMetal is a closed-source component with its own license terms. MacBottle does not redistribute D3DMetal itself.

<div align="center">

**Open source · Built for Apple Silicon · Play more, configure less**

</div>
