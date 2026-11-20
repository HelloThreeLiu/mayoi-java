# mayoi-java 实施计划（Implementation Plan）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 Mayoi 编辑器发布一个基于 Eclipse JDT.LS (jdtls) 的 Java 语言服务器插件（v1 优先做成纯清单、零 JS 代码的插件）。

**Architecture:** 插件是独立 Git 仓库（仓库根即插件目录），核心交付物是 `plugin.json`。v1 走"路径 A"：直接命令模式 `command: "${settings.path}"`，依赖官方 `bin/jdtls` 启动脚本自动处理 JDK、平台 configuration 与按项目 `-data` 目录；若真机验证不过（重点怀疑：Python 依赖、Windows `.bat`），走"路径 B"：自研 resolver（无第三方依赖的 Java helper jar）组装启动命令，去除 Python 依赖。

**Tech Stack:** Mayoi 插件清单（JSON）、Eclipse JDT.LS（运行需 JDK 21+）、官方 jdtls 启动脚本（Python 3.9+，仅路径 A）、路径 B 的 helper 为纯 JDK 源码编译的 jar、开发期冒烟脚本（PowerShell + Bash）。

---

## 0. 背景与已核实事实

规则来源：仓库根 `PLUGIN-RULES.md`（第 1–3 章为官方硬性规则）。计划编写时已额外核实的事实
（2026-11-20，来自 eclipse-jdtls/eclipse.jdt.ls 主分支源码），**修订了规则文档中的两处假设**：

| # | 事实 | 对计划的影响 |
|---|---|---|
| F1 | 官方发行包的启动器是 **Python 脚本**：`bin/jdtls`（shebang `#!/usr/bin/env python3`，加载 `bin/jdtls.py`）、`bin/jdtls.bat`（内容为 `python "%~dp0/jdtls" %*`） | 路径 A 隐含 **Python 3.9+ 依赖**，必须写进前置要求与安装提示 |
| F2 | `jdtls.bat` 末尾有 **`pause`**，且依赖 PATH 上的 `python`（非 `python3`） | Windows 下服务器进程退出可能挂起在 `pause`；Task 1/3 必须实测 |
| F3 | `jdtls.py` 强制校验 **JDK ≥ 21**（低于 21 直接抛错；Java ≥ 24 时追加 `-Djdk.xml.maxGeneralEntitySizeLimit=0` 等两个参数） | 规则文档中"≥ 17（待验证）"修正为 **21**；前置要求按 21 写 |
| F4 | `jdtls.py` 的 `-data` 默认目录 = `<平台缓存>/jdtls/jdtls-<sha1(cwd 的目录名)>`（Windows `%APPDATA%\jdtls`，macOS `~/Library/Caches/jdtls`，Linux `~/.cache/jdtls`；hash 只取**目录名**） | 同名目录的不同项目会共用数据目录（索引串扰风险）；路径 B 的 resolver 改用完整路径哈希 |
| F5 | Mayoi 仓库（sorrycc/Mayoi）外部不可访问（zread 报 repo not found） | 凡宿主行为一律列为"待验证"，以 Task 1/3 真机实测为准；规则文档为唯一权威 |

## 1. 硬性约束（实现时不得违反，摘自 PLUGIN-RULES.md）

- 插件名 `java`（小写字母/数字/连字符）；所有 ID 以 `java.` 开头；语言服务器 id 固定为
  **`java.server`**，跨版本不得变更。
- 插件 JS 跑在 moejs（非 Node）：无 `require`/`node:`/npm 运行时；**v1 设计为零 JS**，
  完全规避该约束。resolver 是宿主直接启动的外部进程，不占插件 JS 预算，但
  **resolve + initialize 共享 30 秒时限**，且必须快速、离线。
- 纯语言服务器插件可以没有 `activation`、没有 `main`（官方 gopls/basedpyright 即清单式）。
- 用户覆盖：settings.json 的 `languageServers` 下按 id `java.server` 覆盖。
- Maven/Gradle 导入行为 v1 不承诺（取决于 jdtls 自身，列为待验证）。

## 2. 文件结构（最终形态）

```
mayoi-java/                     # 仓库根 = 插件目录（mayoi plugin install owner/repo 要求）
├── plugin.json                 # 插件清单（核心交付物）
├── README.md                   # 用户文档（已有，随 Task 2/4 更新）
├── LICENSE                     # MIT
├── .gitignore                  # 已有
├── PLUGIN-RULES.md             # 官方规则整理（已有，不改动）
├── docs/
│   ├── PLAN.md                 # 本计划
│   └── VERIFICATION.md         # 验收记录（Task 1/3 产出）
├── scripts/                    # 开发期冒烟脚本（随仓库走，非插件运行时依赖）
│   ├── lsp-smoke.ps1           # Windows 冒烟
│   └── lsp-smoke.sh            # macOS/Linux 冒烟
├── test-fixtures/              # 验收用最小 Maven 工程（Task 3）
│   ├── pom.xml
│   └── src/main/java/demo/App.java
└── helper/                     # 仅路径 B（Task 4，条件执行）
    ├── src/Resolve.java        # resolver 源码（纯 JDK，无第三方依赖）
    ├── mayoi-java-resolver.jar # 编译产物（入库分发）
    └── out/                    # 编译中间产物（gitignore）
```

> 本插件**永远不需要** `main.ts` / `mayoi.d.ts`：v1 是纯清单插件；路径 B 的 helper 也是
> 外部进程（宿主经 resolver 协议启动），不涉及插件 JS。除非将来要加命令/视图类功能。

## 3. 里程碑总览

