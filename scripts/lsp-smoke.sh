#!/usr/bin/env bash
# scripts/lsp-smoke.sh — jdtls stdio 冒烟测试：发送 initialize，等待含 capabilities 的响应
# 用法（在任意空目录下执行）: bash scripts/lsp-smoke.sh [jdtls 路径或名字] [data 目录]
set -euo pipefail

JDTLS="${1:-jdtls}"
DATA_DIR="${2:-${TMPDIR:-/tmp}/jdtls-smoke}"

init=$(printf '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":%d,"rootUri":"file://%s","capabilities":{}}}' "$$" "$PWD")
frame=$(printf 'Content-Length: %d\r\n\r\n%s' "${#init}" "$init")

coproc JDTLS { "$JDTLS" -data "$DATA_DIR"; }
printf '%s' "$frame" >&"${JDTLS[1]}"

length=""
while IFS= read -r line <&"${JDTLS[0]}"; do
  [ -z "$line" ] && break
  case "$line" in Content-Length:*) length="${line#Content-Length: }" ;; esac
done
[ -n "$length" ] || { echo "SMOKE FAIL: no Content-Length header" >&2; exec {JDTLS[1]}>&-; kill "$JDTLS_PID" 2>/dev/null || true; exit 1; }

body=""
IFS= read -r -N "$length" body <&"${JDTLS[0]}" || true
exec {JDTLS[1]}>&-
kill "$JDTLS_PID" 2>/dev/null || true

echo ">> response (first 500 chars):"
printf '%s\n' "${body:0:500}"
if [[ "$body" == *'"capabilities"'* ]]; then echo "SMOKE OK"; else echo "SMOKE FAIL: no capabilities" >&2; exit 1; fi
