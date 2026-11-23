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

# ---- 1. Managed JRE 25 (TUNA latest scraped like bootstrap.sh + pinned + Adoptium API fallback; .jre-version marker drives upgrades on re-run) ----
$TunaJreDir    = "https://mirrors.tuna.tsinghua.edu.cn/Adoptium/25/jre/x64/windows/"
$JrePinnedName = "OpenJDK25U-jre_x64_windows_hotspot_25.0.5_8.zip"   # static fallback when the TUNA listing is unreachable (TUNA keeps old files listed)
$JreApiUrl     = "https://api.adoptium.net/v3/binary/latest/25/ga/windows/x64/jre/hotspot/normal/eclipse?project=jdk"
$jreMarker     = Join-Path $JreDir ".jre-version"
$jreInstalled  = ""
if (Test-Path $jreMarker) { $jreInstalled = (Get-Content $jreMarker -Raw).Trim() }

# First zip filename in the TUNA directory listing (bootstrap.sh tuna_latest_name / head -n 1 parity); empty when unreachable
function Get-LatestJreName {
    $html = (& curl.exe -fsSL --retry 2 --retry-delay 2 "$TunaJreDir") -join "`n"
    if ($LASTEXITCODE -ne 0) { return "" }
    [regex]::Match($html, "OpenJDK25U-jre_x64_windows_hotspot_[0-9._]+\.zip").Value
}

$jreNeed = $true
$jreDesired = Get-LatestJreName
if (Test-Path (Join-Path $JreDir "bin\java.exe")) {
    if (-not $jreDesired) {
        Write-Host "Managed JRE already present ($(if ($jreInstalled) { $jreInstalled } else { 'version unknown' })); TUNA unreachable, keeping existing install"
        $jreNeed = $false
    } elseif ($jreInstalled -eq $jreDesired) {
        Write-Host "Managed JRE already present and up to date ($jreDesired), skipping"
        $jreNeed = $false
    } else {
        Write-Host "Managed JRE version change: $(if ($jreInstalled) { $jreInstalled } else { 'unknown' }) -> $jreDesired, reinstalling"
    }
}
if ($jreNeed) {
    Step "Downloading Temurin JRE 25 (~56MiB)"
    $targets = @()
    if ($jreDesired) { $targets += "$TunaJreDir$jreDesired" }
    $targets += "$TunaJreDir$JrePinnedName"
    $targets += $JreApiUrl
    $targets = $targets | Select-Object -Unique
    $zip = $null
    $chosen = ""
    foreach ($u in $targets) {
        Write-Host "   Source: $u"
        $f = Join-Path $TmpDir ((Get-UrlKey $u) + ".zip")
        curl.exe --ssl-no-revoke -L -C - --fail --retry 3 --retry-delay 2 -o "$f" $u
        if ($LASTEXITCODE -eq 0) { $zip = $f; $chosen = $u; break }
        Write-Host "   Source failed (exit $LASTEXITCODE), trying the next one" -ForegroundColor Yellow
    }
    if (-not $zip) { throw "JRE download failed from all sources. Re-run to resume; or manually download a zip, extract it to $JreDir (must contain bin\java.exe), then re-run." }
    Step "Extracting JRE"
    $ex = Join-Path $TmpDir "jre-extract"
    if (Test-Path $ex) { Remove-Item $ex -Recurse -Force }
    New-Item $ex -ItemType Directory -Force | Out-Null
    tar.exe -xf "$zip" -C "$ex"   # bsdtar reads zip too; much faster than Expand-Archive
    if ($LASTEXITCODE -ne 0) { throw "JRE zip extraction failed: $zip" }
    $inner = Get-ChildItem $ex -Directory | Select-Object -First 1     # jdk-25.0.x-jre/
    if (-not $inner) { throw "JRE zip layout unexpected (no inner directory): $zip" }
    if (-not (Test-Path (Join-Path $inner.FullName "bin\java.exe"))) { throw "JRE zip layout unexpected (no bin\java.exe inside): $zip" }
    # version marker written into the extracted tree (moves into place with the swap); TUNA sources -> zip filename,
    # API fallback -> fixed tag (parity with bootstrap.sh; floating-latest churn between sources re-extracts once, by design)
    if ($chosen -eq $JreApiUrl) { $jreMarkerVal = "adoptium-api-latest" } else { $jreMarkerVal = ($chosen -split "/")[-1] }
    Set-Content (Join-Path $inner.FullName ".jre-version") $jreMarkerVal -Encoding ascii
    if (Test-Path $JreDir) { Remove-Item $JreDir -Recurse -Force }
    Move-Item (Join-Path $ex $inner.Name) $JreDir
    Remove-Item $zip, $ex -Recurse -Force -ErrorAction SilentlyContinue
    $eap = $ErrorActionPreference; $ErrorActionPreference = "Continue"   # java -version writes to stderr; with EAP=Stop, 2>&1 raises a spurious terminating error
    $javaVer = (& (Join-Path $JreDir "bin\java.exe") -version 2>&1 | Select-Object -First 1)
    $ErrorActionPreference = $eap
    Write-Host "JRE: $javaVer"
}

