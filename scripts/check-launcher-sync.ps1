# scripts/check-launcher-sync.ps1 - launcher drift check (same pairs as the CI "Launcher sync" step)
# Verifies the embedded copies in the bootstrap scripts stay in sync with the canonical launcher files:
#   1) bootstrap.ps1 here-string ($launcher = @' ... '@) == launcher/jdtls.bat (line-equal, EOL-insensitive)
#   2) bootstrap.sh heredoc (<<'MAYOI_LAUNCHER_EOF')     == launcher/jdtls     (line-equal, EOL-insensitive)
# Release discipline: any change to launcher/jdtls[.bat] must be mirrored in the embedded copy,
# otherwise the bootstrap-installed launcher drifts from the repo (PLAN-v0.2 risk table).
# Usage (any cwd, works in Windows PowerShell 5.1+ and pwsh 7+):
#   pwsh scripts/check-launcher-sync.ps1
# Exit 0 = in sync; exit 1 = drift (first differing line printed).
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot

function Get-FileLines($path) {
    # ReadAllLines is EOL-agnostic (CRLF / LF both handled) and decodes UTF-8 by default,
    # so this check behaves the same on Windows and Linux checkouts.
    [IO.File]::ReadAllLines($path)
}

function Get-Embedded([string]$label, [string[]]$lines, [scriptblock]$isStart, [scriptblock]$isEnd) {
    $startIdx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if (& $isStart $lines[$i]) { $startIdx = $i; break }
    }
    if ($startIdx -lt 0) {
        Write-Host "FAIL: embedded section start not found in $label" -ForegroundColor Red
        exit 1
    }
    for ($j = $startIdx + 1; $j -lt $lines.Count; $j++) {
        if (& $isEnd $lines[$j]) {
            $n = $j - $startIdx - 1
            $out = New-Object string[] $n
            [Array]::Copy($lines, $startIdx + 1, $out, 0, $n)
            Write-Host "$label : extracted $n lines (source lines $($startIdx + 2)-$j)"
            return $out
        }
    }
    Write-Host "FAIL: embedded section end not found in $label" -ForegroundColor Red
    exit 1
}

function Compare-Pair([string]$pairName, [string[]]$embedded, [string[]]$canonical) {
    $max = [Math]::Max($embedded.Count, $canonical.Count)
    for ($i = 0; $i -lt $max; $i++) {
        $a = "<EOF>"; $b = "<EOF>"
        if ($i -lt $embedded.Count) { $a = $embedded[$i] }
        if ($i -lt $canonical.Count) { $b = $canonical[$i] }
        if ($a -cne $b) {
            Write-Host "FAIL: $pairName - drift at line $($i + 1):" -ForegroundColor Red
            Write-Host "  embedded : $a"
            Write-Host "  canonical: $b"
            exit 1
        }
    }
    Write-Host "OK: $pairName ($($embedded.Count) lines identical)" -ForegroundColor Green
}

# Pair 1: bootstrap.ps1 embedded here-string vs launcher/jdtls.bat
$ps1Lines = Get-FileLines (Join-Path $root "bootstrap\bootstrap.ps1")
$embeddedBat = Get-Embedded "bootstrap.ps1 (`$launcher = @')" $ps1Lines `
    { param($l) $l -eq "`$launcher = @'" } `
    { param($l) $l -eq "'@" }
$batLines = Get-FileLines (Join-Path $root "launcher\jdtls.bat")
Compare-Pair "bootstrap.ps1 embedded == launcher/jdtls.bat" $embeddedBat $batLines

# Pair 2: bootstrap.sh embedded heredoc vs launcher/jdtls
$shLines = Get-FileLines (Join-Path $root "bootstrap\bootstrap.sh")
$embeddedSh = Get-Embedded "bootstrap.sh (MAYOI_LAUNCHER_EOF heredoc)" $shLines `
    { param($l) $l -like "*<<'MAYOI_LAUNCHER_EOF'" } `
    { param($l) $l -eq "MAYOI_LAUNCHER_EOF" }
$shCanonical = Get-FileLines (Join-Path $root "launcher\jdtls")
Compare-Pair "bootstrap.sh embedded == launcher/jdtls" $embeddedSh $shCanonical

Write-Host "launcher sync check passed: both embedded copies match the canonical files." -ForegroundColor Green
exit 0
