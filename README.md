<div align="center">

# MacBottle 🍾

**在 Mac 上玩 Windows 游戏，就是这么简单。**
_Play Windows games on your Mac. Simply._

[简体中文](#简体中文) · [English](#english) · [路线图](./PROJECT_PLAN.md) · [贡献指南](./CONTRIBUTING.md) · [交付流程](./CONTRIBUTING.md#delivery-loop-issue--pr--main--ci--merge)

</div>

---

> **Fork 声明 / Fork Notice**
>
> 本项目基于 [Whisky](https://github.com/Whisky-App/Whisky)（由 Isaac Marovitz 创建，GPL-3.0 授权，已于 2025-05-11 归档）衍生，并作出若干修改与扩展。MacBottle 的目标是接续 Whisky 停止维护后留下的空位，以社区驱动、持续维护、中英双语一等公民的方式，继续为 Mac 用户提供现代化的 Wine 图形化封装。
>
> This project is a derivative of [Whisky](https://github.com/Whisky-App/Whisky) (created by Isaac Marovitz, licensed under GPL-3.0, archived on 2025-05-11) with modifications and extensions. MacBottle aims to fill the gap left by Whisky's end of maintenance, continuing to provide a modern graphical Wine wrapper for Mac users through community-driven, actively maintained, bilingual-first development.
>
> MacBottle 保留 Whisky 原作者与贡献者的全部署名，并与 Whisky 一致采用 GPL-3.0 协议发布。/ MacBottle preserves all original Whisky authorship and contributor credits, and is released under GPL-3.0 consistent with Whisky.

---

## 简体中文

### MacBottle 是什么

MacBottle 是一个为 Apple Silicon Mac 打造的 Wine 图形化封装工具。它让你不需要懂命令行、不需要配置 wine prefix，就能在 Mac 上运行 Windows 游戏和应用。

MacBottle **不提供游戏本体**，游戏由你通过 Steam、Epic、GOG、Battle.net 等合法渠道获取。MacBottle 只负责让 Windows 游戏在你的 Mac 上跑起来。

### 为什么做 MacBottle

- **Whisky 停更了。** 2025 年 5 月，深受喜爱的 Whisky 项目宣布停止维护。留下了 13k+ star 的社区和无处安放的需求。
- **中文用户没有好工具。** 现有方案界面全英文、文档全英文、兼容性数据库也以英文为主。
- **Apple Silicon 值得更好的游戏体验。** M 系列芯片性能足以运行 AAA 游戏，瓶颈在生态和工具，不在硬件。

### 系统要求

- CPU：Apple Silicon（M1 / M2 / M3 / M4 系列）
- OS：macOS Sonoma 14.0 或更高版本
- 推荐：16 GB 以上内存，macOS 15 Sequoia 或更高版本

### 当前状态

**🚧 v0.1 开发中。** 详见 [路线图](./PROJECT_PLAN.md)。

### 如何参与

欢迎通过以下方式参与：

- 提 Issue 反馈 bug 或建议
- 提交 PR 贡献代码或游戏兼容性配方
- 翻译界面到其他语言
- 在 V2EX、小红书、B 站分享你的使用经验

详见 [CONTRIBUTING.md](./CONTRIBUTING.md)。代码交付遵循 **Issue → PR → main → CI → merge**（Issue 仅在合并后通过 `Fixes #N` 关闭）。

---

## English

### What is MacBottle

MacBottle is a graphical Wine wrapper for Apple Silicon Macs. It lets you run Windows games and applications on your Mac without touching the command line or configuring wine prefixes manually.

MacBottle **does not ship any game content**. You obtain games through legitimate channels such as Steam, Epic, GOG, and Battle.net. MacBottle is only concerned with running them well on your Mac.

### Why MacBottle

- **Whisky is archived.** In May 2025, the beloved Whisky project stopped maintenance, leaving behind a 13k+ star community with nowhere to go.
- **Chinese-speaking users deserve a first-class experience.** Existing solutions are English-only in UI, documentation, and compatibility databases.
- **Apple Silicon deserves better gaming tooling.** M-series chips have the raw performance for AAA games. The bottleneck is ecosystem and tooling, not hardware.

### System Requirements

- CPU: Apple Silicon (M1 / M2 / M3 / M4 series)
- OS: macOS Sonoma 14.0 or later
- Recommended: 16 GB RAM or more, macOS 15 Sequoia or later

### Current Status

**🚧 v0.1 in development.** See [Project Plan](./PROJECT_PLAN.md) for the roadmap.

### Contributing

Contributions welcome:

- File issues for bugs and feature requests
- Submit PRs for code or game compatibility recipes
- Translate the UI to more languages
- Share your experience in your local Mac-gaming community

See [CONTRIBUTING.md](./CONTRIBUTING.md). Delivery loop: **Issue → PR → main → CI → merge** (Issues close on merge via `Fixes #N` only).

---

## 致谢 / Credits & Acknowledgments

MacBottle 站在以下项目的肩膀上，向所有作者致以最深的敬意：
MacBottle stands on the shoulders of these projects. Our deepest thanks to all their authors.

### 核心前辈 / Core Heritage

- **[Whisky](https://github.com/Whisky-App/Whisky)** by [Isaac Marovitz](https://github.com/IsaacMarovitz) — MacBottle 直接 fork 自 Whisky。没有 Whisky 就没有 MacBottle。
- **[CrossOver 22.1.1](https://www.codeweavers.com/crossover)** by CodeWeavers and WineHQ
- **[D3DMetal (Game Porting Toolkit)](https://developer.apple.com/documentation/gameportingtoolkit)** by Apple

### 依赖与组件 / Dependencies & Components

- [msync](https://github.com/marzent/wine-msync) by marzent
- [DXVK-macOS](https://github.com/Gcenx/DXVK-macOS) by Gcenx and doitsujin
- [MoltenVK](https://github.com/KhronosGroup/MoltenVK) by KhronosGroup
- [Sparkle](https://github.com/sparkle-project/Sparkle) by sparkle-project
- [SemanticVersion](https://github.com/SwiftPackageIndex/SemanticVersion) by SwiftPackageIndex
- [swift-argument-parser](https://github.com/apple/swift-argument-parser) by Apple
- [SwiftyTextTable](https://github.com/scottrhoyt/SwiftyTextTable) by scottrhoyt

特别感谢 Gcenx、ohaiibuzzle、Nat Brown 对 Whisky 的长期支持与贡献。
Special thanks to Gcenx, ohaiibuzzle, and Nat Brown for their long-term support of Whisky.

---

## 许可证 / License

MacBottle 采用 **GNU GPL-3.0** 协议发布，与上游 Whisky 保持一致。详见 [LICENSE](./LICENSE)。
MacBottle is released under **GNU GPL-3.0**, consistent with upstream Whisky. See [LICENSE](./LICENSE).

请注意：Apple 的 D3DMetal 为闭源组件，有其独立的许可条款。MacBottle 不分发 D3DMetal 本身。
Note: Apple's D3DMetal is a closed-source component with its own license terms. MacBottle does not redistribute D3DMetal itself.