# ---- 2. jdtls 1.63.0 (eclipse.org direct + resume; MAYOI_JDTLS_TGZ local/custom source; pinned SHA256 verified before install; marker version compare drives upgrades) ----
$JdtlsVersion = "1.63.0"
$JdtlsSha256  = "b1f2abe0b3cccb462cf64fb4a5587c7d09df60cf8be7748b152cbd89d018bdc4"   # same pinned artifact/hash as bootstrap.sh (mismatch -> refuse install)
$JdtlsUrl     = "https://download.eclipse.org/jdtls/milestones/1.63.0/jdt-language-server-1.63.0-202610191322.tar.gz"
$marker = Join-Path $JdtlsDir ".mayoi-java-installed"
$jdtlsInstalled = ""
if (Test-Path $marker) { $jdtlsInstalled = (Get-Content $marker -Raw).Trim() }
if ($jdtlsInstalled -eq $JdtlsVersion) {
    Write-Host "Managed jdtls already present ($JdtlsVersion), skipping"
} else {
    if ($jdtlsInstalled) { Write-Host "Managed jdtls version change: $jdtlsInstalled -> $JdtlsVersion, reinstalling" }
    Step "Downloading jdtls $JdtlsVersion (~49MB; eclipse.org is slow from CN, resumable)"
    $tgz = $null
    $src = $env:MAYOI_JDTLS_TGZ
    if ($src -and (Test-Path -LiteralPath $src -PathType Leaf)) {
        $tgz = $src
        Write-Host "   Using local source: $tgz"
    } elseif ($src -match "^https?://") {
        Write-Host "   Custom source: $src"
        $tgz = Join-Path $TmpDir ((Get-UrlKey $src) + ".tar.gz")
        # fixed cache name per URL -> cached file matching the pinned hash skips the download (old curl 416 resume boundary; bootstrap.sh M-3 parity)
        if ((Test-Path $tgz) -and ((Get-FileHash -Algorithm SHA256 -LiteralPath $tgz).Hash.ToLowerInvariant() -eq $JdtlsSha256)) {
            Write-Host "   Cached archive matches the pinned SHA256, skipping download"
        } else {
            curl.exe --ssl-no-revoke -L -C - --fail --retry 3 --retry-delay 2 -o "$tgz" $src
            if ($LASTEXITCODE -ne 0) { throw "jdtls download failed (partial file kept at $tgz; re-run to resume)" }
        }
    } elseif ($src) {
        throw "MAYOI_JDTLS_TGZ='$src' is neither an existing local file nor an http(s) URL (relative paths resolve against the current directory)"
    } else {
        $tgz = Join-Path $TmpDir ((Get-UrlKey $JdtlsUrl) + ".tar.gz")
        Write-Host "   Source: $JdtlsUrl (you can also download it manually and point MAYOI_JDTLS_TGZ at the file)"
        # fixed artifact -> fixed cache name; pinned-hash shortcut skips the download when the cache is already complete
        if ((Test-Path $tgz) -and ((Get-FileHash -Algorithm SHA256 -LiteralPath $tgz).Hash.ToLowerInvariant() -eq $JdtlsSha256)) {
            Write-Host "   Cached archive matches the pinned SHA256, skipping download"
        } else {
            curl.exe --ssl-no-revoke -L -C - --fail --retry 3 --retry-delay 2 -o "$tgz" $JdtlsUrl
            if ($LASTEXITCODE -ne 0) { throw "jdtls download failed (partial file kept at $tgz; re-run to resume)" }
        }
    }
    Step "Verifying jdtls SHA256 (pinned)"
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $tgz).Hash.ToLowerInvariant()
    if ($actual -ne $JdtlsSha256) { throw "jdtls SHA256 mismatch (expected $JdtlsSha256, got $actual): corrupted, or not the official $JdtlsVersion package: $tgz" }
    Write-Host "   SHA256 verified"
    Step "Extracting jdtls"
    if (Test-Path $JdtlsDir) { Remove-Item $JdtlsDir -Recurse -Force }
    New-Item $JdtlsDir -ItemType Directory -Force | Out-Null
    tar.exe -xzf "$tgz" -C "$JdtlsDir"
    if ($LASTEXITCODE -ne 0) {
        if (-not $src) { throw "jdtls extraction failed (tar.gz may be incomplete; delete $tgz and re-run)" }
        throw "jdtls extraction failed (tar.gz verification failed for local/custom source: $tgz)"
    }
    Set-Content $marker "$JdtlsVersion" -Encoding ascii
    if (-not $src) { Remove-Item $tgz -Force -ErrorAction SilentlyContinue }
    Write-Host "jdtls $JdtlsVersion installed"
}

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
rem java resolution: managed JRE (%~dp0..\jre), then JAVA_HOME, then PATH; -data uses sanitized cwd basename + full-path hash suffix
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

