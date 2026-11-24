# 上游建议草稿：LSP documentSymbol 与 codeAction 客户端支持

> 状态：**草稿，未提交**（提交需用户确认）。目标仓库：sorrycc/Mayoi。
> 依据：v0.23.3 源码（本机 F:\VibeCodingProject\Mayoi = 106341f）。
> 关联插件：HelloThreeLiu/mayoi-java（索引 PR mayoi-editor/plugins#1，待合并）。

## 建议 1：document 的语言有 LSP 服务器时，优先用 textDocument/documentSymbol 提供符号列表

现状（v0.23.3）：

- 面包屑点文件名的符号框（`cmd/mayoi/crumbsymbols.go`）与 Go → Go to Symbol
  （`cmd/mayoi/quickopen.go`）共用 `symbolsOf`（`cmd/mayoi/symbols.go`），来源是
  `internal/symbols.Find` 的**文本正则**（`declaration` 一条正则），与 LSP 无关。

对 Java 的实际影响（mayoi-java + jdtls 1.63.0 实测场景）：

- `public class Foo` / `interface` / `enum` 可命中（修饰符表含 public 等，关键字表含
  class/interface/enum）
- **方法全部不可见**：`public void foo(...) {` / `public int bar() {` 的声明词 `void`/`int`
  不在关键字表；`record` 也不在——而方法恰是 Java 符号导航的主体
- jdtls 本身有精确的层级 `textDocument/documentSymbol`，客户端未请求该能力
  （`internal/lsp/client.go` 无 documentSymbol 相关代码）

建议：文档语言的 LSP 服务器声明 `documentSymbolProvider` 时，符号列表优先取
`textDocument/documentSymbol`（层级 flat 化或按 children 展示均可），正则方案保留为
无 LSP 时的回退。缓存键已有 `{doc, version}`，并入语言维度即可。

## 建议 2：客户端请求 textDocument/codeAction（+ 可选 codeLens），接住 0.23.3 的 source actions

现状：

- 0.23.3 新增了插件 API「source actions above lines」（`cmd/mayoi/codelenses.go`）——
  插件可以把可点击动作钉在源码行上方，编辑/重载后自动清理
- 但 `internal/lsp/client.go` 未请求 `codeActionProvider`/`codeLensProvider`，
  语言服务器的动作数据到不了插件层

机会：Java 是这个组合的最大受益者——jdtls 自带 run/debug code lens（main 方法、
JUnit/TestNG 测试）。客户端请求 codeAction 后，语言类插件即可把服务器的 action
渲染成 source actions（或经 `go.*` 命令桥接），形成「打开 Java 文件即见 run/debug」
的开箱体验；lsp-smoke 层面 jdtls 的该能力已就绪。

## 证据

| # | 事实 | 来源 |
|---|---|---|
| F1 | 符号列表来源 = `internal/symbols.Find` 文本正则 | cmd/mayoi/symbols.go symbolsOf |
| F2 | declaration 正则关键字表无 void/int/record 等，Java 方法不命中 | internal/symbols/symbols.go |
| F3 | client.go 无 documentSymbol / codeAction 请求 | internal/lsp/client.go |
| F4 | jdtls 提供 documentSymbolProvider / codeActionProvider / codeLensProvider | jdtls 1.63.0 官方能力 |
| F5 | 插件侧无法自救：插件运行时（moejs）无进程/LSP 直连 API，服务器由宿主拉起 | docs/PLUGINS.md |
