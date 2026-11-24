# mayoi-java

![CI](https://github.com/HelloThreeLiu/mayoi-java/actions/workflows/ci.yml/badge.svg)

为 [Mayoi](https://github.com/sorrycc/Mayoi) 编辑器提供 Java 语言支持的插件，基于
[Eclipse JDT.LS (jdtls)](https://github.com/eclipse-jdtls/eclipse.jdt.ls)。

## 功能范围

由 Mayoi 宿主 LSP 客户端提供（本插件只是把 jdtls 接进来）：

- ✅ 诊断（Problems）、hover、跳转到定义（F12 / ⌘-click）、补全（⌃Space）、格式化
- ✅ 查找引用（Shift+F12）、转到实现（⌘/Ctrl+F12）、转到类型定义（无默认键，可自行绑定）
  —— 需 **Mayoi ≥ 0.23.1**（上游 #211；0.23.3 源码 `commands.go` 注册 + 本机
  `go test -run TestFindReferencesPicker` PASS）
- ❌ 重命名、document highlight、code lens（run/debug）—— 宿主客户端暂未实现这些 LSP 能力
  （前两者见 `PLUGIN-RULES.md` 第 1、3.3 章；code lens 需宿主请求 `textDocument/codeAction`，
  尚未实现，已拟上游建议，见 `docs/ISSUE-lsp-symbols-and-actions.md`）

宿主另有基于**文本解析**（非 LSP）的文件符号列表（面包屑点文件名 / Go → Go to Symbol，全语言通用）：
Java 的类/接口/枚举可列出，**方法暂不显示**（宿主声明关键字正则不含 Java 方法形态；
`textDocument/documentSymbol` 未接入，同见上游建议草稿）。

Java 语法高亮由 Mayoi 内置（Chroma lexer）提供，插件无需贡献语言定义。

## 前置要求

| 依赖 | 要求 | 说明 |
|---|---|---|
| Mayoi | >= 0.19.0 | 已在 Mayoi 0.23.1 完成真机验收 |
| 网络 | 初次使用 | 需联网下载约 105MB（受管 JRE 约 56MiB + jdtls 约 49MB） |

以下依赖由引导脚本自动满足（或已存在时自动跳过）：JDK/JRE 21+（最新 jdtls 需 25+，受管 JRE 25 随引导安装）、Python 3.9+（仅当使用你自装的官方 bin/jdtls 启动器时）、jdtls 1.63.0。

## 安装

一条命令（自动安装受管 JRE 25 + jdtls 1.63.0、免 Python 启动器并接入 PATH，约 105MB 下载：受管 JRE 约 56MiB + jdtls 约 49MB）：

```powershell
# Windows PowerShell
iwr -useb https://raw.githubusercontent.com/HelloThreeLiu/mayoi-java/main/bootstrap/bootstrap.ps1 | iex
```

```sh
# macOS / Linux
curl -fsSL https://raw.githubusercontent.com/HelloThreeLiu/mayoi-java/main/bootstrap/bootstrap.sh | sh
```

完成后重启 Mayoi，打开任意 `.java` 文件即可使用。已手动安装 jdtls/JDK 的用户可跳过引导——检测到 PATH 上已有 jdtls 时脚本会自动跳过运行时安装（见下“手动安装（进阶）”）。

## 更新

- Mayoi 内 **Plugins 页 → Update** 按钮，一键更新到最新版；
- 或在终端执行：

  ```sh
  mayoi plugin update java
  ```

> **注意（Windows）**：Mayoi **0.23.1 及更早**版本运行中更新会因插件目录被占用而失败（上游 issue
> [sorrycc/Mayoi#233](https://github.com/sorrycc/Mayoi/issues/233)）——请先**完全退出 Mayoi**
> 再执行更新，更新完成后重新启动。**该问题已随 Mayoi 0.23.2 修复**：0.23.2 起应用内 Update
> 在 Windows 上直接可用（原地 git 更新，不再 rename）。

> **说明**：Plugins 页的 **Update 按钮对所有 Git 来源安装的插件常驻显示**（宿主 UI 行为），
> 它只是"执行更新"的动作，**不代表有新版本**；真正的"有可用更新"会以独立小标签与通知提示，
> 判定依据是源仓库 HEAD 的 commit 是否前进（宿主每约 1 小时比对一次），与 `plugin.json`
> 的版本号无关。

## 手动安装（进阶）

不想用引导脚本的用户可按下列步骤手动安装：

1. 安装插件本体：

   ```sh
   mayoi plugin install HelloThreeLiu/mayoi-java
   ```

2. 安装 jdtls 与 JDK，并把 jdtls 的 `bin` 目录加入 PATH：
   - macOS：`brew install jdtls`
   - 其他平台：从 [官方 milestones](https://download.eclipse.org/jdtls/milestones/) 下载解压后将 `bin` 目录加入 PATH
   - JDK 21+（最新 jdtls 需 25+；jdtls 启动脚本强制校验，Java >= 24 时自动追加兼容参数，且优先使用 `JAVA_HOME` 指向的 JDK——请确保满足版本要求）
   - 官方 `bin/jdtls` 启动脚本为 Python 脚本，此路径需 Python 3.9+

3. Windows 下若宿主无法按名解析 `jdtls`，可在 Mayoi 设置里把 `plugins.java.path` 指向 `bin\jdtls.bat` 的完整路径（见下“设置”）。

## 卸载

1. 移除插件：

   ```sh
   mayoi plugin remove java
   ```

2. 删除受管运行时（约 240MB）：
   - Windows：`%LOCALAPPDATA%\mayoi-java`
   - macOS / Linux：`~/.local/share/mayoi-java`

3. 删除打开过的项目的 jdtls 工作区数据（每个项目的导入索引，长期使用可能比运行时还大）：
   - Windows：`%APPDATA%\mayoi-java\jdtls\`
   - macOS / Linux：`${XDG_CACHE_HOME:-~/.cache}/mayoi-java/jdtls/`

4. 清理 PATH 接入：
   - Windows：在系统“编辑账户的环境变量”里删除用户 PATH 中的 `...\mayoi-java\bin` 条目；
   - macOS / Linux：删除 `~/.local/bin/jdtls` wrapper（引导脚本写入的 PATH 副本）；若不再需要，
     可一并移除引导时追加到 rc 文件（`~/.zshrc` / `~/.bashrc`）的
     `export PATH="$HOME/.local/bin:$PATH"` 行（若该行系其他工具所加则保留）。

## 设置

设置挂在 `plugins.java` 下（settings.json）：

| 键 | 类型 | 默认 | 用途 |
|---|---|---|---|
| `path` | string | `jdtls` | jdtls 程序，按名字或路径（Windows 下若宿主无法按名解析，可设为 `bin\jdtls.bat` 的完整路径） |
| `jvmArgs` | array | `[]` | 语言服务器额外 JVM 参数（如 `["-Xmx1g"]` 限制堆上限）；后写胜出，可覆盖内置 `-Xms256m` |

也可在 settings.json 的 `languageServers` 下按服务器 id `java.server` 覆盖
`initializationOptions` 等（见官方 `docs/SETTINGS.md`）。

## 已知限制

- 受管运行时占用约 240MB 磁盘（实测；`%LOCALAPPDATA%\mayoi-java` / `~/.local/share/mayoi-java`）；删除该目录后重跑引导脚本即可重置。重跑引导脚本也会把受管 JRE 升级到 TUNA 上的最新 25.x（`.jre-version` marker 版本比较驱动）；受管 jdtls 同理按 marker 升级（随插件发布更新版本号）。
- Mayoi 0.23 的补全命令（Complete Word）默认无快捷键，建议在设置中自行绑定（如 Ctrl+Alt+Space），或经命令面板触发。
- JVM 内存：启动器内置参数只有 `-Xms256m`，无 `-Xmx`（JVM 默认上限 = 物理内存 1/4）。大项目用户建议设置 `plugins.java.jvmArgs = ["-Xmx1g"]` 限制堆上限（参数追加在内置项之后，后写胜出）。内存实测参考：小型项目空闲态工作集 ~270MB / 提交 ~460MB。
- 修改 `jvmArgs` 后需重启语言服务器（如重启 Mayoi）方对新启动的进程生效：Mayoi 的设置热加载仅对 `initializationOptions` 变更自动重启服务器，`args` 变更不在其列。

## 常见问题

**完全无反应 / 无补全快捷键？**
Mayoi 0.23 的补全命令（Complete Word）默认无快捷键：在设置中自行绑定（如 Ctrl+Alt+Space），
或经命令面板触发。

**首次打开项目较慢？**
jdtls 首次导入项目需要时间（本项目实测约 25s，大项目 160s+）。导入完成后，后续打开秒开。

**诊断/补全无响应，怎么排查？**
先看 jdtls 自己的日志 `<数据目录>/<项目目录名>-<8 位哈希>/.metadata/.log`（Windows 在 `%APPDATA%\mayoi-java\jdtls\` 下、macOS / Linux 在 `~/.cache/mayoi-java/jdtls/` 下；目录名 = 净化后的项目目录名 + 完整路径哈希后缀，用于隔离同名项目）。再用 **Plugins → Show Language Servers** 看服务器状态、**Show Plugin Log** 看宿主日志。改过 `plugins.java.path` / `jvmArgs` 后需重启语言服务器（重启 Mayoi 最彻底）。

**修改 `jvmArgs` 不生效？**
需重启语言服务器——重启 Mayoi 最彻底（原因见上“已知限制”）。

**JDK 8 用户需要升级 JDK 吗？**
不需要：jdtls 运行在插件自带的受管 JRE 25 上，你的 JDK 8 只用于运行自己的程序；
jdtls 内置的 ECJ 编译器支持 `release=8`，可正常分析老项目。

**Windows 安装/更新报 rename Access denied？**
先完全退出 Mayoi 再试——运行中的 Mayoi 占用插件目录（上游 issue
[sorrycc/Mayoi#233](https://github.com/sorrycc/Mayoi/issues/233)）。

**Plugins 页为什么一直显示「更新」按钮？**
该按钮对所有 Git 来源安装的插件**常驻显示**，不代表有新版本（真正的"有可用更新"会有
独立的小标签和通知，见上"更新"一节）。源仓库每前进一个 commit 就会触发一次提示，
与版本号无关。Mayoi 0.23.2 起点击 Update 即可原地更新（#233 已修复）；更早版本
请退出 Mayoi 后用 `mayoi plugin update java` 更新。

**Windows 上周期性闪黑色控制台窗口？**
与 Java/语言服务器无关（jdtls 启动链经实测无窗口）。这是 Mayoi 宿主对 Git 插件
**更新检查**的实现问题：应用启动约 30 秒后、之后每约 1 小时，宿主对每个 Git 来源
安装的插件执行一次 `git ls-remote`，而该 git 调用未加隐藏窗口标记（上游
[sorrycc/Mayoi#235](https://github.com/sorrycc/Mayoi/issues/235)，
`internal/plugin/install.go` 的 git 调用未走 `vfs.Command` 的隐藏窗口处理），
裸启动的 git 便闪一个控制台窗口——影响**所有** Git 来源安装的插件，插件侧无法规避。
上游已确认并修复（[sorrycc/Mayoi#235](https://github.com/sorrycc/Mayoi/issues/235)，
[c634faa](https://github.com/sorrycc/Mayoi/commit/c634faa)），**已随 Mayoi 0.23.2 发布**
（同版还包含 #233 的应用内更新修复）；0.23.2 起更新检查与安装不再闪控制台窗口，
应用内 Update 在 Windows 上也可用。

## 开发

```sh
mayoi plugin dev <本目录>   # 链接进 Mayoi，保存即热加载
```

打开任意 `.java` 文件，通过 **Plugins → Show Language Servers** 确认 `java.server`
被拉起，再验证诊断/补全/跳转。

- 开发规则与设计备忘：`PLUGIN-RULES.md`
- 实施计划：`docs/PLAN.md`
- 验收记录：`docs/VERIFICATION.md`

## 兼容承诺

- 语言服务器 id `java.server` 跨版本不变；
- `plugins.java.*` 设置键只增不删不改名；
- 破坏性变更升 major 版本并在此处说明。

## License

MIT
