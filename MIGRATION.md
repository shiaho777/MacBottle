# Whisky → MacBottle 品牌化迁移清单

本文档跟踪从 Whisky 迁移到 MacBottle 过程中需要改动的所有地方。

**重要原则：** 代码层面的大改名已完成（`MacBottle.xcodeproj`、`MacBottleKit`、`MacBottleCmd`、`MacBottleThumbnail`，以及全部 Swift 源文件头）。为兼容已有安装和保留署名，GPL 许可正文中的 "Whisky"、磁盘上的 `WhiskyWineVersion.plist`、旧版 `com.isaacmarovitz.Whisky` 恢复路径、`@AppStorage` 键与历史本地化键保持不变；这些是**有意冻结**的兼容面，不是未完成的改名。`scripts/check-branding.sh` 会在 CI 中阻止源文件头或 target 名回归到上游名称。

## 分类

### ✅ 已完成
- 建立 git 基线仓库
- 路线图（PROJECT_PLAN.md）与本迁移清单

### 🚧 v0.1 需要做的"外在品牌"改动（影响用户可见的部分）

| 位置 | 改动内容 | 状态 |
| --- | --- | --- |
| `README.md` | 重写为 MacBottle 品牌，保留 Whisky 致谢 | ✅ 已完成 |
| `MacBottle/Info.plist` → `CFBundleDisplayName` | `Whisky` → `MacBottle`（由 target 名 `MacBottle` 经 `PRODUCT_NAME` 生成） | ✅ 已完成 |
| `MacBottle/Info.plist` → `CFBundleName` | `Whisky` → `MacBottle`（由 target 名 `MacBottle` 经 `PRODUCT_NAME` 生成） | ✅ 已完成 |
| `MacBottle.xcodeproj` → `PRODUCT_BUNDLE_IDENTIFIER` | `com.isaacmarovitz.Whisky` → `app.macbottle.MacBottle`（含 Cmd / Thumbnail 变体）+ 源码里 fallback 同步更新 | ✅ 已完成 |
| `Assets.xcassets` → AppIcon | 替换为 MacBottle 图标（临时占位可接受） | ⏳ |
| 应用更新源 | 已移除 Sparkle 及 `SUFeedURL` / `SUEnableAutomaticChecks`;改为读取本仓库 GitHub Releases 的 latest-release API(见 `docs/RELEASE.md`) | ✅ 已完成 |
| Crowdin 配置（`crowdin.yml`） | 暂时保留，后期切换到 MacBottle 自己的 Crowdin 项目 | ⏳ |
| `LICENSE` | 保持逐字不动（GPL-3.0 禁止修改）。衍生声明另放 `NOTICE` 文件 | ✅ 已完成 |

### ✅ "内在代码"改名

| 位置 | 改动内容 | 状态 |
| --- | --- | --- |
| Xcode project 与 target 名 | `Whisky` → `MacBottle` | ✅ 已完成 |
| Swift Package `WhiskyKit` | → `MacBottleKit` | ✅ 已完成 |
| CLI `WhiskyCmd` | → `MacBottleCmd`，命令名 `macbottle` | ✅ 已完成 |
| Extension bundle `WhiskyThumbnail` | → `MacBottleThumbnail` | ✅ 已完成 |
| Swift 源文件头 | `Whisky` / `WhiskyKit` / `WhiskyCmd` / `WhiskyKitTests` / `WhiskyThumbnail` → `MacBottle` 对应名称 | ✅ 已完成 |
| Swift 源码中的 `Whisky` 字样 | 除下方冻结兼容面外均已改名 | ✅ 已完成 |
| 改名回归防护 | `scripts/check-branding.sh`，由 SwiftLint CI 执行 | ✅ 已完成 |

### ❌ 永不改动（保留上游痕迹与兼容面）

- 所有致谢、贡献者信息、Copyright 头
- GPL 许可正文中的 "Whisky" 字样（衍生作品署名）
- Git 历史中引用的原作者 commits
- 上游依赖（CrossOver、Sparkle、DXVK 等）的名称与链接
- 磁盘兼容标识：`WhiskyWineVersion.plist`（引擎版本文件，已有安装和上游构建都依赖该文件名）
- 旧版安装恢复路径：`com.isaacmarovitz.Whisky`
- `@AppStorage` 兼容键：`checkWhiskyWineUpdates`
- 引擎展示名中的上游署名：`CrossOver Wine (Whisky build)`

## GPL-3.0 合规要点

作为 Whisky 的衍生作品：

1. ✅ 源码公开：本项目在 GitHub 开源
2. ✅ 协议一致：继续用 GPL-3.0
3. ✅ 署名保留：README、文档、LICENSE 保留 Isaac Marovitz 和原始贡献者署名
4. ✅ 修改声明：在 README 顶部、LICENSE 顶部显著注明"本项目基于 Whisky 修改"
