# claude-guard.ps1 —— Windows 版：出口 IP 与锚定 IP 不一致时关闭 Claude
#
# 用法（管理员 PowerShell）：
#   .\claude-guard.ps1 -Check
#   .\claude-guard.ps1 -Watch [-DryRun]
#   .\claude-guard.ps1 -Install      注册登录自启的计划任务
#   .\claude-guard.ps1 -Uninstall
#
# 配置：%USERPROFILE%\.config\claude-guard\config（同一份 KEY=VALUE 格式）

param(
    [switch]$Check,
    [switch]$Watch,
    [switch]$Install,
    [switch]$Uninstall,
    [switch]$DryRun
)

$ErrorActionPreference = "Continue"
# Windows PowerShell 5.1 在部分系统上默认不启用 TLS 1.2，会导致取不到 trace 而误判为出口异常
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
$ConfPath = Join-Path $env:USERPROFILE ".config\claude-guard\config"
$LogDir = Join-Path $env:USERPROFILE ".config\claude-guard"
$LogPath = Join-Path $LogDir "guard.log"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$ExpectIp = ""
$CheckUrl = "https://claude.ai/cdn-cgi/trace"
$Interval = 15
$Threshold = 2

$AppName = "Claude"
$AppNameExplicit = $false

if (Test-Path $ConfPath) {
    Get-Content $ConfPath | ForEach-Object {
        # 允许行尾 # 注释（与 macOS/Linux 版共用同一份配置文件）
        $line = ($_ -replace '\s+#.*$', '').Trim()
        if ($line -match '^([A-Za-z_]+)\s*=\s*(.*)$') {
            $k = $Matches[1].ToUpper(); $v = $Matches[2].Trim().Trim('"').Trim("'")
            switch ($k) {
                "EXPECT_IP"   { $ExpectIp = $v }
                "CHECK_URL"   { $CheckUrl = $v }
                "INTERVAL"    { if ($v -match '^\d+$') { $Interval = [int]$v } }
                "THRESHOLD"   { if ($v -match '^\d+$') { $Threshold = [int]$v } }
                "APP_NAME"    { if ($v) { $AppName = $v; $AppNameExplicit = $true } }
                "APP_PATTERN" {
                    # macOS 行的写法是完整路径，这里只取可执行文件名
                    if (-not $AppNameExplicit -and $v) {
                        $AppName = [IO.Path]::GetFileName($v) -replace '\.exe$', ''
                    }
                }
            }
        }
    }
}

function Write-Log($msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg"
    Write-Host $line
    Add-Content -Path $LogPath -Value $line
}

function Get-ExitIp {
    try {
        $resp = (Invoke-WebRequest -UseBasicParsing -Uri $CheckUrl -TimeoutSec 8).Content
        $m = [regex]::Match($resp, '(?m)^ip=(.+)$')
        if ($m.Success) { return $m.Groups[1].Value.Trim() }
    } catch { }
    return ""
}

function Stop-Claude {
    if ($DryRun) { Write-Log "[dry-run] 将结束进程: $AppName"; return }
    $p = Get-Process -Name $AppName -ErrorAction SilentlyContinue
    if ($p) { $p | Stop-Process -Force; Write-Log "已结束 $AppName 进程" }
}

function Send-Notice($msg) {
    if (Get-Command New-BurntToastNotification -ErrorAction SilentlyContinue) {
        New-BurntToastNotification -Text "claude-guard", $msg
    } else {
        Write-Log "通知: $msg"
    }
}

function Do-Check {
    if (-not $ExpectIp) { Write-Log "[ERROR] 未配置 EXPECT_IP：$ConfPath"; exit 2 }
    $ip = Get-ExitIp
    if ($ip -eq $ExpectIp) { Write-Log "[OK] 出口正常：$ip"; exit 0 }
    Write-Log "[FAIL] 出口异常：当前=$(if ($ip) {$ip} else {'取不到'}) 期望=$ExpectIp"
    exit 1
}

function Do-Watch {
    if (-not $ExpectIp) { Write-Log "[ERROR] 未配置 EXPECT_IP：$ConfPath"; exit 2 }
    $fails = 0; $blocked = $false
    Write-Log "开始守护：期望=$ExpectIp 间隔=${Interval}s 阈值=$Threshold dry-run=$DryRun"
    while ($true) {
        $ip = Get-ExitIp
        if ($ip -eq $ExpectIp) {
            $fails = 0
            if ($blocked) {
                $blocked = $false
                Write-Log "[RECOVER] 出口恢复正常"
                Send-Notice "出口已恢复，可以继续使用 Claude"
            }
        } else {
            $fails++
            Write-Log "[FAIL $fails/$Threshold] 当前=$(if ($ip) {$ip} else {'取不到'}) 期望=$ExpectIp"
            if ($fails -ge $Threshold) {
                Stop-Claude
                if (-not $blocked) {
                    Send-Notice "出口 IP 异常，已关闭 Claude"
                    $blocked = $true
                }
            }
        }
        Start-Sleep -Seconds $Interval
    }
}

function Do-Install {
    $self = $PSCommandPath
    $action = "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$self`" -Watch"
    schtasks /Create /TN "claude-guard" /TR $action /SC ONLOGON /RL HIGHEST /F
    Write-Log "已注册计划任务 claude-guard（登录时启动）"
}

function Do-Uninstall {
    schtasks /Delete /TN "claude-guard" /F
    Write-Log "已删除计划任务"
}

if ($Uninstall) { Do-Uninstall; exit 0 }
if ($Install)   { Do-Install; exit 0 }
if ($Check)     { Do-Check }
else            { Do-Watch }
