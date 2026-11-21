# Changelog

All notable changes to this project are documented here.
Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