rem soft version hint for external java only (managed JRE is known-good 25); warn, keep launching
rem (java output goes through a temp file: a for /f command string starting with a quote triggers cmd's
rem  first/last-quote stripping and breaks; direct execution + file read avoids the quoting entirely)
if /i "%JAVA_EXE%"=="%JRE_JAVA%" goto :version_hint_done
if not defined TEMP set "TEMP=%LOCALAPPDATA%\Temp"
set "JAVA_MAJOR="
set "JV_TMP=%TEMP%\mayoi-java-ver-%RANDOM%.tmp"
call "%JAVA_EXE%" -version >"%JV_TMP%" 2>&1
for /f "tokens=3 delims= " %%v in ('findstr /i "version" "%JV_TMP%"') do if not defined JAVA_MAJOR set "JAVA_MAJOR=%%v"
del "%JV_TMP%" >nul 2>nul
if not defined JAVA_MAJOR goto :version_hint_done
set "JAVA_MAJOR=%JAVA_MAJOR:"=%"
for /f "delims=. tokens=1" %%m in ("%JAVA_MAJOR%") do set "JAVA_MAJOR=%%m"
echo(%JAVA_MAJOR%| findstr /r "^[0-9][0-9]*$" >nul || goto :version_hint_done
if %JAVA_MAJOR% LSS 21 echo mayoi-java: warning: external java is major %JAVA_MAJOR%; jdtls 1.63 needs Java 21+ (managed JRE 25 recommended). Trying anyway... 1>&2
:version_hint_done

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

rem -data dir: %APPDATA%\mayoi-java\jdtls\[sanitized cwd basename]-[8-hex sha256 of full cwd]
rem the hash suffix isolates same-named projects (official jdtls.py hashes the basename only)
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
set "PATH_HASH="
if not defined TEMP set "TEMP=%LOCALAPPDATA%\Temp"
set "HASH_TMP=%TEMP%\mayoi-java-hash-%RANDOM%%RANDOM%.tmp"
>"%HASH_TMP%" echo("%CD%"
for /f "usebackq skip=1 delims=" %%h in (`certutil -hashfile "%HASH_TMP%" SHA256 2^>nul`) do if not defined PATH_HASH set "PATH_HASH=%%h"
del "%HASH_TMP%" >nul 2>nul
if defined PATH_HASH set "PATH_HASH=%PATH_HASH: =%"
if defined PATH_HASH set "PATH_HASH=%PATH_HASH:~0,8%"
set "DATA_DIR=%APPDATA%\mayoi-java\jdtls\%CWD_NAME%"
if defined PATH_HASH set "DATA_DIR=%DATA_DIR%-%PATH_HASH%"
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
  -Xms256m ^
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

# ---- 4. PATH append (append-only, never overwrite; raw registry read/write keeps the value kind) ----
$envKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Environment", $true)
if (-not $envKey) { throw "cannot open HKCU\Environment for writing" }
$rawPath = [string]$envKey.GetValue("Path", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
if ((($rawPath -split ";") | ForEach-Object { $_.TrimEnd('\') }) -notcontains ($BinDir.TrimEnd('\'))) {
    Step "Appending $BinDir to user PATH"
    # Raw registry read/write preserves the value kind: a REG_EXPAND_SZ Path keeps %var% entries expandable
    # ([Environment]::SetEnvironmentVariable rewrites it as REG_SZ). WM_SETTINGCHANGE is then broadcast so
    # new terminals / restarted apps pick the change up (the .NET API used to do this implicitly).
    $kind = $null
    try { $kind = $envKey.GetValueKind("Path") } catch { }
    if (-not $kind) { $kind = [Microsoft.Win32.RegistryValueKind]::ExpandString }
    $envKey.SetValue("Path", (($rawPath.TrimEnd(";") + ";" + $BinDir).Trim(";")), $kind)
    $envKey.Close()
    if (-not ("Win32.NativeMethods" -as [type])) {
        Add-Type -Namespace Win32 -Name NativeMethods -MemberDefinition '[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)] public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);'
    }
    $upd = [UIntPtr]::Zero
    [void][Win32.NativeMethods]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, "Environment", 2, 5000, [ref]$upd)
    Write-Host "User PATH updated (takes effect in new terminals / restarted apps; a running Mayoi must be restarted)"
} else {
    $envKey.Close()
    Write-Host "User PATH already contains $BinDir, skipping"
}

} # end -not $skipRuntime

# ---- 5. Plugin install (three-level mayoi CLI probe; skipped when installed; success verified by directory state, not shim stdout) ----
$mayoiDataRoot = if ($env:MAYOI_DATA_DIR) { $env:MAYOI_DATA_DIR } else { Join-Path $env:USERPROFILE ".mayoi" }
$pluginDir = Join-Path $mayoiDataRoot "plugins\java"
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
        # CreateNoWindow: no console is allocated at all (Start-Process -WindowStyle Hidden still flashes for .cmd shims,
        # because conhost appears before the hidden style takes effect).
        # Wrapped via %ComSpec% /d /c: with UseShellExecute=$false, direct .NET launch of a .cmd is restricted on some
        # .NET versions; /d ignores AutoRun, and the doubled outer quotes keep spaced paths intact.
        # The shim sets MAYOI_CLI=1 itself (its content includes `set "MAYOI_CLI=1"`), so we do not set it externally.
        # No stdout/stderr redirect (F13: shim output is unreliable; success is verified by the directory state below) -
        # do NOT add RedirectStandardOutput/-Error either (async drain deadlock risk).
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = $env:ComSpec
        $psi.Arguments = "/d /c `"`"$mayoiCli`" plugin install HelloThreeLiu/mayoi-java`""
        $psi.CreateNoWindow = $true
        $psi.UseShellExecute = $false
        [System.Diagnostics.Process]::Start($psi).WaitForExit()
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
