# 验证记录

## 路径 A 冒烟验证（Task 1）— 2026-11-21 / Windows (NT 10.0.26300, x64) / jdtls 1.63.0 (202610191322) / JDK 21.0.4（PATH）/ Python 3.14.2

| 检查项 | 结果 | 备注 |
|---|---|---|
| stdio 启动（Step 4） | ⚠️ 阻塞 | 启动链路全部打通（cmd→bat→python→java→Equinox），但 jdtls 1.63.0 的 bundle 要求 JavaSE 25，本机 JDK 21 无法完成 OSGi 解析，服务未启动、未收到 initialize 响应。详见附录 A1 |
| 自动 -data 目录（Step 5） | ⚠️ 未测成 | 同上阻塞（OSGi 解析失败，-data 目录未被创建）。另实测发现官方脚本机制与计划预期不同：sha1 输入是**工作目录最后一段**而非 data 目录名，且该默认路径**仅在未传 `-data`** 时生效；冒烟脚本显式传了 `-data`，故不会产生 `%APPDATA%\jdtls\jdtls-<hash>`。详见附录 A2 |
| JDK 缺失报错（Step 6） | ✅ | 快速失败（秒级、exit 1、不挂死）。两种场景实测：① 完全无 java → Python traceback，末行 `FileNotFoundError: [WinError 2] 系统找不到指定的文件`（可读性一般）；② `JAVA_HOME` 指向 JDK 8 → 干净单行 `Exception: jdtls requires at least Java 21`（完全符合 validate-java-version 报错预期）。实际输出见附录 A3 |
| Windows .bat 经 cmd 可启动 | ✅（修正引号后） | 逐字脚本的 `/c "bat" -data "dir"`（4 个引号）必失败——cmd 对 `/c` 后多引号命令行做首尾引号剥离，报"文件名、目录名或卷标语法不正确"；改用 `/s /c ""bat" -data "dir""` 后成功拉起 bat 并进入 JVM 启动。证明宿主可用 cmd 语义拉起 jdtls.bat，但 Task 2 实现必须用修正后的引号形式。详见附录 A4 |

## 决策门结论

- [ ] 路径 A 全部通过 → 执行 Task 2 —— **未达成**（Step 4/5 被 jdtls 1.63.0 与 JDK 21 的版本不匹配阻塞）
- [ ] 存在失败项 → 跳过 Task 2 的 command 模式，先执行 Task 4（路径 B）—— **不建议就此跳过**：两项阻塞均为版本/JDK 匹配问题或冒烟脚本引号缺陷，**不是路径 A 机制本身的失败**（cmd→bat→python→java→Equinox 链路已被证明可走通）
- [x] **待决策后补验再过门**（超出任务文本的决策，上报控制器二选一）：
  - **方案 1**：本机安装 JDK 25（用户级），保留 jdtls 1.63.0（最新 milestone 官方基线已是 Java 25：jdt.ls README 主分支已改 "requires Java 25"，jdt.core 2025-09-22 构建起引入 JavaSE 25 依赖，见 jdt.ls issue #3537；Eclipse platform 亦有 "Require Java-25 for the Eclipse SDK" 提交）
  - **方案 2**：改用仍支持 Java 21 的较老 milestone（推断为 1.50.0 / 2025-09-04，位于 JavaSE 25 依赖引入之前），需重新下载安装到 `%LOCALAPPDATA%\Programs\jdtls` 并重跑 Step 4/5

  补验时的已知修正项（与是否采纳方案无关，均须落实）：
  1. 冒烟脚本 `scripts/lsp-smoke.ps1` 的 cmd 引号缺陷需改一行：`/c "..."` → `/s /c ""...""`（本仓库脚本按任务要求保持逐字未改，修正版验证副本在 `%TEMP%\lsp-smoke-fixed.ps1` 已证明可行）
  2. 本机 `JAVA_HOME=D:\Development\CodeDevEnvironment\Java\jdk1.8.0_202`（JDK 8），官方 jdtls.py 会**优先采用 JAVA_HOME 的 java** 而无视 PATH 上的 21.0.4 → 拉起 jdtls 时必须显式纠正（修正 JAVA_HOME、或传 `--java-executable <JDK21/25>\bin\java.exe`）。这是 Task 2 宿主实现的关键输入
  3. Step 5 判定口径按附录 A2 的真实机制执行：在**不传 `-data`** 的前提下于固定工作目录启动，验证 `%APPDATA%\jdtls\jdtls-<sha1(工作目录名)>` 生成与复用不新增

