# MacBottle 项目路线图

> Fork 自 [Whisky](https://github.com/Whisky-App/Whisky)（GPL-3.0，已归档）。面向 Apple Silicon 的现代 Wine 图形化封装。

## 项目信念

**代码即作品，仓库即展品。**

我们不做社区运营、不做独立域名、不做媒体 push、不做 SEO、不做赞助、不做周边。
我们把仓库本身做到工程师看了会尊敬的程度，让开发者自己找上门、自己提 PR、自己把它带到更多地方。

## 唯一的问题

让 Windows 游戏在 Apple Silicon 上跑起来。

## 技术边界

**做**：
- Bottle 管理（继承 Whisky）
- Wine / CrossOver / GPTK 启动链（继承 Whisky）
- **配方（Recipe）系统** —— 整个项目唯一的护城河
- Apple Silicon / macOS 15+ 新 API 适配

**不做**：
- 不做虚拟机方案
- 不自研 DX→Metal 翻译层
- 不碰内核态反作弊
- 不分发游戏本体
- 不做云服务、不做付费功能

## 配方系统（Recipe）

这是 MacBottle 与 Whisky 的核心区别。一个配方是一份 JSON 文件，描述"让这个游戏跑起来需要哪些设置"。

- 位置：`WhiskyKit/Sources/WhiskyKit/Recipes/<platform>/<id>.json`
- 格式：JSON，有 schema 校验（`docs/recipe.v1.schema.json`）
- 贡献方式：开发者提交 PR，加一个 JSON 文件
- 运行时：App 启动时从 bundle 加载所有配方，用户对一个 bottle 挂载某个配方后，启动游戏时配方里的 env、winetricks、注册表自动应用

详见 [`docs/RECIPE_AUTHORING.md`](./docs/RECIPE_AUTHORING.md) 和 [`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md)。

## 版本节奏

| 版本 | 核心交付 |
| -- | -- |
| v0.1 | 品牌切换 + 可编译 .app（沿用 Whisky 的 CrossOver 打包） |
| v0.2 | Recipe 系统（schema、loader、applier、示例配方） |
| v0.3 | CI schema-lint + PR 模板 + 完善架构文档 + Recipe UI |
| v0.4 | Wine 引擎抽象层，CrossOverEngine 为首个实现 |
| v0.5 | 远程配方同步（Stage 1 数据层 + Stage 2 同步引擎 + Stage 3 diff UI） |
| v0.6 | 用户可切换引擎，第二个实现（纯上游 Wine 或 GPTK2） |
| v1.0 | 正式发布，GitHub Release，Show HN 一次 |

### v0.5 子阶段

远程配方同步是 MacBottle 的核心护城河交付，拆为三个独立 commit：

- **v0.5.1 数据层**：配方 schema 加图标、扩充到约 20 款热门游戏、UI 展示图标
- **v0.5.2 同步引擎**：`RecipeSyncSource` 走 GitHub Contents API，`RecipeCache` 落盘到 Application Support，带 ETag 缓存
- **v0.5.3 diff UI**：用户进入游戏列表时自动检查，变更弹 sheet 展示 `+新增 / -删除 / ~更新`，支持全选和逐条勾选

v1.0 之后：**只合 PR，只做引擎层维护。** 配方由社区贡献者自行添加。

## 许可

- 本项目：**GPL-3.0**（继承自 Whisky，永久）
- D3DMetal：Apple 闭源，不随包分发，运行时检测本地 GPTK
- CrossOver：v0.1 沿用 Whisky 的打包方式；v0.4 评估切换到纯上游 Wine

## 致谢

永久保留对 Whisky、CrossOver、Wine、D3DMetal、DXVK、MoltenVK 等上游项目的署名。详见 `NOTICE` 与 `README.md`。
