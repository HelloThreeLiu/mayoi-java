#!/bin/sh
# bootstrap.sh — mayoi-java 一键引导（macOS / Linux）
# 用法: curl -fsSL https://raw.githubusercontent.com/HelloThreeLiu/mayoi-java/main/bootstrap/bootstrap.sh | sh
# 可选环境变量:
#   MAYOI_JDTLS_TGZ=<本地 tar.gz 路径 或 自定义 URL>
#     （eclipse.org 国内较慢；可先手动下载 jdt-language-server-1.63.0-*.tar.gz，再把它指向本地文件。
#      本地相对路径基于当前目录解析）
#   MAYOI_INSTALL_DIR=<安装根目录>（默认 ~/.local/share/mayoi-java；可覆盖便于测试）
# 幂等：受管 JRE / jdtls（marker 文件带版本比较）/ PATH / 插件 已就绪时，对应步骤自动跳过；
#       安装/升级一律"先解压到 <安装目录>/.tmp-extract 校验、成功才交换"，绝不在校验前删除现有安装。
# POSIX sh（/bin/sh 兼容，无 bash 特性）。curl 统一 -fsSL -C - --retry 3 --retry-delay 2
# （macOS 老 curl 不识别 --ssl-no-revoke，故不加）。
# local 用法依赖：dash / ash(busybox) / mksh / bash / zsh 均支持函数内 local；
# ksh93 的 POSIX 模式不支持 —— 如需 ksh93 兼容，移除各函数内 local 声明即可（变量全局化不影响正确性）。
# 下载缓存与解压中间物一律落 <安装目录>/.cache（per-user 私有域，不用共享 /tmp，与 Windows 侧
# bootstrap.ps1 用 per-user %TEMP% 的做法对称）。
# PATH 副本（~/.local/bin/jdtls）是 wrapper（绝对路径转发 exec 正本），不是字节拷贝 ——
# 正本按 $0 相对路径解析 ../jre 与 ../jdtls，字节拷贝会解析错位。
set -eu

step() { printf '== %s\n' "$1"; }
warn() { printf '   [警告] %s\n' "$1"; }
die()  { printf 'mayoi-java: %s\n' "$1" >&2; exit 1; }

# HOME 未设 → 无法确定安装目录（M-7）
[ -n "${HOME:-}" ] || die "环境变量 HOME 未设置，无法确定安装目录（请在登录 shell 中重跑本脚本）"

INSTALL_DIR="${MAYOI_INSTALL_DIR:-$HOME/.local/share/mayoi-java}"
BIN_DIR="$INSTALL_DIR/bin"
JRE_DIR="$INSTALL_DIR/jre"
JDTLS_DIR="$INSTALL_DIR/jdtls"
EXTRACT_DIR="$INSTALL_DIR/.tmp-extract"
CACHE_DIR="$INSTALL_DIR/.cache"    # I-2: 私有缓存域（替代共享的 /tmp/mayoi-java-bootstrap）
mkdir -p "$BIN_DIR" "$CACHE_DIR" || die "无法创建安装目录 $INSTALL_DIR（权限不足？）"

JDTLS_VERSION="1.63.0"
# 钉死源哈希：jdtls tar.gz 为全平台同一产物（来源：Task 1 验收时 tar -tzf 全量校验通过的官方包，
# 51,143,565 bytes）。哈希不匹配即失败，绝不落盘安装。
JDTLS_SHA256="b1f2abe0b3cccb462cf64fb4a5587c7d09df60cf8be7748b152cbd89d018bdc4"
JDTLS_URL="https://download.eclipse.org/jdtls/milestones/1.63.0/jdt-language-server-1.63.0-202610191322.tar.gz"

# ---- 平台矩阵（JRE 下载目标；Git Bash/MINGW 落 *) linux 分支，仅用于流程冒烟）----
case "$(uname -s)" in
    Darwin) plat_os="mac" ;;
    *)      plat_os="linux" ;;
esac
# 显式架构白名单（M-5）：i686/armv7l 等不再静默下载不可运行产物
case "$(uname -m)" in
    x86_64|amd64)      plat_arch="x64" ;;
    aarch64|arm64)     plat_arch="aarch64" ;;
    *) die "不支持的 CPU 架构: $(uname -m)（仅支持 x86_64/amd64 与 aarch64/arm64）" ;;
