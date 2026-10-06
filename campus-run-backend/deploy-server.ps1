# Deploy campus-run backend to the Tencent Cloud server.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File deploy-server.ps1 -Password 'xxx'
#   powershell -ExecutionPolicy Bypass -File deploy-server.ps1 -Password 'xxx' -SkipMigrations
#
# IMPORTANT: the server builds from SOURCE (docker-compose.deploy.yml uses
# `build: context: .` with a multi-stage Dockerfile), so there is no
# target/*.jar on the server. We upload the source tree and let Docker run
# `mvn package` inside the build container.
#
# WHY TAR INSTEAD OF ZIP:
#   PowerShell's Compress-Archive writes Windows path separators, so the zip
#   contains entries like "campus-run-server\src\main\". On Linux, unzip treats
#   the backslash as a *filename character* rather than a separator - the tree
#   comes out flat/wrong. On top of that, Compress-Archive drops the directory
#   execute bit, and `unzip -q` returns exit code 1 on any warning (which kills
#   a `set -e` script). Windows' bundled bsdtar writes proper forward slashes,
#   so we use that and extract straight over the project directory.
#
# This script is intentionally ASCII-only: Windows PowerShell 5.1 reads
# non-BOM UTF-8 as GBK and mangles non-ASCII characters. Long remote logic
# lives in deploy-remote.sh, which is uploaded and executed there.

param(
    [Parameter(Mandatory = $true)][string]$Password,
    [string]$Server = '122.51.191.145',
    [string]$User = 'ubuntu',
    [string]$RemoteDir = '/home/ubuntu/campus-run-backend',
    [switch]$SkipMigrations
)

$ErrorActionPreference = 'Stop'
Import-Module Posh-SSH

function Write-Step($m) { Write-Host "`n=== $m ===" -ForegroundColor Cyan }

$Root = $PSScriptRoot
$TmpDir = '/home/ubuntu/deploy-tmp'
$Stage = Join-Path $env:TEMP 'crdeploy'
$Tar = Join-Path $env:TEMP 'campus-run-src.tar.gz'

# ---- stage + pack ----------------------------------------------------------
Write-Step 'Stage and pack source tree'

$migrations = @(
    "$Root\docs\migrations\002_profile_privacy_and_media.sql",
    "$Root\docs\migrations\003_fix_badge_mojibake.sql",
    "$Root\docs\migrations\004_admin_and_password_reset.sql"
)
$remoteScript = "$Root\deploy-remote.sh"
foreach ($f in ($migrations + $remoteScript)) {
    if (-not (Test-Path $f)) { throw "missing file: $f" }
}

if (Test-Path $Stage) { Remove-Item $Stage -Recurse -Force }
if (Test-Path $Tar) { Remove-Item $Tar -Force }
New-Item -ItemType Directory -Force -Path $Stage | Out-Null

Copy-Item "$Root\pom.xml" "$Stage\pom.xml"
foreach ($m in @('campus-run-common', 'campus-run-server')) {
    New-Item -ItemType Directory -Force -Path "$Stage\$m" | Out-Null
    Copy-Item "$Root\$m\pom.xml" "$Stage\$m\pom.xml"
    Copy-Item "$Root\$m\src" "$Stage\$m\src" -Recurse
}

Push-Location $Stage
try {
    & tar -czf $Tar pom.xml campus-run-common campus-run-server
    if ($LASTEXITCODE -ne 0) { throw "tar failed with $LASTEXITCODE" }
} finally { Pop-Location }

$t = Get-Item $Tar
Write-Host ("  packed: {0}  {1:N0} KB" -f $Tar, ($t.Length / 1KB))

# sanity: tar must use forward slashes
$listing = & tar -tzf $Tar
if (-not ($listing | Where-Object { $_ -match '^campus-run-server/src/' })) {
    throw "tar listing has no forward-slash paths - refuse to deploy a broken archive"
}
Write-Host ("  entries: {0}  (forward slashes OK)" -f $listing.Count)

