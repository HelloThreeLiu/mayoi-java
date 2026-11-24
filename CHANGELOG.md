# Changelog

All notable changes to this project are documented here.
Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- README 常见问题补两条：Plugins 页 Update 按钮的常驻语义（Git 插件一律显示，≠ 有新版本）；Windows 上周期性闪控制台黑窗的根因（宿主 Git 插件更新检查未隐藏窗口，上游问题）与用户应对
- `docs/ISSUE-win-console-window.md`：上游 issue（[sorrycc/Mayoi#235](https://github.com/sorrycc/Mayoi/issues/235)，当天修复于 c634faa，已随 v0.23.2 发布并本机验证：回归测试 PASS）及其 GUI 子系统四组对照实验：裸 git 启动必现黑窗、vfs.Command/jdtls 链路零窗口
- `docs/VERIFICATION.md` 补"上游反馈 2"实验记录（黑窗来源实证、安装方式规避矩阵、Update 按钮语义实证）
- Windows 引导脚本补齐 POSIX 侧已有的升级路径：受管 JRE 写 `.jre-version` marker 并与 TUNA 目录最新文件名比较（重跑自动升级到最新 25.x；TUNA 不可达时保留现有安装）；受管 jdtls marker 增加版本比较（版本变更时重装，此前仅存在性检查）
- `bootstrap.ps1` 为 jdtls 包加钉死 SHA256 校验（与 `bootstrap.sh` 同一固定产物/哈希；本地/自定义源同样校验，不匹配拒绝安装），缓存命中哈希时跳过下载（消除老 curl `-C -` 对完整文件的 416 续传边界，`bootstrap.sh` M-3 同款捷径）
- 启动器 `-data` 目录名追加完整路径 SHA256 前 8 位后缀：同名目录的不同项目不再共用工作区数据（官方 `jdtls.py` 只哈希目录名的已知串扰风险，PLAN F4；**迁移说明：更新后首次打开每个项目会触发一次重新导入**，旧目录可在清理时删除）
- 启动器对外部 java 做轻量版本提示（仅警告不阻断）：主版本 < 21 时打印可读警告（受管 JRE 分支不触发，不改变"无版本校验"的启动语义）
- CI：各 job 加 `timeout-minutes`（smoke 为阻塞式读，防挂起烧满默认 6 小时）；新增 `e2e-macos` job（macos-latest 真机 bootstrap + LSP 冒烟；brew bash ≥4 跑 smoke 脚本）

### Changed
- `bootstrap.ps1` 的用户 PATH 写入改为原始注册表读写：`REG_EXPAND_SZ` 类型不再被降级为 `REG_SZ`（含 `%var%` 条目的用户 PATH 保持可展开），写后广播 `WM_SETTINGCHANGE`
- 两侧引导脚本的插件安装检测遵循 `MAYOI_DATA_DIR`（此前硬编码 `~/.mayoi/plugins/java`，自定义数据目录的用户会每次重复安装）
- `plugin.json` 语言服务器缺失时的 `install` 提示由 `brew install jdtls` 改为指向仓库安装文档（宿主将其作为纯展示文本嵌入 LspMissing 消息，`brew` 提示对 Windows 用户误导）

### Fixed
- README 卸载章节补上打开过的项目的 jdtls 工作区数据目录（`%APPDATA%\mayoi-java\jdtls` / `~/.cache/mayoi-java/jdtls`，长期使用可能比运行时还大）；FAQ 补排障入口：jdtls 日志位于 `<数据目录>/<项目>/.metadata/.log`
- macOS 真机三连修（新增 CI e2e-macos 首跑暴露，均经 runner 真机归因）：`bootstrap.sh` 顶部钉 `LC_ALL=C`（macOS `/bin/sh` = bash 3.2.57 POSIX 模式 + UTF-8 locale + `set -u` 下 `$var` 紧跟 CJK 字符误报 unbound，T1–T8 矩阵实证）；JRE 解压校验识别 Temurin mac 包的 `Contents/Home` bundle 布局并提升为安装根（落位仍为 `$JRE_DIR/bin/java`，与 Windows/Linux 一致）；`lsp-smoke.sh` 清理前捕获 coproc PID（bash 5.3 收割后撤销 `<name>_PID`，set -u 下误报 unbound）
- README/PLUGIN-RULES 能力范围勘误（依 0.23.3 源码 + 本机 `go test -run TestFindReferencesPicker` PASS）：查找引用（Shift+F12）、转到实现（⌘/Ctrl+F12）、转到类型定义自 **Mayoi 0.23.1**（上游 #211）起已由宿主提供——原文档引用了 `docs/PLUGINS-DESIGN.md` 的过时声明「references 未做」；仍不提供 rename、document highlight、codeAction/documentSymbol（面包屑符号列表为文本正则，Java 类/接口/枚举可见而方法不可见——上游建议草稿见 `docs/ISSUE-lsp-symbols-and-actions.md`）

## [0.2.1] - 2026-11-21

### Added
- `plugins.java.jvmArgs`（array）：用户可配置语言服务器额外 JVM 参数（如 `["-Xmx1g"]` 限制堆上限），后写胜出可覆盖内置 `-Xms256m`；默认 `[]` 行为与 0.2.0 一致

### Fixed
- `bootstrap/bootstrap.sh` 补充 PATH 副本所有权守卫、私有缓存域、架构白名单等加固（复审项）

## [0.2.0] - 2026-11-21

### Added
- **一键引导**：Windows / macOS / Linux 每平台一条命令完成受管 JRE 25 + jdtls 1.63.0 + 免 Python 启动器安装，并接入 PATH（`bootstrap/bootstrap.ps1` / `bootstrap/bootstrap.sh`）
- **免 Python 启动器**：`launcher/jdtls.bat` / `launcher/jdtls`——复刻官方 `bin/jdtls`（Python 3.9+）启动语义，去掉 Python 依赖；JVM 参数含 Java ≥ 24 兼容项
- 受管运行时装于 `%LOCALAPPDATA%\mayoi-java`（POSIX `~/.local/share/mayoi-java`），JDK 8 存量用户不受影响

### Changed
- `-Xms256m`（官方 jdtls.py 为 `-Xms1G`）：实测私有提交 1.3GB → 约 0.5GB，堆按需自动增长

## [0.1.0] - 2026-11-21

### Added
- 首个可用版本：纯清单插件（`command: "jdtls"`），诊断/hover/跳转/补全/格式化经 Mayoi LSP 客户端提供
- 手动安装路径：jdtls（PATH 或 `plugins.java.path`）+ JDK 21+/25 + Python 3.9+