esac
TUNA_DIR="https://mirrors.tuna.tsinghua.edu.cn/Adoptium/25/jre/$plat_arch/$plat_os/"
# 回退源为浮动 latest（302 → 官方 CDN），无法钉死哈希 —— 与 Windows 侧 bootstrap.ps1 的 M6 结论
# 同口径声明；jdtls（固定产物）已钉死 SHA256。
JRE_API_URL="https://api.adoptium.net/v3/binary/latest/25/ga/$plat_os/$plat_arch/jre/hotspot/normal/eclipse?project=jdk"

# 统一 curl 参数（断点续传 + 重试）
fetch() { curl -fsSL -C - --retry 3 --retry-delay 2 -o "$1" "$2"; }

# TUNA 目录页抓取最新 JRE 文件名（M-6，归拢重复逻辑；失败 → 空）
tuna_latest_name() {
    curl -fsSL "$TUNA_DIR" | grep -o 'OpenJDK25U-jre_[^"]*\.tar\.gz' | head -n 1 || true
}

# ---- 哈希工具探测（M-4）：sha256sum → shasum -a 256 → openssl dgst -sha256 ----
SHA_KIND=""
if command -v sha256sum >/dev/null 2>&1; then
    SHA_KIND="sha256sum"
elif command -v shasum >/dev/null 2>&1; then
    SHA_KIND="shasum"
elif command -v openssl >/dev/null 2>&1; then
    SHA_KIND="openssl"
fi

# 输出 $1 的小写十六进制 SHA256；工具缺失时输出空串
sha256_of() {
    case "$SHA_KIND" in
        sha256sum) sha256sum "$1" | cut -d' ' -f1 ;;
        shasum)    shasum -a 256 "$1" | cut -d' ' -f1 ;;
        openssl)   openssl dgst -sha256 "$1" | awk '{print $NF}' ;;
        *) : ;;
    esac
}

# M-3 捷径判定：缓存文件非空且哈希命中钉死值
jdtls_cache_ok() {
    [ -n "$SHA_KIND" ] || return 1
    h=$(sha256_of "$1") || return 1
    [ "$h" = "$JDTLS_SHA256" ]
}