# ---- connect ---------------------------------------------------------------
Write-Step 'Connect over SSH'
$sec = ConvertTo-SecureString $Password -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential($User, $sec)
$session = New-SSHSession -ComputerName $Server -Credential $cred -AcceptKey -Force
if (-not $session) { throw 'SSH connection failed' }
$sid = $session.SessionId
Write-Host ("  connected (SessionId={0})" -f $sid)

function Invoke-Remote($cmd) {
    $r = Invoke-SSHCommand -SessionId $sid -Command $cmd -TimeOut 3600
    if ($r.Output) { $r.Output | ForEach-Object { "  $_" } }
    if ($r.Error) { $r.Error | ForEach-Object { "  ERR: $_" } }
    if ($r.ExitStatus -ne 0) { Write-Host ("  [exit {0}]" -f $r.ExitStatus) -ForegroundColor Yellow }
}

try {
    Write-Step 'Inspect server'
    Invoke-Remote 'whoami; hostname; docker --version 2>/dev/null || sudo docker --version'

    Write-Step 'Upload tar + migrations + remote script'
    foreach ($item in (@($Tar, $remoteScript) + $migrations)) {
        Set-SCPItem -ComputerName $Server -Credential $cred -AcceptKey `
            -Path $item -Destination '/home/ubuntu' -Force | Out-Null
        Write-Host ("  uploaded {0}" -f (Split-Path $item -Leaf))
    }

    Write-Step 'Extract source directly over the project directory'
    # bsdtar wrote forward slashes, so -C works as expected. Extraction merges
    # into the existing tree (it does not delete files we no longer ship).
    Invoke-Remote @"
set -e
cd /home/ubuntu
ls -la campus-run-src.tar.gz
tar -xzf campus-run-src.tar.gz -C $RemoteDir
echo "--- sanity: the fix we are deploying must be present ---"
grep -c 'chatPreferenceMapper.deleteByUser' $RemoteDir/campus-run-server/src/main/java/com/campusrun/server/service/impl/UserServiceImpl.java
grep -c 'deviceTokenMapper.deleteByUserId' $RemoteDir/campus-run-server/src/main/java/com/campusrun/server/service/impl/UserServiceImpl.java
echo "--- stage migrations + remote script ---"
mkdir -p $TmpDir && rm -f $TmpDir/*
for suf in 002_profile_privacy_and_media.sql 003_fix_badge_mojibake.sql 004_admin_and_password_reset.sql deploy-remote.sh; do
    hit=`$(find /home/ubuntu -maxdepth 1 -type f -name "*`$suf" | head -1)
    if [ -z "`$hit" ]; then echo "MISSING `$suf"; else cp -f "`$hit" "$TmpDir/`$suf"; echo "staged `$suf"; fi
done
sed -i 's/\r`$//' $TmpDir/deploy-remote.sh
chmod +x $TmpDir/deploy-remote.sh
rm -f /home/ubuntu/campus-run-src.tar.gz /home/ubuntu/*.sql /home/ubuntu/deploy-remote.sh
ls -la $TmpDir
"@

    $skip = if ($SkipMigrations) { '1' } else { '0' }
    Invoke-Remote "cd /home/ubuntu && REMOTE_DIR=$RemoteDir TMP_DIR=$TmpDir SKIP_MIGRATIONS=$skip bash $TmpDir/deploy-remote.sh"

    Write-Step 'Verify public API from this machine'
    foreach ($url in @(
            'http://122.51.191.145:8080/api/v1/leaderboard?scope=daily&type=1',
            'http://122.51.191.145:8080/api/v1/user/1/profile')) {
        try {
            $r = Invoke-WebRequest -Uri $url -TimeoutSec 25 -UseBasicParsing
            Write-Host ("  OK {0} -> HTTP {1}" -f $url, $r.StatusCode)
        }
        catch {
            $code = $_.Exception.Response.StatusCode.value__
            if ($code) { Write-Host ("  {0} -> HTTP {1} (401 expected when not logged in)" -f $url, $code) }
            else { Write-Host ("  {0} -> {1}" -f $url, $_.Exception.Message) }
        }
    }
}
finally {
    try { Remove-SSHSession -SessionId $sid | Out-Null } catch { }
    Write-Host "`n=== finished (SSH closed) ===" -ForegroundColor Green
}
