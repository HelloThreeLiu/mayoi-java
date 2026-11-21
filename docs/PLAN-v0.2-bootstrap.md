# v0.2 一键引导（Bootstrap）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 mayoi-java 的使用前置从"手动装 jdtls + Python + JDK 21/25"压缩为**每个平台一条终端命令**：下载并安装受管 JRE + jdtls、生成免 Python 启动器、接入 PATH，使插件默认配置（`command: "jdtls"`）开箱即用。

**Architecture:** 新增 `bootstrap/`（每平台一个自包含引导脚本）与 `launcher/`（免 Python 的 jdtls 启动器，提交入库）。引导脚本幂等：检测到可用环境即跳过对应步骤；一切装到**固定目录** `%LOCALAPPDATA%\mayoi-java\`（POSIX：`~/.local/share/mayoi-java/`），并把启动器目录**追加**（绝不覆盖）到用户 PATH。启动器按 PATH 优先级解析 java（受管 JRE 优先），复刻 `jdtls.py` 全部启动参数（Task 1 已逐字核实源码）。**不做** settings.json 写入（默认 `"jdtls"` 经 PATH 即可命中，避免 CLI 无法写嵌套插件键的限制）；**不做**编辑器内命令（v0.3，需 main.ts 且受 10 秒预算约束）。

**Tech Stack:** PowerShell 5.1+（bootstrap.ps1，`iwr | iex` 模式）、POSIX sh（bootstrap.sh，`curl | sh` 模式）、Windows 批处理 + POSIX sh（启动器）、Temurin JRE 25（清华 Adoptium 镜像为主源）、eclipse.org jdtls milestone 1.63.0（唯一源，支持断点续传）。

---

## 0. 背景与已核实事实

v0.1 验收（`docs/VERIFICATION.md`）暴露的产品问题（用户反馈）：使用本插件需要预装 **jdtls + Python 3.9 + JDK 21/25**，且 JDK 8 存量用户被拒之门外。技术事实：

| # | 事实 | 对本计划的意义 |
|---|---|---|
| G1 | jdtls 本体只需 **JRE 25+** 即可运行（Task 1 A1 实测 = JDK 25 运行）；用户的 JDK 8 只用于运行他们自己的程序，与编辑器无关——ECJ 可分析 `release=8` 的老项目 | 引导脚本装 **JRE**（≈45MB）而非 JDK（≈135MB）即可 |
| G2 | `jdtls.py` 的启动参数已全部核实（Task 1 A0/B2：17 项固定参数、平台 config、`-data` 哈希、Java≥24 附加参数） | 免 Python 启动器可逐字复刻，零猜测 |
| G3 | Mayoi 用 Go `exec.LookPath` 按 PATH 找 `command`（Windows 按 PATHEXT 命中 `.bat`）——**PATH 上有我们的启动器 = 插件默认配置直接可用**，无需写 settings.json | PATH 追加是本方案的"配置"步骤 |
| G4 | Windows 10 1803+ 自带 `curl.exe` 与 `tar.exe`；macOS/Linux 自带 curl 与 tar | 下载/解压零外部依赖，支持 `-C -` 断点续传 |
| G5 | TUNA 镜像有 Adoptium **JRE** 产物（`/Adoptium/25/jre/x64/windows/OpenJDK25U-jre_x64_windows_hotspot_25.0.5_8.zip`，约 45MB，国内快）；**jdtls 无国内镜像**（Task 1 实测 404），只能 eclipse.org 直连（49MB，国内慢，必须支持断点续传与本地预下载通道） | 下载策略：JRE 走镜像直下；jdtls 支持续传 + 手动预下载参数 |
| G6 | Mayoi 设置支持热加载；`mayoi settings` CLI 无法写 `plugins.<name>.<key>` 嵌套键（Task 2 实测） | 方案彻底绕开 settings 写入（PATH 即配置） |
| G7 | Mayoi 对不存在文件场景：`keymap.Watch` 监目录（可热加载）；插件命令需 main.ts 且单命令 10 秒预算 | 编辑器内触发推 v0.3；本版用终端一条命令 |

## 1. 设计定案

### 1.1 用户体验（最终形态）

```powershell
# Windows（PowerShell 任意安全策略下可用——iex 字符串不受执行策略限制）
iwr -useb https://raw.githubusercontent.com/HelloThreeLiu/mayoi-java/main/bootstrap/bootstrap.ps1 | iex
```
```sh
# macOS / Linux
curl -fsSL https://raw.githubusercontent.com/HelloThreeLiu/mayoi-java/main/bootstrap/bootstrap.sh | sh
```

一条命令完成后：受管 JRE + jdtls 已装好、启动器已进 PATH、（若检测到 mayoi CLI）插件本体已安装。用户重启 Mayoi 打开 `.java` 即可用。

### 1.2 安装布局（固定，启动器按相对路径引用 JRE）

```
Windows: %LOCALAPPDATA%\mayoi-java\
├── jre\            （Temurin JRE 25，bin\java.exe）
├── jdtls\          （官方 milestone 包原样解压：bin\ config_win\ plugins\ …）
└── bin\
    └── jdtls.bat   （免 Python 启动器；%~dp0 相对引用 ..\jre 与 ..\jdtls）