# ---- 0. 已有 jdtls 检测（幂等矩阵第一行：PATH 上已有非受管 jdtls → 全跳过，仅保留插件步骤）----
# 受管启动器（$INSTALL_DIR/bin/jdtls 及其 ~/.local/bin PATH wrapper）不算"外部" jdtls。
skip_runtime=false
existing_jdtls=$(command -v jdtls 2>/dev/null || true)
if [ -n "$existing_jdtls" ] && [ -x "$existing_jdtls" ]; then
    case "$existing_jdtls" in
        "$INSTALL_DIR"/*|"$HOME/.local/bin/jdtls") ;;
        *)
            skip_runtime=true
            echo "检测到现有 jdtls: $existing_jdtls —— 跳过运行时安装。"
            echo "若其无法启动（需 Python+JDK25），可删除它后重跑本脚本切换到受管运行时。"
            ;;
    esac
fi

# I-1②：退役受管残留 PATH 副本（仅在 skip_runtime 分支调用）。
# 选择"直接退役（删除）"而非仅警告：此时外部 jdtls 生效，而受管 wrapper 在 PATH 上（典型顺序
# ~/.local/bin 先于系统目录）会**遮蔽外部 jdtls**，且正本一旦缺失 wrapper 自身必坏（exec 目标
# 不存在，无自愈路径）——删除是唯一同时消除"遮蔽"与"必坏"的动作；且该文件带 mayoi-java 指纹、
# 是本脚本产物，删除不涉及用户自放文件（用户文件场景由第 5 步所有权守门排除）。
retire_stale_copy() {
    dest="$HOME/.local/bin/jdtls"
    if [ -f "$dest" ] && grep -q mayoi-java "$dest" 2>/dev/null; then
        rm -f "$dest" && echo "已退役受管 PATH 副本: $dest（外部 jdtls 生效；受管副本会遮蔽它且可能已失联，删除以恢复外部优先）"
    fi
}

ensure_jre() {
    # ---- 1. 受管 JRE 25（TUNA 主源按平台矩阵 + Adoptium 官方 API 回退；版本化幂等 + 解压后交换）----
    local need=true marker_val="" inner="" d
    local jre_marker="$JRE_DIR/.jre-version"
    local jre_desired=""
    if [ -f "$JRE_DIR/bin/java" ]; then
        local jre_installed=""
        if [ -f "$jre_marker" ]; then
            jre_installed=$(tr -d '\r' < "$jre_marker")
        fi
        jre_desired=$(tuna_latest_name)
        if [ -n "$jre_desired" ] && [ "$jre_installed" = "$jre_desired" ]; then
            echo "受管 JRE 已存在且版本匹配（$jre_desired），跳过"
            need=false
        elif [ -n "$jre_desired" ]; then
            echo "受管 JRE 版本变更: ${jre_installed:-未知} → $jre_desired，重装"
        else
            echo "受管 JRE 已存在（${jre_installed:-版本未知}）；TUNA 目录暂不可达，无法核对版本，保留现有安装"
            need=false
        fi
    else
        echo "未检测到受管 JRE，开始安装"
    fi
    [ "$need" = true ] || return 0

    # 首装路径同样先抓 TUNA 文件名（主源）；抓取失败 → 空 → Adoptium API 回退
    if [ -z "$jre_desired" ]; then
        jre_desired=$(tuna_latest_name)
    fi

    step "下载 Temurin JRE 25 ($plat_os/$plat_arch，约 45MB)"
    echo "   注意: JRE 源为浮动 latest（TUNA 目录页 / Adoptium API），无法钉死哈希；jdtls 侧已钉死 SHA256"
    local cache="" ok=false
    if [ -n "$jre_desired" ]; then
        echo "   源: $TUNA_DIR$jre_desired"
        cache="$CACHE_DIR/$jre_desired"
        if fetch "$cache" "$TUNA_DIR$jre_desired"; then
            marker_val="$jre_desired"
            ok=true
        else
            warn "TUNA 源失败，尝试 Adoptium 官方 API 回退"
        fi
    fi
    if [ "$ok" = false ]; then
        # 浮动源旧缓存不可安全续传（版本可能已变，拼接会产出坏包）——先清缓存全量下载
        cache="$CACHE_DIR/jre-adoptium-api-$plat_os-$plat_arch.tar.gz"
        rm -f "$cache"
        echo "   源: $JRE_API_URL"
        if fetch "$cache" "$JRE_API_URL"; then
            marker_val="adoptium-api-latest"
            ok=true
        fi
    fi
    [ "$ok" = true ] || die "JRE 两个源均下载失败。重跑本脚本可续传；或手动下载 tar.gz 解压到 $JRE_DIR（需含 bin/java）后重跑。"

    step "解压 JRE（先解压校验，成功才交换）"
    rm -rf "$EXTRACT_DIR"
    mkdir -p "$EXTRACT_DIR"
    if ! tar -xzf "$cache" -C "$EXTRACT_DIR"; then
        rm -rf "$EXTRACT_DIR"
        die "JRE tar.gz 解压失败: $cache（文件可能不完整：重跑本脚本将重新下载）"
    fi
    for d in "$EXTRACT_DIR"/*/; do
        if [ -f "${d}bin/java" ]; then
            inner="${d%/}"
            break
        fi
    done
    if [ -z "$inner" ]; then
        rm -rf "$EXTRACT_DIR"
        die "JRE tar.gz 结构异常（无含 bin/java 的内层目录）: $cache"
    fi
    # 校验通过 → 写版本 marker（写入解压树，随交换一并落位）→ 交换
    printf '%s\n' "$marker_val" > "$inner/.jre-version" || {
        rm -rf "$EXTRACT_DIR"
        die "无法写入 JRE 版本 marker（目录不可写）: $inner"
    }
    rm -rf "$JRE_DIR"
    mv "$inner" "$JRE_DIR"
    rm -rf "$EXTRACT_DIR"
    rm -f "$cache"
    case "$(uname -s)" in
        Linux|Darwin) echo "JRE: $("$JRE_DIR/bin/java" -version 2>&1 | head -n 1)" ;;
        *) warn "宿主 $(uname -s) 无法运行 $plat_os 产物，跳过 java -version 打印（属预期）" ;;
    esac
}