| 里程碑 | 任务 | 产出 | 状态 |
|---|---|---|---|
| M0 仓库与计划 | — | git 仓库、PLUGIN-RULES、PLAN | ✅ 本次提交完成 |
| M1 环境与路径 A 验证 | Task 1 | 冒烟脚本、验证结论、决策门判定 | 待执行 |
| M2 v1 插件（路径 A） | Task 2 | plugin.json、README、LICENSE | 待执行（Task 1 通过才做） |
| M3 真机验收 | Task 3 | VERIFICATION.md、验收矩阵结论 | 待执行 |
| M4 路径 B resolver | Task 4 | helper jar、resolve 模式清单 | **条件执行**（见决策门） |
| M5 发布 | Task 5 | GitHub、index.json PR | 待执行 |

---

### Task 1: 环境准备与路径 A 冒烟验证（决策门）

**Files:**
- Create: `scripts/lsp-smoke.ps1`
- Create: `scripts/lsp-smoke.sh`
- Create: `docs/VERIFICATION.md`

目的：在动手写插件前，用最小成本验证规则文档 4.2 节路径 A 的四项检查清单
（stdio 启动 / 自动 data 目录 / 平台行为 / JDK 缺失报错），并结合 F1–F4 事实。

- [ ] **Step 1: 安装并核对前置依赖**

```sh
# JDK >= 21（硬性，jdtls.py 强制校验）
java -version          # 期望输出含 version "21" 或更高

# Python >= 3.9（路径 A 的官方启动脚本依赖；Windows 上是 python 不是 python3）
python3 --version      # Windows: python --version

# jdtls
#   macOS:   brew install jdtls
#   Windows/Linux: 从 https://download.eclipse.org/jdtls/milestones/ 下载最新
#   jdt-language-server-*.tar.gz 解压，把解压目录下的 bin 加入 PATH
jdtls --help 2>&1 | head -5   # 能打印用法/不报"command not found"即可
```

Windows 附加确认（对应 F2）：执行 `where jdtls`，确认 PATH 上找到的是 `jdtls.bat`；
打开该 `.bat` 确认内容为 `python "%~dp0/jdtls" %*` + `pause` 两行。

- [ ] **Step 2: 写 Windows 冒烟脚本 `scripts/lsp-smoke.ps1`**

