<div align="center">

<img src="../../Whisky/Assets.xcassets/AppIcon.appiconset/512@2x.png" width="96" alt="MacBottle 图标" />

# MacBottle 🍾

### 在 Mac 上畅玩 Windows 游戏。就这么简单。

**MacBottle 是一款专为 Apple Silicon 打造的现代化 Wine 封装,由社区持续维护。选一个容器,把 Windows 游戏放进去,点击播放——不用碰终端,不用手动配置 Wine 前缀,也不用反复试错。当某款游戏需要默认设置之外的调整时,社区配方会自动应用正确的环境变量、Winetricks 和注册表设置。**

[English](https://github.com/shiaho777/MacBottle/blob/main/README.md) · **简体中文**

[![License](https://img.shields.io/badge/License-GPL--3.0-blue?style=for-the-badge)](../../LICENSE)
[![Platform](https://img.shields.io/badge/macOS-14%2B-black?style=for-the-badge&logo=apple&logoColor=white)](#系统要求)
[![Chip](https://img.shields.io/badge/Apple%20Silicon-Only-red?style=for-the-badge)](#系统要求)
[![Swift](https://img.shields.io/badge/Swift-6-orange?style=for-the-badge&logo=swift&logoColor=white)](#)

</div>

<p align="center">
  <a href="#为什么是-macbottle">为什么是 MacBottle</a> ·
  <a href="#能力概览">能力概览</a> ·
  <a href="#你能用它做什么">你能用它做什么</a> ·
  <a href="#完整功能地图">功能地图</a> ·
  <a href="#配方系统">配方系统</a> ·
  <a href="#架构">架构</a> ·
  <a href="#路线图">路线图</a> ·
  <a href="#如何参与">如何参与</a>
</p>

---

## 为什么选择 MacBottle

在 Apple Silicon 上玩 Windows 游戏,不该还需要先学一遍命令行。MacBottle 替你把这些事做完,并且在默认配置停下的地方继续往前:

- **持续维护中。** 开源、持续开发——修复、新配方、对最新 Apple Silicon 与 macOS 的适配都会持续推进。
- **不需要命令行。** 不用手搓 wine prefix,不用背 `WINEPREFIX`。MacBottle 用原生 macOS 窗口完成每一个瓶子的创建、配置与启动。
- **免费,且开源。** MacBottle 所做的一切都是 GPL-3.0、公开构建——没有授权费,没有订阅,没有锁起来的功能。
- **每款游戏都有自己的配方。** 一份配方就是一个 JSON 文件,记录单款游戏所需的一切:环境变量、winetricks 动词、注册表调整、合适的渲染器。配方经社区验证,从共享目录同步,启动时自动应用。普通封装工具让你自己猜答案,配方直接把答案交给 MacBottle。
- **自动选择正确的引擎。** 每次启动都会检查可执行文件(PE 导入和运行时画像),结合挂载的配方,自动选用 **D3DMetal**、**DXVK** 或 **WineD3D**,并运行对应的 Wine 引擎——全程不用你操心。
- **中英文,从一开始就一起写。** 界面、配方、文档从第一行起就用两种语言编写,而不是事后补的翻译。

---

## 能力概览

盒子里有什么,快速扫一眼。

| 领域 | 亮点 |
| --- | --- |
| **瓶子管理** | 创建、配置、重命名、删除;Pin 快捷方式;每个瓶子独立绑定引擎 |
| **游戏配方** | 社区 JSON 配方(Steam / GOG / 通用),内置目录 + ETag 缓存远程同步,diff UI 逐条勾选 |
| **渲染方案** | 自动选择 **D3DMetal**(Apple GPTK)、**DXVK**(异步 + HUD)或 **WineD3D**;Metal HUD/Trace;DXR 开关 |
| **Wine 引擎层** | 目前为 CrossOver 系引擎;可插拔的 `WineEngine` 协议,为将来接入纯上游 Wine 留好位置 |
| **启动体验** | wineserver 预热、启动状态反馈、每个程序的运行日志、冻结运行时强制停止、陈旧状态对账 |
| **瓶子内部** | Winetricks 分类动词表、环境变量、Windows 版本与增强同步(msync/esync)、AVX 开关 |
| **集成与工具** | CLI 伴生工具(`WhiskyCmd`)、Finder 中 `.exe` 文件的缩略图预览、着色器缓存清理 |

---

## 你能用它做什么

| 来源 | MacBottle 做什么 | 适合 |
| --- | --- | --- |
| Steam 游戏库 | 指向游戏的 `.exe`;配方(如有)自动应用调优 | Apple Silicon 上的 3A 与独立游戏 |
| GOG / 无 DRM 安装包 | 装进瓶子一次,以后从程序列表直接启动 | 你真正拥有的游戏 |
| 零售 / 其他安装器 | 挂一个 `generic` 配方,或手动配置 | Origin、Battle.net 等杂牌安装器 |
| 经典 32 位老游戏 | `classic32` 运行时画像强制走 WineD3D 路径 | 从未出过 64 位移植的老作品 |
| 非游戏 Windows 应用 | 与游戏完全一样——瓶子不挑食 | 办公工具、实用软件、老共享软件 |

---

## 完整功能地图

MacBottle 的开关比表面看起来多得多。下面按使用场景分组,全部可折叠,保证页面顶部保持清爽可扫读。

<details>
<summary><b>🍾 瓶子管理</b></summary>

- **一键创建** —— 起个名字、选个 Windows 版本,完成。不用输入 prefix 路径,不用编辑配置文件。
- **每个瓶子的独立设置** —— 环境变量、Windows 版本(win10/…)、增强同步(**msync** 默认,或 esync)、AVX 开关、Retina 模式、DXR。
- **引擎绑定** —— 把瓶子固定到某个 Wine 引擎,或交给自动选择(`LaunchEnginePolicy` 每次启动决定)。
- **Pin 快捷方式** —— 把已安装的程序钉到瓶子首页,附带独立的启动环境参数。
- **Winetricks 目录** —— 分类动词表,一键安装(vcrun、dotnet 等)。
- **日常维护** —— 从菜单栏重命名、删除、强制停止瓶子内所有进程。

</details>

<details>
<summary><b>🧪 配方系统</b></summary>

- **内置目录** —— 配方随 App 一起发布,启动即加载,零配置。
- **远程同步** —— 目录通过 GitHub 托管的清单(`_index.json`,每次合并到 main 后由 CI 重新生成)+ raw CDN 的 ETag 条件请求更新——几乎不受限流影响,不需要 API key。
- **Diff UI** —— 进入游戏列表时自动检查更新,以 sheet 展示 `+新增 / −删除 / ~更新`,支持逐条勾选与「同步选中」。没有变化时完全不会打扰你。
- **游戏详情与安装向导** —— 以图库形式浏览配方、阅读兼容性说明,或运行引导式安装:自动建瓶、应用 winetricks/注册表、启动游戏。
- **冲突时配方优先** —— 配方是比瓶子默认值更窄、更经社区验证的事实来源;不认同就卸载配方。

</details>

<details>
<summary><b>⚙️ Wine 引擎层</b></summary>

- **`WineEngine` 协议** —— 「这个安装用哪个 Wine」的全部逻辑收敛到一个接口后面;将来换引擎是一行注册表改动,而不是全仓库查找替换。
- **`CrossOverEngine`** —— 第一个具体实现,承接 Whisky/CrossOver 系的打包方式。
- **`LaunchEnginePolicy`** —— 每次启动的决策引擎:扫描 PE 导入 + 运行时画像,尊重瓶子固定与配方的 `renderer`,D3DMetal 未安装时优雅降级。
- **临时切换引擎** —— 自动选择只对本次启动生效,你保存的选择事后会恢复。

</details>

<details>
<summary><b>🚀 启动体验</b></summary>

- **Wineserver 预热** —— 游戏启动前先暖引擎,第一次点击不再是干等。
- **启动状态反馈** —— UI 反映真实状态,而不是沉默地转圈。
- **运行日志** —— 每次运行都会写日志,可从界面直接打开(`⌘L` 打开日志文件夹);超过 7 天的旧日志自动清理。
- **强制停止** —— 冻结的 Wine 运行时由宿主侧强制停止,`⌘⇧K` 一键杀掉所有瓶子;游戏进程真正死亡后,过期的「运行中」状态会被自动对账清除。

</details>

<details>
<summary><b>🔌 集成与工具</b></summary>

- **CLI 伴生工具** —— `WhiskyCmd` 把瓶子与启动工作流带进终端,从 App 菜单一键安装。
- **Finder 缩略图** —— 扩展为 Windows 可执行文件在 Finder 中渲染预览。
- **着色器缓存管理** —— 图形异常时,一个菜单项即可杀瓶子并清掉 D3DMetal 着色器缓存。
- **首次启动向导** —— 引导安装 Rosetta 2 与 Wine 引擎下载/安装,全新 Mac 一次坐定,从零到能玩。

</details>

---

## 配方系统

配方是 MacBottle 作为独立 fork 存在的理由,也是项目最主要的增长机制。一份配方就是一个 JSON 文件——贡献它不需要懂 Swift:

```
WhiskyKit/Sources/WhiskyKit/Recipes/
  steam/<AppID>.json       # 例:steam/2050650.json(黑神话:悟空)
  gog/<ProductID>.json     # 例:gog/1207658924.json(巫师 2)
  generic/<slug>.json      # 平台外的作品或零售安装器
```

每份配方声明游戏的 DirectX 版本、最低 macOS、推荐渲染器、可选的 winetricks 动词、环境变量、注册表调整,以及一个诚实的兼容性分级(platinum → broken,沿用 ProtonDB 刻度)。CI 用真实的 Swift `Recipe` 类型校验每一份文件——配方要么能解码,要么错误信息直接告诉你哪个字段不对。

完整 schema、示例与评审标准见 [`docs/RECIPE_AUTHORING.md`](../../docs/RECIPE_AUTHORING.md)。

---

## 架构

```
Whisky/                  macOS App 目标 —— SwiftUI 视图、瓶子/程序交互
WhiskyKit/               核心库(SwiftPM)—— 模型、Wine 调用、配方
  ├─ Recipe/             配方类型、加载器、应用器、远程同步、diff
  ├─ Recipes/            随包发布的配方 JSON
  ├─ WineEngine/         引擎协议、CrossOverEngine、目录、启动策略
  ├─ Whisky/             Bottle / Program / 设置模型
  ├─ Wine/               启动协调器、运行日志、强制停止、优化器
  └─ PE/                 Windows PE 解析器(导入、架构、图形 API)
WhiskyCmd/               CLI 伴生工具
WhiskyThumbnail/         Finder 缩略图扩展(PE 文件)
```

游戏启动按严格顺序合并环境变量——程序默认值 → 瓶子设置 → 配方覆盖(配方优先)——再经由 `LaunchEnginePolicy` 选中的引擎执行 `wine <exe>`。未挂配方时,代码路径与上游 Whisky 完全一致;配方层纯粹是增量。

完整设计思路见 [`docs/ARCHITECTURE.md`](../../docs/ARCHITECTURE.md)。

---

## 路线图

| 版本 | 核心交付 |
| -- | -- |
| v0.1 | 品牌切换 + 可编译、可运行的 `.app`(沿用 Whisky/CrossOver 打包) |
| v0.2 | 配方系统——schema、loader、applier、示例配方 |
| v0.3 | CI schema-lint + PR 模板 + 架构文档 + 配方 UI |
| v0.4 | Wine 引擎抽象层,`CrossOverEngine` 为首个实现 |
| v0.5 | 远程配方同步(数据层 → 同步引擎 → diff UI) |
| v0.6 | 用户可切换引擎,第二个实现(纯上游 Wine 或 GPTK2) |
| v1.0 | 正式发布,GitHub Release |

完整规划——包括 v0.5 子阶段与明确的不做清单(不做虚拟机、不碰 DRM/反作弊、不分发游戏本体)——见 [`PROJECT_PLAN.md`](../../PROJECT_PLAN.md)。

---

## 系统要求

- **CPU:** Apple Silicon(M1 / M2 / M3 / M4 系列)
- **OS:** macOS Sonoma 14.0 或更高版本
- **推荐:** 16 GB 以上内存,macOS 15 Sequoia 或更高版本

MacBottle **不提供游戏本体**。游戏通过 Steam、Epic、GOG、Battle.net 等合法渠道获取;MacBottle 只负责让它们在你的 Mac 上跑起来。

---

## 如何参与

| 通道 | 你做什么 | 工作量 |
| --- | --- | --- |
| **配方** | 把一款游戏跑起来,然后新增或更新它的 JSON 配方——影响力最大的贡献方式 | 数小时 |
| **Issue** | 报 bug、提需求,或为跑不起来的游戏提交配方请求 | 几分钟 |
| **代码** | 在 Swift App / WhiskyKit 里修 bug 或做功能 | 数天 |
| **翻译** | 帮助界面文案与文档保持双语(中文 / English) | 视情况 |

所有工作遵循同一条交付闭环——**Issue → PR → main → CI → merge**(Issue 仅在合并时通过 `Fixes #N` 关闭)。完整指南,包括必检 CI 与代码风格,见 [`CONTRIBUTING.md`](../../CONTRIBUTING.md)。

---

## Whisky 传承与致谢

MacBottle 衍生自 [Whisky](https://github.com/Whisky-App/Whisky)(Isaac Marovitz 创建,GPL-3.0,2025-05-11 归档),并站在让「Mac 上的 Wine」成为可能的所有项目肩上:CrossOver/WineHQ、Apple 的 D3DMetal(Game Porting Toolkit)、DXVK-macOS、MoltenVK、wine-msync、Sparkle 等。所有原作者的署名与致谢,完整保留在每一个继承的文件与 [`NOTICE`](../../NOTICE) 中。

## 许可证

[GPL-3.0](../../LICENSE),与上游 Whisky 保持一致。

请注意:Apple 的 D3DMetal 为闭源组件,有其独立的许可条款。MacBottle 不分发 D3DMetal 本身。

<div align="center">

**开源 · 为 Apple Silicon 而生 · 少配置,多游玩**

</div>