ensure_jdtls() {
    # ---- 2. jdtls 1.63.0（eclipse.org 直连 + 续传；MAYOI_JDTLS_TGZ 三分支；钉死 SHA256 + 解压后交换）----
    local marker="$JDTLS_DIR/.mayoi-java-installed"
    local installed="" tgz="" src="" f="" found="" url_key="" base="" actual=""
    local is_temp_cache=false
    installed=""
    if [ -f "$marker" ]; then
        installed=$(tr -d '\r' < "$marker")
    fi
    if [ "$installed" = "$JDTLS_VERSION" ]; then
        echo "受管 jdtls 已存在（$JDTLS_VERSION），跳过"
        return 0
    fi
    [ -z "$installed" ] || echo "受管 jdtls 版本变更: $installed → $JDTLS_VERSION，重装"
    step "安装 jdtls $JDTLS_VERSION (约 49MB；eclipse.org 国内较慢，失败重跑可续传)"

    # M-4 收紧：默认 eclipse 源在全无哈希工具时直接拒绝（提前 die，不浪费 49MB 下载）；
    # 本地/自定义源无工具时仅警告跳过校验（见下方校验段）。
    if [ -z "$SHA_KIND" ] && [ -z "${MAYOI_JDTLS_TGZ:-}" ]; then
        die "未找到 sha256sum / shasum / openssl，无法校验官方 jdtls 包完整性 —— 拒绝从默认源安装。请安装任一哈希工具后重跑，或设 MAYOI_JDTLS_TGZ 指向本地包（本地源将跳过校验并警告）"
    fi

    src="${MAYOI_JDTLS_TGZ:-}"
    if [ -n "$src" ] && [ -f "$src" ]; then
        tgz="$src"
        echo "   使用本地源: $tgz（相对路径基于当前目录解析）"
    elif [ -n "$src" ]; then
        case "$src" in
            http://*|https://*)
                echo "   自定义源: $src"
                # 缓存名用 URL 哈希前 16 位（ps1 Get-UrlKey 同构）：保证 -C - 续传绝不把两个不同源的字节拼进同一个文件
                if [ -n "$SHA_KIND" ]; then
                    case "$SHA_KIND" in
                        sha256sum) url_key=$(printf '%s' "$src" | sha256sum | cut -d' ' -f1 | cut -c 1-16) ;;
                        shasum)    url_key=$(printf '%s' "$src" | shasum -a 256 | cut -d' ' -f1 | cut -c 1-16) ;;
                        openssl)   url_key=$(printf '%s' "$src" | openssl dgst -sha256 | awk '{print $NF}' | cut -c 1-16) ;;
                    esac
                fi
                if [ -n "$url_key" ]; then
                    tgz="$CACHE_DIR/custom-$url_key.tar.gz"
                else
                    base=${src##*/}
                    base=${base%%\?*}
                    [ -n "$base" ] || base="jdtls-custom.tar.gz"
                    tgz="$CACHE_DIR/$base"
                fi
                # M-3 捷径：缓存完整且哈希命中钉死值 → 跳过下载（消老 curl 416 死循环边界）
                if [ -s "$tgz" ] && jdtls_cache_ok "$tgz"; then
                    echo "   已有缓存且哈希命中钉死值，跳过下载"
                elif ! fetch "$tgz" "$src"; then
                    die "jdtls 下载失败（已保留部分文件 $tgz，重跑本脚本可续传）"
                fi
                ;;
            *)
                die "MAYOI_JDTLS_TGZ='$src' 不是已存在的本地文件，也不是 http(s) URL（本地相对路径基于当前目录解析）"
                ;;
        esac
    else
        echo "   源: $JDTLS_URL （也可手动下载后设 MAYOI_JDTLS_TGZ 指向它）"
        # 固定产物 → 固定缓存文件名 → -C - 续传安全；成功后清理
        tgz="$CACHE_DIR/jdt-language-server-$JDTLS_VERSION-202610191322.tar.gz"
        is_temp_cache=true
        # M-3 捷径：缓存完整且哈希命中钉死值 → 跳过下载
        if [ -s "$tgz" ] && jdtls_cache_ok "$tgz"; then
            echo "   已有缓存且哈希命中钉死值，跳过下载"
        elif ! fetch "$tgz" "$JDTLS_URL"; then
            die "jdtls 下载失败（已保留部分文件 $tgz，重跑本脚本可续传）"
        fi
    fi

    if [ -n "$SHA_KIND" ]; then
        step "校验 jdtls SHA256（钉死值）"
        actual=$(sha256_of "$tgz")
        if [ "$actual" != "$JDTLS_SHA256" ]; then
            die "jdtls SHA256 不匹配（期望 $JDTLS_SHA256，实际 ${actual:-空}）：文件损坏或非 $JDTLS_VERSION 官方包: $tgz"
        fi
        echo "   SHA256 校验通过"
    else
        # 只可能到达本地/自定义源（默认源已在下载前 die）
        warn "未找到 sha256sum / shasum / openssl，跳过 jdtls SHA256 校验（本地/自定义源）"
    fi

    step "解压 jdtls（先解压校验，成功才交换）"
    rm -rf "$EXTRACT_DIR"
    mkdir -p "$EXTRACT_DIR"
    if ! tar -xzf "$tgz" -C "$EXTRACT_DIR"; then
        rm -rf "$EXTRACT_DIR"
        die "jdtls 解压失败（tar.gz 可能不完整：删除 $tgz 后重跑；本地/自定义源请重新获取）"
    fi
    # 校验 1: equinox launcher glob 非空（官方包为根目录布局 bin/ plugins/ features/…）
    for f in "$EXTRACT_DIR"/plugins/org.eclipse.equinox.launcher_*.jar; do
        if [ -f "$f" ]; then
            found="$f"
            break
        fi
    done
    if [ -z "$found" ]; then
        rm -rf "$EXTRACT_DIR"
        die "jdtls 解压产物缺少 plugins/org.eclipse.equinox.launcher_*.jar: $tgz"
    fi
    # 校验 2: marker 可写（写入解压树，随交换一并落位）
    printf '%s\n' "$JDTLS_VERSION" > "$EXTRACT_DIR/.mayoi-java-installed" || {
        rm -rf "$EXTRACT_DIR"
        die "无法写入 jdtls marker（安装目录不可写）: $EXTRACT_DIR"
    }
    # 校验全部通过 → 交换
    rm -rf "$JDTLS_DIR"
    mv "$EXTRACT_DIR" "$JDTLS_DIR"
    echo "jdtls $JDTLS_VERSION 安装完成"
    if [ "$is_temp_cache" = true ]; then
        rm -f "$tgz"    # 默认源缓存清理；本地/自定义源保留（用户文件 / 续传）
    fi
}

