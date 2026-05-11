# MacBottle 项目路线图

> 基于 Whisky（GPL-3.0，已于 2025-05-11 归档）派生，面向 Apple Silicon 的现代 Wine 图形化封装。

## 一、产品定位

**一句话：** 让 Mac 用户在自己的 Apple Silicon Mac 上，以最简方式运行 Windows 游戏与应用。

**三条核心承诺：**
1. **开源永久免费** —— GPL-3.0，与 Whisky 保持一致，社区驱动。
2. **中英双语一等公民** —— 界面、文档、兼容性数据库从第一天起就支持中文。
3. **Apple Silicon 原生体验** —— 针对 M 系列芯片、macOS 15+ 新 API（Game Mode、MetalFX、ProMotion）深度适配。

**明确不做：**
- 不做虚拟机方案（性能损失大、GPU 直通受限）。
- 不自研 DX→Metal 翻译层（直接用 Apple D3DMetal / DXVK / DXMT）。
- 不碰内核态反作弊（EAC/BattlEye kernel mode 在 Mac 上无解）。
- 不分发任何游戏本体。游戏由用户自备，通过 Steam/Epic/GOG/Battle.net 等合法渠道获取。

## 二、与前辈/同行的关系

| 项目 | 状态 | 与 MacBottle 的关系 |
| --- | --- | --- |
| Whisky | 2025-05-11 归档 | **直接 fork 起点**，保留致谢 |
| Kegworks / Sikarugir | 活跃，Wineskin 路线 | 不同技术路径（一游戏一 .app vs 中央启动器） |
| Mythic | 活跃，自有 Engine | 同赛道竞争者，需要长期观察 |
| CrossOver | 商业闭源 | 付费用户的替代方案 |
| Heroic | 跨平台启动器 | 可能的上游协作对象（Epic/GOG 后端） |

## 三、护城河

技术层都是公共资产（Wine / D3DMetal / MoltenVK），护城河是：

1. **兼容性配方数据库**（对标 ProtonDB）—— 游戏 × 配置 × 社区评分。
2. **中文社区 + 中文内容生态** —— V2EX、小红书、B 站、知乎。
3. **活跃维护 + 持续迭代** —— 接住 Whisky 13k star 留下的空位。
4. **Apple Silicon / macOS 新 API 专注** —— 比跨平台方案更原生。

## 四、里程碑

### v0.1 —— 接手与品牌化（当前阶段）
目标：用户下载一个叫 MacBottle 的 App，功能上与 Whisky 等价，但有独立身份。

- [ ] 仓库 git 基线固化 ✅ 已完成
- [ ] 路线图与品牌化清单文档 🚧 进行中
- [ ] 重写 README（中英双语）
- [ ] App 显示名、bundle id、图标资源切换
- [ ] 首次本地 Xcode 编译通过
- [ ] 产出可安装的 `.app`

### v0.2 —— 兼容性配方系统 MVP
目标：每个游戏有一份"配方"，一键应用。

- [ ] 配方数据格式（JSON + Schema）
- [ ] 内置 50 个热门游戏的初始配方
- [ ] 配方本地应用机制（自动 winetricks、DXVK、环境变量）
- [ ] 配方远程更新通道（GitHub raw 或轻量 CDN）

### v0.3 —— 中文本地化与社区
目标：V2EX / 小红书 / B 站首发可用。

- [ ] 界面完整中文化（简体 + 繁体）
- [ ] 中文文档站
- [ ] 社区贡献配方的 PR 流程

### v0.4 —— 崩溃与日志回流
目标：把用户的问题变成我们的数据。

- [ ] 可选的匿名崩溃日志上报
- [ ] 兼容性数据库自动生成的报告页

### v1.0 —— 启动器聚合
目标：在一个 App 里管理 Steam / Epic / GOG 游戏库。

- [ ] 集成 Legendary（Epic）
- [ ] 集成 gogdl（GOG）
- [ ] Steam 账户登录检测与游戏自动发现

## 五、许可与合规

- **本项目**：GPL-3.0（继承自 Whisky）
- **Wine 运行时**：v0.1 计划沿用 Whisky 的 CrossOver 22.1.1 打包方式。v0.2 评估切换到纯上游 Wine 或 Apple GPTK2 官方 Wine。
- **D3DMetal**：Apple 闭源，仅限 Apple Silicon + 非商业使用。不随 App 打包，运行时动态加载或要求用户安装 GPTK。
- **致谢**：README 永久保留对 Whisky、CrossOver、Wine、D3DMetal、MoltenVK、DXVK 等上游项目的致谢。

## 六、风险

1. **Apple 政策风险**：GPTK 许可对商业分发有限制。我们走非商业开源路线，目前合规。
2. **CrossOver 许可风险**：如直接打包其 Wine 分发物，需与 CodeWeavers 澄清。v0.2 计划规避。
3. **Apple 自己下场**：苹果若推出消费级 Game Mode，本项目需要以"社区 + 配方库"作为护城河。
4. **反作弊兼容**：EAC/BattlEye 等 kernel-level 反作弊无法支持，需在文档和 UI 中明确告知用户。
5. **单人维护**：短期内仅一位维护者，需尽早建立贡献者社区与自动化 CI。

## 七、最近更新

- 2026-05-11 ：项目启动，Whisky 源码导入作为基线。