POSIX: ~/.local/share/mayoi-java/
├── jre/
├── jdtls/
└── bin/jdtls       （启动器；另复制一份到 ~/.local/bin/jdtls，PATH 常规覆盖处）
```

### 1.3 启动器规范（免 Python，逐项对应 jdtls.py 已核实行为）

1. **java 解析优先级**：`<安装目录>\jre\bin\java(.exe)`（受管 JRE，存在即用）→ `JAVA_HOME\bin\java(.exe)` → PATH `java`。受管 JRE 优先保证 JRE 缺失回退时给出明确告警。
2. **固定 JVM 参数**（G2，逐字）：`-Declipse.application=org.eclipse.jdt.ls.core.id1`、`-Dosgi.bundles.defaultStartLevel=4`、`-Declipse.product=org.eclipse.jdt.ls.core.product`、`-Dosgi.checkConfiguration=true`、`-Dosgi.sharedConfiguration.area=<jdtls目录>\config_win|mac|linux`、`-Dosgi.sharedConfiguration.area.readOnly=true`、`-Dosgi.configuration.cascaded=true`、`-Xms1G`、`--add-modules=ALL-SYSTEM`、`--add-opens java.base/java.util=ALL-UNNAMED`、`--add-opens java.base/java.lang=ALL-UNNAMED`、`-Djdk.xml.maxGeneralEntitySizeLimit=0`、`-Djdk.xml.totalEntitySizeLimit=0`（最后两项 jdtls.py 仅在 Java≥24 追加；`-D` 系统属性在旧 JVM 上无害，**无条件追加**以免启动器做版本解析）。
3. **入口 jar**：glob `plugins/org.eclipse.equinox.launcher_*.jar`（优先精确名 `org.eclipse.equinox.launcher.jar`）。
4. **`-data` 目录**：`<平台缓存>\mayoi-java\jdtls\<净化后的 cwd 目录名>`（净化 = 替换 `\/:*?"<>|` 为 `_`）。**偏离官方 sha1 哈希**（批处理无法便捷计算字符串 sha1；同为 basename 粒度，碰撞特性与官方一致，净化后合法性更好）。平台缓存：Windows `%APPDATA%`、macOS `~/Library/Caches`、Linux `~/.cache`（与官方一致）。
5. **参数透传**：`%*` / `"$@"` 追加在末尾（用户可自行 `-data` 覆盖、传 `--jvm-arg` 等）。
6. **无版本校验、无 pause、无 python**：受管 JRE 恒为 25（版本必然达标）；回退路径失败时 OSGi 报错已含可读原因（Task 1 A3 ② 实测形态）。

### 1.4 幂等矩阵

| 环境状态 | 引导脚本行为 |
|---|---|
| PATH 已有 jdtls（`command -v` / `where` 命中且非本安装目录） | 打印"检测到现有 jdtls，跳过安装"；仍确保受管 JRE？否——全跳过，仅提示插件安装步骤 |
| 受管 JRE 已存在 | 跳过 JRE 下载 |
| 受管 jdtls 已存在（marker 文件版本相同） | 跳过 jdtls 下载 |
| 用户 PATH 已含安装 bin 目录 | 跳过 PATH 追加 |
| 已通过 `mayoi` CLI 检测到插件已安装 | 跳过插件安装 |

### 1.5 下载源与容错