if [ "$skip_runtime" = true ]; then
    retire_stale_copy
    echo "（检测到现有 jdtls）跳过受管运行时 / 启动器 / PATH 步骤。"
else

ensure_jre
ensure_jdtls

# ---- 3. 启动器落位（内嵌副本，与仓库 launcher/jdtls 逐字同源；LF + chmod +x）----
# 发布纪律：修改 launcher/jdtls 必须同步此处内嵌副本（PLAN-v0.2 风险表约定），否则引导安装的
# 启动器与仓库漂移。UTF-8 注释在此处合法（无 ps1 的 ASCII 编码限制）。
step "安装启动器"
cat > "$BIN_DIR/jdtls" <<'MAYOI_LAUNCHER_EOF'
#!/bin/sh
# mayoi-java 免 Python jdtls 启动器（复刻官方 jdtls.py 启动语义，无版本校验）
# java 解析：受管 JRE（../jre）> JAVA_HOME > PATH；-data 用净化 cwd 目录名
# NOTE: official-style --jvm-arg= / --java-executable / -data overrides are NOT parsed here; all args are passed through verbatim to java
# NOTE: Darwin intentionally uses the same XDG-style cache root as Linux instead of ~/Library/Caches (mayoi-java namespace isolation; intentional deviation)
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
JDTLS_DIR="$HERE/../jdtls"

JAVA_EXE=""
if [ -x "$HERE/../jre/bin/java" ]; then
  JAVA_EXE="$HERE/../jre/bin/java"
