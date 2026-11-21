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

## 冒烟脚本勘误（相对任务原文的三处修订，均已实测）

1. **cmd 引号修正**：`$psi.Arguments` 改为 `/s /c` + 整体外层引号对形式（见 A4）。注意：控制器下发的 `` "/s /c `"`"`"$Jdtls`" -data `"$DataDir`"`"" ``（3+2 引号）实测**不可行**——cmd /s 剥掉首尾引号后残留 `""bat"` 前缀报"不是内部或外部命令"；可行形式是 2+2：`` "/s /c `"`"$Jdtls`" -data `"$DataDir`"`"" ``。docs/PLAN.md 第 144 行如沿用 3+2 形式需同步修正。
2. **无 `-data` 模式**：`$DataDir` / `$DATA_DIR` 默认空串，为空时不追加 `-data` 参数（这正是 Mayoi 宿主的真实启动形态）。`lsp-smoke.sh` 用 `${DATA_DIR:+-data "$DATA_DIR"}` 等效实现（bash 3.2 兼容，规避空数组 + `set -u` 坑）。
3. **逐帧读取修正**：jdt.ls 在 initialize 响应前会先推送 `language/status` 等 notification（如 `{"type":"Starting","message":"Init..."}`），原单帧读取必然误判 FAIL。改为逐帧读取、跳过 notification，直到收到含 `"capabilities"` 的响应帧。两个脚本已同步修正。

---

## 附录：实测证据

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

- 每次冒烟结束由脚本 `taskkill /PID <cmd> /T /F` 清理进程树（输出"成功: 已终止 PID …"），事后核查无 java/python/curl 残留进程
- 冒烟产物：`%TEMP%\jdtls-smoke`（显式 data）、`%APPDATA%\jdtls\jdtls-b5794618…`（默认 data，保留供 Task 2 对照）——均属测试产物，不入库
