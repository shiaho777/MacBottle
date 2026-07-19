# Contributing to MacBottle

Thanks for wanting to help. MacBottle is a small, focused project with one
goal: make Windows games runnable on Apple Silicon Macs. There are three
ways to contribute, listed here by how often people actually do them.


## Delivery loop (Issue → PR → main → CI → merge)

All intentional non-trivial work follows this loop. Agents follow the same rules in [`AGENTS.md`](./AGENTS.md).

```text
Issue open → branch from main → PR into main (Fixes #N) → CI green → merge → Issue closes
```

1. **Issue first.** Open or reuse a GitHub Issue describing the problem/goal and acceptance criteria. Recipe-only contributions may still link an Issue when useful.
2. **Branch from `main`.** Prefer a short topic branch (for example `codex/topic-name`).
3. **Open a PR into `main`.** Use [.github/PULL_REQUEST_TEMPLATE.md](./.github/PULL_REQUEST_TEMPLATE.md). Include `Fixes #N` or `Closes #N` so the Issue closes **on merge only** — not when the PR is opened, and not while CI is red.
4. **CI is the merge gate.** Do not merge with red required checks. CI must not close Issues; merge does.
5. **Required checks** (from real workflows; path filters apply):

| When | Workflow | Job id | Check name |
|------|----------|--------|------------|
| App/code changes | [`.github/workflows/Build.yml`](./.github/workflows/Build.yml) | `build` | `xcodebuild Debug` |
| App/code changes | [`.github/workflows/Build.yml`](./.github/workflows/Build.yml) | `test` | `WhiskyKit tests` |
| Swift sources changed | [`.github/workflows/SwiftLint.yml`](./.github/workflows/SwiftLint.yml) | `SwiftLint` | `SwiftLint` |
| Recipe sources/tests changed | [`.github/workflows/RecipeLint.yml`](./.github/workflows/RecipeLint.yml) | `RecipeLint` | `RecipeLint` |

- Pure markdown/docs PRs may skip `Build` because of path filters.
- [RecipeIndex](./.github/workflows/RecipeIndex.yml) regenerates `_index.json` on `main` after recipe pushes. It is not a PR gate and does not close Issues.
- Automated index bot commits may omit `Fixes #N`.

6. **No secrets or machine-local junk** in commits.

**Recommended for maintainers:** enable branch protection on `main` requiring the checks above for PR merges. This repository may not have protection configured yet — treat green CI as policy either way.

## 1. Add a game recipe (easiest, highest impact)

A recipe is a single JSON file under
`WhiskyKit/Sources/WhiskyKit/Recipes/<platform>/<id>.json` describing how to
run a specific Windows game. This is the primary way MacBottle grows.

**Workflow:**

1. Install the game on your Apple Silicon Mac through MacBottle and confirm
   it runs well enough to earn at least a `bronze` compatibility tier.
2. Read [`docs/RECIPE_AUTHORING.md`](./docs/RECIPE_AUTHORING.md) for the
   schema and review rules.
3. Copy the closest existing recipe in the same platform folder and edit it.
4. Open a PR using the "Recipe" section of the PR template.

**CI automatically validates** every recipe through the `RecipeLint`
workflow by decoding it with the real `Recipe` Swift type. If it decodes,
it passes. If it doesn't, the error message tells you which field is off.

You don't need to understand Swift to contribute a recipe.

## 2. Report a broken or missing game

If you can't get a game running yourself, open a
**Recipe Request** issue. Someone else (maybe a future you) will use the
information to build a working recipe.

If you find a bug in MacBottle itself — bottle creation fails, UI crashes,
something non-game — use the **Bug Report** issue template.

## 3. Contribute code

Open an issue first for anything non-trivial so we can align on scope
before you write code. See the Delivery loop above and [`AGENTS.md`](./AGENTS.md) for coding agents. See [`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md)
for the module layout and the runtime flow of a game launch.

**Build environment:**

- macOS 14 Sonoma or later, on Apple Silicon
- Xcode 16 or later
- SwiftLint (`brew install swiftlint`)
- All other dependencies are managed through Swift Package Manager

**Before opening a PR:**

- Build the app in Xcode (`⌘B`). SwiftLint runs as a build phase; zero
  violations is a merge requirement.
- From `WhiskyKit/`, run `swift test`. All tests must pass.
- If you touched recipe code, the `RecipeTests` suite must still pass.
- If you added non-trivial logic, add a test. If you chose not to, explain
  why in the PR.

**Code style:**

- 4-space indentation
- No SwiftLint suppressions without a comment justifying the exception
- New files use the file header pattern enforced by `.swiftlint.yml`
- Public API has DocC comments
- User-facing strings go into `Whisky/Localizable.xcstrings`. Add only the
  English key; translation happens separately

**Scope:**

MacBottle deliberately does not accept contributions that:

- Add virtualization-based compatibility layers
- Attempt to bypass DRM or anti-cheat
- Bundle game content, installers, or pirated material
- Add paid features, telemetry, or analytics

See [`PROJECT_PLAN.md`](./PROJECT_PLAN.md) for the full project scope.

## License

By contributing, you agree that your contributions will be licensed under
the same GPL-3.0 license that covers the project.

## Relationship to Whisky

MacBottle is a fork of [Whisky](https://github.com/Whisky-App/Whisky),
which stopped maintenance in May 2025. We preserve the original author's
attribution in every inherited file and in `NOTICE`. New files authored for
MacBottle follow the same GPL-3.0 terms.