elif [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ]; then
  JAVA_EXE="$JAVA_HOME/bin/java"
elif command -v java >/dev/null 2>&1; then
  JAVA_EXE="java"
else
  echo "mayoi-java: 未找到 java。请重跑引导脚本安装受管 JRE，或安装 JDK 21+。" >&2
  exit 1
fi

LAUNCHER=""
if [ -f "$JDTLS_DIR/plugins/org.eclipse.equinox.launcher.jar" ]; then
  LAUNCHER="$JDTLS_DIR/plugins/org.eclipse.equinox.launcher.jar"
else
  for f in "$JDTLS_DIR"/plugins/org.eclipse.equinox.launcher_*.jar; do
    [ -f "$f" ] && LAUNCHER="$f" && break
  done
fi
[ -n "$LAUNCHER" ] || { echo "mayoi-java: 在 $JDTLS_DIR 下未找到 equinox launcher。" >&2; exit 1; }

case "$(uname -s)" in
  Darwin) CONFIG_DIR=config_mac ;;
  *)      CONFIG_DIR=config_linux ;;
esac

CWD_NAME=$(basename "$(pwd)")
CWD_NAME=$(printf '%s' "$CWD_NAME" | tr '/:*?"<>| ' '_________')
CWD_NAME=$(printf '%s' "$CWD_NAME" | cut -c1-64)
DATA_DIR="${XDG_CACHE_HOME:-${HOME:-${TMPDIR:-/tmp}}/.cache}/mayoi-java/jdtls/$CWD_NAME"
mkdir -p "$DATA_DIR"

exec "$JAVA_EXE" \
  -Declipse.application=org.eclipse.jdt.ls.core.id1 \
  -Dosgi.bundles.defaultStartLevel=4 \
  -Declipse.product=org.eclipse.jdt.ls.core.product \
  -Dosgi.checkConfiguration=true \
  "-Dosgi.sharedConfiguration.area=$JDTLS_DIR/$CONFIG_DIR" \
  -Dosgi.sharedConfiguration.area.readOnly=true \
  -Dosgi.configuration.cascaded=true \
  -Xms1G \
  --add-modules=ALL-SYSTEM \
  --add-opens java.base/java.util=ALL-UNNAMED \
  --add-opens java.base/java.lang=ALL-UNNAMED \
  -Djdk.xml.maxGeneralEntitySizeLimit=0 \
  -Djdk.xml.totalEntitySizeLimit=0 \
  -jar "$LAUNCHER" \
  -data "$DATA_DIR" "$@"
MAYOI_LAUNCHER_EOF
chmod +x "$BIN_DIR/jdtls"

# ---- 4. PATH（~/.local/bin 不在 PATH 时 best-effort 追加到存在的 rc；仅追加，绝不覆盖）----
local_bin_on_path=false
path_via_rc_only=false    # C-1: ~/.local/bin 仅经 rc 接入（需重开终端生效）→ 影响完成语
case ":$PATH:" in
    *":$HOME/.local/bin:"*|*":$HOME/.local/bin/:"*) local_bin_on_path=true ;;
esac
if [ "$local_bin_on_path" = true ]; then
    echo "PATH 已含 $HOME/.local/bin，跳过追加"
else
    rc_file=""
    if [ -f "$HOME/.zshrc" ]; then
        rc_file="$HOME/.zshrc"    # zshrc 优先于 bashrc
    elif [ -f "$HOME/.bashrc" ]; then
        rc_file="$HOME/.bashrc"
    elif [ -n "${SHELL:-}" ] && printf '%s' "$SHELL" | grep -q zsh; then
        rc_file="$HOME/.zshrc"
    elif [ -n "${SHELL:-}" ] && printf '%s' "$SHELL" | grep -q bash; then
        rc_file="$HOME/.bashrc"
    fi
    if [ -n "$rc_file" ]; then
        step "追加 \$HOME/.local/bin 到 PATH（$rc_file）"
        # M-8: 精确行去重（避免误判用户 rc 里恰好提到 mayoi-java 的无关行）
        if grep -qF 'export PATH="$HOME/.local/bin:$PATH"' "$rc_file" 2>/dev/null; then
            echo "   $rc_file 已含 mayoi-java PATH 条目，跳过"
            local_bin_on_path=true
            path_via_rc_only=true
        elif printf '\n# added by mayoi-java bootstrap (managed jdtls)\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$rc_file"; then
            local_bin_on_path=true    # M-1: 仅在追加成功后置位
            path_via_rc_only=true
            echo "已就绪（新开的终端生效；当前终端可执行: source $rc_file）"
        else
            warn "写入 $rc_file 失败，请手动把 $HOME/.local/bin 加入 PATH"
        fi
    else
        warn "未找到可追加的 rc（~/.zshrc / ~/.bashrc），请手动把 $HOME/.local/bin 加入 PATH"
    fi