| 产物 | 主源 | 回退 |
|---|---|---|
| JRE 25 (zip/tar.gz) | TUNA `https://mirrors.tuna.tsinghua.edu.cn/Adoptium/25/jre/<platform>/OpenJDK25U-jre_<plat>_windows_hotspot_25.0.5_8.zip` | Adoptium 官方 API `https://api.adoptium.net/v3/binary/latest/25/ga/windows/x64/jre/hotspot/normal/eclipse?project=jdk`（302 到官方 CDN） |
| jdtls 1.63.0 (tar.gz) | `https://download.eclipse.org/jdtls/milestones/1.63.0/jdt-language-server-1.63.0-202610191322.tar.gz`，`curl -C -` 续传 | 无镜像（Task 1 实测）；支持 `MAYOI_JDTLS_TGZ` 环境变量指向**本地预下载文件**或自定义 URL |

curl 统一参数：`--ssl-no-revoke -L -C - --retry 3 --retry-delay 2 -o <file>`（Windows curl.exe 7.83+ 全支持；POSIX curl 同）。

## 2. 文件结构

```
mayoi-java/
├── bootstrap/
│   ├── bootstrap.ps1        # Windows 一条命令入口（iwr | iex）
│   └── bootstrap.sh         # POSIX 一条命令入口（curl | sh）
├── launcher/
│   ├── jdtls.bat            # Windows 免 Python 启动器（bootstrap 复制到安装目录）
│   └── jdtls                # POSIX 免 Python 启动器（同上）
├── plugin.json              # version → 0.2.0（Task 5）
├── README.md                # 前置要求改写 + 一条命令安装（Task 5）
└── docs/PLAN-v0.2-bootstrap.md  # 本计划
```

## 3. 任务总览

| Task | 内容 | 验证 |
|---|---|---|
| Task 1 | 启动器 `launcher/jdtls.bat` + `launcher/jdtls` | smoke 脚本指向启动器 → SMOKE OK |
| Task 2 | `bootstrap/bootstrap.ps1` | 本机 E2E：跑完后**删除 settings 里 java.path**，用默认 `"jdtls"` 经 PATH 打开 .java 全功能 |
| Task 3 | `bootstrap/bootstrap.sh` | `bash -n` 语法 + Git Bash 假服务器冒烟（同 C1 模式）；真机 POSIX 留待 |
| Task 4 | plugin.json 0.2.0 + README 一条命令安装 + 前置要求改写 | JSON 校验 + 三方口径一致 |
| Task 5 | 提交、合并 main、tag v0.2.0、推送 | GitHub 可见；`plugin install` 升级测试 |

---

## Task 1: 免 Python 启动器

**Files:**
- Create: `launcher/jdtls.bat`
- Create: `launcher/jdtls`

- [ ] **Step 1: 写 `launcher/jdtls.bat`**（内容如下，逐字）

```bat
@echo off
rem mayoi-java 免 Python jdtls 启动器（复刻官方 jdtls.py 启动语义，无版本校验）
rem java 解析：受管 JRE（%~dp0..\jre）> JAVA_HOME > PATH；-data 用净化 cwd 目录名
setlocal EnableExtensions

set "HERE=%~dp0"
set "JRE_JAVA=%HERE..\jre\bin\java.exe"
set "JAVA_EXE="

if exist "%JRE_JAVA%" set "JAVA_EXE=%JRE_JAVA%"
if not defined JAVA_EXE if defined JAVA_HOME if exist "%JAVA_HOME%\bin\java.exe" set "JAVA_EXE=%JAVA_HOME%\bin\java.exe"
if not defined JAVA_EXE (
    where java >nul 2>nul && set "JAVA_EXE=java"
)
if not defined JAVA_EXE (
    echo mayoi-java: 未找到 java。请重跑引导脚本安装受管 JRE，或安装 JDK 21+。 1>&2
    exit /b 1
)

rem 定位 equinox launcher：优先精确名，再 glob 版本名
set "JDTLS_DIR=%HERE..\jdtls"
set "LAUNCHER="
if exist "%JDTLS_DIR%\plugins\org.eclipse.equinox.launcher.jar" set "LAUNCHER=%JDTLS_DIR%\plugins\org.eclipse.equinox.launcher.jar"
if not defined LAUNCHER (
    for /r "%JDTLS_DIR%\plugins" %%f in (org.eclipse.equinox.launcher_*.jar) do set "LAUNCHER=%%f" & goto :launcher_found
)
:launcher_found
if not defined LAUNCHER (
    echo mayoi-java: 在 %JDTLS_DIR% 下未找到 equinox launcher。 1>&2
    exit /b 1
)

rem 平台 shared configuration
set "CONFIG_DIR=config_win"
if /i "%PROCESSOR_ARCHITECTURE%"=="ARM64" set "CONFIG_DIR=config_win"

rem -data 目录：%APPDATA%\mayoi-java\jdtls\<净化 cwd 目录名>
set "CWD_NAME=%CD%"
for %%p in ("%CD%") do set "CWD_NAME=%%~nxp"
set "CWD_NAME=%CWD_NAME:\=_%"
set "CWD_NAME=%CWD_NAME:/=_%"
set "CWD_NAME=%CWD_NAME::=_%"
set "CWD_NAME=%CWD_NAME:*=_%"
set "CWD_NAME=%CWD_NAME:?=_%"
set "CWD_NAME=%CWD_NAME:<=_%"
set "CWD_NAME=%CWD_NAME:>=_%"
set "CWD_NAME=%CWD_NAME:|=_%"
set "CWD_NAME=%CWD_NAME: =_%"
set "DATA_DIR=%APPDATA%\mayoi-java\jdtls\%CWD_NAME%"
if not exist "%DATA_DIR%" mkdir "%DATA_DIR%" >nul 2>nul

"%JAVA_EXE%" ^
  -Declipse.application=org.eclipse.jdt.ls.core.id1 ^
  -Dosgi.bundles.defaultStartLevel=4 ^
  -Declipse.product=org.eclipse.jdt.ls.core.product ^
  -Dosgi.checkConfiguration=true ^
  "-Dosgi.sharedConfiguration.area=%JDTLS_DIR%\%CONFIG_DIR%" ^
  -Dosgi.sharedConfiguration.area.readOnly=true ^
  -Dosgi.configuration.cascaded=true ^
  -Xms1G ^
  --add-modules=ALL-SYSTEM ^
  --add-opens java.base/java.util=ALL-UNNAMED ^
  --add-opens java.base/java.lang=ALL-UNNAMED ^
  -Djdk.xml.maxGeneralEntitySizeLimit=0 ^
  -Djdk.xml.totalEntitySizeLimit=0 ^
  -jar "%LAUNCHER%" ^
  -data "%DATA_DIR%" %*
```

