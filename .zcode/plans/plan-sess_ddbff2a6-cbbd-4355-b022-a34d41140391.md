# 目标:打破翻译税 —— 原生 aarch64 Wine 引擎接入(打破 Mac 跑 Win 游戏卡顿的诅咒)

## 背景(已实证)

- 实测:同一 Java 工作负载,原生 ARM64 JVM **0.06s** vs 瓶内 x86_64 JVM(Rosetta)**2.17s** —— **36× 翻译税**。
- 当前引擎 Wine 纯 x86_64:`lib/wine/` 只有 `i386-windows`/`x86_64-unix`/`x86_64-windows`,无 aarch64。
- 上游 Wine(wine-11.x)已支持 macOS ARM64(new WoW64:aarch64-unix 侧 + x86_64 PE 侧,或纯 arm64 PE)。缺的不是协议层——`WineEngine` 协议、`LocalPathEngine`、`LaunchEnginePolicy`、`WineEngineRegistry` 全部为"第二引擎"就绪,是当年 v0.4 设计的目标场景。
- 阻塞点全在**架构硬编码**:3 处 `x86_64-unix` 探测、`wine64` 优先的二进制命名、无第三方引擎的注册/导入 UI。

## 实施计划(4 个可独立交付的 PR)

### PR-1:引擎层架构泛化(纯重构,行为不变,先合)

1. 新增 `WineArchitecture` 枚举(`WhiskyKit/Sources/WhiskyKit/WineEngine/`):`x86_64` / `aarch64`,由引擎根目录探测(`Wine/lib/wine/aarch64-unix` 存在 → aarch64)。
2. 泛化三处硬编码探测,改为"任一架构目录命中即通过":
   - `LocalPathEngine.supportsD3DMetalBridge`(`LocalPathEngine.swift:87-101`)
   - `D3DMetalCapability.hasLinkedUnixModules`(`D3DMetalCapability.swift:191-200`)
   - `WineEngineCatalog.preferredBackupLibraries`(`WineEngineCatalog.swift:130-147`)
3. 测试:临时目录伪造 `aarch64-unix` 布局,断言探测通过;`x86_64` 旧布局回归不变。

### PR-2:arm64 引擎注册 + 本地导入通道

1. `WineEngineCatalog` 注册第三个引擎 `upstream-arm64`("Upstream Wine (ARM64)"),`LocalPathEngine(libraryRoot: Engines/upstream-arm64)`;`allEngines()`/`engine(id:)`/Settings 与 ConfigView 的 Picker 从硬编码改为遍历(新增项自动出现)。
2. **本地导入 UI**(Settings 加按钮):用户选一个 tar.gz/目录 → 校验布局(`Wine/bin/wine` 或 `wine64` 可执行 + `lib/wine/aarch64-unix/` 存在)→ 解包到 `Engines/upstream-arm64` + 自动写 `WhiskyWineVersion.plist`(若 tarball 无则读 `wine --version` 生成)→ 注册表 `select()`,校验失败给明确错误。
3. `LaunchEnginePolicy`:当 PE 是 x86 且选了 arm64 引擎时的回退提示(classic32 在 new-WoW64 下仍可跑,但警告性能);`LaunchEnginePolicyTests` 用 `isInstalled()` 条件断言模式(CI 无 arm64 引擎也绿)。
4. 测试:`FakeEngine` 模式 + 临时目录伪造 aarch64 引擎树,验证 catalog 注册、picker 列表、import 校验(成功/失败)。

### PR-3:真实 aarch64 构建获取 + A/B 实测(用户亲眼见证的一步)

1. 获取渠道(按序尝试,只做**运行时检测/导入**,不分发二进制,守住许可红线):
   - 本地已构建的 aarch64 Wine(如用户环境有 SwiftNativeEngine 项目,路径已在 `PATH` 观察到);
   - 上游 wine-11.x macOS ARM64 官方/社区 tarball;
   - 兜底:提供从源码构建的脚本(`scripts/build-wine-arm64.sh`,clang autoconf,~30 分钟)。
2. 用 PR-2 的导入 UI 装入测试瓶,重跑 **MC 1.21.1 同工作负载基准**(已就绪:`HeapTouch3` + 完整游戏):
   - 基线数字(已测):原生 ARM64 JVM 0.06s vs Rosetta 瓶 2.17s;
   - 预期:arm64 Wine 下瓶内 JVM 接近原生值,游戏帧率显著回升。
3. 实测数字写进 Issue/PR 与 `docs/ARCHITECTURE.md` 引擎章节。

### PR-4(后续,本轮不做):引擎分发自主权

按 PROJECT_PLAN Track A:`ChunkedDownloader`(已有 SHA-256/断点续传)接 GitHub Releases manifest,把"本地导入"升级为"一键下载"。本轮只留接口。

## 交付纪律

每个 PR:Issue → `codex/*` 分支 → PR(`Fixes #N`)→ swift test + xcodebuild + swiftlint 本地绿 → CI 三项绿 → merge。AGENTS.md 规范全程适用,无注释原则、最小 diff。

## 成功标准

1. `HeapTouch3` 在 arm64 引擎瓶内耗时 ≤ 0.3s(对比 Rosetta 2.17s,收窄 ≥85%);
2. MC 1.21.1 在 arm64 引擎下可启动进入标题/世界,无崩溃;
3. 全部现有测试不回归 + 新增架构泛化测试绿;
4. 用户在 UI 中可见并选择 ARM64 引擎。