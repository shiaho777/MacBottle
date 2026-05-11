# Writing a Recipe

A recipe is a single JSON file describing how to run a specific Windows game
on macOS via a MacBottle bottle. Each recipe lives under
`WhiskyKit/Sources/WhiskyKit/Recipes/<platform>/<id>.json` and is shipped
inside the WhiskyKit bundle at build time.

## Quick start

1. Install the game and get it running in MacBottle on your Apple Silicon Mac.
2. Note every setting you changed from the defaults: environment variables,
   winetricks verbs, registry tweaks, renderer choice.
3. Copy the closest existing recipe in the same platform folder and edit it.
4. Open a PR. CI will validate your file against the schema below.

## File location

```
WhiskyKit/Sources/WhiskyKit/Recipes/
  steam/<AppID>.json         # e.g. steam/2050650.json for Black Myth: Wukong
  gog/<ProductID>.json       # e.g. gog/1207658924.json for The Witcher 2
  generic/<slug>.json        # out-of-platform titles or retail installers
```

The filename stem should match the numeric id of the recipe's `id` field, so
reviewers can find a file by platform id without grep.

## Schema (v1)

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `schema` | integer | yes | Must be `1`. |
| `id` | string | yes | `<platform>.<platformID>`. Pattern: `^(steam\|gog\|generic)\.[A-Za-z0-9_-]+$`. |
| `title` | string | yes | 1-200 chars, human readable. |
| `icon_url` | string | no | HTTPS URL to a cover image (JPEG/PNG). Steam header art is `https://cdn.cloudflare.steamstatic.com/steam/apps/<AppID>/header.jpg`. ~460×215 or square, under 200 KB recommended. |
| `dx_version` | enum | yes | `d3d9` \| `d3d10` \| `d3d11` \| `d3d12` \| `vulkan` \| `opengl`. |
| `min_macos` | string | yes | Semantic version, e.g. `14.0`. |
| `renderer` | enum | yes | `d3dmetal` (default, Apple Silicon) \| `dxvk` \| `wined3d`. |
| `winetricks` | string[] | no | Verbs to install, lowercase. Example: `["vcrun2022", "dotnet48"]`. |
| `env` | object | no | String-to-string map. Keys are env vars. Example: `{"WINEESYNC": "1"}`. |
| `registry` | object[] | no | See below. |
| `compatibility` | enum | yes | `platinum` \| `gold` \| `silver` \| `bronze` \| `broken`. |
| `notes` | string | no | Up to 2000 chars, Markdown allowed, shown to users. |

### `registry` object shape

```json
{
  "path": "HKCU\\Software\\Wine\\Direct3D",
  "key": "csmt",
  "type": "REG_SZ",
  "value": "enabled"
}
```

- `path` must start with `HKCU\\`, `HKLM\\`, `HKCR\\`, `HKU\\`, or `HKCC\\`.
- `type` is one of `REG_SZ`, `REG_DWORD`, `REG_BINARY`.

### Compatibility tiers

Mirrors the ProtonDB scale; choose honestly. If in doubt, go one tier lower.

| Tier | Meaning |
| --- | --- |
| `platinum` | Runs perfectly out of the box. |
| `gold` | Runs perfectly with minor tweaks (some env vars or winetricks). |
| `silver` | Playable with noticeable issues (stutter, occasional crashes). |
| `bronze` | Runs but with significant issues (major bugs, instability). |
| `broken` | Does not run or crashes on launch. |

## Minimum viable recipe

```json
{
  "schema": 1,
  "id": "steam.105600",
  "title": "Terraria",
  "dx_version": "d3d9",
  "min_macos": "14.0",
  "renderer": "wined3d",
  "compatibility": "platinum"
}
```

## Recommended shape (Steam title)

```json
{
  "schema": 1,
  "id": "steam.2050650",
  "title": "Black Myth: Wukong",
  "icon_url": "https://cdn.cloudflare.steamstatic.com/steam/apps/2050650/header.jpg",
  "dx_version": "d3d12",
  "min_macos": "14.0",
  "renderer": "d3dmetal",
  "env": { "WINEESYNC": "1" },
  "compatibility": "silver",
  "notes": "First launch compiles shaders for several minutes."
}
```

## Review criteria

PRs are reviewed against these rules; violations block merge.

1. The recipe must validate against the schema above.
2. `id` must be unique across all shipped recipes.
3. `title` must match the canonical title on the platform (Steam store page,
   GOG product page). No fan translations in `title`; put translated names
   in `notes` if you want them visible.
4. Recipes for games that require DRM circumvention, piracy, or cracked
   installers are rejected without exception.
5. Recipes for games with kernel-level anti-cheat (EAC/BattlEye kernel mode,
   Vanguard) that results in bans may still be accepted, but the `notes`
   field must warn users explicitly. The `compatibility` tier must reflect
   the anti-cheat outcome.
6. `notes` must be written in neutral, factual English. UI-facing Chinese
   translation is handled by the app's localization layer, not per-recipe.

## Testing your recipe locally

1. Build WhiskyKit: `cd WhiskyKit && swift build`.
2. Run the unit tests: `swift test` (see `docs/ARCHITECTURE.md` for test
   structure).
3. Run the app from Xcode and confirm your recipe appears in the bottle's
   recipe picker.