- [ ] **Step 2: 写 `launcher/jdtls`**（POSIX，逐字）

```sh
#!/bin/sh
# mayoi-java 免 Python jdtls 启动器（复刻官方 jdtls.py 启动语义，无版本校验）
# java 解析：受管 JRE（../jre）> JAVA_HOME > PATH；-data 用净化 cwd 目录名
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
JDTLS_DIR="$HERE/../jdtls"

JAVA_EXE=""
if [ -x "$HERE/../jre/bin/java" ]; then
  JAVA_EXE="$HERE/../jre/bin/java"
elif [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ]; then
  JAVA_EXE="$JAVA_HOME/bin/java"
elif command -v java >/dev/null 2>&1; then
  JAVA_EXE="java"
else
  echo "mayoi-java: 未找到 java。请重跑引导脚本安装受管 JRE，或安装 JDK 21+。" >&2
  exit 1
fi

LAUNCHER=""
if [ -f "$JDTLS_DIR/plugins/org.eclipse.equinox.launcher.jar" ]; then
  LAUNCHER="$JDTLS_DIR/plugins/org.eclipse.equinox.launcher.jar"
else
  for f in "$JDTLS_DIR"/plugins/org.eclipse.equinox.launcher_*.jar; do
    [ -f "$f" ] && LAUNCHER="$f" && break
  done
fi
[ -n "$LAUNCHER" ] || { echo "mayoi-java: 在 $JDTLS_DIR 下未找到 equinox launcher。" >&2; exit 1; }

case "$(uname -s)" in
  Darwin) CONFIG_DIR=config_mac ;;
  *)      CONFIG_DIR=config_linux ;;
esac

CWD_NAME=$(basename "$(pwd)")
CWD_NAME=$(printf '%s' "$CWD_NAME" | tr '/:*?"<>| ' '_________')
DATA_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/mayoi-java/jdtls/$CWD_NAME"
mkdir -p "$DATA_DIR"

exec "$JAVA_EXE" \
  -Declipse.application=org.eclipse.jdt.ls.core.id1 \
  -Dosgi.bundles.defaultStartLevel=4 \
  -Declipse.product=org.eclipse.jdt.ls.core.product \
  -Dosgi.checkConfiguration=true \
  "-Dosgi.sharedConfiguration.area=$JDTLS_DIR/$CONFIG_DIR" \
  -Dosgi.sharedConfiguration.area.readOnly=true \
  -Dosgi.configuration.cascaded=true \
  -Xms1G \
  --add-modules=ALL-SYSTEM \
  --add-opens java.base/java.util=ALL-UNNAMED \
  --add-opens java.base/java.lang=ALL-UNNAMED \
  -Djdk.xml.maxGeneralEntitySizeLimit=0 \
  -Djdk.xml.totalEntitySizeLimit=0 \
  -jar "$LAUNCHER" \
  -data "$DATA_DIR" "$@"
```

