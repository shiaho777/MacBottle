# Contributing to MacBottle

Thanks for wanting to help. MacBottle is a small, focused project with one
goal: make Windows games runnable on Apple Silicon Macs. It moves fastest
when contributions stay **small and well-scoped** — pick one of the lanes
below and ignore the rest.

> **English** · [简体中文](#贡献-macbottle简体中文)

---

## Lanes

| You want to… | Go to | Effort |
| --- | --- | --- |
| Add or update a **game recipe** (JSON — no Swift needed) | [Lane 1](#1-add-a-game-recipe-easiest-highest-impact) | hours |
| Report a **bug** or request a **feature** | [GitHub Issues](https://github.com/shiaho777/MacBottle/issues) | minutes |
| Request a **recipe** for a game you can't run | [Recipe Request issues](https://github.com/shiaho777/MacBottle/issues/new/choose) | minutes |
| Fix a bug or build a feature in the **Swift code** | [Lane 3](#3-contribute-code) | days |

Not sure which lane fits? Open an issue or a discussion first — there is no
need to write code before there is agreement on the shape of the change.

---

## Delivery loop (Issue → PR → main → CI → merge)

Every intentional non-trivial change — code **or docs** — follows this loop.
Coding agents follow the same rules in [`AGENTS.md`](./AGENTS.md).

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

---

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

---

## License

By contributing, you agree that your contributions will be licensed under
the same GPL-3.0 license that covers the project.

## Relationship to Whisky

MacBottle is a fork of [Whisky](https://github.com/Whisky-App/Whisky),
which stopped maintenance in May 2025. We preserve the original author's
attribution in every inherited file and in `NOTICE`. New files authored for
MacBottle follow the same GPL-3.0 terms.

---

## 贡献 MacBottle(简体中文)

感谢你愿意帮忙。MacBottle 是一个目标单一的小项目:让 Windows 游戏在
Apple Silicon Mac 上跑起来。贡献方式按「大家实际会怎么做」排序:

| 你想… | 去哪里 | 工作量 |
| --- | --- | --- |
| 新增或更新**游戏配方**(JSON,不需要会 Swift) | [通道一](#1-新增游戏配方最容易影响力最大) | 数小时 |
| 报 **bug** 或提 **feature** 需求 | [GitHub Issues](https://github.com/shiaho777/MacBottle/issues) | 几分钟 |
| 为跑不起来的游戏提交**配方请求** | [Recipe Request 模板](https://github.com/shiaho777/MacBottle/issues/new/choose) | 几分钟 |
| 在 **Swift 代码**里修 bug 或做功能 | [通道三](#3-贡献代码) | 数天 |

不确定走哪个通道?先开 Issue 或讨论——在动手写代码之前先对齐改动形态,
没有坏处。

### 交付闭环(Issue → PR → main → CI → merge)

所有有意的、非琐碎的改动——代码**或文档**——都走这条闭环。代理同样遵循
[`AGENTS.md`](./AGENTS.md) 中的规则。

```text
开 Issue → 从 main 切分支 → PR 进 main(Fixes #N)→ CI 变绿 → 合并 → Issue 关闭
```

1. **先开 Issue。** 描述问题/目标与验收标准;纯配方贡献如需要也可关联 Issue。
2. **从 `main` 切分支。** 建议短主题分支(例如 `codex/topic-name`)。
3. **PR 进 `main`。** 使用 [PR 模板](./.github/PULL_REQUEST_TEMPLATE.md),body 含 `Fixes #N` 或 `Closes #N`,确保 Issue **仅在合并时**关闭——不是 PR 打开时,也不是 CI 红时。
4. **CI 是合并门槛。** 必检红时不合并。CI 不关闭 Issue,合并才关闭。
5. **必检项**(来自真实 workflow,路径过滤适用):

| 何时触发 | Workflow | Job id | 检查名 |
|------|----------|--------|------------|
| App/代码改动 | [`.github/workflows/Build.yml`](./.github/workflows/Build.yml) | `build` | `xcodebuild Debug` |
| App/代码改动 | [`.github/workflows/Build.yml`](./.github/workflows/Build.yml) | `test` | `WhiskyKit tests` |
| Swift 源码改动 | [`.github/workflows/SwiftLint.yml`](./.github/workflows/SwiftLint.yml) | `SwiftLint` | `SwiftLint` |
| 配方源码/测试改动 | [`.github/workflows/RecipeLint.yml`](./.github/workflows/RecipeLint.yml) | `RecipeLint` | `RecipeLint` |

- 纯 markdown/文档 PR 可能因路径过滤跳过 `Build`。
- [RecipeIndex](./.github/workflows/RecipeIndex.yml) 在配方推送后在 `main` 上重新生成 `_index.json`,不是 PR 门槛,也不关闭 Issue。
- 自动化索引 bot 提交可以省略 `Fixes #N`。

6. **提交里不含密钥或本机垃圾。**

**给维护者的建议:** 在 `main` 上开启分支保护,要求上述检查通过才能合并。
本仓库可能尚未配置保护——无论如何,把绿色 CI 当作政策。

### 1. 新增游戏配方(最容易、影响力最大)

一份配方就是 `WhiskyKit/Sources/WhiskyKit/Recipes/<platform>/<id>.json`
下的一个 JSON 文件,描述如何运行某款 Windows 游戏。这是 MacBottle
成长的主要方式。

**流程:**

1. 在 Apple Silicon Mac 上通过 MacBottle 把游戏跑起来,确认至少能到 `bronze` 兼容级别。
2. 阅读 [`docs/RECIPE_AUTHORING.md`](./docs/RECIPE_AUTHORING.md) 了解 schema 与评审规则。
3. 复制同平台文件夹下最接近的现有配方,改它。
4. 用 PR 模板的「Recipe」区段开 PR。

**CI 自动校验**每份配方:`RecipeLint` 用真实的 `Recipe` Swift 类型解码。
能解码就通过;不能,错误信息会告诉你哪个字段不对。

贡献配方不需要懂 Swift。

### 2. 报告跑不起来的游戏

自己搞不定,就开一个 **Recipe Request** Issue。别人(也许是未来的你)
会利用这些信息做出可用的配方。

如果是 MacBottle 本身的 bug——建瓶失败、UI 崩溃等——用 **Bug Report**
模板。

### 3. 贡献代码

任何非琐碎改动都先开 Issue 对齐范围,再写代码。交付闭环见上,
[`AGENTS.md`](./AGENTS.md) 约束编码代理;模块布局与启动流程见
[`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md)。

**构建环境:**

- macOS 14 Sonoma 或更高,Apple Silicon
- Xcode 16 或更高
- SwiftLint(`brew install swiftlint`)
- 其余依赖全部由 Swift Package Manager 管理

**开 PR 之前:**

- 在 Xcode 里构建 App(`⌘B`)。SwiftLint 作为 build phase 运行;零违规是合并要求。
- 在 `WhiskyKit/` 下运行 `swift test`,全部通过。
- 改过配方代码,`RecipeTests` 必须仍然通过。
- 新增非琐碎逻辑要配测试;不配就在 PR 里说明理由。

**代码风格:**

- 4 空格缩进
- 不允许无注释理由的 SwiftLint 豁免
- 新文件遵守 `.swiftlint.yml` 强制的文件头模式
- Public API 有 DocC 注释
- 用户可见字符串进 `Whisky/Localizable.xcstrings`,只加英文 key;翻译另行进行

**范围:**

MacBottle 明确不接受以下贡献:

- 基于虚拟化的兼容层
- 绕过 DRM 或反作弊
- 捆绑游戏本体、安装器或盗版材料
- 付费功能、遥测、分析

完整范围见 [`PROJECT_PLAN.md`](./PROJECT_PLAN.md)。

### 许可

提交即表示你同意贡献按项目同款 GPL-3.0 许可发布。

### 与 Whisky 的关系

MacBottle 是 [Whisky](https://github.com/Whisky-App/Whisky) 的 fork,
上游于 2025 年 5 月停止维护。我们在每个继承文件与 `NOTICE` 中保留原作者
署名;MacBottle 新写的文件同样遵循 GPL-3.0。
