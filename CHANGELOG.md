# Changelog

All notable changes to this project are documented here.
Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- README 常见问题补两条：Plugins 页 Update 按钮的常驻语义（Git 插件一律显示，≠ 有新版本）；Windows 上周期性闪控制台黑窗的根因（宿主 Git 插件更新检查未隐藏窗口，上游问题）与用户应对
- `docs/ISSUE-win-console-window.md`：上游 issue（[sorrycc/Mayoi#235](https://github.com/sorrycc/Mayoi/issues/235)，当天修复于 c634faa，已随 v0.23.2 发布并本机验证：回归测试 PASS）及其 GUI 子系统四组对照实验：裸 git 启动必现黑窗、vfs.Command/jdtls 链路零窗口
- `docs/VERIFICATION.md` 补"上游反馈 2"实验记录（黑窗来源实证、安装方式规避矩阵、Update 按钮语义实证）

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