- [ ] **Step 3: 单元验证**

```powershell
# Windows 主路径：smoke 指向启动器（无 -data 分支即 Mayoi 真实形态）
$env:JAVA_HOME = "D:\Development\CodeDevEnvironment\Java\jdk-25.0.5.1"   # 本会话沿用
mkdir "$env:TEMP\launcher-ws" -Force; cd "$env:TEMP\launcher-ws"
pwsh F:\VibeCodingProject\mayoi-java\scripts\lsp-smoke.ps1 -Jdtls "F:\VibeCodingProject\mayoi-java\launcher\jdtls.bat"
# 期望: SMOKE OK（launcher 的 -data 落在 %APPDATA%\mayoi-java\jdtls\<净化名>）
```

注意：launcher.bat 解析 JRE 的相对路径 `%HERE..\jre` 在**仓库内**并不存在（jre 由 bootstrap 安装到 %LOCALAPPDATA%\mayoi-java），本步会回退 JAVA_HOME=JDK 25 → 依然 SMOKE OK，这恰好同时验证了**回退链**。受管 JRE 的正向验证在 Task 2 E2E 完成。

```bash
# POSIX 侧：语法校验 + Git Bash 假服务器（同 VERIFICATION C1 模式）
bash -n launcher/jdtls && echo "syntax OK"
```

- [ ] **Step 4: Commit** `feat: python-free jdtls launchers (bat/sh) replicating jdtls.py`

---

## Task 2: Windows 引导脚本

**Files:**
- Create: `bootstrap/bootstrap.ps1`

- [ ] **Step 1: 写 `bootstrap/bootstrap.ps1`**（逐字；要点：幂等检测 → JRE → jdtls → 启动器落位 → PATH 追加 → 插件安装提示/执行 → 汇总）