fi

# ---- 5. 启动器 PATH 副本（C-1: wrapper 转发正本，绝不字节拷贝）----
# 字节拷贝必坏：正本按 $0 相对路径解析 ../jre 与 ../jdtls，拷到 ~/.local/bin 后解析错位。
# wrapper 用绝对路径 exec 转发，正本收到的 $0 即其真实位置，相对解析保持正确。
# I-1①: 目标已存在但非本脚本产物（无 mayoi-java 指纹）→ 不覆盖用户文件，仅警告。
if [ "$local_bin_on_path" = true ]; then
    dest="$HOME/.local/bin/jdtls"
    if [ -f "$dest" ] && ! grep -q mayoi-java "$dest" 2>/dev/null; then
        warn "$dest 已存在且非本脚本产物（无 mayoi-java 指纹），不覆盖 —— 请自行决定保留或移除该文件"
    elif mkdir -p "$HOME/.local/bin" 2>/dev/null; then
        if { printf '#!/bin/sh\n# mayoi-java managed launcher wrapper — forwards to canonical copy (re-run bootstrap to refresh)\nexec "%s" "$@"\n' "$BIN_DIR/jdtls" > "$dest" && chmod +x "$dest"; }; then
            echo "启动器 PATH 副本（wrapper）已就位: $dest -> $BIN_DIR/jdtls"
        else
            warn "写入 $dest 失败"
        fi
    else
        warn "无法创建 $HOME/.local/bin，请手动把 $BIN_DIR 加入 PATH"
    fi
else
    warn "未能把 $HOME/.local/bin 接入 PATH —— 请手动把 $BIN_DIR 加入 PATH，否则 Mayoi 默认的 command:\"jdtls\" 无法命中"
fi

fi  # end -not $skip_runtime

# ---- 6. 插件安装（mayoi CLI 探测；已装则跳过；用户自装 POSIX shim 无句柄链问题，不涉及 F13）----
plugin_dir="$HOME/.mayoi/plugins/java"
if [ -d "$plugin_dir" ]; then
    echo "mayoi-java 插件已安装（$plugin_dir），跳过"
elif command -v mayoi >/dev/null 2>&1; then
    step "安装 mayoi-java 插件"
    if MAYOI_CLI=1 mayoi plugin install HelloThreeLiu/mayoi-java; then
        if [ -d "$plugin_dir" ]; then
            echo "插件安装成功: $plugin_dir"
        else
            warn "未能确认插件自动安装，请手动执行: mayoi plugin install HelloThreeLiu/mayoi-java"
        fi
    else
        warn "mayoi plugin install 失败，请手动执行: mayoi plugin install HelloThreeLiu/mayoi-java"
    fi
else
    echo "未检测到 mayoi CLI。请安装插件:"
    echo "  mayoi plugin install HelloThreeLiu/mayoi-java"
fi

printf '\n'
if [ "$skip_runtime" = true ]; then
    echo "完成。检测到外部 jdtls 生效，语言服务将按 PATH 使用它 —— 重启 Mayoi 后打开任意 .java 文件即可。"
elif [ "$path_via_rc_only" = true ]; then
    echo "完成。~/.local/bin 刚接入 PATH（经 rc）—— 请重开终端（或 source rc）让 PATH 生效，再重启 Mayoi 打开任意 .java 文件即可使用（语言服务由受管 JRE + 免 Python 启动器拉起）。"
else
    echo "完成。重启 Mayoi 后打开任意 .java 文件即可使用（语言服务由受管 JRE + 免 Python 启动器拉起）。"
fi
