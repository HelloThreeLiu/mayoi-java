# bootstrap.ps1 — mayoi-java 一键引导（Windows）
# 用法: iwr -useb https://raw.githubusercontent.com/HelloThreeLiu/mayoi-java/main/bootstrap/bootstrap.ps1 | iex
# 可选环境变量: MAYOI_JDTLS_TGZ=<本地 tar.gz 路径 或 自定义 URL>
#   （eclipse.org 国内较慢；可先手动下载 jdt-language-server-1.63.0-*.tar.gz，再把它指向本地文件）
# 幂等：受管 JRE / jdtls（marker 文件）/ PATH / 插件 已就绪时，对应步骤自动跳过
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$InstallDir = Join-Path $env:LOCALAPPDATA "mayoi-java"
$BinDir     = Join-Path $InstallDir "bin"
$JreDir     = Join-Path $InstallDir "jre"
$JdtlsDir   = Join-Path $InstallDir "jdtls"
$TmpDir     = Join-Path ([IO.Path]::GetTempPath()) "mayoi-java-bootstrap"
New-Item $BinDir, $TmpDir -ItemType Directory -Force | Out-Null

function Step($m) { Write-Host "== $m" -ForegroundColor Cyan }

# 下载缓存文件名：取 URL 哈希前 16 位。保证 -C - 续传绝不把两个不同源的字节拼进同一个文件。
function Get-UrlKey($u) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($u))) -replace "-", "").Substring(0, 16).ToLowerInvariant()
}

# ---- 0. 已有 jdtls 检测（幂等矩阵 §1.4 第一行：PATH 上已有非受管 jdtls → 全跳过，仅保留插件步骤）----
$existing = Get-Command jdtls -ErrorAction SilentlyContinue
$skipRuntime = $false
if ($existing -and ($existing.CommandType -eq 'Application') -and ($existing.Source -notlike "$InstallDir*")) {
    $skipRuntime = $true
    Write-Host "检测到现有 jdtls: $($existing.Source) —— 跳过运行时安装。" -ForegroundColor Yellow
    Write-Host "若其无法启动（需 Python+JDK25），可删除它后重跑本脚本切换到受管运行时。"
}