---

## 附录：实测证据

### A0. 环境与安装（Step 1）

- `java -version` → `java version "21.0.4" 2024-07-16 LTS`（PATH 首个 java 为 Oracle javapath shim，真实 `java.home = D:\Development\CodeDevEnvironment\Java\jdk-21`）
- **注意**：`JAVA_HOME = D:\Development\CodeDevEnvironment\Java\jdk1.8.0_202`（JDK 8，本机既有状态，本任务未修改）
- `python --version` → `Python 3.14.2`（`python3` 不存在，Windows 正常；实际解释器 `D:\Development\CodeDevEnvironment\Python\Python314\python.exe`）
- 安装前 `where.exe jdtls*` → 未找到（exit 1）
- 安装包：`jdt-language-server-1.63.0-202610191322.tar.gz`（51,143,565 字节 ≈ 48.77MB，官方 `https://download.eclipse.org/jdtls/milestones/1.63.0/`，用户手动下载提供；清华 TUNA 镜像 `/eclipse/jdtls/` 下无 milestones 目录、且不支持断点续传）
- `tar -tzf` 全量校验通过（137 个条目无错误），解压到 `%LOCALAPPDATA%\Programs\jdtls`（tar exit 0），`bin\`、`config_win\`、`plugins\` 就位
- **`bin\jdtls.bat` 实际内容（3 行）**：
  ```
  @echo off
  python "%~dp0/jdtls" %*
  pause
  ```
  与计划预期的两行核心内容（`python "%~dp0/jdtls" %*` + `pause`）一致，另含 `@echo off` 头。
- `bin\jdtls.py` 头部确认：`JAVA_HOME\bin\java.exe` 存在则优先使用；`--validate-java-version` 默认开启，`java_major_version < 21` 即抛 `jdtls requires at least Java 21`；支持 `--java-executable` 显式指定 java；`-data` 默认值为 `%APPDATA%\jdtls\jdtls-<sha1(cwd 目录名)>`

### A1. stdio 启动（Step 4）——阻塞于 JavaSE 25

执行（TEMP 修正引号副本 + 子进程级 JAVA_HOME 临时指向 JDK 21，未动注册表/系统设置）：

```
>> starting: cmd.exe /s /c ""C:\Users\10966\AppData\Local\Programs\jdtls\bin\jdtls.bat" -data "C:\Users\10966\AppData\Local\Temp\jdtls-smoke""
Exception: stdout closed before response; stderr: WARNING: Using incubator modules: jdk.incubator.vector
```

手动复现（stdin 给 EOF）stderr 仅有上述 WARNING；stdout 输出：

```
An error has occurred. See the log file
C:\Users\10966\AppData\Local\Programs\jdtls\configuration\1795223819784.log.
```

该 Equinox 日志关键内容：

```
org.osgi.framework.BundleException: Could not resolve module: org.eclipse.buildship.core [22]
  Unresolved requirement: Require-Bundle: org.eclipse.debug.core
    -> org.eclipse.debug.core [34]
         Unresolved requirement: Require-Bundle: org.eclipse.core.resources ...
           -> org.eclipse.core.resources [31]
                Unresolved requirement: Require-Bundle: org.eclipse.core.filesystem
                  -> org.eclipse.core.filesystem [28]
                       Unresolved requirement: Require-Capability: osgi.ee; filter:="(&(osgi.ee=JavaSE)(version=25))"
