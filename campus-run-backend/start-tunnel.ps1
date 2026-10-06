# 一键启动：后端 + Cloudflare 隧道
#
# ⚠️ 当前状态：**本脚本有已知的 PowerShell 解析问题，暂未完全验证可用**。
#    手动步骤见 docs/deploy-cloudflare-tunnel.md，那套命令已实测可行。
#    使用前请先跑：pwsh -NoProfile -Command "& './start-tunnel.ps1'"
#    若报解析错误，请按文档手动执行（4 条命令）。
#
# 用法（在 campus-run-backend/ 目录下）：
#   pwsh -File start-tunnel.ps1
#
# 每次重启电脑后跑这一个脚本即可。
# 注意：免费随机隧道的地址每次都会变，所以每次都要在 App 里重填一次。

$ErrorActionPreference = 'Stop'

$Cloudflared = "$env:USERPROFILE\cloudflared.exe"
$BackendDir = Join-Path $PSScriptRoot 'campus-run-server'
$Jar = Join-Path $BackendDir 'target\campus-run-server-1.0.0-SNAPSHOT.jar'
$TunnelOut = Join-Path $env:TEMP 'cftunnel-run.log'
$TunnelErr = Join-Path $env:TEMP 'cftunnel-run.err'

if (-not (Test-Path $Cloudflared)) {
    Write-Host "[X] 找不到 cloudflared: $Cloudflared"
    Write-Host "    安装见 docs/deploy-cloudflare-tunnel.md"
    exit 1
}
if (-not (Test-Path $Jar)) {
    Write-Host "[X] 找不到后端 jar: $Jar"
    Write-Host "    先构建: mvn -B clean package -DskipTests -Djacoco.skip=true"
    exit 1
}

function Start-Tunnel {
    Get-Process cloudflared -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Remove-Item $TunnelOut, $TunnelErr -ErrorAction SilentlyContinue
    Start-Process -FilePath $Cloudflared `
        -ArgumentList 'tunnel', '--url', 'http://localhost:8080', '--no-autoupdate', '--protocol', 'http2' `
        -RedirectStandardOutput $TunnelOut -RedirectStandardError $TunnelErr -WindowStyle Hidden
}

# 1. 停旧后端
Write-Host '-> 停止旧的后端进程...'
Get-CimInstance Win32_Process -Filter "Name='java.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match 'campus-run-server' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

# 2. 启动隧道并等待地址（首次失败时重试一次）
Write-Host '-> 启动 Cloudflare 隧道...'
$url = $null
for ($attempt = 1; $attempt -le 3 -and -not $url; $attempt++) {
    Start-Tunnel
    for ($i = 0; $i -lt 25; $i++) {
        Start-Sleep -Seconds 2
        $log = ''
        if (Test-Path $TunnelOut) { $log += (Get-Content $TunnelOut -Raw -ErrorAction SilentlyContinue) }
        if (Test-Path $TunnelErr) { $log += (Get-Content $TunnelErr -Raw -ErrorAction SilentlyContinue) }
        if (-not $log) { continue }

        if ($log -match 'failed to request quick Tunnel') {
            Write-Host "   第 $attempt 次创建失败（瞬时故障），重试..."
            break
        }
        $m = [regex]::Match($log, 'https://(?!api\.|developers\.|www\.)[a-z0-9-]+\.trycloudflare\.com')
        if ($m.Success) { $url = $m.Value; break }
    }
}

if (-not $url) {
    Write-Host '[X] 三次都没拿到隧道地址。日志:'
    Write-Host "    $TunnelOut"
    Get-Content $TunnelOut, $TunnelErr -Tail 15 -ErrorAction SilentlyContinue
    exit 1
}
Write-Host "   隧道地址: $url"

# 3. 用隧道地址启动后端
Write-Host '-> 启动后端...'
$env:DB_URL = 'jdbc:mysql://localhost:3306/campus_run?useSSL=false&serverTimezone=Asia/Shanghai&characterEncoding=utf8&allowPublicKeyRetrieval=true'
$env:DB_USERNAME = 'root'
$env:DB_PASSWORD = 'root'
$env:CORS_ALLOWED_ORIGINS = 'https://*.trycloudflare.com,http://localhost:*'
$env:PUBLIC_BASE_URL = $url

$BackendOut = Join-Path $env:TEMP 'backend-tunnel.log'
$BackendErr = Join-Path $env:TEMP 'backend-tunnel.err'
Start-Process -FilePath 'java' -ArgumentList '-jar', $Jar `
    -WorkingDirectory $BackendDir -WindowStyle Hidden `
    -RedirectStandardOutput $BackendOut -RedirectStandardError $BackendErr

$ready = $false
for ($i = 0; $i -lt 24; $i++) {
    Start-Sleep -Seconds 2
    if (Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue) {
        $ready = $true
        break
    }
}
if (-not $ready) {
    Write-Host "[X] 后端未监听 8080，看日志: $BackendOut"
    exit 1
}
Write-Host '   后端已就绪'

# 4. 更新数据库里已有的头像 URL（只存绝对地址，换地址后会失效）
Write-Host '-> 更新头像 URL...'
$env:MYSQL_PWD = 'root'
$newHost = $url -replace 'https://', ''
try {
    $hosts = mysql -u root campus_run -N -e "SELECT DISTINCT SUBSTRING_INDEX(SUBSTRING_INDEX(avatar_url,'/uploads/',1),'://',-1) FROM user WHERE avatar_url LIKE '%/uploads/%';" 2>$null
    foreach ($h in ($hosts | Where-Object { $_ -and $_.Trim() -ne '' })) {
        $h = $h.Trim()
        if ($h -eq $newHost) { continue }
        $sql = "UPDATE user SET avatar_url = REPLACE(avatar_url,'$h','$newHost') WHERE avatar_url LIKE '%$h%';"
        mysql -u root campus_run -e $sql 2>$null
        Write-Host "   已把 $h 替换为 $newHost"
    }
} catch {
    Write-Host '   (头像 URL 更新失败，不影响其他功能)'
}

# 5. 打印手机要填的地址
Write-Host ''
Write-Host '=================================================='
Write-Host ' 手机端: App -> 修改服务器地址 -> 填下面这一行'
Write-Host ''
Write-Host "   $url"
Write-Host ''
Write-Host ' 注意: 必须带 https:// 前缀。'
Write-Host ' 隧道是 https，而 App 的自动补全只会补 http://'
Write-Host '=================================================='
