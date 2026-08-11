#!/usr/bin/env python3
import json, sys

PATH = "Whisky/Localizable.xcstrings"

CATALOG = {
    # --- engine / theme ---
    "engine.auto": ("Auto", "自动"),
    "bottle.pinned": ("pinned", "固定"),

    # --- launch coordinator ---
    "launch.alreadyLaunching %@": ("“%@” is already launching, please wait", "「%@」正在启动中，请稍候"),
    "engineCatalog.installed": ("Installed", "已安装"),
    "engineCatalog.notInstalled": ("Not installed", "未安装"),
    "engineCatalog.d3dmetalBackupMissing": ("No Wine backup with D3DMetal found (Libraries.bak*)", "未找到带 D3DMetal 的 Wine 备份（Libraries.bak*）"),
    "engineCatalog.engineNotInstalled": ("The selected Wine engine is not installed yet", "所选 Wine 引擎尚未安装"),

    # --- toolbar / sidebar (ContentView) ---
    "toolbar.engine.help": ("Current global Wine engine", "当前全局 Wine 引擎"),
    "sidebar.discover": ("Discover", "发现"),
    "sidebar.library": ("Game Library", "游戏库"),
    "sidebar.bottles": ("Bottles", "容器"),
    "sidebar.bottles.search": ("Search bottles", "搜索容器"),

    # --- main empty states ---
    "bottle.unavailable.title": ("Bottle unavailable", "容器不可用"),
    "bottle.unavailable.message": ("The selected bottle may have been removed or moved.", "所选容器可能已被移除或移动。"),
    "main.createFirst.message": ("A bottle is an isolated Windows environment. Create one, then install or import a game.", "容器是隔离的 Windows 环境。先建一个，再安装或导入游戏。"),
    "main.pickSidebar.title": ("Pick an item in the sidebar", "选择左侧项目"),
    "main.pickSidebar.message": ("Browse playable recipes from the library, or open a bottle to manage installed programs.", "从游戏库浏览可玩配方，或打开一个容器管理已安装程序。"),

    # --- programs pane/filter/sort/layout enums ---
    "programs.pane.library": ("Library", "程序库"),
    "programs.pane.recent": ("Recent", "最近运行"),
    "programs.pane.blocklist": ("Blocklist", "屏蔽列表"),
    "programs.filter.all": ("All", "全部"),
    "programs.filter.pinned": ("Pinned", "已固定"),
    "programs.filter.unpinned": ("Unpinned", "未固定"),
    "programs.filter.x64": ("64-bit", "64 位"),
    "programs.filter.x86": ("32-bit", "32 位"),
    "programs.filter.games": ("Games / main", "游戏/主程序"),
    "programs.filter.tools": ("Tools / installers", "工具/安装器"),
    "programs.sort.pinnedFirst": ("Pinned first", "固定优先"),
    "programs.sort.recent": ("Recently run", "最近运行"),
    "programs.sort.name": ("Name", "名称"),
    "programs.sort.folder": ("Folder", "目录"),
    "programs.sort.architecture": ("Architecture", "架构"),
    "programs.layout.flat": ("List", "列表"),
    "programs.layout.folders": ("By folder", "按文件夹"),

    # --- programs view ---
    "programs.title": ("Installed Programs", "已安装程序"),
    "programs.search": ("Search name or path", "搜索名称或路径"),
    "programs.hideNoise": ("Hide system noise", "隐藏系统噪声"),
    "programs.hideNoise.help": ("Hide uninstall, crash, redist and other common non-main programs", "隐藏 uninstall、crash、redist 等常见非主程序"),
    "programs.stats.library %lld %lld %lld": ("%lld total · %lld pinned · %lld shown", "共 %lld 个 · 固定 %lld · 显示 %lld"),
    "programs.stats.recent %lld": ("%lld recently run", "最近运行 %lld 个"),
    "programs.stats.blocklist %lld": ("%lld blocked", "已屏蔽 %lld 个"),
    "programs.empty.title": ("No programs to show", "还没有可显示的程序"),
    "programs.empty.search.title": ("No matches", "没有匹配结果"),
    "programs.empty.message": ("Click refresh in the toolbar to scan drive_c. You can also import from the pinned area or “Browse other programs” at the bottom.", "点右上角刷新扫描 drive_c。也可从固定区或底部「浏览其他程序」导入。"),
    "programs.empty.search.message": ("Try another keyword, or turn off “Hide system noise”.", "试试换关键词，或关闭「隐藏系统噪声」。"),
    "programs.empty.action": ("Refresh & scan", "刷新扫描"),
    "programs.recent.empty.title": ("No run history yet", "还没有运行记录"),
    "programs.recent.empty.message": ("After you launch a program from the library or pinned area, it shows up here by time for one-click relaunch.", "从程序库或固定区启动程序后，会按时间显示在这里，方便一键再开。"),
    "programs.blocklist.empty.title": ("Blocklist is empty", "屏蔽列表为空"),
    "programs.blocklist.empty.message": ("Blocked exes no longer appear in library scan results. Right-click a program to block it.", "被屏蔽的 exe 不会再出现在程序库扫描结果中。可从程序库右键加入。"),
    "programs.blocklist.remove": ("Remove", "移除"),
    "programs.blocklist.unblock": ("Unblock", "移除屏蔽"),
    "programs.run": ("Run", "运行"),
    "programs.pin": ("Pin", "固定"),
    "programs.unpin": ("Unpin", "取消固定"),
    "programs.pinToHome": ("Pin to Home", "固定到主页"),
    "programs.config": ("Configure", "配置"),
    "programs.programConfig": ("Program Config", "程序配置"),
    "programs.block": ("Block", "屏蔽"),
    "programs.showInFinder": ("Show in Finder", "在 Finder 中显示"),
    "programs.clearHistory": ("Clear History", "清除记录"),
    "programs.clearHistory.help": ("Clears the last-run time of selected items; clears all if none selected", "清除选中项的最近运行时间；未选中则清空全部"),
    "programs.expandAll": ("Expand All", "全部展开"),
    "programs.collapseAll": ("Collapse All", "全部折叠"),
    "programs.refresh": ("Refresh", "刷新"),
    "programs.addToBlocklist": ("Add to Blocklist", "加入屏蔽列表"),
    "programs.clearRunHistory": ("Clear Run History", "清除运行记录"),
    "programs.runCount %lld": ("%lld runs", "%lld 次运行"),
    "programs.exitCode %lld": ("Exit code %lld", "退出码 %lld"),
    "programs.selected %lld": ("%lld selected", "已选 %lld"),

    # --- bottle view ---
    "bottle.section.pinned": ("Pinned Programs", "固定程序"),
    "bottle.section.pinned.hint": ("Click to launch · drag to reorder", "点击启动 · 拖拽排序"),
    "bottle.section.recent": ("Recently Run", "最近运行"),
    "bottle.section.recent.all": ("All", "全部"),
    "bottle.section.manage": ("Manage", "管理"),
    "bottle.manage.programs.title": ("Installed Programs", "已安装程序"),
    "bottle.manage.programs.subtitle": ("Filter, group, recent and blocklist management", "筛选、分组、最近运行与屏蔽管理"),
    "bottle.manage.config.title": ("Bottle Config", "容器配置"),
    "bottle.manage.config.subtitle": ("Windows version, engine binding, DXVK, Metal", "Windows 版本、引擎绑定、DXVK、Metal"),
    "bottle.manage.processes.title": ("Running Processes", "运行中的进程"),
    "bottle.manage.processes.subtitle": ("View and end Windows processes in this bottle", "查看并结束容器内 Windows 进程"),
    "bottle.manage.logs.title": ("Run Logs", "运行日志"),
    "bottle.manage.logs.subtitle": ("Per-program full run logs and live output", "按程序查看完整运行日志与实时输出"),
    "bottle.launch.warming": ("Warming up bottle", "正在预热容器"),
    "bottle.launch.warming.message %@": ("Starting wineserver for %@; the next launch will be faster…", "为 %@ 启动 wineserver，二次启动会更快…"),
    "bottle.launch.launching": ("Launching", "正在启动"),
    "bottle.launch.launched": ("Launched", "已启动"),
    "bottle.launch.failed %@": ("Launch failed · %@", "启动失败 · %@"),
    "bottle.launch.viewLogs": ("Run Logs", "运行日志"),
    "bottle.launch.close": ("Close", "关闭"),
    "bottle.bar.cDrive": ("C Drive", "C 盘"),
    "bottle.bar.terminal": ("Terminal", "终端"),
    "bottle.bar.logs": ("Run Logs", "运行日志"),
    "bottle.bar.forceStop": ("Force Stop Runtime", "强制结束运行时"),
    "bottle.bar.forceStop.help": ("Immediately end this bottle's Wine/wineserver (use when frozen)", "立即结束本容器的 Wine/wineserver（卡死时使用）"),
    "bottle.bar.browsePrograms": ("Browse other programs…", "浏览其他程序…"),
    "bottle.bar.runSelected %@": ("Run %@", "运行 %@"),
    "bottle.bar.runProgram": ("Run Program", "运行程序"),
    "bottle.run.panel.message": ("Choose a Windows program to run in this bottle (.exe / .msi)", "选择要在此容器中运行的 Windows 程序（.exe / .msi）"),
    "bottle.run.panel.prompt": ("Run", "运行"),
    "bottle.run.info.launched.title": ("Launched", "已启动"),
    "bottle.run.info.launched.message %@": ("Running: %@\n\nIf no window appears, try a freshly created empty bottle (don't run installers in a bottle that already has DXVK on for a game).", "正在运行：%@\n\n若没有窗口出现，请换一个新建的空容器再试（不要用已开 DXVK 的游戏容器跑安装包）。"),
    "bottle.run.info.failed.title": ("Launch failed", "启动失败"),
    "bottle.run.launching": ("Launching", "正在启动"),
    "bottle.recent.configure": ("Configure", "配置"),

    # --- pin view ---
    "pin.help %@": ("Click to launch %@ · drag to reorder", "点击启动 %@ · 可拖拽排序"),
    "pin.run": ("Run", "运行"),
    "pin.moveLeft": ("Move Left", "前移"),
    "pin.moveRight": ("Move Right", "后移"),
    "pin.moveToFront": ("Move to Front", "移到最前"),
    "pin.moveToBack": ("Move to Back", "移到最后"),
    "pin.rename": ("Rename", "重命名"),
    "pin.unpin": ("Unpin", "取消固定"),
    "pin.launching": ("Launching", "正在启动"),
    "pin.add": ("Add Pin", "添加固定"),

    # --- program logs view ---
    "logs.title": ("Run Logs", "运行日志"),
    "logs.sort": ("Sort", "排序"),
    "logs.verbose": ("Verbose debug", "详细调试"),
    "logs.verbose.help": ("When on, captures detailed Wine output (up to ~12MB per run); when off, only metadata and heartbeats", "开启后捕获 Wine 详细输出（最多约 12MB/次）；关闭时仅记录元数据与心跳"),
    "logs.export": ("Export", "导出"),
    "logs.copy": ("Copy", "复制"),
    "logs.delete": ("Delete", "删除"),
    "logs.clean": ("Clean", "清理"),
    "logs.clean.program": ("Clear this program's logs", "清空当前程序日志"),
    "logs.clean.bottle": ("Clear all logs in this bottle", "清空本容器全部日志"),
    "logs.sidebar.programs": ("Programs", "程序"),
    "logs.empty.programs.title": ("No program logs yet", "暂无程序日志"),
    "logs.empty.programs.subtitle": ("After you run a program, logs are recorded per program", "运行程序后会按程序分类记录完整日志"),
    "logs.section.runs": ("Run Records", "运行记录"),
    "logs.empty.runs.title": ("No run records", "无运行记录"),
    "logs.empty.runs.subtitle": ("Select a program on the left to see its run logs", "选择左侧程序查看每次运行日志"),
    "logs.liveOutput": ("Live output", "实时输出"),
    "logs.detail.placeholder": ("Log content", "日志内容"),
    "logs.followTail": ("Follow tail", "跟随底部"),
    "logs.forceStop": ("Force Stop", "强制结束"),
    "logs.empty.detail.title": ("Select a run record", "选择一条运行记录"),
    "logs.empty.detail.subtitle": ("View, copy, or export the log preview (tail snippet)", "可查看、复制、导出日志预览（末尾片段）"),
    "logs.loading.title": ("Loading…", "正在加载…"),
    "logs.loading.subtitle": ("Reading only the tail of the log to avoid stalls", "仅读取日志末尾预览，避免卡顿"),
    "logs.empty.output.title": ("No output yet", "暂无输出"),
    "logs.empty.output.subtitle": ("This run has not produced any displayable log yet", "该次运行尚未产生可显示日志"),
    "logs.export.failed": ("Export failed", "导出失败"),

    # --- log sort / status (WhiskyKit display, moved to app) ---
    "logs.sort.newest": ("Newest first", "最新优先"),
    "logs.sort.oldest": ("Oldest first", "最旧优先"),
    "logs.sort.failedFirst": ("Failed first", "失败优先"),
    "logs.sort.longest": ("Longest first", "时长优先"),
    "logs.status.running": ("Running", "运行中"),
    "logs.status.finished": ("Finished", "已结束"),
    "logs.status.failed": ("Failed", "失败"),

    # --- settings ---
    "settings.engine.section": ("Wine Engine", "Wine 引擎"),
    "settings.engine.autoSelect": ("Auto-select engine per game on launch", "启动时按游戏自动选择引擎"),
    "settings.engine.autoSelect.help": ("Recipe renderer / PE imports temporarily switch the engine at launch without overriding your manual choice.", "配方 renderer / PE 导入表会在启动瞬间临时切换引擎，不覆盖你的手动选择。"),
    "settings.engine.current": ("Current engine", "当前引擎"),
    "settings.engine.help": ("Modern: Wine 11.x general stack. D3DMetal: legacy CrossOver stack, stronger for 64-bit D3D11/12. Reopen games after switching.", "Modern：Wine 11.x 通用栈。D3DMetal：旧 CrossOver 栈，64 位 D3D11/12 更强。切换后请重开游戏。"),
    "settings.engine.busy": ("Working…", "处理中…"),
    "settings.engine.installD3DMetal": ("Install / Repair D3DMetal Engine", "安装 / 修复 D3DMetal 引擎"),
    "settings.engine.refresh": ("Refresh status", "刷新状态"),
    "settings.engine.switched %@": ("Switched to %@", "已切换到 %@"),
    "settings.engine.d3dmetalReady %@": ("D3DMetal engine ready: %@", "D3DMetal 引擎已就绪：%@"),
    "settings.section.update": ("Updates", "更新"),

    # --- config view ---
    "config.engineBinding": ("Wine engine binding", "Wine 引擎绑定"),
    "config.engineBinding.auto": ("Auto (recipe / PE)", "自动（配方 / PE）"),
    "config.engineBinding.help": ("Applies to this bottle only. With “Auto”, the global auto policy is used; pinning an engine overrides recipe/PE suggestions.", "仅对本容器生效。选「自动」时遵循全局自动策略；固定引擎会覆盖配方/PE 建议。"),
    "config.status": ("Status", "状态"),
    "config.d3dmetal.bridgeOk": ("Unix d3d module bridged; 64-bit D3D11/12 can use D3DMetal.", "Unix d3d 模块已桥接，64 位 D3D11/12 可走 D3DMetal。"),
    "config.d3dmetal.foundNoBridge": ("D3DMetal was found, but the current Wine is not linked to the d3d11.so bridge. Old 2D games are unaffected.", "已找到 D3DMetal，但当前 Wine 未链接 d3d11.so 桥。老 2D 游戏不受影响。"),
    "config.d3dmetal.missing": ("No D3DMetal detected. You can restore framework files from a previous WhiskyWine backup.", "未检测到 D3DMetal。可从历史 WhiskyWine 备份恢复框架文件。"),
    "config.d3dmetal.probe": ("Detect / Restore D3DMetal", "探测 / 恢复 D3DMetal"),

    # --- running processes ---
    "processes.forceStop": ("Force Stop Runtime", "强制结束运行时"),

    # --- program view ---
    "program.unpin": ("Unpin", "取消固定"),
    "program.pinToHome": ("Pin to Home", "固定到主页"),
    "program.runLogs": ("Run Logs", "运行日志"),
    "program.pinned": ("Pinned", "已固定"),

    # --- recipe library ---
    "library.title": ("Game Library", "游戏库"),
    "library.search": ("Search games / recipes", "搜索游戏 / 配方"),
    "library.empty.title": ("No recipes yet", "还没有游戏配方"),
    "library.empty.message": ("Click the sync button in the toolbar to fetch the latest recipes from the community.", "点击工具栏同步按钮，从社区获取最新配方。"),
}

def main():
    with open(PATH, "r", encoding="utf-8") as f:
        d = json.load(f)
    strings = d.setdefault("strings", {})
    added = 0
    updated = 0
    for key, (en, zh) in CATALOG.items():
        entry = strings.setdefault(key, {})
        locs = entry.setdefault("localizations", {})
        if "en" not in locs:
            added += 1
        else:
            updated += 1
        locs["en"] = {"stringUnit": {"state": "translated", "value": en}}
        locs["zh-Hans"] = {"stringUnit": {"state": "translated", "value": zh}}
    d["sourceLanguage"] = "en"
    with open(PATH, "w", encoding="utf-8") as f:
        json.dump(d, f, ensure_ascii=False, indent=2, sort_keys=False)
        f.write("\n")
    print(f"added={added} updated={updated} total_keys={len(strings)}")

if __name__ == "__main__":
    main()
