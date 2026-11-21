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

| 依赖 | 版本 | 说明 |
|---|---|---|
| Mayoi | >= 0.19.0 | 最低版本下界待核对；已在 Mayoi 0.23.1 完成真机验收 |
| JDK | 21+（jdtls 1.51+ 需 25+） | jdtls 1.51+ 需 JDK 25+，约 1.50.0 及更早需 21+（截至本验证时点）。jdtls 启动脚本强制校验（Java >= 24 时脚本自动追加兼容参数）。jdtls 官方启动脚本优先使用 `JAVA_HOME` 指向的 JDK——请确保它满足上述版本要求 |
| Python | 3.9+ | 路径 A（当前版本的唯一启动方式，各平台均需；官方 `bin/jdtls` 启动脚本为 Python 脚本） |
| jdtls | 1.9.0+（本机验证 1.63.0） | macOS: `brew install jdtls`；其他平台从 [官方 milestones](https://download.eclipse.org/jdtls/milestones/) 下载解压后将 `bin` 目录加入 PATH；或在 Mayoi 设置里把 `plugins.java.path` 指向 `bin\jdtls.bat` 的完整路径 |

## 安装

```sh
mayoi plugin install HelloThreeLiu/mayoi-java
```

## 设置

设置挂在 `plugins.java` 下（settings.json）：

| 键 | 类型 | 默认 | 用途 |
|---|---|---|---|
| `path` | string | `jdtls` | jdtls 程序，按名字或路径（Windows 下若宿主无法按名解析，可设为 `bin\jdtls.bat` 的完整路径） |
| `javaHome` | string | 空 | JDK 路径；空则自动探测（仅路径 B 使用） |
| `helperPath` | string | （路径 B 引入时定） | resolver helper 程序路径 |

也可在 settings.json 的 `languageServers` 下按服务器 id `java.server` 覆盖
`initializationOptions` 等（见官方 `docs/SETTINGS.md`）。

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
