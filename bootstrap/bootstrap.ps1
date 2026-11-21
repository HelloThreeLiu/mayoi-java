# bootstrap.ps1 - mayoi-java one-command bootstrap (Windows)
# Usage: iwr -useb https://raw.githubusercontent.com/HelloThreeLiu/mayoi-java/main/bootstrap/bootstrap.ps1 | iex
# Optional env var: MAYOI_JDTLS_TGZ=<local tar.gz path or custom URL>
#   (eclipse.org is slow from CN; download jdt-language-server-1.63.0-*.tar.gz manually and point this at the local file)
# Idempotent: managed JRE / jdtls (marker file) / PATH / plugin steps are skipped when already in place
# NOTE: this file must stay pure ASCII - see the release-discipline comment at the launcher section below.
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$InstallDir = Join-Path $env:LOCALAPPDATA "mayoi-java"
$BinDir     = Join-Path $InstallDir "bin"
$JreDir     = Join-Path $InstallDir "jre"
$JdtlsDir   = Join-Path $InstallDir "jdtls"
$TmpDir     = Join-Path ([IO.Path]::GetTempPath()) "mayoi-java-bootstrap"
New-Item $BinDir, $TmpDir -ItemType Directory -Force | Out-Null

function Step($m) { Write-Host "== $m" -ForegroundColor Cyan }

# Download cache file name: first 16 hex chars of the URL hash. Guarantees that -C - resume never
# mixes bytes from two different sources into one file.
function Get-UrlKey($u) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($u))) -replace "-", "").Substring(0, 16).ToLowerInvariant()
}

# ---- 0. Existing jdtls detection (idempotency matrix section 1.4 row 1: unmanaged jdtls on PATH -> skip all runtime install, keep plugin step) ----
$existing = Get-Command jdtls -ErrorAction SilentlyContinue
$skipRuntime = $false
if ($existing -and ($existing.CommandType -eq 'Application') -and ($existing.Source -notlike "$InstallDir*")) {
    $skipRuntime = $true
    Write-Host "Existing jdtls detected: $($existing.Source) - skipping runtime install." -ForegroundColor Yellow
    Write-Host "If it fails to launch (needs Python+JDK25), remove it and re-run this script to switch to the managed runtime."
}

