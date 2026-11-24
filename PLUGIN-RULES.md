# Mayoi Java 插件 — 开发规则与设计备忘

> 目标：为 [Mayoi](https://github.com/sorrycc/Mayoi) 编辑器提供 Java 语言支持
> （基于 Eclipse JDT.LS / jdtls）。
>
> 本文整理自 Mayoi 官方文档 `docs/PLUGINS.md`、`docs/PLUGINS-DESIGN.md`、
> `internal/plugin/agents.md` 及内置插件源码（`plugins/gopls`、`plugins/basedpyright`），
> **第 1–3 章为官方硬性规则**，以官方文档为准；**第 4 章及以后为本插件的设计建议**，
> 标注"待验证"的内容需实测确认。

---

## 1. 总体结论：独立项目，不 fork Mayoi

- 插件从设计上就是独立 Git 仓库，通过 `mayoi plugin install owner/repo` 安装，与 Mayoi 本体零耦合。
- Mayoi 内置插件（Word Count、TODOs、各语言服务器）只是"随编辑器出厂的例子"，与第三方插件
  使用**完全相同的 API**，没有特权接口。
- 官方索引（`mayoi-editor/plugins` 仓库的 `index.json`）明确接受第三方语言服务器插件，
  并为其设计了自动探测与引导安装的体验链路（见第 6 章）。
- 只有当需要**修改 Mayoi 核心能力**时才需要向官方提 PR / fork。已知与 Java 插件相关的核心能力面
  （2026-11-24 依 **0.23.3 源码**修订，原文档 `docs/PLUGINS-DESIGN.md` 的声明已过时，以
  `internal/lsp/client.go` 能力初始化与 `cmd/mayoi/commands.go` 命令注册为准）：
  LSP 客户端做 diagnostics、hover、definition、completion、formatting，以及
  **typeDefinition / implementation / references**（0.23.1 起，上游 #211：
  `go.typeDefinition` 无默认键、`go.implementation` ⌘/Ctrl+F12、`go.references` Shift+F12）；
  **rename 与 document highlight 仍未实现**；codeAction/codeLens、documentSymbol 也未请求
  （面包屑符号列表与 Go to Symbol 为 `internal/symbols` 文本正则实现，非 LSP）。

---

## 2. 插件通用硬性规则

### 2.1 插件形态

一个插件 = 一个文件夹：

```
mayoi-java/
  plugin.json    # 清单（必需）
  main.ts        # 入口（纯 LSP 声明式插件可以没有，见 2.5 与 4.1）
  mayoi.d.ts     # API 类型文件（由脚手架生成，供编辑器补全）
  helper/        # 本插件自用：jdtls 启动辅助脚本（设计见 4.2）
```

### 2.2 命名与 ID 规则

| 规则 | 说明 |
|---|---|
| 插件 `name` | 仅小写字母、数字、连字符，如 `java` |
| 所有 ID | 必须以插件名开头加 `.`，如 `java.server` |
| 保留前缀 | `file`、`edit`、`view`、`git` 等宿主前缀不可用 |
| 服务器 `id` 稳定性 | 语言服务器 id 必须跨版本保持不变，用户按 id 覆盖配置 |

### 2.3 运行时环境（moejs，不是 Node）

插件 JS/TS 运行在 Mayoi 自研引擎 [moejs](https://github.com/MoeForge/moejs) 中，
TypeScript 原生运行、无构建步骤。

**有**：`mayoi` 模块、`console`（输出进插件日志）、`fetch`、`Request`/`Response`/`Headers`、
`URL`、`URLSearchParams`、Streams、`AbortController`、`setTimeout`、`setInterval`、
`queueMicrotask`、按相对路径导入自己的文件（可带可不带扩展名）。

**没有**：`require`、`node:` 模块、运行时 npm 包、`eval`、`new Function`。

需要 npm 包时：在插件目录 `npm install` 后运行 `mayoi plugin pack`，
它把代码 import 到的 ESM 产物拷入 `vendor/` 并改写导入路径。
**纯 CommonJS 包无法运行。**

### 2.4 资源预算（超出即被强制中断）

| 项目 | 上限 | 触发后果 |
|---|---|---|
| 激活 | 2 秒 | 启动失败并记录日志 |
| 单个命令 / 事件回调 | 10 秒 | 中断，该次调用失败 |
| `onWillSave` | 1 秒 | 文件照常保存（fail-open） |
| 单文件加载 | 1 MiB | 不编译不加载 |
| 每插件内存 | 256 MiB | 中断，运行时重建 |
| 连续崩溃 | 3 次 | 插件被禁用，需 **Plugins → Reload Plugins** |
| LSP resolve + initialize | 共 30 秒 | 服务器启动失败（见 3.2） |

### 2.5 激活机制

`activation` 声明启动时机：`onCommand:<id>`、`onLanguage:<lang>`、`workspaceContains:<glob>`、
`onView:<id>`、`onPreview:<id>`、`onStartup`、`*`（任意）。

- 激活前宿主只读清单：命令已在命令面板可见、快捷键已生效，首个触发事件才真正启动插件。
- 语言名 = 高亮器（Chroma）的名称小写，如 `java`。
- **纯语言服务器插件可以不写 `activation` 也可以没有 `main`**——官方内置的
  `gopls`、`basedpyright` 等就是"仅清单"（manifest-only）插件，
  宿主按 `contributes.languageServers.languages` 在相应文档打开时启动服务器。

### 2.6 编辑与坐标

- 所有触达编辑器的 API 调用返回 **Promise**。
- 位置 = `{ line, character }`，UTF-16 code units，均从 0 起（与 JS 字符串和 LSP 一致）。
- `edit(edits, {version})` 必须携带读文本时的文档版本；期间文档变了则编辑被丢弃、
  返回 `false`（乐观锁）。成功的编辑是一次撤销步骤。

### 2.7 UI 与快捷键

- 侧边栏视图用 `views.render(id, tree)` 提交**声明式节点树**，宿主以原生控件绘制；
  `webviews`（HTML 面板）是逃生舱而非默认。
- 插件声明的快捷键只在**该键空闲**时生效（不与宿主默认命令、用户 keybindings.json 冲突）；
  被占用的键会在设置窗口 Plugins 页提示。

### 2.8 文件与进程的 SSH 透明性

插件代码永远跑在**本机**；`workspace.*` 与 `process.run` 路由到文件夹所在机器
（本地或 SSH 远端）。语言服务器也启动在文件夹所在机器上。

### 2.9 信任模型

- 插件与设置一样被**完全信任**：无权限弹窗，以用户身份运行，**不是安全沙箱**。
- 项目级插件（`.mayoi/plugins`）不会被执行——克隆仓库永远不触发代码执行。
- 不兼容 VS Code 扩展 API；只借用其**格式**：keybindings、themes、snippets。

---

## 3. 语言服务器插件规则（本插件的核心）

### 3.1 基本声明

```jsonc
"languageServers": [{ "id": "java.server", "languages": ["java"], "command": "jdtls" }]
```

- 服务器在**该语言的文档打开时**由宿主启动（在文件夹所在机器）。
- LSP 报告的语言名按协议标准：Java 即 `"java"`（对照：C++ 是 `cpp`，`.jsx/.tsx` 是
  `javascriptreact`/`typescriptreact`）。
- `command` 与 `args` 支持 `${settings.key}` 插值；
  一个**整体**为 `type: "array"` 设置的参数会展开为多个字符串参数。
- 服务器崩溃或无法启动时，宿主会在该语言的文档再次打开时重试数次；
  彻底失败会说明原因（程序未安装 / 进程退出 / 无响应）并提供 **Restart**。

### 3.2 `resolve` 机制（jdtls 大概率需要）

jdtls 不像 `gopls` 那样一条命令即可启动（需要 JDK、按项目隔离的 workspace 数据目录等），
此时用 `resolve` 代替 `command`：

```jsonc
"languageServers": [{
  "id": "java.server", "languages": ["java"],
  "resolve": { "command": "${settings.helperPath}", "args": ["resolve"] }
}]
```

resolver 协议（官方规则，逐条）：

1. **运行时机**：服务器每次启动前运行一次，运行在 workspace 所在机器上。
2. **stdin 输入**：JSON `{root, settings}` —— `root` 为宿主机绝对路径；
   `settings` 只含用户**显式保存过**的插件设置（**不含**清单里的默认值，
   resolver 必须自己兜底默认值）。
3. `${settings.key}` 插值在 resolver 命令与参数中同样可用，以"已存设置 + 清单默认值"兜底；
   插值按字面量传参，**绝不经过 shell**。
4. **stdout 输出**：必须打印**一个 JSON 对象**并以退出码 0 结束：

   ```jsonc
   {
     "command": "java",                        // 必需；宿主直接启动它
     "args": ["-jar", "…"],                    // 可选
     "env": { "JAVA_HOME": "…" },              // 可选；覆盖继承的环境变量
     "unsetEnv": ["…"],                        // 可选；在 workspace 主机上移除变量
     "initializationOptions": {},              // 可选
     "configuration": { "java": {} },          // 可选；按点分段应答 workspace/configuration
     "workspaceFolders": [{ "uri": "file:///…", "name": "…" }], // 可选；第一个提供 rootUri
     "pathMappings": [{ "clientURI": "file:///…", "serverURI": "file:///…" }] // 可选
   }
   ```

5. `workspaceFolders` 与 `pathMappings` 必须使用**绝对 `file:` URI**；
   映射双向生效、按完整路径段匹配、最长优先，覆盖 LSP 已知的文档/工作区/定义/诊断 URI 字段
   （含 workspace edits 内的键）。
6. resolve 与 initialize **共享 30 秒时限**；保持快速且离线——**依赖安装不属于 resolver**，
   应放在单独的 setup 命令中。

### 3.3 宿主提供的 LSP 能力范围

由宿主统一提供：诊断（Problems + 状态栏计数 + 光标行消息）、hover、go to definition
（F12 / ⌘-click）、**go to references（Shift+F12）/ go to implementation（⌘/Ctrl+F12）/
go to type definition（无默认键）**（以上三项 0.23.1 起，#211）、补全（⌃Space）、
formatting（仅当没有插件为该语言注册 formatter 时）。
**不提供**：rename、document highlight、codeAction/codeLens、documentSymbol 等其余 LSP 能力
（面包屑符号列表与 Go to Symbol 为 `internal/symbols` 文本正则实现，非 LSP——Java 类/接口/枚举
可见、方法不可见）。
> 修订记录：2026-11-24 依 0.23.3 源码修订本节——0.23.1（#211）已加入 references/implementation/
> typeDefinition；此前本节引用的 `docs/PLUGINS-DESIGN.md`「references 未做」为过时声明。

### 3.4 用户覆盖配置

用户可在 settings.json 的 `languageServers` 键下按服务器 `id` 覆盖
`initializationOptions` 等（见官方 `docs/SETTINGS.md`）。这也是服务器 id 必须稳定的原因。

---

## 4. Java 插件设计（建议，非官方规则）

### 4.1 plugin.json 骨架

内置 `gopls` 插件为本插件的直接参照：

```jsonc
{
  "name": "java",
  "displayName": "Java",
  "version": "0.1.0",
  "description": "Go to Definition, hovers, completions and problems in Java files, with jdtls",
  "author": "",
  "mayoi": ">=0.19.0",            // 按实际使用的 API 能力核对最低版本
  "enabled": true,                // 或 false 交由设置开启（内置语言插件默认 off）
  "contributes": {
    "settings": {
      "path": { "type": "string", "default": "jdtls", "description": "The jdtls program, by name or path" }
    },
    "languageServers": [
      // v1 先走最简路径：命令模式（若 4.2 的验证通过）
      { "id": "java.server", "languages": ["java"], "command": "${settings.path}",
        "install": "brew install jdtls" }
    ]
  }
}
```

说明：

- Java 语法高亮由 Chroma 内置 lexer 提供，**无需**贡献 `languages`（待验证：
  确认 `lineComment` 等是否需要显式声明）。
- 若必须走 resolver 路径，`command` 换为 `"resolve": { … }`，并增加
  `helperPath` 一类的设置项指向辅助脚本。

### 4.2 启动方式：两条路径，先验证再定

**路径 A（优先验证）：直接命令模式。**
eclipse.jdt.ls 自 1.9.0 起附带 `bin/jdtls` 启动脚本，能自动处理 configuration 与
按项目的 `-data` workspace 目录。若验证满足——

- [ ] `jdtls` 在 PATH 时能以 stdio 模式启动（不接 GUI）；
- [ ] 对打开的文件夹能自动创建/复用 workspace 数据目录；
- [ ] 在 macOS / Windows / Linux 三平台行为一致（Windows 下确认可执行名与调用方式）；
- [ ] 无 JDK 或 JDK 版本不足时的报错路径可接受；

则 `command: "${settings.path}"` 即可，插件可以**零 JS 代码**（纯清单）。

**路径 B（兜底）：resolve 模式。** 路径 A 验证不通过时，提供 helper（脚本或小 jar），
按 3.2 的协议实现：

1. 读 stdin `{root, settings}`，未存设置时自行兜底；
2. 定位 JDK（`JAVA_HOME` → `java.home` 设置 → PATH `java`，测 `java -version` ≥ 17，待验证目标版本）；
3. 为 `root` 派生并复用 workspace 数据目录（如 `~/.cache/mayoi-java/<hash(root)>`）；
4. 组装 `{command, args, env, initializationOptions}`（含 configuration、bundle 等按需）；
5. 打印单个 JSON 对象，退出 0。

resolver 必须快速且离线（30 秒时限与 initialize 共享）；下载/安装依赖绝不放在 resolver 里。

### 4.3 设置项规划（挂在 `plugins.java` 下）

| 键 | 类型 | 默认（建议） | 用途 |
|---|---|---|---|
| `path` | string | `jdtls` | jdtls 程序，按名字或路径 |
| `javaHome` | string | 空 | JDK 路径；空则自动探测 |
| `helperPath` | string | 视路径 B 而定 | resolver helper 程序 |

设置类型仅 `boolean` / `number` / `string` / `array`（字符串数组），可用 `enum`。

### 4.4 已知能力边界（如实告知用户）

- ✅ 诊断、hover、定义跳转、补全、格式化（宿主 LSP 客户端提供）
- ✅ 查找引用 / 转到实现 / 转到类型定义（Mayoi ≥ 0.23.1 起宿主提供，#211）
- ❌ 重命名、document highlight（宿主客户端暂未实现，需核心支持，见第 1 章）
- ❌ code lens（run/debug）、LSP documentSymbol（宿主未请求相应能力；符号列表为文本正则，
  Java 方法不可见——已拟上游建议，见 `docs/ISSUE-lsp-symbols-and-actions.md`）
- Gradle/Maven 复杂项目的 import 行为取决于 jdtls 自身与 initializationOptions，
  属"待验证"范围，v1 不做承诺。

---

## 5. 开发工作流

```sh
# 生成脚手架（在任意空目录执行；本目录已有文档，可将生成的文件合并进来，
# 或直接手写 plugin.json 等三个文件）
mayoi plugin new java

# 热加载开发：链接本文件夹进 Mayoi，保存即重载
mayoi plugin dev <本目录>

# 单测某个命令（纯 LSP 插件通常用不到）
mayoi run <command-id>
```

- 本地安装目录：`~/.mayoi/plugins/<name>/`（Windows 即 `%USERPROFILE%`；
  设了 `MAYOI_DATA_DIR` 则在其中）。
- 调试入口：
  - **Plugins → Show Plugin Log** —— 插件日志与错误，可按插件/级别/文本过滤；
  - **Plugins → Show Running Plugins** —— 各插件状态、CPU 时间、内存、崩溃率；
  - **Plugins → Show Language Servers** —— 服务器列表、运行位置、重启；
  - `mayoi --disable-plugins` —— 只带内置插件启动，排查冲突。
- 测试 Java 支持的最短路径：`mayoi plugin dev` 后打开任意 `.java` 文件，
  观察语言服务器是否被拉起、诊断/补全是否工作。

---

## 6. 发布清单

1. [ ] 推送到 GitHub 仓库（如 `you/mayoi-java`）；
2. [ ] 本地验证 `mayoi plugin install you/mayoi-java` 全流程可用；
3. [ ] 向 [mayoi-editor/plugins](https://github.com/mayoi-editor/plugins) 的 `index.json`
      提 PR 增加条目（带语言服务器插件的额外字段）：

   ```json
   { "name": "java", "displayName": "Java", "description": "Java with jdtls",
     "repository": "https://github.com/you/mayoi-java",
     "languages": ["java"], "detect": "jdtls", "install": "brew install jdtls" }
   ```

4. [ ] `install` 字段为程序缺失时展示给用户的安装提示命令（官方示例为单条字符串，
       `install`/`detect` 需真实可执行）；
5. [ ] 上索引后的官方链路：用户打开 `.java` 文件 → Mayoi 按 `detect` 在文件夹所在机器找
       `jdtls` → 找到则一次性提示安装本插件；没找到则一次性提示如何安装 jdtls，
       并在一分钟后的文档打开时重查；
6. [ ] 跨版本保持语言服务器 `id`（`java.server`）不变。

---

## 7. 参考索引（Mayoi 仓库内路径）

| 文件 | 内容 |
|---|---|
| `docs/PLUGINS.md` | 插件作者指南（权威规则来源） |
| `docs/PLUGINS-DESIGN.md` | 设计与实现差异（能力边界、预算表） |
| `docs/SETTINGS.md` | 用户设置细节（`plugins.<name>`、`languageServers` 覆盖） |
| `internal/plugin/agents.md` | 官方给插件的 agent 备忘（运行模型摘要） |
| `plugins/gopls/plugin.json` | 语言服务器插件的最小范本 |
| `plugins/basedpyright/plugin.json` | 带参数的语言服务器范本 |
| `plugins/word-count/`、`plugins/todos/` | 事件/状态栏/视图 API 的完整 JS 范例 |
