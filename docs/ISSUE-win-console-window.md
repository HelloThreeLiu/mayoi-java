# Windows: plugin update checks (`git ls-remote`) flash a console window hourly — `internal/plugin`'s git is not run through `vfs.Command` (no CREATE_NO_WINDOW)

> 已提交：[sorrycc/Mayoi#235](https://github.com/sorrycc/Mayoi/issues/235)（2026-11-21）。
> 本文件为仓库留档，与线上 issue 内容一致（标题在提交时以 ASCII 连字符替代破折号）。

**TL;DR**: On Windows, the plugin system's own git calls are spawned with a raw
`exec.CommandContext`, without the `HideWindow` / `CREATE_NO_WINDOW` treatment that
`internal/git` gets via `vfs.Command`. Mayoi is a GUI-subsystem process, and Windows
gives every console program that a windowless process starts a console window of its
own — so the plugin update check (`git ls-remote`, first run ~30 s after start, then
hourly) flashes a black console window on the desktop for **every Git-installed
plugin**, even when the plugin is up to date. The `git clone`/`fetch` of an
install/update flashes the same window for longer. Fix: run `internal/plugin`'s git
through `vfs.Command` (or apply the same `SysProcAttr`).

## 环境

- Mayoi 0.23.1, windows/amd64（Windows 11，NT 10.0.26300；默认终端 = Windows Terminal，
  故闪现的窗口标题为 "Terminal"；默认终端为 conhost 的机器上是经典黑窗）
- 触发条件：装有**任意 Git 来源安装**的插件（复现用自写的 java 语言服务器插件，
  `mayoi plugin install HelloThreeLiu/mayoi-java`）；内置插件无安装记录，不受影响

## 现象

- Mayoi 启动约 30 秒后，桌面闪现一个控制台窗口，持续约 1~3 秒（`git ls-remote` 的网络往返时长）；
- 之后每约 1 小时复现一次；
- **插件已是最新时同样闪**（实测安装记录 commit == 源仓库 HEAD，`aa4fe55 == aa4fe55`）——
  检查本身无条件执行，不因"无更新"跳过；
- 应用内点 Update、或应用运行中终端执行 `plugin install` 时，clone/fetch 阶段黑窗更长
  （0.23.1 上随后因 #233 的 rename Access denied 失败）；
- 与语言服务器无关：jdtls 启动链（cmd → jdtls.bat → java）经实测**无**窗口（见下）。

## 根因

1. `cmd/mayoi/pluginsync.go` 的 `checkPluginUpdates()`：启动 30 秒后、之后每
   `pluginUpdateEvery = time.Hour` 跑一次 `findPluginUpdates()`，对 `plugin.ReadRecords`
   里的每个 Git 插件调 `plugin.Latest()` → `git ls-remote`：

   ```go
   timer := time.NewTimer(30 * time.Second)
   for range timer.C {
       h.findPluginUpdates()
       timer.Reset(pluginUpdateEvery)
   }
   ```

2. `internal/plugin/install.go` 的 `git()` 辅助函数**裸启动** git，未设置任何 SysProcAttr：

   ```go
   cmd := exec.CommandContext(ctx, "git", args...)
   ```

   `Install`/`Update` 的 clone/fetch/checkout 同样经它启动。

3. 对比：编辑器自身的 git（status/blame/history 等）经 `internal/git/git.go` 的
   `vfs.Command` → `internal/vfs/hidewindow_windows.go` 为每个命令设置
   `SysProcAttr{HideWindow: true, CreationFlags: CREATE_NO_WINDOW}`
   （#18，ce553d2，2026-10-16）。0.23.1 已包含 #18，但它只覆盖 `vfs.Command*`
   的调用方（含 LSP 启动链 `vfs.CommandEnvironment`）；`internal/plugin`
   自带的 git 辅助函数漏掉了同样的处理。

### 实证（GUI 子系统四组对照实验，隔离变量）

用 `-ldflags -H=windowsgui` 编译的**无控制台**测试进程（与 Mayoi 同类进程形态），
复刻两种启动方式拉起同样的命令，`EnumWindows` 每 100 ms 轮询新增可见窗口并按进程归属归类：

| 启动方式 | 对应 Mayoi 代码路径 | 结果 |
|---|---|---|
| 裸 `exec.Command` + `git ls-remote` | `internal/plugin/install.go` 的 `git()` | **t+0.1s 出现控制台窗口**（`WindowsTerminal.exe` "Terminal" + git.exe 的 `PseudoConsoleWindow`） |
| 同上 + `SysProcAttr{HideWindow, CREATE_NO_WINDOW}` | `internal/git` 经 `vfs.Command` | 运行 15 s，**零窗口** |
| 裸启动 jdtls.bat 链（cmd → bat → java） | ——（负向对照） | t+0.3s 出现同款控制台窗口 |
| 同上 + 同样的 `SysProcAttr` | `vfs.CommandEnvironment`（0.23.1 的 LSP 实际路径） | 运行 10 s，**零窗口** |

同一台机器、同一命令：走 `vfs` 的无窗口，裸启动的必现窗口。

## 复现步骤

1. Windows 上 `mayoi plugin install <owner/repo>`（任意 Git 插件）；
2. 启动 Mayoi，放置不动；
3. 约 30 秒后（及此后每小时）观察桌面：闪现一个控制台窗口
   （默认终端为 Windows Terminal 时标题 "Terminal"，conhost 时为黑窗）；
4. （可选）点该插件 Update：clone/fetch 阶段黑窗更长，随后因 #233 的
   rename Access denied 失败（0.23.1）。

## 修复建议

`internal/plugin/install.go` 的 `git()`（及同包其他裸启动子进程处）对齐 `internal/git`：
经 `vfs.Command` 创建命令；或最小改动——在该 `git()` 里同样设置
`SysProcAttr{HideWindow: true, CreationFlags: CREATE_NO_WINDOW}`（即 #18 的既有修法）。
Remote SSH 分支不受影响（Mayoi 不在 Windows 上触及 SSH 文件夹，同 #18 口径）。

## 附带说明

- 初看容易把黑窗误判到插件头上（如语言服务器的 .bat 启动器）——实验证明 LSP 链路在
  0.23.1 上无窗口。另建议顺手评估：Plugins 页的 **Update 按钮对 fromGit 插件一律常驻渲染**
  （`prefsplugins.go`，`if it.fromGit && !pl.Bundled`），与"有可用更新"的 pill/通知无关联，
  用户容易把按钮误读为"有新版本"的提示；若能按 `updateWaits` 条件显示或区分文案更佳（UX 建议，非缺陷）。
- 姊妹 issue：#233（应用内 Update 的 rename 失败）已由 cc5603d 修复、待发版；
  本 issue 的 clone/fetch 黑窗在其发版后仍会存在，需本修复覆盖。
- 复现实验与记录：mayoi-java 仓库 `docs/VERIFICATION.md`（上游反馈 2 一节）。
