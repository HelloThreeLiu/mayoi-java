# 验证记录

## 路径 A 冒烟验证（Task 1）— 2026-11-21 / Windows (NT 10.0.26300, x64) / jdtls 1.63.0 (202610191322) / JDK 25.0.5.1（JAVA_HOME）+ 21.0.4（PATH）/ Python 3.14.2

| 检查项 | 结果 | 备注 |
|---|---|---|
| stdio 启动（Step 4） | ✅ | 显式 `-data` 运行，收到 initialize 响应：`{"jsonrpc":"2.0","id":1,"result":{"capabilities":{"textDocumentSync":…,"hoverProvider":true,…}}}`，`SMOKE OK`（exit 0）。启动链：cmd `/s /c` → `jdtls.bat` → `python bin/jdtls` → java（JDK 25）→ Equinox |
| 自动 -data 目录（Step 5） | ✅ | 无 `-data` 运行两次：首次生成 `%APPDATA%\jdtls\jdtls-b5794618ba77a0ba790c602f30381a38f5b7ad8b`（内含 `.metadata`），二次复用**未新增**目录。哈希实测 = `sha1("mayoi-java")`，即 **basename(子进程真实 cwd)**——机制勘误与实现注记见 B2 |
| JDK 缺失报错（Step 6） | ✅ | 快速失败（秒级、exit 1、不挂死）。① 完全无 java：traceback 末行 `FileNotFoundError: [WinError 2] 系统找不到指定的文件`（可读性一般）；② JAVA_HOME 指向 JDK 8：单行 `Exception: jdtls requires at least Java 21`。实际输出见 A3 |
| Windows .bat 经 cmd 可启动 | ✅ | `/s /c ""bat" args""`（整体外层引号对包裹）可正常拉起；逐字版 `/c "bat" args`（4 引号）因 cmd 剥首尾引号必失败。勘误与对照实验见 A4 |

## 决策门结论

- [x] **路径 A 全部通过 → 执行 Task 2**
- [ ] 存在失败项 → 跳过 Task 2 的 command 模式，先执行 Task 4（路径 B）——不适用

补充：决策门一度因 **jdtls 1.63.0 的 OSGi bundle 要求 JavaSE 25** 而阻塞（本机最初仅 JDK 21，Equinox 解析失败，详见 A1）。经控制器决策安装 **Oracle JDK 25.0.5.1 LTS**（用户级 `JAVA_HOME = D:\Development\CodeDevEnvironment\Java\jdk-25.0.5.1`）后全项通过。**Task 2 的宿主实现必须保证以 JDK ≥ 25 拉起 jdtls 1.63.0**（jdtls.py 优先取 `JAVA_HOME\bin\java.exe`，其次 PATH；亦支持 `--java-executable` 显式指定）。

## 本机环境两点说明

1. **用户级 `JAVA_HOME` 已指向 JDK 25**（`D:\Development\CodeDevEnvironment\Java\jdk-25.0.5.1`，用户手动安装 Oracle JDK 25.0.5.1 LTS；机器级旧值 jdk1.8.0_202 未动，用户级覆盖仅对新进程生效）。jdtls.py 的 java 选择顺序 = `--java-executable` 参数 > `JAVA_HOME\bin\java.exe`（存在时）> PATH 上的 `java`；25.0.5.1 满足 1.63.0 的 JavaSE 25 要求，且 `java_major_version >= 24` 时官方脚本自动追加 `-Djdk.xml.maxGeneralEntitySizeLimit=0`、`-Djdk.xml.totalEntitySizeLimit=0` 两个兼容参数（与 PLAN F3 一致）。
2. **PATH 上的 java 仍是 21.0.4**（Oracle javapath shim），与 JAVA_HOME=25 共存：不影响 jdtls（优先 JAVA_HOME），但宿主若依赖 PATH 找 java 则拿到 21——**无法运行 jdtls 1.63.0**。清单/文档需引导用户保证 JAVA_HOME ≥ 25 或在 settings 中显式指定。

## 冒烟脚本勘误（相对任务原文的修订，均已实测）

