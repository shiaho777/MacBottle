<!--
Thanks for contributing to MacBottle.
https://github.com/shiaho777/MacBottle

Pick the section that matches your change and delete the others.

- Recipe: adding/updating files under WhiskyKit/Sources/WhiskyKit/Recipes/
- Code / Docs: Swift, docs, workflows, delivery process
-->

## Summary

<!-- What user-visible outcome does this change deliver? Why? -->

## Issue

Fixes #

<!-- Or: Closes # -->
<!-- Full URL welcome: https://github.com/shiaho777/MacBottle/issues/N -->
<!--
Issue closes on *merge* via Fixes/Closes — not when the PR opens, not while CI is red.
Bot/catalog PRs (for example recipe index regeneration) may omit Fixes.
-->

---

## Recipe

<!-- Fill this out if your PR adds or updates a recipe file. -->

- **Game:** <!-- e.g. Black Myth: Wukong -->
- **Platform id:** <!-- e.g. steam.2050650 -->
- **Compatibility tier:** <!-- platinum | gold | silver | bronze | broken -->
- **Tested on:**
  - Chip: <!-- e.g. M4 Pro -->
  - macOS: <!-- e.g. 15.1 -->
  - Result: <!-- e.g. 60fps at 1440p medium -->

### Evidence

<!-- Optional. Screenshot, short clip, or log excerpt. -->

### Checklist

- [ ] I confirm the game launches and is playable on my Apple Silicon Mac
- [ ] My recipe file validates against `docs/RECIPE_AUTHORING.md`
- [ ] `id` is unique across existing recipes
- [ ] `notes` is factual, in English, and does not contain promotion or piracy links
- [ ] This recipe does not require DRM circumvention
- [ ] Required CI is green before merge (`RecipeLint` when recipe paths change)

---

## Code / Docs

<!-- Fill this out if your PR changes Swift code, documentation, or workflows. -->

### What does this change do?

<!-- Short summary. -->

### Why?

<!-- Link the Issue above. Prefer Fixes #N so it closes on merge. -->

### Test plan

- [ ] `swift test` passes locally (from `WhiskyKit/`)
- [ ] The app builds in Xcode without new SwiftLint violations
- [ ] I have added tests for new non-trivial logic, or explained why not
- [ ] Required CI is green before merge
  - Code: `xcodebuild Debug`, `WhiskyKit tests`, and `SwiftLint` when Swift changes
  - Recipes: `RecipeLint` when recipe paths change
  - Docs-only: Build may be skipped by path filters; still wait for any checks that did run

### Notes for reviewers

<!-- Optional: risk, rollout, screenshots, follow-ups -->