```powershell
# bootstrap.ps1 — mayoi-java 一键引导（Windows）
# 用法: iwr -useb https://raw.githubusercontent.com/HelloThreeLiu/mayoi-java/main/bootstrap/bootstrap.ps1 | iex
# 可选环境变量: MAYOI_JDTLS_TGZ=<本地 tar.gz 或自定义 URL>（国内下载慢时先手动下载再指向它）
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$InstallDir = Join-Path $env:LOCALAPPDATA "mayoi-java"
$BinDir     = Join-Path $InstallDir "bin"
$JreDir     = Join-Path $InstallDir "jre"
$JdtlsDir   = Join-Path $InstallDir "jdtls"
$TmpDir     = Join-Path ([IO.Path]::GetTempPath()) "mayoi-java-bootstrap"
New-Item $BinDir, $TmpDir -ItemType Directory -Force | Out-Null
$IsWin = $true   # 本脚本仅 Windows；POSIX 用 bootstrap.sh

function Step($m) { Write-Host "== $m" -ForegroundColor Cyan }

# ---- 0. 已有 jdtls 检测（PATH 上且非本安装目录 → 仅提示插件安装）----
$existing = Get-Command jdtls -ErrorAction SilentlyContinue
if ($existing -and ($existing.Source -notlike "$InstallDir*")) {
    Write-Host "检测到现有 jdtls: $($existing.Source) —— 跳过运行时安装。" -ForegroundColor Yellow
    Write-Host "若其无法启动（需 Python+JDK25），可删除它后重跑本脚本切换到受管运行时。"
}

# ---- 1. 受管 JRE 25（TUNA 主源，Adoptium 官方回退；已存在则跳过）----
if (-not (Test-Path (Join-Path $JreDir "bin\java.exe"))) {
    Step "下载 Temurin JRE 25 (约 45MB)"
    $zip = Join-Path $TmpDir "jre25.zip"
    $urls = @(
        "https://mirrors.tuna.tsinghua.edu.cn/Adoptium/25/jre/x64/windows/OpenJDK25U-jre_x64_windows_hotspot_25.0.5_8.zip",
        "https://api.adoptium.net/v3/binary/latest/25/ga/windows/x64/jre/hotspot/normal/eclipse?project=jdk"
    )
    $ok = $false
    foreach ($u in $urls) {
        Write-Host "   源: $u"
        curl.exe --ssl-no-revoke -L -C - --retry 3 --retry-delay 2 -o "$zip" $u
        if ($LASTEXITCODE -eq 0) { $ok = $true; break }
        Write-Host "   该源失败（exit $LASTEXITCODE），尝试下一源" -ForegroundColor Yellow
    }
    if (-not $ok) { throw "JRE 下载失败。可手动下载 zip 后: [Environment]::SetEnvironmentVariable 解压到 $JreDir" }
    Step "解压 JRE"
    if (Test-Path $JreDir) { Remove-Item $JreDir -Recurse -Force }
    $ex = Join-Path $TmpDir "jre-extract"; New-Item $ex -ItemType Directory -Force | Out-Null
    Expand-Archive $zip $ex -Force
    $inner = Get-ChildItem $ex -Directory | Select-Object -First 1     # jdk-25.0.x-jre/
    Move-Item (Join-Path $ex $inner.Name) $JreDir
    Remove-Item $zip, $ex -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "JRE: $(& (Join-Path $JreDir 'bin\java.exe') -version 2>&1 | Select-Object -First 1)"
} else { Write-Host "受管 JRE 已存在，跳过" }

# ---- 2. jdtls 1.63.0（eclipse.org 直连 + 续传；支持 MAYOI_JDTLS_TGZ 本地/自定义源）----
$marker = Join-Path $JdtlsDir ".mayoi-java-installed"
if (-not (Test-Path $marker)) {
    Step "下载 jdtls 1.63.0 (约 49MB；eclipse.org 国内较慢，失败可重跑续传)"
    $tgz = if ($env:MAYOI_JDTLS_TGZ) { $env:MAYOI_JDTLS_TGZ } else { Join-Path $TmpDir "jdtls.tar.gz" }
    if ($env:MAYOI_JDTLS_TGZ -and (Test-Path $env:MAYOI_JDTLS_TGZ)) {
        $tgz = $env:MAYOI_JDTLS_TGZ; Write-Host "   使用本地/自定义源: $tgz"
    } else {
        $u = "https://download.eclipse.org/jdtls/milestones/1.63.0/jdt-language-server-1.63.0-202610191322.tar.gz"
        Write-Host "   源: $u （慢属正常；也可手动下载后设 MAYOI_JDTLS_TGZ 指向它）"
        curl.exe --ssl-no-revoke -L -C - --retry 3 --retry-delay 2 -o "$tgz" $u
        if ($LASTEXITCODE -ne 0) { throw "jdtls 下载失败（已保留部分文件，重跑本脚本可续传）" }
    }
    Step "解压 jdtls"
    if (Test-Path $JdtlsDir) { Remove-Item $JdtlsDir -Recurse -Force }
    New-Item $JdtlsDir -ItemType Directory -Force | Out-Null
    tar -xzf "$tgz" -C "$JdtlsDir"
    if ($LASTEXITCODE -ne 0) { throw "解压失败（tar.gz 可能不完整：删除 $tgz 后重跑）" }
    Set-Content $marker "1.63.0" -Encoding ascii
    if (-not $env:MAYOI_JDTLS_TGZ) { Remove-Item $tgz -Force -ErrorAction SilentlyContinue }
    Write-Host "jdtls: $marker 已写 1.63.0"
} else { Write-Host "受管 jdtls 已存在（$((Get-Content $marker))），跳过" }

# ---- 3. 启动器落位（内嵌，来自仓库 launcher/jdtls.bat 同源内容）----
Step "安装启动器"
# 启动器内容与仓库 launcher/jdtls.bat 逐字一致（任务文本 Task 1 Step 1），
# 此处以内嵌 here-string 落盘，保证单文件引导即可完成。
$launcher = @'
<与 launcher/jdtls.bat 逐字相同的内容——实施者从仓库文件读取并内嵌>
'@
# 实施注记：为避免双源漂移，用 Get-Content 不可行（iex 场景无仓库文件）。
# 实施方式：发布前由 CI/人工把 launcher/jdtls.bat 的最新内容粘入上面的 here-string；
# 本脚本入库后内容即冻结，修改启动器须同步修改此处（PLAN 附注）。
Set-Content (Join-Path $BinDir "jdtls.bat") $launcher -Encoding ascii

# ---- 4. PATH 追加（仅追加，绝不覆盖）----
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if (($userPath -split ";") -notcontains $BinDir) {
    Step "追加 $BinDir 到用户 PATH"
    [Environment]::SetEnvironmentVariable("Path", (($userPath.TrimEnd(";") + ";" + $BinDir).Trim(";")), "User")
    Write-Host "已写入用户 PATH（新开的终端/应用生效；已运行的 Mayoi 需重启）"
} else { Write-Host "用户 PATH 已含 $BinDir" }

# ---- 5. 插件安装（检测 mayoi CLI；无则打印手动指引）----
$mayoiExe = "D:\Development\ProgrammingTools\Mayoi\Mayoi.exe"   # ← 发布版需改为探测逻辑，见任务注记
# 探测顺序: (1) %LOCALAPPDATA%\Mayoi\bin\mayoi.cmd (2) Get-Command mayoi (3) 常见安装目录 Mayoi.exe
$mayoiCmd = Get-Command mayoi -ErrorAction SilentlyContinue
if ($mayoiCmd) {
    Step "安装/更新 mayoi-java 插件"
    $env:MAYOI_CLI = "1"
    Start-Process -FilePath $mayoiCmd.Source -ArgumentList "plugin","install","HelloThreeLiu/mayoi-java" -NoNewWindow -Wait -RedirectStandardOutput "$TmpDir\pi.txt" -RedirectStandardError "$TmpDir\pi-err.txt"
    Get-Content "$TmpDir\pi.txt", "$TmpDir\pi-err.txt"
} else {
    Write-Host "未检测到 mayoi CLI。请安装插件:" -ForegroundColor Yellow
    Write-Host "  mayoi plugin install HelloThreeLiu/mayoi-java"
}

Write-Host ""
Write-Host "完成。重启 Mayoi 后打开任意 .java 文件即可使用。" -ForegroundColor Green
```