1. **cmd 引号修正**：`$psi.Arguments` 改为 `/s /c` + 整体外层引号对形式（见 A4）。注意：控制器下发的 `` "/s /c `"`"`"$Jdtls`" -data `"$DataDir`"`"" ``（3+2 引号）实测**不可行**——cmd /s 剥掉首尾引号后残留 `""bat"` 前缀报"不是内部或外部命令"；可行形式是 2+2：`` "/s /c `"`"$Jdtls`" -data `"$DataDir`"`"" ``。docs/PLAN.md 第 144 行已由控制器同步修正。
2. **无 `-data` 模式**：`$DataDir` / `$DATA_DIR` 默认空串，为空时不追加 `-data` 参数（这正是 Mayoi 宿主的真实启动形态）。`lsp-smoke.sh` 用 `${DATA_DIR:+-data "$DATA_DIR"}` 等效实现——仅此构造兼容 bash 3.2；脚本整体需要 bash 4.1+（coproc/read -N 为 4.0、`{fd}` 关闭语法为 4.1），macOS 自带 bash 3.2 需用 Homebrew bash（已在脚本头部注明）。
3. **逐帧读取修正**：jdt.ls 在 initialize 响应前会先推送 `language/status` 等 notification（如 `{"type":"Starting","message":"Init..."}`），原单帧读取必然误判 FAIL。改为逐帧读取、跳过 notification，直到收到含 `"capabilities"` 的响应帧。两个脚本已同步修正。

### 复审加固（详见附录 C1）

bash 侧剥离 LSP header 的行尾 `\r`（bash read 只剥 `\n`，否则空行判定永不成立且 Content-Length 带尾 `\r`）；ps1 把启动到读取包进 `try/finally`（任何 throw 都会 taskkill 清理进程树，finally 兜底清理 stderr 临时文件）；两侧 stderr 均改为文件重定向——**M4 选择说明**：选择了实现重定向而非保留 + 注释方案，理由是重定向消除了一类真实的死锁（stderr 管道 >4KB 无人排水会阻塞子进程），Windows 侧经 cmd 层 `2>` 落文件、POSIX 侧在 coproc 内落文件，失败路径打印该文件、成功后删除，复杂度可控且两侧均实测；ps1 的 POSIX 分支不经过 shell，stderr 直通控制台（无管道阻塞风险）；sh 侧另加 `command -v` 前置检查、`>> starting:` 回显、kill 后 `wait` 收割（消除 bash "Terminated" 任务通知）、rootUri 空格转义。ps1 的 stderr 临时文件路径改用跨平台 `[IO.Path]::GetTempPath()` 构造——原写法 `Join-Path $env:TEMP …` 在脚本加载期无条件执行，macOS/Linux 无 TEMP 时（$env:TEMP 为 null）ps1 的 POSIX 分支未跑先崩。

---

## 附录：实测证据

图例：A× = 计划步骤证据；B× = 机制勘误/运维注记；C× = 复审修复回归验证。

### A0. 环境与安装（Step 1）

- 安装前 `where.exe jdtls*` → 未找到（exit 1）
- 安装包：`jdt-language-server-1.63.0-202610191322.tar.gz`（51,143,565 字节 ≈ 48.77MB，官方 `https://download.eclipse.org/jdtls/milestones/1.63.0/` 产物，用户手动下载提供；清华 TUNA 镜像 `/eclipse/jdtls/` 下无 milestones 目录，且不支持断点续传）
- `tar -tzf` 全量校验通过（137 个条目无错误），解压到 `%LOCALAPPDATA%\Programs\jdtls`（tar exit 0），`bin\`、`config_win\`、`plugins\` 就位
- **`bin\jdtls.bat` 实际内容（3 行）**：
  ```
  @echo off
  python "%~dp0/jdtls" %*
  pause
  ```
  与计划预期一致（`python "%~dp0/jdtls" %*` + `pause`，另含 `@echo off` 头）。
- `bin\jdtls.py` 关键事实：`--validate-java-version` 默认开启（< 21 抛 `jdtls requires at least Java 21`）；java 选择顺序见上文环境说明第 1 条；`-data` 默认值 = `<APPDATA>\jdtls\jdtls-<sha1(basename(os.getcwd()))>`；`bin\jdtls`（无扩展名，bat 实际调用入口）为纯加载器，不改 cwd、不改参数

### A1. 决策门阻塞史：JavaSE 25（已由 JDK 25 解决）

最初以 PATH java 21.0.4（子进程 JAVA_HOME 临时指 jdk-21）冒烟，Equinox 启动即写日志 `%LOCALAPPDATA%\Programs\jdtls\configuration\*.log`：

```
org.osgi.framework.BundleException: Could not resolve module: org.eclipse.buildship.core [22]
  ...
                       Unresolved requirement: Require-Bundle: org.eclipse.core.filesystem
                         -> org.eclipse.core.filesystem [28]
                              Unresolved requirement: Require-Capability: osgi.ee; filter:="(&(osgi.ee=JavaSE)(version=25))"