if (-not $skipRuntime) {

# ---- 1. Managed JRE 25 (TUNA primary + Adoptium official fallback; skipped when present) ----
if (-not (Test-Path (Join-Path $JreDir "bin\java.exe"))) {
    Step "Downloading Temurin JRE 25 (~56MiB)"
    $targets = @(
        "https://mirrors.tuna.tsinghua.edu.cn/Adoptium/25/jre/x64/windows/OpenJDK25U-jre_x64_windows_hotspot_25.0.5_8.zip",
        "https://api.adoptium.net/v3/binary/latest/25/ga/windows/x64/jre/hotspot/normal/eclipse?project=jdk"
    )
    $zip = $null
    foreach ($u in $targets) {
        Write-Host "   Source: $u"
        $f = Join-Path $TmpDir ((Get-UrlKey $u) + ".zip")
        curl.exe --ssl-no-revoke -L -C - --fail --retry 3 --retry-delay 2 -o "$f" $u
        if ($LASTEXITCODE -eq 0) { $zip = $f; break }
        Write-Host "   Source failed (exit $LASTEXITCODE), trying the next one" -ForegroundColor Yellow
    }
    if (-not $zip) { throw "JRE download failed from both sources. Re-run to resume; or manually download a zip, extract it to $JreDir (must contain bin\java.exe), then re-run." }
    Step "Extracting JRE"
    $ex = Join-Path $TmpDir "jre-extract"
    if (Test-Path $ex) { Remove-Item $ex -Recurse -Force }
    New-Item $ex -ItemType Directory -Force | Out-Null
    tar.exe -xf "$zip" -C "$ex"   # bsdtar reads zip too; much faster than Expand-Archive
    if ($LASTEXITCODE -ne 0) { throw "JRE zip extraction failed: $zip" }
    $inner = Get-ChildItem $ex -Directory | Select-Object -First 1     # jdk-25.0.x-jre/
    if (-not $inner) { throw "JRE zip layout unexpected (no inner directory): $zip" }
    if (-not (Test-Path (Join-Path $inner.FullName "bin\java.exe"))) { throw "JRE zip layout unexpected (no bin\java.exe inside): $zip" }
    if (Test-Path $JreDir) { Remove-Item $JreDir -Recurse -Force }
    Move-Item (Join-Path $ex $inner.Name) $JreDir
    Remove-Item $zip, $ex -Recurse -Force -ErrorAction SilentlyContinue
    $eap = $ErrorActionPreference; $ErrorActionPreference = "Continue"   # java -version writes to stderr; with EAP=Stop, 2>&1 raises a spurious terminating error
    $javaVer = (& (Join-Path $JreDir "bin\java.exe") -version 2>&1 | Select-Object -First 1)
    $ErrorActionPreference = $eap
    Write-Host "JRE: $javaVer"
} else { Write-Host "Managed JRE already present, skipping" }

# ---- 2. jdtls 1.63.0 (eclipse.org direct + resume; MAYOI_JDTLS_TGZ supports a local file / custom URL) ----
$marker = Join-Path $JdtlsDir ".mayoi-java-installed"
if (-not (Test-Path $marker)) {
    Step "Downloading jdtls 1.63.0 (~49MB; eclipse.org is slow from CN, resumable)"
    $tgz = $null
    $src = $env:MAYOI_JDTLS_TGZ
    if ($src -and (Test-Path -LiteralPath $src -PathType Leaf)) {
        $tgz = $src
        Write-Host "   Using local source: $tgz"
    } elseif ($src -match "^https?://") {
        Write-Host "   Custom source: $src"
        $tgz = Join-Path $TmpDir ((Get-UrlKey $src) + ".tar.gz")
        curl.exe --ssl-no-revoke -L -C - --fail --retry 3 --retry-delay 2 -o "$tgz" $src
        if ($LASTEXITCODE -ne 0) { throw "jdtls download failed (partial file kept at $tgz; re-run to resume)" }
    } elseif ($src) {
        throw "MAYOI_JDTLS_TGZ='$src' is neither an existing local file nor an http(s) URL (relative paths resolve against the current directory)"
    } else {
        # Integrity currently relies on TLS + the official trusted source; pinned SHA256 verification is planned for v0.2.1 (the Adoptium latest fallback URL cannot be pinned)
        $u = "https://download.eclipse.org/jdtls/milestones/1.63.0/jdt-language-server-1.63.0-202610191322.tar.gz"
        Write-Host "   Source: $u (you can also download it manually and point MAYOI_JDTLS_TGZ at the file)"
        $tgz = Join-Path $TmpDir ((Get-UrlKey $u) + ".tar.gz")
        curl.exe --ssl-no-revoke -L -C - --fail --retry 3 --retry-delay 2 -o "$tgz" $u
        if ($LASTEXITCODE -ne 0) { throw "jdtls download failed (partial file kept at $tgz; re-run to resume)" }
    }
    Step "Extracting jdtls"
    if (Test-Path $JdtlsDir) { Remove-Item $JdtlsDir -Recurse -Force }
    New-Item $JdtlsDir -ItemType Directory -Force | Out-Null
    tar.exe -xzf "$tgz" -C "$JdtlsDir"
    if ($LASTEXITCODE -ne 0) {
        if (-not $src) { throw "jdtls extraction failed (tar.gz may be incomplete; delete $tgz and re-run)" }
        throw "jdtls extraction failed (tar.gz verification failed for local/custom source: $tgz)"
    }
    Set-Content $marker "1.63.0" -Encoding ascii
    if (-not $src) { Remove-Item $tgz -Force -ErrorAction SilentlyContinue }
    Write-Host "jdtls 1.63.0 installed"
} else { Write-Host "Managed jdtls already present ($((Get-Content $marker))), skipping" }

# ---- 3. Launcher placement (embedded copy, byte-identical to repo launcher/jdtls.bat) ----
# Release discipline: any change to launcher/jdtls.bat must be mirrored in this embedded copy
# (PLAN-v0.2 risk table), otherwise the bootstrap-installed launcher drifts from the repo.
# The embedded content must stay pure ASCII (Set-Content -Encoding ascii silently turns non-ASCII into '?').
# This script must stay pure ASCII: PS 5.1 reads BOM-less files as ANSI, and the documented entry
# is iex (which chokes on a leading BOM).
Step "Installing launcher"
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

# ---- 4. PATH append (append-only, never overwrite) ----
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if (-not $userPath) { $userPath = "" }
if ((($userPath -split ";") | ForEach-Object { $_.TrimEnd('\') }) -notcontains ($BinDir.TrimEnd('\'))) {
    Step "Appending $BinDir to user PATH"
    # <notes: a REG_EXPAND_SZ value is expanded by the .NET API and written back as REG_SZ; users with %var% entries lose follow-capability - re-evaluate raw registry read/write in v0.2.1>
    [Environment]::SetEnvironmentVariable("Path", (($userPath.TrimEnd(";") + ";" + $BinDir).Trim(";")), "User")
    Write-Host "User PATH updated (takes effect in new terminals / restarted apps; a running Mayoi must be restarted)"
} else { Write-Host "User PATH already contains $BinDir, skipping" }

} # end -not $skipRuntime

# ---- 5. Plugin install (three-level mayoi CLI probe; skipped when installed; success verified by directory state, not shim stdout) ----
$pluginDir = Join-Path $env:USERPROFILE ".mayoi\plugins\java"
if (Test-Path $pluginDir) {
    Write-Host "mayoi-java plugin already installed ($pluginDir), skipping"
} else {
    $mayoiCli = $null
    $shim = Join-Path $env:LOCALAPPDATA "Mayoi\bin\mayoi.cmd"
    if (Test-Path $shim) { $mayoiCli = $shim }
    if (-not $mayoiCli) {
        $c = Get-Command mayoi -ErrorAction SilentlyContinue
        if ($c) { $mayoiCli = $c.Source }
    }
    if ($mayoiCli) {
        Step "Installing/updating mayoi-java plugin"
        $env:MAYOI_CLI = "1"
        # F13: Mayoi.exe is a GUI-subsystem executable and the mayoi.cmd shim breaks the handle chain -> its stdout may be lost; success is verified by plugin directory state
        Start-Process -FilePath $mayoiCli -ArgumentList "plugin","install","HelloThreeLiu/mayoi-java" -NoNewWindow -Wait -RedirectStandardOutput "$TmpDir\plugin-install-out.txt" -RedirectStandardError "$TmpDir\plugin-install-err.txt"
        Get-Content "$TmpDir\plugin-install-out.txt", "$TmpDir\plugin-install-err.txt" -ErrorAction SilentlyContinue
        if (Test-Path $pluginDir) {
            Write-Host "Plugin installed: $pluginDir" -ForegroundColor Green
        } else {
            Write-Host "Could not confirm automatic plugin install; run manually: mayoi plugin install HelloThreeLiu/mayoi-java" -ForegroundColor Yellow
        }
    } else {
        Write-Host "mayoi CLI not detected. Install the plugin with:" -ForegroundColor Yellow
        Write-Host "  mayoi plugin install HelloThreeLiu/mayoi-java"
    }
}

Write-Host ""
if ($skipRuntime) {
    Write-Host "Done. Restart Mayoi and open any .java file (existing jdtls detected; the language service will use it via PATH)." -ForegroundColor Green
} else {
    Write-Host "Done. Restart Mayoi and open any .java file (the language service is served by the managed JRE + python-free launcher)." -ForegroundColor Green
}
