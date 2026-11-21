# scripts/lsp-smoke.ps1 — jdtls stdio 冒烟测试：发送 initialize，等待含 capabilities 的响应
# 用法（在任意空目录下执行）: pwsh scripts/lsp-smoke.ps1 [-Jdtls <名字或路径>] [-DataDir <目录>]
# 注意：读响应为阻塞式；长时间无输出即判定失败（Ctrl+C 结束）。
param(
    [string]$Jdtls = "jdtls",
    [string]$DataDir = ""
)
$ErrorActionPreference = "Stop"

$init = @{
    jsonrpc = "2.0"; id = 1; method = "initialize"
    params  = @{ processId = $PID
                 rootUri   = ([System.Uri]((Get-Location).Path + "/")).AbsoluteUri
                 capabilities = @{} }
} | ConvertTo-Json -Depth 10 -Compress

$bytes = [Text.Encoding]::UTF8.GetByteCount($init)
$frame = "Content-Length: $bytes`r`n`r`n$init"

$psi = [System.Diagnostics.ProcessStartInfo]::new()
$psi.RedirectStandardInput  = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError  = $true
$psi.UseShellExecute = $false
# Windows 下 .bat 必须经 cmd 启动（这同时验证了宿主用 cmd 语义拉起 jdtls.bat 的可行性）
# 引号勘误：cmd 对 /c 后含 >2 个引号的命令行会剥掉第一个和最后一个引号，因此须用 /s + 整体外层引号对
# 包裹整个命令（实测：/s /c ""bat" -data "dir"" 可行；/s /c """bat" -data "dir"" 不可行）
if ($env:OS -eq "Windows_NT") {
    $psi.FileName = "cmd.exe"
    if ($DataDir) {
        $psi.Arguments = "/s /c `"`"$Jdtls`" -data `"$DataDir`"`""
    } else {
        $psi.Arguments = "/s /c `"`"$Jdtls`"`""
    }
} else {
    $psi.FileName = $Jdtls
    if ($DataDir) { $psi.Arguments = "-data `"$DataDir`"" }
}
Write-Host ">> starting: $($psi.FileName) $($psi.Arguments)"
$p = [System.Diagnostics.Process]::Start($psi)
$p.StandardInput.Write($frame)
$p.StandardInput.Flush()

$headers = @{}
$response = ""
while ($true) {
    $headers = @{}
    while ($true) {
        $line = $p.StandardOutput.ReadLine()
        if ($null -eq $line) { throw "stdout closed before response; stderr: $($p.StandardError.ReadToEnd())" }
        if ($line -eq "") { break }
        $idx = $line.IndexOf(":")
        if ($idx -gt 0) { $headers[$line.Substring(0, $idx).Trim()] = $line.Substring($idx + 1).Trim() }
    }
    $len = [int]$headers["Content-Length"]
    $buf = New-Object char[] $len
    $read = 0
    while ($read -lt $len) {
        $n = $p.StandardOutput.Read($buf, $read, $len - $read)
        if ($n -le 0) { throw "stdout EOF at $read/$len" }
        $read += $n
    }
    $response = -join $buf
    # jdt.ls 在 initialize 响应之前会先推送 language/status 等 notification，逐帧跳过直到收到响应帧
    if ($response -match '"capabilities"') { break }
}

if ($env:OS -eq "Windows_NT") { taskkill /PID $p.Id /T /F 2>$null } else { try { $p.Kill() } catch {} }
Write-Host ">> response (first 500 chars):"
Write-Host $response.Substring(0, [Math]::Min(500, $response.Length))
if ($response -match '"capabilities"') { Write-Host "SMOKE OK" -ForegroundColor Green; exit 0 }
else { throw "SMOKE FAIL: no capabilities in response" }