- [ ] **Step 2: 实施注记的两处补全**（子代理执行时）：
  1. `Step 3` 的 here-string `<与 launcher/jdtls.bat 逐字相同的内容>`：用 `Get-Content launcher\jdtls.bat -Raw` 的实际内容粘贴（保持逐字），删除占位行与"实施注记"段
  2. `$mayoiExe` 硬编码行**删除**，改为注释中的三级探测（shim cmd → Get-Command → 常见路径 `%LOCALAPPDATA%\Programs\Mayoi\Mayoi.exe` / `D:\...\Mayoi.exe` 不可靠所以仅前两级），探测不到就走"未检测到"分支

- [ ] **Step 3: E2E 验证（本机，完整"下载即用"证明）**

```powershell
# 1) 临时移除 settings 的 java.path（回到"无手工配置"状态）
#    用 PowerShell JSON 编辑 %APPDATA%\Mayoi\settings.json 删除 plugins.java 键，JSON 校验 OK
# 2) 运行引导（经 iex 一条命令全链验证）:
iwr -useb https://raw.githubusercontent.com/HelloThreeLiu/mayoi-java/main/bootstrap/bootstrap.ps1 | iex
#    期望: JRE 下载解压 → jdtls 下载解压 → 启动器落位 → PATH 追加 → 插件安装
#    （若 jdtls 下载过慢，设置 $env:MAYOI_JDTLS_TGZ 指向此前用户手动下载的
#     E:\FluxDownload\jdt-language-server-1.63.0-202610191322.tar.gz 走本地源通道完成 E2E）
# 3) 重启 Mayoi（新 PATH 生效）→ 重开 test-fixtures 的 App.java → F2 补全
# 期望: 全功能正常（此时 java.server 由受管 JRE + 免 Python 启动器拉起）
# 4) 数据目录核验: %APPDATA%\mayoi-java\jdtls\<净化名> 存在
```

- [ ] **Step 4: Commit** `feat: windows bootstrap (managed jre + jdtls + path-integrated launcher)`

---

## Task 3: POSIX 引导脚本

**Files:**
- Create: `bootstrap/bootstrap.sh`

- [ ] **Step 1: 写 `bootstrap/bootstrap.sh`**（结构与 ps1 同构：幂等检测 → TUNA/官方 JRE（按 `uname -m` 选 aarch64/x64、按 `uname -s` 选 mac/linux）→ jdtls → 启动器落位到 `$HOME/.local/share/mayoi-java/bin/jdtls` 并复制到 `~/.local/bin/jdtls`（`$PATH` 含 `~/.local/bin` 则免复制，直接提示）→ mayoi CLI 检测安装插件）
  - curl 统一 `--ssl-no-revoke -L -C - --retry 3`（macOS 老 curl 不识别 --ssl-no-revoke → 参数置入变量按平台取舍）
  - `set -eu`；每步 `echo "== ..."`；TUNA jre 路径按平台映射（`Adoptium/25/jre/aarch64/mac/`、`/x64/linux/`），文件名从目录页抓取或用 latest API 回退
  - 启动器 here-string 内嵌（同 Task 2 注记，与仓库 `launcher/jdtls` 逐字同步）
  - PATH：`~/.local/bin` 不在 PATH 时追加到 `~/.zshrc`/`~/.bashrc`（检测存在哪个 rc 追加哪个）并提示 `source`
