# AGENTS.md

Instructions for coding agents working in MacBottle.

## Code style

- Do not add code comments unless the user explicitly asks for them.
- Prefer minimal, focused diffs that match existing style.
- Do not commit secrets, local paths, or machine-only junk.

## Delivery (Issue + PR + CI)

Canonical loop:

```text
Issue open → branch from main → PR into main (Fixes #N) → CI green → merge → Issue closes
```

Hard rules:

1. **Base branch is always `main`.** Open feature PRs into `main` only unless a maintainer explicitly names another base.
2. **Issue first** for intentional code/doc/process changes. Reuse an open Issue when one already tracks the work; otherwise create one.
3. **Close Issue on merge only.** PR body includes `Fixes #N` or `Closes #N`. Never close the Issue when the PR is merely opened, while CI is red, or before merge.
4. **CI is the merge gate.** Required checks must be green before merge. CI must **not** auto-close Issues.
5. **One primary Issue per PR** when possible. Extra Issues may be linked without closing keywords unless intentional.
6. **No secrets or junk** in commits.
7. **Do not commit / push / open PRs / file Issues** unless the user asked to deliver, ship, bootstrap, or equivalent.
8. **Permission-aware handoff.** If merge permission is missing: open PR, comment on the Issue with links, leave Issue open, hand off to a maintainer.
9. **User overrides win** for that turn only (for example skip Issue, direct push to main). State the override in the PR/Issue comment.

### Branching

- Branch from up-to-date `main`.
- Prefer prefix `codex/` for agent-created branches (for example `codex/launch-experience`).

### PR body

Must include:

- What changed and why
- `Fixes #N` or `Closes #N`
- Test notes

Use [.github/PULL_REQUEST_TEMPLATE.md](.github/PULL_REQUEST_TEMPLATE.md).

### Required CI checks (merge gate)

Documented from real workflow files under [.github/workflows/](.github/workflows/). Path filters apply — not every PR runs every workflow.

| When | Workflow file | Job id | Check name |
|------|---------------|--------|------------|
| App/code changes (most paths) | [Build.yml](.github/workflows/Build.yml) | `build` | `xcodebuild Debug` |
| App/code changes | [Build.yml](.github/workflows/Build.yml) | `test` | `WhiskyKit tests` |
| Swift sources changed | [SwiftLint.yml](.github/workflows/SwiftLint.yml) | `SwiftLint` | `SwiftLint` |
| Recipe sources/tests changed | [RecipeLint.yml](.github/workflows/RecipeLint.yml) | `RecipeLint` | `RecipeLint` |

Notes:

- `Build` **ignores** pure markdown/docs-only paths; a docs-only PR may not run Build jobs.
- [RecipeIndex.yml](.github/workflows/RecipeIndex.yml) runs on `main` after recipe pushes and regenerates `_index.json`. It is **not** a PR merge gate and must not close Issues.
- Fully automated recipe-index bot commits may omit `Fixes #N`.

### Local verify (before PR)

- Debug build: `xcodebuild -project Whisky.xcodeproj -scheme Whisky -configuration Debug CODE_SIGNING_ALLOWED=NO build`
- Tests: `cd WhiskyKit && swift test`
- SwiftLint when Swift changed: `swiftlint lint --strict`

### Human docs

Same loop for humans: [CONTRIBUTING.md](CONTRIBUTING.md).

### Exceptions

Only on explicit user override for that turn:

- Tiny doc-only direct push to `main`
- Emergency hotfix direct push
- Skip Issue / skip CI / skip PR

Record the override in the handoff message.
