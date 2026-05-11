# Whisky → MacBottle 品牌化迁移清单

本文档跟踪从 Whisky 迁移到 MacBottle 过程中需要改动的所有地方。

**重要原则：** 代码层面的模块名（Swift module `Whisky` / `WhiskyKit`）暂不重命名。Xcode project 重命名风险高，等 v0.1 末期、所有功能跑通后再统一做一次"大改名"。

## 分类

### ✅ 已完成
- 建立 git 基线仓库
- 路线图（PROJECT_PLAN.md）与本迁移清单

### 🚧 v0.1 需要做的"外在品牌"改动（影响用户可见的部分）

| 位置 | 改动内容 | 状态 |
| --- | --- | --- |
| `README.md` | 重写为 MacBottle 品牌，保留 Whisky 致谢 | ✅ 已完成 |
| `Whisky/Info.plist` → `CFBundleDisplayName` | `Whisky` → `MacBottle` | ⏳ |
| `Whisky/Info.plist` → `CFBundleName` | `Whisky` → `MacBottle` | ⏳ |
| `Whisky.xcodeproj` → `PRODUCT_BUNDLE_IDENTIFIER` | `com.isaacmarovitz.Whisky` → `app.macbottle.MacBottle`（含 Cmd / Thumbnail 变体）+ 源码里 fallback 同步更新 | ✅ 已完成 |
| `Assets.xcassets` → AppIcon | 替换为 MacBottle 图标（临时占位可接受） | ⏳ |
| Sparkle 更新源 URL | 原指向 getwhisky.app —— 已换为占位 URL 和占位公钥。**发布前必须生成真实 EdDSA 密钥对并替换** | ✅ 已处理（占位） |
| Crowdin 配置（`crowdin.yml`） | 暂时保留，后期切换到 MacBottle 自己的 Crowdin 项目 | ⏳ |
| `LICENSE` | 保持逐字不动（GPL-3.0 禁止修改）。衍生声明另放 `NOTICE` 文件 | ✅ 已完成 |

### 🔜 v0.1 末期再做的"内在代码"改动（风险高，统一时机做）

| 位置 | 改动内容 |
| --- | --- |
| Xcode project target 名 | `Whisky` → `MacBottle` |
| Swift Package `WhiskyKit` | → `MacBottleKit` |
| Swift Package `WhiskyCmd` | → `macbottle`（CLI 工具） |
| Extension bundle `WhiskyThumbnail` | → `MacBottleThumbnail` |
| 所有 Swift 源码中的 `Whisky` 字样 | 在 Xcode 中批量 rename |

### ❌ 永不改动（保留上游痕迹）

- 所有致谢、贡献者信息、Copyright 头
- Git 历史中引用的原作者 commits
- 上游依赖（CrossOver、Sparkle、DXVK 等）的名称与链接

## GPL-3.0 合规要点

作为 Whisky 的衍生作品：

1. ✅ 源码公开：本项目在 GitHub 开源
2. ✅ 协议一致：继续用 GPL-3.0
3. ✅ 署名保留：README、文档、LICENSE 保留 Isaac Marovitz 和原始贡献者署名
4. ✅ 修改声明：在 README 顶部、LICENSE 顶部显著注明"本项目基于 Whisky 修改"