if (-not $skipRuntime) {

# ---- 1. 受管 JRE 25（TUNA 主源 + Adoptium 官方回退；已存在则跳过）----
if (-not (Test-Path (Join-Path $JreDir "bin\java.exe"))) {
    Step "下载 Temurin JRE 25 (约 56MiB)"
    $targets = @(
        "https://mirrors.tuna.tsinghua.edu.cn/Adoptium/25/jre/x64/windows/OpenJDK25U-jre_x64_windows_hotspot_25.0.5_8.zip",
        "https://api.adoptium.net/v3/binary/latest/25/ga/windows/x64/jre/hotspot/normal/eclipse?project=jdk"
    )
    $zip = $null
    foreach ($u in $targets) {
        Write-Host "   源: $u"
        $f = Join-Path $TmpDir ((Get-UrlKey $u) + ".zip")
        curl.exe --ssl-no-revoke -L -C - --fail --retry 3 --retry-delay 2 -o "$f" $u
        if ($LASTEXITCODE -eq 0) { $zip = $f; break }
        Write-Host "   该源失败（exit $LASTEXITCODE），尝试下一源" -ForegroundColor Yellow
    }
    if (-not $zip) { throw "JRE 两个源均下载失败。重跑本脚本可续传；或手动下载 zip 解压到 $JreDir（需含 bin\java.exe）后重跑。" }
    Step "解压 JRE"
    $ex = Join-Path $TmpDir "jre-extract"
    if (Test-Path $ex) { Remove-Item $ex -Recurse -Force }
    New-Item $ex -ItemType Directory -Force | Out-Null
    tar.exe -xf "$zip" -C "$ex"   # bsdtar 识别 zip；比 Expand-Archive 快数分钟
    if ($LASTEXITCODE -ne 0) { throw "JRE zip 解压失败: $zip" }
    $inner = Get-ChildItem $ex -Directory | Select-Object -First 1     # jdk-25.0.x-jre/
    if (-not $inner) { throw "JRE zip 结构异常（无内层目录）: $zip" }
    if (-not (Test-Path (Join-Path $inner.FullName "bin\java.exe"))) { throw "JRE zip 布局异常（内层无 bin\java.exe）: $zip" }
    if (Test-Path $JreDir) { Remove-Item $JreDir -Recurse -Force }
    Move-Item (Join-Path $ex $inner.Name) $JreDir
    Remove-Item $zip, $ex -Recurse -Force -ErrorAction SilentlyContinue
    $eap = $ErrorActionPreference; $ErrorActionPreference = "Continue"   # java -version 走 stderr；EAP=Stop 下 2>&1 会误报为终止错误
    $javaVer = (& (Join-Path $JreDir "bin\java.exe") -version 2>&1 | Select-Object -First 1)
    $ErrorActionPreference = $eap
    Write-Host "JRE: $javaVer"
} else { Write-Host "受管 JRE 已存在，跳过" }

# ---- 2. jdtls 1.63.0（eclipse.org 直连 + 续传；支持 MAYOI_JDTLS_TGZ 本地文件/自定义 URL）----
$marker = Join-Path $JdtlsDir ".mayoi-java-installed"
if (-not (Test-Path $marker)) {
    Step "安装 jdtls 1.63.0 (约 49MB；eclipse.org 国内较慢，失败重跑可续传)"
    $tgz = $null
    $src = $env:MAYOI_JDTLS_TGZ
    if ($src -and (Test-Path -LiteralPath $src -PathType Leaf)) {
        $tgz = $src
        Write-Host "   使用本地源: $tgz"
    } elseif ($src -match "^https?://") {
        Write-Host "   自定义源: $src"
        $tgz = Join-Path $TmpDir ((Get-UrlKey $src) + ".tar.gz")
        curl.exe --ssl-no-revoke -L -C - --fail --retry 3 --retry-delay 2 -o "$tgz" $src
        if ($LASTEXITCODE -ne 0) { throw "jdtls 下载失败（已保留部分文件 $tgz，重跑本脚本可续传）" }
    } elseif ($src) {
        throw "MAYOI_JDTLS_TGZ='$src' 不是已存在的本地文件，也不是 http(s) URL（相对路径基于当前目录解析）"
    } else {
        # 完整性当前依赖 TLS + 官方信任源；钉死 SHA256 校验计划 v0.2.1 补（Adoptium latest 回退源不可钉哈希）
        $u = "https://download.eclipse.org/jdtls/milestones/1.63.0/jdt-language-server-1.63.0-202610191322.tar.gz"
        Write-Host "   源: $u （也可手动下载后设 MAYOI_JDTLS_TGZ 指向它）"
        $tgz = Join-Path $TmpDir ((Get-UrlKey $u) + ".tar.gz")
        curl.exe --ssl-no-revoke -L -C - --fail --retry 3 --retry-delay 2 -o "$tgz" $u
        if ($LASTEXITCODE -ne 0) { throw "jdtls 下载失败（已保留部分文件 $tgz，重跑本脚本可续传）" }
    }
    Step "解压 jdtls"
    if (Test-Path $JdtlsDir) { Remove-Item $JdtlsDir -Recurse -Force }
    New-Item $JdtlsDir -ItemType Directory -Force | Out-Null
    tar.exe -xzf "$tgz" -C "$JdtlsDir"
    if ($LASTEXITCODE -ne 0) {
        if (-not $src) { throw "jdtls 解压失败（tar.gz 可能不完整：删除 $tgz 后重跑）" }
        throw "jdtls 解压失败（tar.gz 校验失败：请校验/重新获取 $tgz）"
    }
    Set-Content $marker "1.63.0" -Encoding ascii
    if (-not $src) { Remove-Item $tgz -Force -ErrorAction SilentlyContinue }
    Write-Host "jdtls 1.63.0 安装完成"
} else { Write-Host "受管 jdtls 已存在（$((Get-Content $marker))），跳过" }

# ---- 3. 启动器落位（内嵌副本，与仓库 launcher/jdtls.bat 逐字同源）----
# 发布纪律：修改 launcher/jdtls.bat 必须同步此处内嵌副本（PLAN-v0.2 风险表约定），否则引导安装的启动器与仓库漂移；内容必须保持纯 ASCII（Set-Content -Encoding ascii 会把非 ASCII 静默变 ?）。
Step "安装启动器"
$launcher = @'
@echo off
rem mayoi-java python-free jdtls launcher (replicates official jdtls.py semantics, no version check)
rem java resolution: managed JRE (%~dp0..\jre), then JAVA_HOME, then PATH; -data uses sanitized cwd basename
rem NOTE: official-style --jvm-arg= / --java-executable / -data overrides are NOT parsed here; all args are passed through verbatim to java
setlocal EnableExtensions DisableDelayedExpansion

set "HERE=%~dp0"
set "JRE_JAVA=%HERE%..\jre\bin\java.exe"
set "JAVA_EXE="

if exist "%JRE_JAVA%" set "JAVA_EXE=%JRE_JAVA%"
if not defined JAVA_EXE if defined JAVA_HOME if exist "%JAVA_HOME%\bin\java.exe" set "JAVA_EXE=%JAVA_HOME%\bin\java.exe"
set "NoDefaultCurrentDirectoryInExePath=1"
if not defined JAVA_EXE (
    for /f "delims=" %%p in ('where "$PATH:java" 2^>nul ^| findstr /i /v "WindowsApps"') do set "JAVA_EXE=%%p" & goto :java_found
)
:java_found
if not defined JAVA_EXE (
    echo mayoi-java: java not found. Re-run the bootstrap to install the managed JRE, or install JDK 21+. 1>&2
    exit /b 1
)

rem locate equinox launcher: exact name first, then versioned glob
set "JDTLS_DIR=%HERE%..\jdtls"
set "LAUNCHER="
if exist "%JDTLS_DIR%\plugins\org.eclipse.equinox.launcher.jar" set "LAUNCHER=%JDTLS_DIR%\plugins\org.eclipse.equinox.launcher.jar"
if not defined LAUNCHER (
    for /r "%JDTLS_DIR%\plugins" %%f in (org.eclipse.equinox.launcher_*.jar) do set "LAUNCHER=%%f" & goto :launcher_found
)
:launcher_found
if not defined LAUNCHER (
    echo mayoi-java: no equinox launcher found under "%JDTLS_DIR%". 1>&2
    exit /b 1
)

rem platform shared configuration
set "CONFIG_DIR=config_win"

rem -data dir: %APPDATA%\mayoi-java\jdtls\[sanitized cwd basename]
if not defined APPDATA set "APPDATA=%LOCALAPPDATA%"
for %%p in ("%CD%") do set "CWD_NAME=%%~nxp"
if not defined CWD_NAME set "CWD_NAME=_root_"
set "CWD_NAME=%CWD_NAME:\=_%"
set "CWD_NAME=%CWD_NAME:/=_%"
set "CWD_NAME=%CWD_NAME::=_%"
set "CWD_NAME=%CWD_NAME:?=_%"
set "CWD_NAME=%CWD_NAME:<=_%"
set "CWD_NAME=%CWD_NAME:>=_%"
set "CWD_NAME=%CWD_NAME:|=_%"
set "CWD_NAME=%CWD_NAME: =_%"
set "CWD_NAME=%CWD_NAME:~0,64%"
set "DATA_DIR=%APPDATA%\mayoi-java\jdtls\%CWD_NAME%"
if not exist "%DATA_DIR%" mkdir "%DATA_DIR%" >nul 2>nul
if not exist "%DATA_DIR%" (
    echo mayoi-java: cannot create data dir "%DATA_DIR%" 1>&2
    exit /b 1
)

"%JAVA_EXE%" ^
  -Declipse.application=org.eclipse.jdt.ls.core.id1 ^
  -Dosgi.bundles.defaultStartLevel=4 ^
  -Declipse.product=org.eclipse.jdt.ls.core.product ^
  -Dosgi.checkConfiguration=true ^
  "-Dosgi.sharedConfiguration.area=%JDTLS_DIR%\%CONFIG_DIR%" ^
  -Dosgi.sharedConfiguration.area.readOnly=true ^
  -Dosgi.configuration.cascaded=true ^
  -Xms1G ^
  --add-modules=ALL-SYSTEM ^
  --add-opens java.base/java.util=ALL-UNNAMED ^
  --add-opens java.base/java.lang=ALL-UNNAMED ^
  -Djdk.xml.maxGeneralEntitySizeLimit=0 ^
  -Djdk.xml.totalEntitySizeLimit=0 ^
  -jar "%LAUNCHER%" ^
  -data "%DATA_DIR%" %*
'@
$launcher = ($launcher -split "`n") -replace "`r$", "" -join "`r`n"   # normalize LF blob -> CRLF (raw.githubusercontent serves LF)
Set-Content (Join-Path $BinDir "jdtls.bat") $launcher -Encoding ascii

# ---- 4. PATH 追加（仅追加，绝不覆盖）----
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if (-not $userPath) { $userPath = "" }
if ((($userPath -split ";") | ForEach-Object { $_.TrimEnd('\') }) -notcontains ($BinDir.TrimEnd('\'))) {
    Step "追加 $BinDir 到用户 PATH"
    # <notes: REG_EXPAND_SZ 值会被 .NET API 展开并写回 REG_SZ，含 %var% 条目的用户将丢失跟随能力——v0.2.1 评估 registry 原生读写>
    [Environment]::SetEnvironmentVariable("Path", (($userPath.TrimEnd(";") + ";" + $BinDir).Trim(";")), "User")
    Write-Host "已写入用户 PATH（新开的终端/重启应用生效；已运行的 Mayoi 需重启）"
} else { Write-Host "用户 PATH 已含 $BinDir，跳过" }

} # end -not $skipRuntime

# ---- 5. 插件安装（mayoi CLI 三级探测；已装则跳过；成败以目录状态验证，不依赖 shim 的 stdout）----
$pluginDir = Join-Path $env:USERPROFILE ".mayoi\plugins\java"
if (Test-Path $pluginDir) {
    Write-Host "mayoi-java 插件已安装（$pluginDir），跳过"
} else {
    $mayoiCli = $null
    $shim = Join-Path $env:LOCALAPPDATA "Mayoi\bin\mayoi.cmd"
    if (Test-Path $shim) { $mayoiCli = $shim }
    if (-not $mayoiCli) {
        $c = Get-Command mayoi -ErrorAction SilentlyContinue
        if ($c) { $mayoiCli = $c.Source }
    }
    if ($mayoiCli) {
        Step "安装 mayoi-java 插件"
        $env:MAYOI_CLI = "1"
        # F13：Mayoi.exe 为 GUI 子系统、mayoi.cmd shim 会弄断句柄链 → stdout 可能丢失，成败以插件目录状态验证
        Start-Process -FilePath $mayoiCli -ArgumentList "plugin","install","HelloThreeLiu/mayoi-java" -NoNewWindow -Wait -RedirectStandardOutput "$TmpDir\plugin-install-out.txt" -RedirectStandardError "$TmpDir\plugin-install-err.txt"
        Get-Content "$TmpDir\plugin-install-out.txt", "$TmpDir\plugin-install-err.txt" -ErrorAction SilentlyContinue
        if (Test-Path $pluginDir) {
            Write-Host "插件安装成功: $pluginDir" -ForegroundColor Green
        } else {
            Write-Host "未能确认插件自动安装，请手动执行: mayoi plugin install HelloThreeLiu/mayoi-java" -ForegroundColor Yellow
        }
    } else {
        Write-Host "未检测到 mayoi CLI。请安装插件:" -ForegroundColor Yellow
        Write-Host "  mayoi plugin install HelloThreeLiu/mayoi-java"
    }
}

Write-Host ""
if ($skipRuntime) {
    Write-Host "完成。重启 Mayoi 后打开任意 .java 文件即可使用（检测到现有 jdtls，语言服务将按 PATH 使用它）。" -ForegroundColor Green
} else {
    Write-Host "完成。重启 Mayoi 后打开任意 .java 文件即可使用（语言服务由受管 JRE + 免 Python 启动器拉起）。" -ForegroundColor Green
}