- [ ] **Step 2: 验证**：`sh -n bootstrap.sh`（语法）+ `bash -n`；Git Bash 假服务器全链同 C1 模式（本机无 POSIX java，端到端留待——与 C1 同等声明）
- [ ] **Step 3: Commit** `feat: posix bootstrap script`

---

## Task 4: 插件版本与文档

**Files:**
- Modify: `plugin.json`（version → `0.2.0`）
- Modify: `README.md`

- [ ] **Step 1**: plugin.json `version: "0.2.0"`（清单功能不变，仅版本号）
- [ ] **Step 2**: README 改写：
  - 顶部"安装"节改为**一条命令**（Windows/POSIX 两行，从 §1.1 复制），注明"自动安装受管 JRE 25 + jdtls，无需 Python，不影响已有 JDK"
  - 前置要求表收缩为：Mayoi ≥0.19.0 + 网络下载约 95MB（其余全部可选）；已手工安装 jdtls/JDK 的用户可跳过引导（说明检测逻辑）
  - 保留"手动安装"节作为进阶路径（现 README 内容改标题保留）
  - 已知限制节补：受管运行时装在 `%LOCALAPPDATA%\mayoi-java`（约 350MB 磁盘）
- [ ] **Step 3**: JSON 校验 + 三方口径核对（README ↔ plugin.json ↔ PLAN-v0.2）
- [ ] **Step 4: Commit** `feat: v0.2.0 one-command bootstrap docs`

---

## Task 5: 合并、tag、升级测试

- [ ] **Step 1**: `git checkout main && git merge feat/plugin-v1 && git push origin main && git tag v0.2.0 && git push origin v0.2.0`
- [ ] **Step 2**: 升级测试：当前本机已装 0.1.0（真实安装）→ `mayoi plugin install HelloThreeLiu/mayoi-java` 应更新到 0.2.0（`plugin list` 确认）→ 重开 .java 回归 A1/A2/A5
- [ ] **Step 3**: index.json PR（**须用户确认后执行**）——条目不变（`name/displayName/description/repository/languages/detect/install`）

## 验收标准（v0.2 Definition of Done）

1. 干净状态（无手工 settings.path）下，Windows 一条命令后重开 .java：A1/A2/A4/A5 全过
2. 数据目录落 `%APPDATA%\mayoi-java\jdtls\`；无 Python 依赖参与启动链
3. 已有可用环境的用户重跑引导：幂等跳过，无破坏
4. POSIX 脚本语法通过 + 假服务器帧逻辑验证（真机端到端留待，与 C1 同口径声明）

## 风险

| 风险 | 缓解 | 后续 |
|---|---|---|
| jdtls 官方源国内极慢 | 续传 + MAYOI_JDTLS_TGZ 本地通道 + README 提供手动下载指引 |
| TUNA jre 文件名带版本号（升级后失效） | 主源 404 自动回退 Adoptium API latest |
| PATH 追加对用户机器的侵入 | 仅追加不覆盖；README 明示；卸载=删目录+删 PATH 条目 |
| 启动器与 bootstrap 内嵌副本漂移 | PLAN 附注：改启动器必须同步两处；Task 1 Step 1 与 Task 2 Step 3 有逐字一致性检查步骤；内嵌副本内容必须保持纯 ASCII（Set-Content -Encoding ascii 会把非 ASCII 静默变 ?） |
| POSIX 端到端未验 | 与 C1 同口径声明；Git Bash 假服务器覆盖帧逻辑 |
| bootstrap 无版本化升级路径（marker/存在性幂等） | jdtls 1.63.0 → 1.64.0 升级需手动删 %LOCALAPPDATA%\mayoi-java\jdtls 后重跑；JRE 侧以 java.exe 存在性为幂等键、无版本标记，Temurin bump 后同理删 %LOCALAPPDATA%\mayoi-java\jre（POSIX：~/.local/share/mayoi-java/ 对应目录） | v0.2.1 或 v0.3：版本化幂等 + 解压后交换（bootstrap.sh 将按此设计） |
