# MacBottle 项目路线图

> Fork 自 [Whisky](https://github.com/Whisky-App/Whisky)(GPL-3.0,已归档)。面向 Apple Silicon 的现代 Wine 图形化封装,由社区持续维护。

## 项目信念

**代码即作品,仓库即展品。**

我们不做社区运营、不做独立域名、不做媒体 push、不做 SEO、不做赞助、不做周边。
我们把仓库本身做到工程师看了会尊敬的程度,让开发者自己找上门、自己提 PR、自己把它带到更多地方。

## 唯一的问题

让 Windows 游戏在 Apple Silicon 上跑起来。

## 技术边界

| 做 | 不做 |
| -- | -- |
| Bottle 管理(继承 Whisky) | 虚拟机方案 |
| Wine / CrossOver / GPTK 启动链(继承 Whisky) | 自研 DX→Metal 翻译层 |
| **配方(Recipe)系统** —— 整个项目唯一的护城河 | 内核态反作弊 |
| **引擎分发自主权**(不寄生于已归档上游的基础设施) | 分发游戏本体 |
| 发布工程(签名、公证、自动更新) | 云服务、付费功能 |
| Apple Silicon / macOS 15+ 新 API 适配 | |
| 中英双语一等公民的 UI 与文档 | |

## 配方系统(Recipe)

这是 MacBottle 与 Whisky 的核心区别。一份配方是一份 JSON 文件,描述"让这个游戏跑起来需要哪些设置"。

- 位置:`WhiskyKit/Sources/WhiskyKit/Recipes/<platform>/<id>.json`
- 格式:JSON,经 `RecipeLint` CI 用真实的 Swift `Recipe` 类型校验
- 贡献方式:开发者提交 PR,加一个 JSON 文件(不需要懂 Swift)
- 运行时:App 启动时从 bundle 加载所有配方,用户对一个 bottle 挂载某个配方后,启动游戏时配方里的 env、winetricks、注册表自动应用
- 同步:远程目录经 `_index.json` 清单 + raw CDN + ETag 缓存增量更新,变更以 diff UI 呈现

详见 [`docs/RECIPE_AUTHORING.md`](./docs/RECIPE_AUTHORING.md) 和 [`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md)。

## 工作方式:四条 Track

规划按 track 并行推进,版本号只是检查点。每条 track 由追踪 Issue 承载,一切改动仍走 Issue → PR → main → CI 闭环([AGENTS.md](AGENTS.md) / [CONTRIBUTING.md](CONTRIBUTING.md))。

### Track A · 引擎与分发

- ✅ v0.4:`WineEngine` 协议抽象,`CrossOverEngine` 为首个实现
- ✅ 用户可切换引擎:`WineEngineRegistry` 持久化、Settings 切换 UI、D3DMetal 变体引擎、`LaunchEnginePolicy` 自动选型
- 🚧 **引擎分发自主权(v1.0 硬前置)**:已归档上游的服务器(`data.getwhisky.app`)自 2026-11 起返回 404。
  - ✅ 自有清单:`engine-manifest.json` 由 Ed25519 签名,公钥内置于 `Info.plist`(`MBEngineManifestPublicKey`),CI 每周重签,详见 [`docs/ENGINE_DISTRIBUTION.md`](docs/ENGINE_DISTRIBUTION.md)。
  - ✅ 不再向已归档上游发起引擎更新检查;安装向导提供本地导入、旧 Whisky 引擎复用、经签名清单校验的开源 Wine 回退包与 ARM64 自建脚本。
  - 🔜 剩余:自有的 CrossOver 兼容引擎包(含 D3DMetal/DXVK 支持)经同一清单分发,并接回引擎更新检查。仍是 v0.7 的发布硬阻塞。
- 🔜 **引擎目录清单驱动**:把硬编码的 `WineEngineCatalog` 枚举改为 manifest 描述的可插拔引擎包(manifest 描述 + 按需下载安装)。这比手写第二个引擎子类更能兑现抽象层的承诺。
- 🔜 第二个引擎实现(纯上游 Wine):依赖自建 Wine 构建流水线,成本高,单列评估、可推迟;GPTK2 因 Apple 授权不可再分发,维持"运行时本地检测"模式不变。

### Track B · 配方生态

- ✅ v0.2:schema、loader、applier、示例配方
- ✅ v0.3:RecipeLint CI + Recipe UI
- ✅ v0.5:远程配方同步(数据层 → 同步引擎 → diff UI;实际实现采用 raw CDN + `_index.json` 清单 + ETag,替代原计划的 GitHub Contents API)
- 🔜 **配方健康度闭环**:失效反馈入口(Issue 模板联动)→ 兼容性矩阵标注(macOS × 芯片 × 验证状态)→ 评审标准文档化。护城河的可持续性靠信任闭环,不只靠同步机制。
- ✅ 同步完整性加固:manifest 条目携带 SHA-256,客户端在解码前校验下载字节,损坏/污染响应以硬失败呈现;签名清单(release key)仍为后续项。

### Track C · 发布工程

- 🔜 **真实更新渠道**:`SUFeedURL` 已指向本仓库的 `appcast.xml`,但该文件尚不存在、`Info.plist` 中没有 `SUPublicEDKey`,Sparkle 以 `startingUpdater: false` 关闭。需生成 EdDSA 密钥对、发布 appcast 后再启用(见 [`docs/RELEASE.md`](docs/RELEASE.md))。
- 🚧 **Release 工作流**:`.github/workflows/Release.yml` 已就绪,`v*` tag 触发 Release 构建,密钥存在时签名 + 公证 + staple,并上传 `MacBottle.zip` 与 SHA-256 到 GitHub Release。剩余:配置 Apple Developer 密钥并在干净的 Mac 上验证首个公证包。
- 🔜 **v1.0 完成定义**:经过公证的正式包、可用的自动更新渠道、各兼容性档位均有已验证配方、双语文档齐备。满足后才算"正式发布"。

### Track D · 平台与品牌

- 🔜 内部大改名(target 名、`WhiskyKit` → `MacBottleKit`):MIGRATION.md 计划"v0.1 末期"执行但至今未动。必须二选一:分配真实版本执行,或明确宣布永不改、并入"永不改动"清单。悬而不决只会抬高将来的改名成本。
- 🔜 macOS 15+ 新 API 适配(持续)
- 🔜 中英双语 UI 文案与文档补齐(持续)

## 版本检查点

| 版本 | 状态 | 核心交付 |
| -- | -- | -- |
| v0.1 – v0.4 | ✅ 已完成 | 品牌切换 + 可编译 .app;Recipe 系统;CI schema-lint + 文档 + Recipe UI;引擎抽象层 |
| v0.5 | ✅ 已完成 | 远程配方同步(三个子阶段:数据层 → 同步引擎 → diff UI) |
| v0.6 | 🚧 收尾 | 用户可切换引擎已完成;第二引擎移入 Track A 单列评估,不再阻塞本检查点 |
| v0.7 | 计划 | 引擎分发自主权(Track A)+ 发布工程启动:真实更新源、Release 工作流(Track C) |
| v1.0 | 目标 | 正式发布,以 Track C 的完成定义为验收标准 |

v1.0 之后:**只合 PR,只做引擎层维护。** 配方由社区贡献者自行添加。

## 交付纪律

所有改动遵循 **Issue → PR → main → CI → merge** 闭环(Issue 仅在合并后通过 `Fixes #N` 关闭)。编码代理遵循 [`AGENTS.md`](./AGENTS.md),人类贡献者遵循 [`CONTRIBUTING.md`](CONTRIBUTING.md)。

## 许可

- 本项目:**GPL-3.0**(继承自 Whisky,永久)
- D3DMetal:Apple 闭源,不随包分发,运行时检测本地 GPTK
- CrossOver:沿用 Whisky 的打包格式;已归档上游不再提供下载,自有分发与是否迁移纯上游 Wine 由 Track A 推进

## 致谢

永久保留对 Whisky、CrossOver、Wine、D3DMetal、DXVK、MoltenVK 等上游项目的署名。详见 `NOTICE` 与 [`README.md`](README.md)。
