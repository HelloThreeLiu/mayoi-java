#!/usr/bin/env bash
# scripts/lsp-smoke.sh — jdtls stdio 冒烟测试：发送 initialize，等待含 capabilities 的响应
# 用法（在任意空目录下执行）: bash scripts/lsp-smoke.sh [jdtls 路径或名字] [data 目录]
# 需要 bash >= 4.0（coproc/read -N/{fd} 关闭语法）；macOS 自带 bash 3.2，请用 Homebrew bash
# 注意：读响应为阻塞式；长时间无输出即判定失败（Ctrl+C 结束）。stderr 已重定向到临时文件，失败时打印，成功后删除。
set -euo pipefail

JDTLS="${1:-jdtls}"
DATA_DIR="${2:-}"

command -v "$JDTLS" >/dev/null || { echo "SMOKE FAIL: '$JDTLS' not found" >&2; exit 1; }

init=$(printf '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":%d,"rootUri":"file://%s","capabilities":{}}}' "$$" "${PWD// /%20}")
frame=$(printf 'Content-Length: %d\r\n\r\n%s' "${#init}" "$init")

ERR_FILE="$(mktemp)"

echo ">> starting: $JDTLS${DATA_DIR:+ -data $DATA_DIR}"
coproc JDTLS { "$JDTLS" ${DATA_DIR:+-data "$DATA_DIR"} 2>"$ERR_FILE"; }
printf '%s' "$frame" >&"${JDTLS[1]}"

length=""
body=""
while true; do
  length=""
  while IFS= read -r line <&"${JDTLS[0]}"; do
    line="${line%$'\r'}"   # LSP header 以 \r\n 结尾，bash read 只剥 \n，须手工剥 \r
    [ -z "$line" ] && break
    case "$line" in Content-Length:*) length="${line#Content-Length: }" ;; esac
  done
  [ -n "$length" ] || { echo "SMOKE FAIL: no Content-Length header; stderr:" >&2; cat "$ERR_FILE" >&2 || true; exec {JDTLS[1]}>&-; kill "$JDTLS_PID" 2>/dev/null || true; exit 1; }
  IFS= read -r -N "$length" body <&"${JDTLS[0]}" || true
  # jdt.ls 在 initialize 响应之前会先推送 language/status 等 notification，逐帧跳过直到收到响应帧
  [[ "$body" == *'"capabilities"'* ]] && break
done
exec {JDTLS[1]}>&-
# 杀 coproc 进程即可：POSIX 下 jdtls.py 对 java 走 execvp 原位替换（同一 PID），不存在进程树可杀，
# 因此不等价于 Windows taskkill /T；残留风险仅限理论上嵌套更深的子进程
kill "$JDTLS_PID" 2>/dev/null || true
wait "$JDTLS_PID" 2>/dev/null || true   # 同步收割，避免 bash 打印 "Terminated" 任务通知

echo ">> response (first 500 chars):"
printf '%s\n' "${body:0:500}"
if [[ "$body" == *'"capabilities"'* ]]; then rm -f "$ERR_FILE"; echo "SMOKE OK"; else echo "SMOKE FAIL: no capabilities; stderr:" >&2; cat "$ERR_FILE" >&2 || true; exit 1; fi