```powershell
# scripts/lsp-smoke.ps1 — jdtls stdio 冒烟测试：发送 initialize，等待含 capabilities 的响应
# 用法（在任意空目录下执行）: pwsh scripts/lsp-smoke.ps1 [-Jdtls <名字或路径>] [-DataDir <目录>]
# 注意：读响应为阻塞式；长时间无输出即判定失败（Ctrl+C 结束）。
param(
    [string]$Jdtls = "jdtls",
    [string]$DataDir = (Join-Path $env:TEMP "jdtls-smoke")
)
$ErrorActionPreference = "Stop"

$init = @{
    jsonrpc = "2.0"; id = 1; method = "initialize"
    params  = @{ processId = $PID
                 rootUri   = ([System.Uri]((Get-Location).Path + "/")).AbsoluteUri
                 capabilities = @{} }
} | ConvertTo-Json -Depth 10 -Compress

$bytes = [Text.Encoding]::UTF8.GetByteCount($init)
$frame = "Content-Length: $bytes`r`n`r`n$init"

$psi = [System.Diagnostics.ProcessStartInfo]::new()
$psi.RedirectStandardInput  = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError  = $true
$psi.UseShellExecute = $false
# Windows 下 .bat 必须经 cmd 启动（这同时验证了宿主用 cmd 语义拉起 jdtls.bat 的可行性）
if ($env:OS -eq "Windows_NT") {
    $psi.FileName = "cmd.exe"
    $psi.Arguments = "/c `"$Jdtls`" -data `"$DataDir`""
} else {
    $psi.FileName = $Jdtls
    $psi.Arguments = "-data `"$DataDir`""
}
Write-Host ">> starting: $($psi.FileName) $($psi.Arguments)"
$p = [System.Diagnostics.Process]::Start($psi)
$p.StandardInput.Write($frame)
$p.StandardInput.Flush()

$headers = @{}
while ($true) {
    $line = $p.StandardOutput.ReadLine()
    if ($null -eq $line) { throw "stdout closed before response; stderr: $($p.StandardError.ReadToEnd())" }
    if ($line -eq "") { break }
    $idx = $line.IndexOf(":")
    if ($idx -gt 0) { $headers[$line.Substring(0, $idx).Trim()] = $line.Substring($idx + 1).Trim() }
}
$len = [int]$headers["Content-Length"]
$buf = New-Object char[] $len
$read = 0
while ($read -lt $len) {
    $n = $p.StandardOutput.Read($buf, $read, $len - $read)
    if ($n -le 0) { throw "stdout EOF at $read/$len" }
    $read += $n
}
$response = -join $buf

if ($env:OS -eq "Windows_NT") { taskkill /PID $p.Id /T /F 2>$null } else { try { $p.Kill() } catch {} }
Write-Host ">> response (first 500 chars):"
Write-Host $response.Substring(0, [Math]::Min(500, $response.Length))
if ($response -match '"capabilities"') { Write-Host "SMOKE OK" -ForegroundColor Green; exit 0 }
else { throw "SMOKE FAIL: no capabilities in response" }
```

- [ ] **Step 3: 写 macOS/Linux 冒烟脚本 `scripts/lsp-smoke.sh`**

```bash
#!/usr/bin/env bash
# scripts/lsp-smoke.sh — jdtls stdio 冒烟测试：发送 initialize，等待含 capabilities 的响应
# 用法（在任意空目录下执行）: bash scripts/lsp-smoke.sh [jdtls 路径或名字] [data 目录]
set -euo pipefail

JDTLS="${1:-jdtls}"
DATA_DIR="${2:-${TMPDIR:-/tmp}/jdtls-smoke}"

init=$(printf '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":%d,"rootUri":"file://%s","capabilities":{}}}' "$$" "$PWD")
frame=$(printf 'Content-Length: %d\r\n\r\n%s' "${#init}" "$init")

coproc JDTLS { "$JDTLS" -data "$DATA_DIR"; }
printf '%s' "$frame" >&"${JDTLS[1]}"

length=""
while IFS= read -r line <&"${JDTLS[0]}"; do
  [ -z "$line" ] && break
  case "$line" in Content-Length:*) length="${line#Content-Length: }" ;; esac
done
[ -n "$length" ] || { echo "SMOKE FAIL: no Content-Length header" >&2; exec {JDTLS[1]}>&-; kill "$JDTLS_PID" 2>/dev/null || true; exit 1; }

body=""
IFS= read -r -N "$length" body <&"${JDTLS[0]}" || true
exec {JDTLS[1]}>&-
kill "$JDTLS_PID" 2>/dev/null || true

echo ">> response (first 500 chars):"
printf '%s\n' "${body:0:500}"
if [[ "$body" == *'"capabilities"'* ]]; then echo "SMOKE OK"; else echo "SMOKE FAIL: no capabilities" >&2; exit 1; fi
```

- [ ] **Step 4: 在空目录跑冒烟测试（stdio 启动验证）**

```powershell
# Windows
mkdir "$env:TEMP\jdtls-smoke-ws" -Force; cd "$env:TEMP\jdtls-smoke-ws"
pwsh F:\VibeCodingProject\mayoi-java\scripts\lsp-smoke.ps1
# 期望: 打印响应前 500 字符（含 "capabilities"）+ 绿色 SMOKE OK
# 若 jdtls 不在 PATH: pwsh ...\lsp-smoke.ps1 -Jdtls "C:\path\to\jdtls\bin\jdtls.bat"
```

```bash
# macOS / Linux
mkdir -p /tmp/jdtls-smoke-ws && cd /tmp/jdtls-smoke-ws
bash /path/to/mayoi-java/scripts/lsp-smoke.sh
# 期望: 同上 SMOKE OK
```

对应规则 4.2 检查项 1（stdio 模式启动）。若响应慢属正常：首次启动 Equinox 初始化需数秒到数十秒。

- [ ] **Step 5: 验证自动 `-data` workspace 目录（对应规则 4.2 检查项 2 + 事实 F4）**

冒烟通过后检查平台缓存目录是否生成了数据目录：

```powershell
# Windows: 期望出现 %APPDATA%\jdtls\jdtls-<sha1("jdtls-smoke-ws")>
Get-ChildItem "$env:APPDATA\jdtls" -ErrorAction SilentlyContinue
```

```bash
# macOS: ls ~/Library/Caches/jdtls   Linux: ls ~/.cache/jdtls
ls "${XDG_CACHE_HOME:-$HOME/.cache}/jdtls" 2>/dev/null || ls ~/Library/Caches/jdtls
```

再验证"复用"：在**同一目录**再跑一次冒烟，确认没有新增第二个 `jdtls-<hash>` 目录。

- [ ] **Step 6: JDK 缺失报错路径检查（对应规则 4.2 检查项 4）**

```bash
# 临时把 java 从环境中摘掉（示例为 POSIX；Windows 用一个空 PATH 的 cmd 验证）
env PATH="/usr/bin:/bin" jdtls -data /tmp/jdtls-smoke </dev/null
# 期望: 快速失败并给出可读错误（找不到 java / validate-java-version 报错），
# 而不是挂死或输出难以理解的堆栈。把实际输出记入 VERIFICATION.md。
```

- [ ] **Step 7: 记录验证结论并过决策门**

创建 `docs/VERIFICATION.md`（后续 Task 3 继续往里追加）：

```markdown
# 验证记录

## 路径 A 冒烟验证（Task 1）— <日期> / <机器 OS> / <jdtls 版本> / <JDK 版本> / <Python 版本>

| 检查项 | 结果 | 备注 |
|---|---|---|
| stdio 启动（Step 4） | ✅/❌ | |
| 自动 -data 目录（Step 5） | ✅/❌ | hash 值: |
| JDK 缺失报错（Step 6） | ✅/❌ | 实际输出: |
| Windows .bat 经 cmd 可启动 | ✅/❌/未测 | |

## 决策门结论

- [ ] 路径 A 全部通过 → 执行 Task 2
- [ ] 存在失败项 → 跳过 Task 2 的 command 模式，先执行 Task 4（路径 B）
```

- [ ] **Step 8: Commit**

```bash
git add scripts/ docs/VERIFICATION.md
git commit -m "chore: add jdtls stdio smoke scripts and path-A verification record"
```

---

### Task 2: v1 插件清单（路径 A，纯 manifest，零 JS）

**前置**：Task 1 决策门通过（路径 A）。
**Files:**
- Create: `plugin.json`
- Create: `LICENSE`
- Modify: `README.md`（把安装命令里的占位仓库地址改成实际地址；确认前置要求表与 Task 1 实测一致）

- [ ] **Step 1: 写 `plugin.json`**

```json
{
  "name": "java",
  "displayName": "Java",
  "version": "0.1.0",
  "description": "Go to Definition, hovers, completions and problems in Java files, with jdtls",
  "author": "<填写作者/团队名>",
  "mayoi": ">=0.19.0",
  "enabled": true,
  "contributes": {
    "settings": {
      "path": {
        "type": "string",
        "default": "jdtls",
        "description": "The jdtls program, by name or path (on Windows a full path to bin\\jdtls.bat may be required)"
      }
    },
    "languageServers": [
      {
        "id": "java.server",
        "languages": ["java"],
        "command": "${settings.path}",
        "install": "brew install jdtls"
      }
    ]
  }
}
```

说明：
- 不写 `activation`、不写 `main`——宿主按 `languages: ["java"]` 在 `.java` 文档打开时拉起服务器
  （规则 2.5；`java` 语言名来自 Chroma 内置 lexer，无需贡献 `languages` 块，待验证项 V5 见 §5）。
- `id` 固定 `java.server`，此后所有版本不得改动（规则 2.2 / 6.6）。
- `install` 是程序缺失时展示给用户的提示命令（官方示例为单条字符串；Windows/Linux 的
  安装方式写在 README，不塞进清单）。
- `mayoi: ">=0.19.0"` 取自规则文档示例，真机核对后如有出入再修正（待验证项 V1）。

- [ ] **Step 2: 写 `LICENSE`（MIT），版权行填 `Copyright (c) 2026 <作者名>`**

- [ ] **Step 3: JSON 语法校验**

```powershell
pwsh -NoProfile -Command "Get-Content plugin.json -Raw | ConvertFrom-Json | Out-Null; 'JSON OK'"
# 期望输出: JSON OK
```

- [ ] **Step 4: 链接进 Mayoi 热加载开发**

```powershell
mayoi plugin dev F:\VibeCodingProject\mayoi-java
```

然后在 Mayoi 中打开一个 `.java` 文件 → **Plugins → Show Language Servers**：
期望看到 `java.server`，状态为运行中，运行位置为本机。

- [ ] **Step 5: Commit**

```bash
git add plugin.json LICENSE README.md
git commit -m "feat: manifest-only v1 plugin wiring jdtls via command mode"
```

---

### Task 3: Mayoi 真机验收（能力矩阵 + 宿主行为待验证项）

**前置**：Task 2 完成。
**Files:**
- Create: `test-fixtures/pom.xml`
- Create: `test-fixtures/src/main/java/demo/App.java`
- Modify: `docs/VERIFICATION.md`（追加验收矩阵）

- [ ] **Step 1: 建最小 Maven 测试工程**

`test-fixtures/pom.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>demo</groupId>
  <artifactId>simple-maven</artifactId>
  <version>0.0.1</version>
  <properties>
    <maven.compiler.release>17</maven.compiler.release>
  </properties>
</project>
```

`test-fixtures/src/main/java/demo/App.java`:

```java
package demo;

public class App {
    public static void main(String[] args) {
        String message = greet("Mayoi");
        System.out.println(message);
    }

    static String greet(String name) {
        return "Hello, " + name + "!";
    }
}
```

- [ ] **Step 2: 逐项验收（在 Mayoi 中打开 `test-fixtures/` 目录）**

| # | 验收项 | 操作 | 期望 |
|---|---|---|---|
| A1 | 服务器拉起 | 打开 App.java | Show Language Servers 里 `java.server` 运行中 |
| A2 | 诊断 | 把某行改成 `String x = 1;` | Problems 出现类型错误；状态栏计数更新 |
| A3 | hover | 悬停 `greet` | 显示 `String greet(String)` 签名 |
| A4 | 定义跳转 | `greet("Mayoi")` 上 F12 / ⌘-click | 跳到下方定义 |
| A5 | 补全 | `App.` 后 ⌃Space | 出现 `main` 等成员 |
| A6 | 格式化 | 触发宿主格式化 | 文档被 jdtls 格式化（前提：没有其他插件注册 java formatter） |
| A7 | Maven 导入 | 直接打开 `test-fixtures/` | 无报错；依赖解析行为记录（离线首次打开可慢，v1 不承诺，如实记录） |
| A8 | 缺服务器报错 | 把 `plugins.java.path` 改成不存在的值，重开 .java 文件 | 出现明确原因（程序未安装/进程退出/无响应）+ `install` 提示 + **Restart** 按钮；改回后 Restart 可恢复 |
| A9 | 用户覆盖 | settings.json `languageServers["java.server"]` 覆盖配置（如重指 `command` 到另一 jdtls 路径） | 覆盖生效（同时回答待验证 V4：覆盖是否支持 command 字段） |
| A10 | 崩溃恢复 | 杀掉 jdtls 进程 | 宿主重开文档时自动重试；记录 Show Plugin Log 输出 |
| A11 | 日志可读 | Show Plugin Log 过滤 java | 无刷屏错误 |
| A12 | Windows `.bat` 语义 | 仅 Windows：观察 A1 是否成功（宿主能否按名解析 `.bat`；F2 的 `pause` 是否影响退出） | 成功即记录；失败则进入 Task 4 决策 |
| A13 | SSH 远端（可选，有条件才测） | 在 SSH 远端文件夹打开 .java | 服务器起在远端，功能正常 |

- [ ] **Step 3: 把矩阵结果（含每项的实测环境/版本）写入 `docs/VERIFICATION.md`**

- [ ] **Step 4: Commit**

```bash
git add test-fixtures/ docs/VERIFICATION.md
git commit -m "test: add minimal maven fixture and record acceptance matrix"
```

---

### Task 4:（条件）路径 B — resolver helper，去除 Python 依赖

**何时执行本任务**（满足其一，以 Task 1/3 的实测为准）：
- Windows 上 `jdtls.bat`（`pause` / `python` 依赖 / cmd 语义）导致不可用或退出异常；
- 决定把 Python 3.9 从用户前置要求中去掉（作为 0.2.0 的增强目标也可独立执行）。

**设计**：resolver 复刻 `jdtls.py` 的全部启动逻辑（F1–F4），用**纯 JDK** 实现并编译为
无依赖 jar（jdtls 本身要求 JDK ≥ 21，`java` 必然存在；与官方脚本"PATH 上找 java"的限制一致）。
协议严格按规则 3.2：stdin 收 `{root, settings}`（settings 只含用户显式保存过的键，
**必须自行兜底默认值**），stdout 打印**单个 JSON 对象**，退出码 0。
数据目录改用 **完整 root 路径的 SHA-1**（修复 F4 的同名目录冲突），缓存根改为
`<平台缓存>/mayoi-java/` 以免污染其他 jdtls 使用者的目录。

**Files:**
- Create: `helper/src/Resolve.java`
- Create: `helper/mayoi-java-resolver.jar`（编译产物，入库分发）
- Modify: `plugin.json`（command 模式 → resolve 模式；新增 `javaHome`、`helperPath` 设置）
- Modify: `README.md`（去掉 Python 前置，说明 javaHome/helperPath）

- [ ] **Step 1: 写 `helper/src/Resolve.java`（完整实现）**

```java
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Stream;

/**
 * mayoi-java resolver（路径 B）。
 *
 * 协议（Mayoi 官方，PLUGIN-RULES.md 3.2）：
 *   stdin  : {"root": "<workspace 绝对路径>", "settings": {...用户已保存设置...}}
 *   stdout : 单个 JSON 对象 {"command":..., "args":[...], "env":{...}}（可选键见协议）
 *   退出码 : 0 成功；非 0 失败（stderr 给出原因）
 *
 * 用法: java -jar mayoi-java-resolver.jar resolve
 * 约束: 快速且离线——resolve 与 initialize 共享 30 秒时限；严禁在此安装依赖。
 */
public final class Resolve {

    static final class Fail extends RuntimeException {
        Fail(String m) { super(m); }
    }

    public static void main(String[] args) {
        try {
            if (args.length != 1 || !"resolve".equals(args[0])) {
                throw new Fail("usage: java -jar mayoi-java-resolver.jar resolve");
            }
            String input = readAllStdin();
            Map<String, Object> req = asMap(new JsonParser(input).parse());
            String root = asString(req.get("root"));
            if (root == null || root.isEmpty()) throw new Fail("resolver: missing \"root\"");
            Map<String, Object> settings =
                    req.get("settings") instanceof Map ? asMap(req.get("settings")) : new LinkedHashMap<>();

            // settings 兜底默认值（resolver 收到的 settings 不含清单默认值，协议要求自行兜底）
            String pathSetting = str(settings.get("path"), "jdtls");
            String javaHomeSetting = str(settings.get("javaHome"), null);

            Path base = locateBase(pathSetting);
            String javaExec = locateJava(javaHomeSetting);
            int major = javaMajor(javaExec);
            if (major < 21) {
                throw new Fail("resolver: jdtls requires Java >= 21, found " + major + " (" + javaExec + ")");
            }

            String launcher = findLauncher(base);
            String sharedConfig = sharedConfigPath(base);
            String dataDir = dataDirFor(root);

            List<String> jvm = new ArrayList<>(List.of(
                    "-Declipse.application=org.eclipse.jdt.ls.core.id1",
                    "-Dosgi.bundles.defaultStartLevel=4",
                    "-Declipse.product=org.eclipse.jdt.ls.core.product",
                    "-Dosgi.checkConfiguration=true",
                    "-Dosgi.sharedConfiguration.area=" + sharedConfig,
                    "-Dosgi.sharedConfiguration.area.readOnly=true",
                    "-Dosgi.configuration.cascaded=true",
                    "-Xms1G",
                    "--add-modules=ALL-SYSTEM",
                    "--add-opens", "java.base/java.util=ALL-UNNAMED",
                    "--add-opens", "java.base/java.lang=ALL-UNNAMED"));
            if (major >= 24) {
                jvm.add("-Djdk.xml.maxGeneralEntitySizeLimit=0");
                jvm.add("-Djdk.xml.totalEntitySizeLimit=0");
            }

            StringBuilder json = new StringBuilder("{");
            json.append("\"command\":").append(q(javaExec)).append(",\"args\":[");
            for (String a : jvm) json.append(q(a)).append(",");
            json.append(q("-jar")).append(",").append(q(launcher))
                .append(",").append(q("-data")).append(",").append(q(dataDir))
                .append("]");
            if (javaHomeSetting != null) {
                json.append(",\"env\":{\"JAVA_HOME\":").append(q(javaHomeSetting)).append("}");
            }
            json.append("}");
            System.out.println(json);
        } catch (Fail f) {
            System.err.println(f.getMessage());
            System.exit(1);
        } catch (Exception e) {
            System.err.println("resolver: " + e);
            System.exit(1);
        }
    }

    // ---- jdtls 定位：settings.path 按名字或路径（名字 => 逐 PATH 目录找 name / name.bat）----
    static Path locateBase(String pathOrName) throws IOException {
        Path script = findOnPath(pathOrName);
        if (script == null) script = Paths.get(pathOrName).toAbsolutePath();
        Path dir = script.getParent();
        if (dir != null && dir.getFileName() != null && "bin".equalsIgnoreCase(dir.getFileName().toString())) {
            return dir.getParent();
        }
        if (Files.isDirectory(script) && Files.isDirectory(script.resolve("plugins"))) return script;
        if (dir != null && Files.isDirectory(dir) && Files.isDirectory(dir.resolve("plugins"))) return dir;
        throw new Fail("resolver: cannot locate jdtls installation from path=" + pathOrName);
    }

    static Path findOnPath(String name) {
        String path = System.getenv("PATH");
        if (path == null) return null;
        for (String dir : path.split(Pattern.quote(File.pathSeparator))) {
            if (dir.isEmpty()) continue;
            for (String cand : isWindows() ? new String[]{name, name + ".bat", name + ".exe"}
                                           : new String[]{name}) {
                Path p = Paths.get(dir, cand);
                if (Files.isRegularFile(p)) return p.toAbsolutePath();
            }
        }
        return null;
    }

    // ---- JDK 定位：设置 javaHome > 环境变量 JAVA_HOME > PATH 上的 java（与官方脚本一致）----
    static String locateJava(String javaHomeSetting) {
        String home = (javaHomeSetting != null && !javaHomeSetting.isEmpty())
                ? javaHomeSetting : System.getenv("JAVA_HOME");
        if (home != null && !home.isEmpty()) {
            Path p = Paths.get(home, "bin", isWindows() ? "java.exe" : "java").toAbsolutePath();
            if (Files.isRegularFile(p)) return p.toString();
        }
        return "java";
    }

    static int javaMajor(String javaExec) throws IOException, InterruptedException {
        Process p = new ProcessBuilder(javaExec, "-version").redirectErrorStream(true).start();
        String out = new String(p.getInputStream().readAllBytes(), StandardCharsets.UTF_8);
        p.waitFor();
        Matcher m = Pattern.compile("version \"(\\d+)").matcher(out);
        if (!m.find()) throw new Fail("resolver: could not determine java version from " + javaExec);
        return Integer.parseInt(m.group(1));
    }

    static String findLauncher(Path base) throws IOException {
        Path exact = base.resolve("plugins").resolve("org.eclipse.equinox.launcher.jar");
        if (Files.isRegularFile(exact)) return exact.toString();
        try (Stream<Path> s = Files.list(base.resolve("plugins"))) {
            return s.map(Path::getFileName).map(Path::toString)
                    .filter(n -> n.startsWith("org.eclipse.equinox.launcher_") && n.endsWith(".jar"))
                    .sorted().findFirst()
                    .map(n -> base.resolve("plugins").resolve(n).toString())
                    .orElseThrow(() -> new Fail("resolver: cannot find equinox launcher under " + base));
        }
    }

    static String sharedConfigPath(Path base) {
        if (isWindows()) return base.resolve("config_win").toString();
        if (System.getProperty("os.name", "").toLowerCase().contains("mac")) return base.resolve("config_mac").toString();
        return base.resolve("config_linux").toString();
    }

    // 数据目录：<平台缓存>/mayoi-java/jdtls-<sha1(完整 root 路径)>（比官方脚本更精确，见 F4）
    static String dataDirFor(String root) throws Exception {
        String cacheRoot;
        if (isWindows() && System.getenv("APPDATA") != null) cacheRoot = System.getenv("APPDATA");
        else if (System.getenv("HOME") != null && System.getProperty("os.name", "").toLowerCase().contains("mac"))
            cacheRoot = Paths.get(System.getenv("HOME"), "Library", "Caches").toString();
        else if (System.getenv("HOME") != null) cacheRoot = Paths.get(System.getenv("HOME"), ".cache").toString();
        else cacheRoot = System.getProperty("java.io.tmpdir");
        byte[] h = MessageDigest.getInstance("SHA-1").digest(root.getBytes(StandardCharsets.UTF_8));
        StringBuilder sb = new StringBuilder();
        for (byte b : h) sb.append(String.format("%02x", b));
        return Paths.get(cacheRoot, "mayoi-java", "jdtls-" + sb).toString();
    }

    static String readAllStdin() throws IOException {
        return new String(System.in.readAllBytes(), StandardCharsets.UTF_8);
    }

    static String str(Object v, String dflt) { return v instanceof String s && !s.isEmpty() ? s : dflt; }
    static String asString(Object v) { return v instanceof String s ? s : null; }

    @SuppressWarnings("unchecked")
    static Map<String, Object> asMap(Object v) {
        if (!(v instanceof Map)) throw new Fail("resolver: expected JSON object");
        return (Map<String, Object>) v;
    }

    static boolean isWindows() {
        return System.getProperty("os.name", "").toLowerCase().contains("win");
    }

    // JSON 字符串转义（仅输出用；Windows 路径的反斜杠必须转义）
    static String q(String s) {
        StringBuilder sb = new StringBuilder("\"");
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            switch (c) {
                case '"' -> sb.append("\\\"");
                case '\\' -> sb.append("\\\\");
                case '\n' -> sb.append("\\n");
                case '\r' -> sb.append("\\r");
                case '\t' -> sb.append("\\t");
                default -> { if (c < 0x20) sb.append(String.format("\\u%04x", (int) c)); else sb.append(c); }
            }
        }
        return sb.append('"').toString();
    }

    // ---- 最小 JSON 解析器（输入 schema 已知且简单：对象/数组/字符串/数字/字面量）----
    static final class JsonParser {
        private final String s;
        private int i;

        JsonParser(String s) { this.s = s; }

        Object parse() {
            Object v = value();
            ws();
            if (i < s.length()) throw new Fail("resolver: trailing JSON input at " + i);
            return v;
        }

        private Object value() {
            ws();
            if (i >= s.length()) throw new Fail("resolver: unexpected end of JSON");
            char c = s.charAt(i);
            switch (c) {
                case '{': return obj();
                case '[': return arr();
                case '"': return str();
                case 't': expect("true"); return Boolean.TRUE;
                case 'f': expect("false"); return Boolean.FALSE;
                case 'n': expect("null"); return null;
                default: return num();
            }
        }

        private Map<String, Object> obj() {
            Map<String, Object> m = new LinkedHashMap<>();
            i++; ws();
            if (i < s.length() && s.charAt(i) == '}') { i++; return m; }
            while (true) {
                ws();
                if (i >= s.length() || s.charAt(i) != '"') throw new Fail("resolver: bad object key at " + i);
                String k = str();
                ws();
                if (i >= s.length() || s.charAt(i) != ':') throw new Fail("resolver: expected ':' at " + i);
                i++;
                m.put(k, value());
                ws();
                char c = s.charAt(i++);
                if (c == '}') return m;
                if (c != ',') throw new Fail("resolver: expected ',' or '}' at " + (i - 1));
            }
        }

        private List<Object> arr() {
            List<Object> l = new ArrayList<>();
            i++; ws();
            if (i < s.length() && s.charAt(i) == ']') { i++; return l; }
            while (true) {
                l.add(value());
                ws();
                char c = s.charAt(i++);
                if (c == ']') return l;
                if (c != ',') throw new Fail("resolver: expected ',' or ']' at " + (i - 1));
            }
        }

        private String str() {
            StringBuilder sb = new StringBuilder();
            i++;
            while (true) {
                if (i >= s.length()) throw new Fail("resolver: unterminated string");
                char c = s.charAt(i++);
                if (c == '"') return sb.toString();
                if (c == '\\') {
                    char e = s.charAt(i++);
                    switch (e) {
                        case '"' -> sb.append('"');
                        case '\\' -> sb.append('\\');
                        case '/' -> sb.append('/');
                        case 'b' -> sb.append('\b');
                        case 'f' -> sb.append('\f');
                        case 'n' -> sb.append('\n');
                        case 'r' -> sb.append('\r');
                        case 't' -> sb.append('\t');
                        case 'u' -> {
                            sb.append((char) Integer.parseInt(s.substring(i, i + 4), 16));
                            i += 4;
                        }
                        default -> throw new Fail("resolver: bad escape \\" + e);
                    }
                } else sb.append(c);
            }
        }

        private Object num() {
            int start = i;
            while (i < s.length() && "+-0123456789.eE".indexOf(s.charAt(i)) >= 0) i++;
            return Double.parseDouble(s.substring(start, i));
        }

        private void expect(String lit) {
            if (!s.startsWith(lit, i)) throw new Fail("resolver: expected " + lit + " at " + i);
            i += lit.length();
        }

        private void ws() {
            while (i < s.length() && Character.isWhitespace(s.charAt(i))) i++;
        }
    }
}
```

已知限制（写入 README，可接受）：
- `java` 需在 PATH 上（仅设 `JAVA_HOME` 不设 PATH 的用户需自行加 PATH，或改回路径 A 模式）——
  与官方脚本"PATH 上兜底找 java"的限制同级；
- `helperPath` 清单默认值 `helper/mayoi-java-resolver.jar` 按相对路径解析，其基准目录是
  仓库根还是插件安装目录为待验证项 V3；不生效时用户在设置里改成绝对路径即可。

- [ ] **Step 2: 编译为 jar 并入库**

```powershell
# 在仓库根执行（任一 JDK >= 21；javac 目标字节码用 17，兼容性足够）
javac -encoding UTF-8 --release 17 -d helper\out helper\src\Resolve.java
jar --create --file helper\mayoi-java-resolver.jar --main-class Resolve -C helper\out .
Remove-Item -Recurse -Force helper\out   # 中间产物不入库（已在 .gitignore，删不删均可）
# 期望: 生成 helper\mayoi-java-resolver.jar，无编译错误
```

- [ ] **Step 3: 本地直测 resolver 协议**

```powershell
'{"root":"F:/tmp/demo-ws","settings":{}}' | java -jar helper\mayoi-java-resolver.jar resolve
# 期望: 单行 JSON，形如
# {"command":"...java","args":["-Declipse.application=...","-jar","...org.eclipse.equinox.launcher_*.jar","-data","...mayoi-java/jdtls-<sha1>"],...}
# Windows 下注意路径里的反斜杠应被转义为 \\
'{"settings":{}}' | java -jar helper\mayoi-java-resolver.jar resolve
# 期望: 退出码 1，stderr: resolver: missing "root"
'{"root":"F:/tmp/demo-ws","settings":{"javaHome":"C:/not-a-jdk"}}' | java -jar helper\mayoi-java-resolver.jar resolve
# 期望: 回退到 PATH java 并成功输出（javaHome 路径无效时）
```

- [ ] **Step 4: 切换 `plugin.json` 到 resolve 模式**

```json
{
  "name": "java",
  "displayName": "Java",
  "version": "0.2.0",
  "description": "Go to Definition, hovers, completions and problems in Java files, with jdtls",
  "author": "<填写作者/团队名>",
  "mayoi": ">=0.19.0",
  "enabled": true,
  "contributes": {
    "settings": {
      "path": {
        "type": "string",
        "default": "jdtls",
        "description": "The jdtls installation, by name on PATH or path to bin/jdtls(.bat)"
      },
      "javaHome": {
        "type": "string",
        "default": "",
        "description": "Path to a JDK (21+) used to run the language server; empty = auto-detect"
      },
      "helperPath": {
        "type": "string",
        "default": "helper/mayoi-java-resolver.jar",
        "description": "Path to the bundled resolver helper jar"
      }
    },
    "languageServers": [
      {
        "id": "java.server",
        "languages": ["java"],
        "resolve": {
          "command": "java",
          "args": ["-jar", "${settings.helperPath}", "resolve"]
        },
        "install": "brew install jdtls"
      }
    ]
  }
}
```

> `id` 仍为 `java.server` 不变（规则 2.2）；`version` 升为 `0.2.0`。

- [ ] **Step 5: 在 Mayoi 里复跑 Task 3 的验收矩阵（至少 A1–A8、A10），更新 VERIFICATION.md**

- [ ] **Step 6: Commit**

```bash
git add helper/src/Resolve.java helper/mayoi-java-resolver.jar plugin.json README.md docs/VERIFICATION.md
git commit -m "feat: python-free resolver path B (java helper jar), v0.2.0"
```

---

### Task 5: 发布

**前置**：Task 3（及若执行的 Task 4）验收通过；`plugin.json` 的 `author` 已填写。

- [ ] **Step 1: 创建 GitHub 仓库（如 `you/mayoi-java`）并推送**

```bash
git remote add origin git@github.com:you/mayoi-java.git
git push -u origin main
```

- [ ] **Step 2: 全流程安装验证（模拟真实用户）**

```bash
mayoi plugin install you/mayoi-java
# 然后在 Mayoi 打开任意 .java 文件，复验 Task 3 的 A1/A2/A4/A5/A6
```

- [ ] **Step 3: 向 mayoi-editor/plugins 的 index.json 提 PR，追加条目**

```json
{
  "name": "java",
  "displayName": "Java",
  "description": "Java with jdtls",
  "repository": "https://github.com/you/mayoi-java",
  "languages": ["java"],
  "detect": "jdtls",
  "install": "brew install jdtls"
}
```

`repository` 替换为实际地址；`detect`/`install` 必须真实可执行（官方链路：用户打开
`.java` → 宿主按 `detect` 在文件夹所在机器找 `jdtls` → 找到则提示装插件，否则提示装
jdtls 并在一分钟后重查，规则 §6.5）。

- [ ] **Step 4: 发布后在 README 记录版本/id 兼容承诺**

- 语言服务器 id `java.server` 永不更改；
- settings 键只增不删不改名；
- 破坏性变更升 major 版本。

- [ ] **Step 5: Commit（如有 README 变更）并打 tag**

```bash
git tag v0.1.0 && git push origin main --tags
```

---

## 4. 风险登记

| 风险 | 影响 | 缓解 |
|---|---|---|
| 官方启动脚本依赖 Python 3.9+（F1） | 无 Python 的用户路径 A 失败 | README/安装提示写明；Task 4 彻底去除 |
| `jdtls.bat` 的 `pause` 与 `python` 依赖（F2） | Windows 下退出挂起/启动失败 | Task 1 Step 4、Task 3 A12 实测；不通过即走 Task 4 |
| 宿主可能无法按名解析 `.bat`（PATHEXT） | Windows 路径 A 不可用 | 用户把 `plugins.java.path` 设为 `bin\jdtls.bat` 绝对路径（README 说明）；仍不行则 Task 4 |
| `-data` 按目录名哈希（F4），同名目录冲突 | 两个同名项目索引串扰 | 路径 A 记录为已知问题；路径 B 用完整路径哈希修复 |
| resolver 的 `java` 必须在 PATH | 仅设 JAVA_HOME 的用户失败 | 与官方脚本同级限制，README 说明 |
| 宿主 LSP 不支持 references/rename | 功能边界 | README 明示，绝不承诺；等待核心支持后本插件无需改动即可获得 |
| Maven/Gradle 首次导入慢/失败（离线环境） | 大项目体验差 | README 标注"取决于 jdtls 自身"，v1 不承诺 |

## 5. 待验证清单（宿主行为，无法离线确认，真机回填结论）

| # | 待验证项 | 在哪验证 |
|---|---|---|
| V1 | `mayoi` 最低版本字段 `>=0.19.0` 是否准确 | Task 2 Step 4（加载即知） |
| V2 | 宿主启动服务器进程时 cwd 是否为 workspace root（影响路径 A 自动 `-data` 哈希） | Task 3 A1 + 检查缓存目录名 |
| V3 | `resolve.command/args` 中相对路径（helperPath 默认值）的解析基准 | Task 4 Step 5 |
| V4 | settings.json 的 `languageServers` 按 id 覆盖是否支持 `command` | Task 3 A9 |
| V5 | Chroma 的 java lexer 是否需要插件显式贡献 `languages`（如 `lineComment`） | Task 3 A2–A6 顺带观察注释/高亮 |
| V6 | Windows 下宿主对 `.bat` 的启动方式（直接 CreateProcess / cmd 语义 / ShellExecute） | Task 3 A12 |

## 6. 与规则文档的差异说明

- 规则 4.2 假设"bin/jdtls 能自动处理 JDK 与 data 目录"——属实，但补充：脚本本体是
  Python（F1）、强制 JDK ≥ 21（F3）、data 目录按**目录名**哈希（F4）。均已反映到
  Task 1 检查清单与 Task 4 设计中。
- 其余官方规则（命名、ID、预算、resolver 协议、发布链路）以 `PLUGIN-RULES.md` 为准，
  本计划未做任何偏离。