```

扫描 1.63.0 全部 plugin jar 的 MANIFEST.MF，JavaSE 要求分布：≤1.8 有 18 个、11 有 26 个、17 有 1 个、21 有 7 个、**25 有 1 个**（即 `org.eclipse.core.filesystem` 1.12.0.v20260927-0940）。虽然只有 1 个 bundle 要求 25，但 `core.filesystem` 位于 `jdt.ls.core` → `core.resources` 的主干依赖链上，OSGi 全链解析失败，框架无法启动。残留进程检查：无 java/python 残留；`%TEMP%\jdtls-smoke` 未被创建。

### A2. 自动 -data 目录（Step 5）——机制与计划预期不符（实测 `jdtls.py`）

```python
cwd_name = os.path.basename(os.getcwd())          # ← 哈希输入是"工作目录最后一段"
jdtls_data_path = os.path.join(cachedir, "jdtls-" + sha1(cwd_name.encode()).hexdigest())
parser.add_argument("-data", default=jdtls_data_path)  # ← 仅作默认值，显式传 -data 时被覆盖
```

- 计划预期"按 data 目录路径最后一段（jdtls-smoke）做 sha1"与官方实现不符
- 冒烟脚本显式传 `-DataDir %TEMP%\jdtls-smoke` → 不会生成 `%APPDATA%\jdtls\jdtls-<hash>`；实测冒烟后 `%APPDATA%\jdtls` 不存在，`%TEMP%\jdtls-smoke` 亦未创建（OSGi 失败所致）
- 补验口径：不传 `-data`，在固定目录（如 `jdtls-smoke-ws`）启动 → 预期生成 `%APPDATA%\jdtls\jdtls-<sha1("jdtls-smoke-ws")>`（本例预测值 `jdtls-016d45a7ed8cafebb478fd2e3d3ba2675f4c9c61`），同目录二次启动不新增第二个 `jdtls-<hash>` 目录

### A3. JDK 缺失/不可用报错（Step 6）——实际输出

① 字面场景：子进程 PATH 仅留 `C:\Windows\System32;C:\Windows`、删除 `JAVA_HOME`，用绝对路径 python 执行 `bin\jdtls`（stdin 给 EOF）→ **秒级失败，exit 1**，stderr 为 Python traceback，末行：

```
FileNotFoundError: [WinError 2] 系统找不到指定的文件。
```

（快速失败达标；报错形态是堆栈而非友好提示，末行含义可辨认。jdtls.py 的 `subprocess.check_output(['java','-version'])` 直接抛 FileNotFoundError，未做捕获。）

② 环境变体（本机真实状态，冒烟时自然触发）：`JAVA_HOME` 指向 JDK 8 时，**秒级失败**，报错干净可读：

```
Exception: jdtls requires at least Java 21
```

### A4. cmd 引号语义（冒烟脚本逐字版缺陷）

对照实验（.NET ProcessStartInfo 直传 Arguments，等价于宿主 cmd 拉起语义）：

| Arguments 形式 | 结果 |
|---|---|
| `/c "C:\...\hostname.exe" "arg1"` | ❌ stderr：`'C:\...\hostname.exe" "arg1' 不是内部或外部命令`（cmd 剥掉首尾引号） |
| `/s /c ""C:\...\hostname.exe" "arg1""` | ✅ 程序被正常执行 |

规则依据（`cmd /?`）：`/c` 后引号数**恰为 2** 且满足其余条件才保留引号，否则走旧行为"剥掉第一个和最后一个引号"。逐字脚本固定产出 4 个引号 → 在 Windows 上必然失败。修正版（`%TEMP%\lsp-smoke-fixed.ps1`，仅改一行）已打通至 JVM 启动阶段（见 A1）。