```

扫描 1.63.0 全部 plugin jar 的 MANIFEST.MF：JavaSE ≤1.8 有 18 个、11 有 26 个、17 有 1 个、21 有 7 个、**25 有 1 个**（`org.eclipse.core.filesystem` 1.12.0.v20260927-0940）——仅 1 个 bundle 要求 25，但它在 `jdt.ls.core → core.resources` 主干链上，OSGi 全链解析失败。背景佐证：jdt.ls README 主分支已改 "requires Java 25"；jdt.core 2025-09-22 构建引入该依赖（jdt.ls issue #3537）；Eclipse platform 有 "Require Java-25 for the Eclipse SDK" 提交。约 1.50.0（2025-09-04）为最后支持 Java 21 的 milestone（供需要 JDK 21 兼容的用户参考）。

### A2. Step 4 实际输出（最终通过形态）

（转录已省略 taskkill 输出）

```
>> starting: cmd.exe /s /c ""C:\Users\10966\AppData\Local\Programs\jdtls\bin\jdtls.bat" -data "C:\Users\10966\AppData\Local\Temp\jdtls-smoke""
>> response (first 500 chars):
{"jsonrpc":"2.0","id":1,"result":{"capabilities":{"textDocumentSync":{"openClose":true,"change":2,"save":{"includeText":true}},"hoverProvider":true,"completionProvider":{"resolveProvider":true,"triggerCharacters":[".","@","#","*"," "]},"signatureHelpProvider":{"triggerCharacters":["(",","]},"definitionProvider":true,"typeDefinitionProvider":true,"implementationProvider":true,"referencesProvider":true,"documentHighlightProvider":true,"documentSymbolProvider":true,"workspaceSymbolProvider":true,"c
SMOKE OK
```

### A3. Step 6 实际输出

① 字面场景（子进程 PATH 仅留 `C:\Windows\System32;C:\Windows`、删除 JAVA_HOME、绝对路径 python 执行 `bin\jdtls`、stdin 给 EOF）→ 秒级失败，exit 1，stderr 为 Python traceback，末行：

```
FileNotFoundError: [WinError 2] 系统找不到指定的文件。
```

（jdtls.py 对 `subprocess.check_output(['java','-version'])` 的 FileNotFoundError 未做捕获，报错形态是堆栈而非友好提示，但快速失败达标、末行含义可辨认。）

② 环境变体（JAVA_HOME 指向 JDK 8，本机修复前真实状态）→ 秒级失败，单行干净报错：

```
Exception: jdtls requires at least Java 21
```

### A4. cmd 引号语义对照实验（.NET ProcessStartInfo 直传 Arguments，等价宿主 cmd 拉起语义）

| Arguments 形式 | 结果 |
|---|---|
| `/c "exe" "arg"`（任务原文写法，4 引号） | ❌ `'"exe" "arg"' 不是内部或外部命令`（cmd 剥掉首尾引号） |
| `/s /c """exe" "arg""`（控制器/PLAN.md 下发的 3+2 形式） | ❌ `'""exe" "arg"' 不是内部或外部命令`（/s 剥后残留 `""` 前缀） |
| `/s /c ""exe" "arg""`（2+2，**最终采用**） | ✅ 程序被正常执行；冒烟全链 SMOKE OK |

规则依据（`cmd /?`）：`/c` 后引号数恰为 2 且满足其余条件才原样保留；否则剥掉第一个和最后一个引号。`/s` 强制剥首尾引号——因此整体外层再包一对引号即可在剥离后得到干净的 `"bat" args`。

### B2. 自动 -data 目录机制（Step 5 实测勘误与实现注记）

`jdtls.py` 实际逻辑（安装版逐字核对）：

```python
cwd_name = os.path.basename(os.getcwd())
jdtls_data_path = os.path.join(cachedir, "jdtls-" + sha1(cwd_name.encode()).hexdigest())   # 仅作 -data 默认值
```

- 计划原预期"按 data 目录名做 sha1"不成立；真实输入 = **jdtls 进程的工作目录最后一段**，且仅在**未显式传 `-data`** 时生效（显式 `-data` 直接覆盖，不产生 APPDATA 缓存目录）
- 实测陷阱：.NET `ProcessStartInfo` 不设 `WorkingDirectory` 时子进程继承 **Win32 进程级 cwd**（pwsh 会话中即 `[Environment]::CurrentDirectory` = 启动目录），**不是** pwsh `Set-Location` 的目标位置。故冒烟观测到的哈希 = `sha1("mayoi-java")` = `b5794618ba77a0ba790c602f30381a38f5b7ad8b`，而非 `sha1("jdtls-smoke-ws")`（= `016d45a7ed8cafebb478fd2e3d3ba2675f4c9c61`，曾据错误假设预测）
- **Task 2 实现注记**：Mayoi 以 `cmd.Dir = workspace root` 显式设置子进程 cwd（PLAN F8，Go `exec.Command`），因此 data 目录名确定性 = `sha1(basename(workspace root))`——同名叶子目录的不同项目仍会共用同一 data 目录（索引串扰风险，PLAN F4 已识别；宿主侧如需隔离可显式传 `-data` 指定独立目录）
- 复用验证：同一真实 cwd 下两次无 `-data` 冒烟，`%APPDATA%\jdtls` 始终只有一个 `jdtls-b5794618…` 目录，未新增

### B3. 残留物与清理

- 每次冒烟结束由脚本清理进程树（ps1：`taskkill /PID <cmd> /T /F`，已包进 `try/finally`；sh：kill + wait 收割 coproc），事后核查无 java/python/curl 残留进程
- 冒烟产物：`%TEMP%\jdtls-smoke`（显式 data）、`%APPDATA%\jdtls\jdtls-b5794618…`（默认 data，保留供 Task 2 对照）——均属测试产物，不入库

### C1. 复审修复回归验证（2026-11-21）

**sh 侧（Git Bash 4.4.23 + 一次性假 LSP 服务器）**——验证 CRLF 剥离、notification 跳帧、`read -N` 定长读取、`command -v` 前置检查；假服务器为 node 脚本（CRLF 帧格式，先发 `language/status` notification 再发含 `capabilities` 的 initialize 响应，模拟 jdt.ls 真实行为）：

```
$ bash.exe scripts/lsp-smoke.sh C:/Users/10966/AppData/Local/Temp/fake-lsp
>> starting: C:/Users/10966/AppData/Local/Temp/fake-lsp
>> response (first 500 chars):
{"jsonrpc":"2.0","id":1,"result":{"capabilities":{"textDocumentSync":{"openClose":true},"hoverProvider":true}}}
SMOKE OK        （exit 0，且 kill 后 wait 收割，无 "Terminated" 任务通知）

$ bash.exe scripts/lsp-smoke.sh /nonexistent/fake-jdtls
SMOKE FAIL: '/nonexistent/fake-jdtls' not found    （exit 1）
```

注：sh 脚本以 macOS/Linux 为目标，本次在 Windows Git Bash + 假服务器上验证的是**帧处理逻辑**（CRLF 剥离/跳帧/定长读取）；真实 jdtls 在 macOS/Linux 上的端到端实跑留待有条件时补验。

**ps1 侧（真实 jdtls 1.63.0 + JDK 25，显式 `-DataDir`）**——验证 try/finally 改造与 stderr 文件重定向未破坏成功路径：

```
>> starting: cmd.exe /s /c ""C:\...\bin\jdtls.bat" -data "C:\...\Temp\jdtls-smoke" 2>"C:\...\Temp\jdtls-smoke-err-<PID>.log""
>> response (first 500 chars):
{"jsonrpc":"2.0","id":1,"result":{"capabilities":{"textDocumentSync":{"openClose":true,"change":2,...
SMOKE OK        （exit 0；taskkill 在 finally 中照常执行；errFile 成功后已删除）
```

---

## Task 3 真机验收（2026-11-21 / Mayoi 0.23.1 / Windows / jdtls 1.63.0 / JDK 25.0.5.1 / 插件经 junction 链接）

验收环境：`~/.mayoi/plugins/java`（junction → 本仓库；`mayoi plugin dev` 的 symlink 需 Windows 开发者模式，本机未开，故以无需特权的目录 junction 落地，与真 symlink 的差异见上文遗留节）；用户 settings.json 配置 `plugins.java.path = %LOCALAPPDATA%\Programs\jdtls\bin\jdtls.bat`（完整路径——本机 PATH 上无 jdtls，属 README 载明的 Windows 正常配置形态）。

### 验收矩阵结果

| # | 项 | 结果 | 证据/备注 |
|---|---|---|---|
| A1 | 服务器拉起 | ✅ | 插件日志 `10:45:27.422 [info] java: started java.server`；Show Language Servers 面板显示运行中 |
| A2 | 诊断 | ✅ | 注入 `String x = 1;` → jdtls 日志 `2-3 problems reported for /App.java`，Problems 面板与状态栏计数更新；撤销后 `0 problems` |
| A3 | hover | ✅ | `greet` 显示方法签名 |
| A4 | 定义跳转 | ✅ | F12 跳到定义行 |
| A5 | 补全 | ✅ | 命令面板 Complete / F2 触发，返回 `main`、`greet` 及 Object 成员。注意：① Mayoi 无点号自动触发（全源码无 triggerCharacters 处理，`sel.complete` 为手动命令）；② 快捷键问题见宿主观察 1/2 |
| A6 | 格式化 | ✅ | 宿主格式化命令生效 |
| A7 | Maven 导入 | ✅ | jdtls 日志 `Importing Maven project(s)` → `Workspace initialized in 25057ms`；`test-fixtures/.classpath`、`.project`、`.settings/` 落盘（Eclipse 项目元数据，已 gitignore）为导入成功的物证 |
| A8 | 缺服务器报错 + 恢复 | ✅ | 故意配错路径（`C:\nonexistent\jdtls.bat`）→ UI 通知「无法启动 java.server: jdtls.bat 未安装。安装命令： brew install jdtls」+ **Restart** 按钮（截图存档）；日志 `could not start java.server: fork/exec C:\nonexistent\jdtls.bat: The system cannot find the path specified.`（精确 OS 原因）；恢复路径后点 **Restart** → `started java.server` 一键恢复 |
| A9 | 用户覆盖配置 | ✅ | settings.json 顶层 `languageServers.java.server.initializationOptions` → 服务器重启时插件日志出现 `[info] starting java.server with languageServers.java.server.initializationOptions`（源码 `lsp_resolve.go:251` 行为实证，RFC 7386 深合并生效） |
| A10 | 崩溃恢复 | ✅ | `taskkill /F` 强杀 jdtls JVM（PID 35932）→ 重开文档即自动重启（`stopped` → `starting …` → `started java.server`），与源码 `lspRetryPause = 30s` 重试机制吻合 |
| A11 | 插件日志 | ✅ | 无刷屏错误；仅 JDK 25 的良性 JVM 警告（incubator modules / guice Unsafe deprecation） |
| A12 | Windows `.bat` 启动链 | ✅ | 宿主经 cmd 语义拉起 `jdtls.bat` → python → java 全链成功（A1 即证） |
| A13 | SSH 远端 | ⏭️ | 无 SSH 环境条件，留待有条件时补测 |

### 验收过程日志节选（三轮服务器生命周期）

```
10:45:27.422 [info]  java: started java.server                     ← A1 首次拉起
11:43:30.139 [warn]  java: java.server stopped                     ← A9 触发的重启
11:43:30.139 [info]  java: starting java.server with languageServers.java.server.initializationOptions
11:43:31.934 [info]  java: started java.server                     ← A9 覆盖生效
11:47:54.401 [warn]  java: java.server stopped                     ← A10 强杀 JVM（PID 35932）
11:47:54.401 [info]  java: starting java.server with languageServers.java.server.initializationOptions
11:47:55.970 [info]  java: started java.server                     ← A10 自动恢复
11:50:46.377 [warn]  java: java.server stopped                     ← A8 杀掉旧实例
11:50:49.251 [error] java: could not start java.server: fork/exec C:\nonexistent\jdtls.bat: The system cannot find the path specified.   ← A8 失败原因
11:51:36.390 [info]  java: starting java.server with languageServers.java.server.initializationOptions   ← A8 恢复路径后点 Restart
11:51:37.985 [info]  java: started java.server                     ← A8 一键恢复
```

### 宿主观察项（非插件缺陷；供 Mayoi 上游参考，README 已做用户侧提示）

1. **`sel.complete` 无默认快捷键**：`commands.go:122` 默认键为空串，而命令面板标签显示 "Ctrl+Space"（`commandpalette.go:90`）——标签与实现不符，按 Ctrl+Space 无反应。设置编辑器还会为这个不存在的"默认键"生成 `-sel.complete` 解绑条目（VS Code 移除语法）。用户可自行绑定（编辑器内 Alt 组合键另见观察 2，推荐非 Alt 键或命令面板路径）。
2. **含 Alt 的 keybindings 绑定在 Windows 编辑器内不触发**：`ctrl+alt+space` 绑定无反应，改绑 `F2` 立即生效（热加载正常，排除加载问题）；疑与 mygo Windows 输入层对 `WM_SYSKEYDOWN` 的处理有关（未深究，Mayoi 内核范畴）。命令面板触发不受影响。
3. **服务器重启 + 编辑器打开时的 `BadLocationException`**：`WorkspaceDiagnosticsHandler.convertRange` 竞态，3/3 次重启复现，一次性、自愈，不影响后续诊断（jdtls 上游已知类问题）。
4. **孤儿 JVM**：异常结束的会话（首次 160s 导入被中止的那次）其 jdtls java 进程存活逾 1 小时（`cmd→bat→python→java` 链，宿主树杀未及孙子进程），已手动清理（taskkill PID 43712）。
5. **install 提示的平台偏置**：失败通知展示 `brew install jdtls`（清单 install 为单字符串，Windows/Linux 用户需按 README 兜底指引安装）。

### 遗留

- A13 SSH 远端验收：留待有条件时补测。
- 首次 Maven 导入冷启动耗时明显（大项目实测 160s；本项目首次 25s）——属 jdtls 行为，README 已注明，v1 不承诺。
- `plugin list` 对 junction 链接不显示 dev 标记、`plugin install` 不拒绝覆盖 junction（源码 registry.go 检查 ModeSymlink）——**Task 5 安装测试前须先 `cmd /c rmdir` 删除 junction**（已在 PLAN Task 5 记载）。

### Task 4 决策门（更新）

路径 A 全项通过 → **Task 4（路径 B resolver）按计划跳过**，不执行。若未来 Mayoi/jdtls 演进导致路径 A 失效，或需要去除 Python 依赖，再按 PLAN Task 4 重启该任务（其设计注记已按源码事实更新完毕）。

---

## v0.2 一键引导验证（2026-11-21 / Mayoi 0.23.1 / Windows / jdtls 1.63.0 / 受管 Temurin JRE 25.0.5+8）

背景：v0.1 依赖用户预装 jdtls + Python 3.9 + JDK 21/25。v0.2 新增 `bootstrap/`（每平台一条命令）与 `launcher/`（免 Python 启动器），目标 = 下载即用；JDK 8 存量用户不受影响（jdtls 运行在受管 JRE 25 上，ECJ 可分析 `release=8` 老项目；用户 JDK 8 仅用于运行其应用，与编辑器无关）。设计定案与幂等矩阵见 `docs/PLAN-v0.2-bootstrap.md` §1。

### 启动器验证（Task 1）

- Windows 全链：发布后布局（%TEMP% 下真实 jdtls 完整拷贝 + JAVA_HOME 回退链驱动）→ `SMOKE OK`；数据目录 `%APPDATA%\mayoi-java\jdtls\<净化名>` 生成；equinox 定位覆盖 glob+goto 分支（精确名不存在）
- POSIX：`bash -n` / `dash -n` 通过；假 java 单测（受管 JRE 分支获胜、19 项参数全落位、透传逐字）
- 质量修复（ee66b2d → 92b0f65，复审 Approved closed）：`.gitattributes` EOL 钉死（fresh clone 防两端同时损坏）、bat 全 ASCII 化（CP936 控制台假错误逐字节消除验证）、cwd 注入双保险（`where "$PATH:java"` + `NoDefaultCurrentDirectoryInExePath`，负路径 PWNED 零命中）、HOME 三级回退链修正（控制器模板笔误由实施者捕获）等

### Windows 引导 E2E（Task 2）

- 一条命令全链（本地等价 iex；jdtls 下载腿走 `MAYOI_JDTLS_TGZ` 本地通道——续传机制已另行实测）：
  JRE TUNA 55.87MB @ 4.4MB/s（12s）→ `openjdk version "25.0.5"` → jdtls 本地源解压（marker `1.63.0`）→ 启动器落位（SHA-256 与仓库 `launcher/jdtls.bat` 一致）→ 用户 PATH 追加（注册表核验，21 个既有条目无损）→ 插件已装跳过
- **行为级证据（核心）**：Mayoi 重启至 test-fixtures → 约 10 秒内 java 进程 CommandLine = `...\mayoi-java\bin\..\jre\bin\java.exe` + 全部固定参数 + `-data ...\mayoi-java\jdtls\test-fixtures`——**受管 JRE + 免 Python 启动器在真实宿主链路中被使用**；Maven 导入元数据落盘
- 幂等重跑：四步全跳过、零网络、launcher SHA 不变
- 质量修复（3f0d784 → 0d8e77a → fe76833）：`curl --fail`（404 四象限实测：修复前错误页 20669B 静默落盘击穿双源回退，修复后 exit 22 零落盘）、JRE 内层 `bin\java.exe` 预校验（README-only zip 负路径：throw + 旧 JRE 完好）、`-LiteralPath`（`[x]` 路径 plain Test-Path 误判 False 实证）、tar 替代 Expand-Archive（5.1 下分钟级→秒级）、LF→CRLF 归一（AST 求值顺序证明 + LF blob 端到端字节模拟：73 lone-LF → 0）；复审 Approved closed

### POSIX 引导结构级验证（Task 3，Git Bash）

- 全量安装：TUNA 目录页抓名（`OpenJDK25U-jre_x64_linux_hotspot_25.0.5_8.tar.gz`）→ 下载 → 解压校验交换 → marker `1.63.0` / `.jre-version` → wrapper 落位 `chmod +x` → `~/.local/bin` 副本 → `.zshrc` 追加；幂等重跑（sh + 真 dash）全跳过
- 负路径三连：marker 缺失 → 重装；`1.62.0` → `版本变更: 1.62.0 → 1.63.0` 重装；**篡改源（截断 1MB）→ `SHA256 不匹配` exit 1 且现有安装字节未动** + 重跑恢复
- 质量修复（05eef54 → 4703d00，复审 Approved closed）：`~/.local/bin` 副本 wrapper 化（字节拷贝因启动器 `$0` 相对解析必坏——沙箱复现；wrapper 修复 7/7 断言：空格路径/透传/exec/重装自愈）、所有权指纹守卫（用户文件不覆盖实测）、私有缓存域、架构白名单 die、`tuna_latest_name` 归拢、HOME/mkdir die、rc 精确行去重
- 边界声明：真机 POSIX 端到端、Adoptium API 回退分支、JRE 版本变更实付重下 未验（与 C1 同口径）

### 最终整体审查（6668481..f55abe4）

- 设计定案全达成、四方口径一致（README ↔ plugin.json ↔ PLAN-v0.2 ↔ bootstrap 脚本：一条命令/URL/布局/体积逐字）、内嵌启动器副本与仓库文件程序化逐字一致、升级兼容无迁移面（plugin.json 仅 version 一行）、无敏感信息、10 提交线性
- 必做修复：bootstrap.ps1 加 UTF-8 BOM（Windows PowerShell 5.1 文件执行解析失败——文档化 `iwr|iex` 入口不受影响；BOM 修复三路验证通过）
- v0.2.1 记账：ps1 钉死 jdtls SHA256 + 缓存完整+哈希命中跳过下载捷径、体积口径复核、`install` 提示平台对齐、`tuna_latest_name` 取尾防御、REG_EXPAND_SZ kind 保持

### Task 4/5

- plugin.json 0.2.0 + README 一条命令安装改写（提交 `802b099`）
- 合并 main、tag v0.2.0、`plugin install` 升级测试（0.1.0 → 0.2.0）：见本节顶部时序，结果随验收推进回填

### 上游反馈：应用内更新失败（sorrycc/Mayoi#233，已修复）

- 验收中发现的"应用内 Update 按钮 Windows 失败"已报上游 → **sorrycc 当天回复并修复**（commit `cc5603d`，issue 已关闭）：
  - 根因确认：插件 watcher 对每个插件目录及其子目录（bootstrap/launcher/scripts）持有句柄，Windows rename 被阻断；复现测试 `TestUpdateKeepsFolderWhileWatched` 补充于 `install_test.go`（作者无 Windows 机器，mac 上以"更新整体替换插件目录"复现）
  - 修复方案 ≈ 本计划建议②：同源更新改为**原地 git 更新**（新版本仍先克隆到临时目录校验 manifest，再从临时 clone fetch 新 commit 并在**原目录原地 checkout**——全程无 rename）；覆盖 Update 按钮、应用运行中的 `plugin install/update`、settings sync；新版删除的文件会移除、untracked（node_modules）保留；非 Git clone 目录仍走 rename
- **版本状态**：`cc5603d` 领先 v0.23.1 七个提交（未随 0.23.1 发布）；Mayoi 发版节奏约 1-2 天一版 + 应用自动更新 → 发布后应用内 Update 按钮即可用
- **过渡期口径**（0.23.1 及更早版本）：更新插件 = 完全退出 Mayoi → `mayoi plugin update java` → 重开（本验收已实测成功）
- 上游已知未修：**移除**插件时 Windows 运行中可能撞同款句柄问题（作者留待出现时再修）——本插件的卸载指引（退出 Mayoi 后操作）已覆盖

---

## 上游反馈 2：Git 插件更新检查闪控制台黑窗（Windows，2026-11-21，[sorrycc/Mayoi#235](https://github.com/sorrycc/Mayoi/issues/235)）

用户报告：移除后重装 Git 来源的 java 插件，仍周期性闪黑窗口、"一直提示更新"。经源码比对 + GUI 子系统四组对照实验定位，**为宿主通用问题，插件侧无法规避**。

### 实验（winexp，`-ldflags -H=windowsgui` 无控制台进程 + EnumWindows 每 100ms 轮询新增可见窗口，按进程归属归类）

| 启动方式 | 对应 Mayoi 路径 | 结果 |
|---|---|---|
| 裸 `exec.Command` + `git ls-remote` | `internal/plugin/install.go` 的 `git()` | t+0.1s 出现窗口：`WindowsTerminal.exe` "Terminal"（Win11 默认终端）+ git.exe `PseudoConsoleWindow` |
| 同上 + `SysProcAttr{HideWindow, CREATE_NO_WINDOW}` | `internal/git` → `vfs.Command` | 运行 15s 零窗口 |
| 裸启动 jdtls.bat 链（cmd→bat→java） | ——（负向对照） | t+0.3s 同款窗口 |
| 同上 + 同 SysProcAttr | `vfs.CommandEnvironment`（0.23.1 LSP 实际路径） | 运行 10s 零窗口（仅桌面噪音 GCUService 弹窗，已按进程归属排除） |

### 结论

- 黑窗源 = 宿主插件系统的**裸 git 调用**：更新检查 `checkPluginUpdates()`（启动 +30s、之后每 `pluginUpdateEvery = 1h`，`cmd/mayoi/pluginsync.go`）对每个 Git 安装插件跑 `git ls-remote`；`Install`/`Update` 的 clone/fetch 同理且窗口更长。`internal/plugin` 未走 `internal/git` 的 `vfs.Command`（`hidewindow_windows.go` 的 HideWindow + CREATE_NO_WINDOW，#18/ce553d2）。
- LSP 链路无窗口：v0.23.1 为 ce553d2 后代（GitHub compare behind_by=0），`hidden-jdtls` 实测零窗口——**修改插件安装方式/启动器不影响黑窗**。
- 通用性：影响所有 Git 来源插件；内置插件无 records 不受影响。插件侧规避矩阵：Git 安装→黑窗+常驻 Update 按钮；钉 tag `@v0.2.1`（lightweight）→提示消失、黑窗仍在；dev 链接（junction，不写 records）→两者消失，仅限作者机。
- 同时实证「一直提示更新」：安装记录 commit == 远端 HEAD（`aa4fe55`，实测 `plugins.json` vs `git ls-remote`）时 Update 按钮仍常驻（`prefsplugins.go:473`，`fromGit` 一律渲染）——按钮语义是"执行更新"而非"有新版"；"有可用更新"另有 pill/通知（commit 级比对，`pluginsync.go updateWaits`）。0.23.1 点击 Update 失败（#233，cc5603d 待发版），提示故而无法消除。
- 自查口径：黑窗出现于 Mayoi 启动 +30s 或其后整小时；打开 .java 触发 LSP 启动时无黑窗。
- 实验材料：`winexp/`（Temp 下）四份日志；issue 草稿：`docs/ISSUE-win-console-window.md`。
- **上游处理（当天修复关闭）**：sorrycc 以读代码方式复现（macOS 无法亲见窗口，实验证据为定性关键），修复于 [c634faa](https://github.com/sorrycc/Mayoi/commit/c634faa)（"Fixes #235"）：导出 `vfs.HideWindow`，`internal/plugin` 新增 `gitCommand()` 应用之（仍 `exec.CommandContext`，30s 更新检查超时与同步超时语义不变）；补回归测试 `TestGitOfAPluginTakesNoConsoleWindow`（Windows CI）；CHANGELOG："On Windows, plugin update checks and installs no longer flash a console window."。Update 按钮常驻的 UX 建议留作单独改动。
- **随 v0.23.2 发布（2026-11-22），本机验证通过**：① 安装二进制 `Mayoi.exe` ProductVersion 0.23.2；② tag v0.23.2 包含 c634faa（compare behind_by=0），`install.go gitCommand()` 应用导出的 `vfs.HideWindow`、回归测试文件在位；③ 在本机（go 1.26.4 工具链）对 v0.23.2 源码实跑 `go test -run TestGitOfAPluginTakesNoConsoleWindow ./internal/plugin` → **PASS**；④ 同版 CHANGELOG 亦含 #233 修复（"Updating a plugin installed from Git no longer fails on Windows with Access is denied while Mayoi is open."），应用内 Update 于 Windows 可用。java 插件保持 Git 安装（records commit aa4fe55 == 远端 HEAD）即可，无需再以 dev 链接规避。

---

## v0.2.2 优化轮验证（2026-11-23 / Windows 11 x64（PowerShell 5.1 + pwsh 7）+ WSL2 Ubuntu 24.04 x64 / jdtls 1.63.0 / Temurin JRE 25.0.5.1）

背景：兑现 v0.2 最终审查的"v0.2.1 记账"遗留（ps1 钉死 jdtls SHA256、缓存哈希命中跳过下载捷径、install 提示平台对齐、REG_EXPAND_SZ kind 保持）+ 升级路径（两侧 JRE/jdtls marker 版本比较）、F4 同名目录 `-data` 隔离、外部 java 版本提示、CI 超时与 macOS e2e 等，明细见 CHANGELOG `[Unreleased]`。

### 静态检查（终态全绿）

- launcher 同步：两对内嵌副本逐行一致（ps1 ↔ jdtls.bat 101 行；sh ↔ jdtls 78 行）
- `bootstrap.ps1`：`Parser::ParseFile` 0 错误；ASCII-only 0 非字节
- `sh -n`（WSL dash）/ `bash -n`：bootstrap.sh 与 launcher/jdtls 双通过；bashism grep 零命中
- `plugin.json` jq 合法；`ci.yml` PyYAML 解析通过

### 逻辑单测

| 项 | 用例 | 结果 |
|---|---|---|
| .bat `-data` 哈希段 | 同名两级目录（`…\proj one` 与 `…\proj one\proj one`） | 后缀 `ad186b02` / `029bdf89` 互异，与 PowerShell `Get-FileHash`（`echo("<path>"` + CRLF 字节）独立复算一致；certutil 解析（`skip=1` + 去空格 + 截 8）稳定 |
| .bat 版本提示 | stub java 输出 17 / 25 / 乱码 / `JAVA_TOOL_OPTIONS` 干扰行 | 17→警告；25→静默；乱码→数值守卫（`findstr ^[0-9]*$`）安全跳过；干扰行→正确取 `openjdk version "17.0.2"` 行 |
| POSIX sed 解析 | 同前三类（dash 实跑） | `17` / `25` / 空 ✓ |
| POSIX 哈希后缀 | `/tmp` 同名两级目录 | `f349c64b` / `e55cd391` 互异，`sha256sum` 独立复算一致 |

**实现期发现并修复**：`for /f … in ('"%JAVA_EXE%" -version …')` 以引号开头的命令串触发 cmd 的首尾引号剥离规则 → 报"文件名、目录名或卷标语法不正确"。修复为 `call` 直执行 + `>"%JV_TMP%" 2>&1` 落临时文件、`for /f` 读文件（`findstr` 在命令串开头，无引号问题）；四用例回归通过后回写 launcher 与 bootstrap.ps1 内嵌副本。

### Windows 真机（PowerShell 5.1 实跑 bootstrap.ps1，共四轮）

1. 首跑（旧装无 `.jre-version` marker）：TUNA 抓名 → `版本变更: unknown -> …25.0.5_8.zip` → 下载 55.87MB → 解压校验 → marker 落位 → `JRE: openjdk version "25.0.5" 2026-10-20 LTS`；jdtls marker 比较 `1.63.0` 命中跳过
2. 二跑：`already present and up to date (…25.0.5_8.zip), skipping`——全幂等、零下载
3. JRE 升级实付（三跑，TUNA 路线已切换最新）：`版本变更: …25.0.5_8.zip -> …25.0.5.1_2.zip` → 重装 → `JRE: openjdk version "25.0.5.1" 2026-11-17 LTS`——**marker 升级路径端到端实付**
4. jdtls SHA 负路径：摘 marker + `MAYOI_JDTLS_TGZ` 指向无关文件 → `SHA256 mismatch (expected …d018bdc4, got d8945996…)` exit 1，**现有 jdtls 目录字节未动**（校验先于删除）
5. jdtls SHA 好路径：官方包（51,143,565 B，与 PLAN 记载一致）独立复算哈希 == 钉死值 → 本地源 → `SHA256 verified` → 重装 → marker 回写 `1.63.0`
6. M-3 捷径：默认源缓存名（URL-key `9e944aead06a080b`）预置完整包 + 摘 marker → `Cached archive matches the pinned SHA256, skipping download`（老 curl `-C -` 416 边界消除）→ 校验 → 重装
7. LSP 冒烟 e2e（lsp-smoke.ps1，pwsh）：`SMOKE OK`，capabilities 全量；data 目录 `ci-smoke-ws-check-8f9d5e92`，`8f9d5e92` 与独立复算闭环一致；bootstrap 落位的 `bin\jdtls.bat` 与仓库文件行数/内容一致（含新逻辑）

### POSIX 真机（WSL2 Ubuntu 24.04 x64；/bin/sh = dash，bash 5.2；默认安装位 `~/.local/share/mayoi-java`）

- bootstrap.sh 全流程：首跑 JRE TUNA 抓名（`…25.0.5.1_2.tar.gz`）→ 解压校验交换 + marker（jdtls 下载中被打断）；二跑 `受管 JRE 已存在且版本匹配，跳过` → jdtls 下载 → `SHA256 校验（钉死值）通过` → 解压校验 → 交换 → `1.63.0 安装完成` → 启动器落位
- rc 追加负路径：目标 rc 目录不存在 → 写入失败 warn + 完成语降级，未触碰任何真实 rc；wrapper 落位随 PATH 未接入 warn（全程无 crash）
- LSP 冒烟 e2e（lsp-smoke.sh，bash 5.2）：`SMOKE OK`；data 目录 `smoke-ws-posix-a06bbb08`，`a06bbb08` = sha256(`/tmp/smoke-ws-posix`) 前 8 位闭环一致
- mayoi CLI 缺失 → 插件安装提示分支 ✓

### 观察与备注

- **TUNA 不同存储节点列表内容可能不同**（本机 curl 路线曾返回 25.0.5_8，服务端抓取路线同时段为 25.0.5.1_2，两日后本机路线亦切换）：marker 比较的最坏代价 = 一次有效 JRE 的重复安装（与 sh 侧既有口径相同）；`tuna_latest_name` / `Get-LatestJreName` 首匹配的"取尾防御"仍留待（当前每目录仅一个 zip，排序歧义未实际发生）
- **pwsh 7 实测 `Set-Location` 会传播到子进程 Win32 cwd**（.bat 的 `%CD%` = Set-Location 目标，由 data 目录名实证）——PLAN Task 1 Step 5 的"pwsh 不传播"注记适用于 Windows PowerShell 5.1 语境
- **本机 pwsh→bash 调用链会剥落内联命令的引号与 `$`**（本次 POSIX 隔离环境变量失效的根因，遂退化为默认安装位的真实用户场景）：WSL 本地测试应将脚本落盘执行，勿用长内联 `-c` 串
- PATH 注册表原始写入分支（kind 保持 + `WM_SETTINGCHANGE` 广播）未实付触发：本机用户 Path 已含 BinDir（追加分支跳过）且现有 kind 为 REG_SZ；实现为标准模式（`DoNotExpandEnvironmentNames` 读 + 按原 kind `SetValue` + `SendMessageTimeout` 广播），待有 `%var%` 条目环境再实证
- 清理：WSL 侧测试安装（`~/.local/share/mayoi-java`、`~/.cache/mayoi-java`）与临时文件已删除；Windows 侧为真实安装的就地升级，保留

### 遗留

- macOS 真机验证：由新增 CI `e2e-macos` job 覆盖（本机无 mac 设备）
- Adoptium API 回退分支（两侧）仍未实付验证（TUNA 持续可用）——口径同 v0.2
- `tuna_latest_name` 取尾防御（见观察；待 TUNA 实际列出多版本再定排序语义）
- 索引（mayoi-editor/plugins index.json）提交流程：PLAN Task 5，按用户指示留待最后执行
