# mayoi-java

为 [Mayoi](https://github.com/sorrycc/Mayoi) 编辑器提供 Java 语言支持的插件，基于
[Eclipse JDT.LS (jdtls)](https://github.com/eclipse-jdtls/eclipse.jdt.ls)。

## 功能范围

由 Mayoi 宿主 LSP 客户端提供（本插件只是把 jdtls 接进来）：

- ✅ 诊断（Problems）、hover、跳转到定义（F12 / ⌘-click）、补全（⌃Space）、格式化
- ❌ 查找引用、重命名、document highlight —— 宿主客户端暂未实现这些 LSP 能力，
  需等 Mayoi 核心支持（详见 `PLUGIN-RULES.md` 第 1、3.3 章）

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

## 设置

设置挂在 `plugins.java` 下（settings.json）：

| 键 | 类型 | 默认 | 用途 |
|---|---|---|---|
| `path` | string | `jdtls` | jdtls 程序，按名字或路径（Windows 下若宿主无法按名解析，可设为 `bin\jdtls.bat` 的完整路径） |
| `javaHome` | string | 空 | JDK 路径；空则自动探测（仅路径 B 使用） |
| `helperPath` | string | （路径 B 引入时定） | resolver helper 程序路径 |

也可在 settings.json 的 `languageServers` 下按服务器 id `java.server` 覆盖
`initializationOptions` 等（见官方 `docs/SETTINGS.md`）。

## 已知限制

- 受管运行时占用约 240MB 磁盘（实测；`%LOCALAPPDATA%\mayoi-java` / `~/.local/share/mayoi-java`）；删除该目录后重跑引导脚本即可重置。
- Mayoi 0.23 的补全命令（Complete Word）默认无快捷键，建议在设置中自行绑定（如 Ctrl+Alt+Space），或经命令面板触发。

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
