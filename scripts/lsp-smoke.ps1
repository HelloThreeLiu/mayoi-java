# scripts/lsp-smoke.ps1 — jdtls stdio 冒烟测试：发送 initialize，等待含 capabilities 的响应
# 用法（在任意空目录下执行）: pwsh scripts/lsp-smoke.ps1 [-Jdtls <名字或路径>] [-DataDir <目录>]
# 注意：读响应为阻塞式；长时间无输出即判定失败（Ctrl+C 结束，Ctrl+C 退出可能残留子进程）。
# stderr 在 Windows 侧经 cmd 重定向到临时文件（失败时打印、成功后删除）；POSIX 分支不经过 shell，stderr 直通控制台。
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

# stderr 临时文件路径用跨平台 API 构造（POSIX 上 $env:TEMP 为 null，Join-Path 会崩）
$errFile = Join-Path ([IO.Path]::GetTempPath()) ("jdtls-smoke-err-" + $PID + ".log")
$psi = [System.Diagnostics.ProcessStartInfo]::new()
$psi.RedirectStandardInput  = $true
$psi.RedirectStandardOutput = $true
$psi.UseShellExecute = $false
# Windows 下 .bat 必须经 cmd 启动（这同时验证了宿主用 cmd 语义拉起 jdtls.bat 的可行性）
# 引号勘误：cmd 对 /c 后含 >2 个引号的命令行会剥掉第一个和最后一个引号，因此须用 /s + 整体外层引号对
# 包裹整个命令（实测：/s /c ""bat" -data "dir"" 可行；/s /c """bat" -data "dir"" 不可行）
# stderr 在 cmd 层重定向到文件：避免 stderr 管道无人排水，>4KB 时子进程阻塞
if ($env:OS -eq "Windows_NT") {
    $psi.FileName = "cmd.exe"
    if ($DataDir) {
        $psi.Arguments = "/s /c `"`"$Jdtls`" -data `"$DataDir`" 2>`"$errFile`"`""
    } else {
        $psi.Arguments = "/s /c `"`"$Jdtls`" 2>`"$errFile`"`""
    }
} else {
    $psi.FileName = $Jdtls
    if ($DataDir) { $psi.Arguments = "-data `"$DataDir`"" }
}

function Read-SmokeStderr {
    if ($env:OS -eq "Windows_NT" -and (Test-Path $errFile)) { Get-Content $errFile -Raw }
}

Write-Host ">> starting: $($psi.FileName) $($psi.Arguments)"
$p = [System.Diagnostics.Process]::Start($psi)
$response = ""
try {
    $p.StandardInput.Write($frame)
    $p.StandardInput.Flush()

    while ($true) {
        $headers = @{}
        while ($true) {
            $line = $p.StandardOutput.ReadLine()
            if ($null -eq $line) { throw "stdout closed before response; stderr: $(Read-SmokeStderr)" }
            if ($line -eq "") { break }
            $idx = $line.IndexOf(":")
            if ($idx -gt 0) { $headers[$line.Substring(0, $idx).Trim()] = $line.Substring($idx + 1).Trim() }
        }
        $len = [int]$headers["Content-Length"]
        $buf = New-Object char[] $len
        $read = 0
        while ($read -lt $len) {
            $n = $p.StandardOutput.Read($buf, $read, $len - $read)
            if ($n -le 0) { throw "stdout EOF at $read/$len; stderr: $(Read-SmokeStderr)" }
            $read += $n
        }
        $response = -join $buf
        # jdt.ls 在 initialize 响应之前会先推送 language/status 等 notification，逐帧跳过直到收到响应帧
        if ($response -match '"capabilities"') { break }
    }
} finally {
    # 无论成功、失败还是异常，都清理整个进程树（cmd + python + java）与 stderr 临时文件
    if ($env:OS -eq "Windows_NT") { taskkill /PID $p.Id /T /F 2>$null } else { try { $p.Kill() } catch {} }
    Remove-Item $errFile -ErrorAction SilentlyContinue
}
Write-Host ">> response (first 500 chars):"
Write-Host $response.Substring(0, [Math]::Min(500, $response.Length))
if ($response -match '"capabilities"') { Write-Host "SMOKE OK" -ForegroundColor Green; exit 0 }
else { throw "SMOKE FAIL: no capabilities in response" }
