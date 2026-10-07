# Publish a new App release: upload the APK + write version.json.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File campus-run-backend\release-apk.ps1 `
#       -Password 'xxx' -Version '1.2.0' -Changelog '1. fix ...'
#
# Source APK defaults to ..\campus-run.apk (the file you hand to testers).
#
# WHY THIS IS A SEPARATE SCRIPT FROM deploy-server.ps1:
#   Deploying backend code rebuilds the Docker image (mvn runs inside), which
#   takes ~8 minutes. Publishing an App update is just "swap one file", so it
#   must NOT trigger that. version.json is read by the server on every request,
#   so this script takes effect in seconds with zero restart.
#
# This script is ASCII-only: Windows PowerShell 5.1 reads non-BOM UTF-8 as GBK.

param(
    [Parameter(Mandatory = $true)][string]$Password,
    [Parameter(Mandatory = $true)][string]$Version,
    [string]$Changelog = '',
    [string]$MinSupported = '',
    [string]$ApkPath = '',
    [string]$Server = '122.51.191.145',
    [string]$User = 'ubuntu'
)

$ErrorActionPreference = 'Stop'
Import-Module Posh-SSH

function Write-Step($m) { Write-Host "`n=== $m ===" -ForegroundColor Cyan }

# Resolve the APK to publish. Order matters:
#   1. -ApkPath if given
#   2. the Flutter build output (the freshest artefact, and the one that
#      always matches the current source -- no manual copying involved)
#   3. ../campus-run.apk and ~/Desktop/campus-run.apk (the hand-off copies)
if (-not $ApkPath) {
    $candidates = @(
        (Join-Path (Split-Path $PSScriptRoot -Parent) 'campus-run-app\build\app\outputs\flutter-apk\app-release.apk'),
        (Join-Path $PSScriptRoot '..\campus-run.apk'),
        (Join-Path ([Environment]::GetFolderPath('Desktop')) 'campus-run.apk')
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { $ApkPath = $c; break }
    }
}
if (-not $ApkPath -or -not (Test-Path $ApkPath)) {
    throw ("APK not found. Build it first (subst P: <project>\campus-run-app, " +
           "then: flutter build apk --release), or pass -ApkPath.")
}
if ($Version -notmatch '^\d+\.\d+\.\d+') { throw "Version must look like 1.2.0 (got '$Version')" }

$apk = Get-Item $ApkPath
Write-Step 'Local APK'
Write-Host ("  {0}" -f $apk.FullName)
Write-Host ("  {0:N1} MB   {1}" -f ($apk.Length / 1MB), $apk.LastWriteTime)
$sha = (Get-FileHash $apk.FullName -Algorithm SHA256).Hash
Write-Host ("  sha256 {0}" -f $sha)

# ---- build version.json locally (UTF-8 without BOM) ------------------------
#
# WARNING: the changelog must NOT be empty -- fail loudly instead of silently
# writing an empty string.
#
# Why: version.json is replaced WHOLESALE. Omitting -Changelog therefore wipes
# the changelog already on the server, and the app's "what's new" section goes
# blank -- while this script still reports success. A textbook silent failure.
# It happened 3 times (each needing a manual fix-up on the server), so now we
# stop the release instead of shipping an empty changelog.
#
# NOTE: keep this file pure ASCII. Windows PowerShell 5.1 decodes a BOM-less
# .ps1 as ANSI, so non-ASCII comments here break the parser. The changelog text
# itself is passed on the command line, where UTF-8 is handled correctly.
if ([string]::IsNullOrWhiteSpace($Changelog)) {
    throw ('-Changelog must not be empty: version.json is replaced wholesale ' +
           'and an empty value blanks out the changelog shown in the app. ' +
           'Pass the release notes explicitly on the command line.')
}

$meta = [ordered]@{
    latest       = $Version
    minSupported = $MinSupported
    changelog    = $Changelog
    sha256       = $sha
    releasedAt   = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
}
$metaPath = Join-Path $env:TEMP 'version.json'
$metaJson = $meta | ConvertTo-Json
[System.IO.File]::WriteAllText($metaPath, $metaJson, (New-Object System.Text.UTF8Encoding($false)))
Write-Step 'version.json'
Write-Host $metaJson

# ---- upload ---------------------------------------------------------------
Write-Step 'Upload over SSH'
$sec = ConvertTo-SecureString $Password -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential($User, $sec)
$session = New-SSHSession -ComputerName $Server -Credential $cred -AcceptKey -Force
if (-not $session) { throw 'SSH connection failed' }
$sid = $session.SessionId

# NOTE: this returns a HASHTABLE, not a bare exit code.
#
# Why: in Windows PowerShell 5.1, `Write-Host` output still lands in the
# function's output stream, so `return [int]$r.ExitStatus` came back as
# Object[] (host text + the int) and `[int]$st` then threw
# "Cannot convert the System.Object[] value ... to type System.Int32".
# Returning a single structured object removes the ambiguity entirely.
function Invoke-Remote($cmd) {
    $r = Invoke-SSHCommand -SessionId $sid -Command $cmd -TimeOut 3600
    Write-Host ("  --- remote (exit {0}) ---" -f $r.ExitStatus)
    if ($r.Output) { $r.Output | ForEach-Object { Write-Host "  $_" } }
    if ($r.Error) {
        $r.Error | Where-Object { $_ -and $_.Trim() } | ForEach-Object { Write-Host "  ERR: $_" }
    }
    return @{ Exit = [int]$r.ExitStatus; Output = (($r.Output | Out-String).Trim()) }
}

$remoteApkDir = '/home/ubuntu/campus-run-backend/apk'

$failed = $false

try {
    Invoke-Remote 'mkdir -p /home/ubuntu/campus-run-backend/apk' | Out-Null

    Write-Host '  uploading APK (54 MB, takes a minute or two over this link)...'
    # Set-SCPItem's -Destination is a DIRECTORY, not a file path: passing
    # "dir/file" yields `scp: .../file: Not a directory`.
    # So upload into a staging dir and move into place afterwards -- which also
    # makes the swap atomic, so a download that starts mid-upload can never get
    # a truncated APK (Android would just say "package appears to be invalid").
    $r0 = Invoke-Remote "rm -rf $remoteApkDir/staging && mkdir -p $remoteApkDir/staging"
    if ($r0.Exit -ne 0) { throw "cannot create staging dir (exit $($r0.Exit))" }

    Set-SCPItem -ComputerName $Server -Credential $cred -AcceptKey `
        -Path $apk.FullName -Destination "$remoteApkDir/staging" -Force | Out-Null
    Set-SCPItem -ComputerName $Server -Credential $cred -AcceptKey `
        -Path $metaPath -Destination "$remoteApkDir/staging" -Force | Out-Null
    Write-Host '  uploaded to staging'

    Write-Step 'Install atomically + fix permissions'
    # SCP keeps the LOCAL basename, so normalise whatever landed.
    # `mv` inside one filesystem is atomic: readers see the old file or the new
    # one, never a half-written one.
    $r1 = Invoke-Remote @"
set -e
cd $remoteApkDir
for f in staging/*.apk;  do [ -f "`$f" ] && mv -f "`$f" campus-run.apk; done
for f in staging/*.json; do [ -f "`$f" ] && mv -f "`$f" version.json;   done
rmdir staging 2>/dev/null || true
# The container runs as app(uid 999) and mounts this dir read-only.
# A 600 file would be unreadable -> the app reports 404 on download.
chmod 755 .
chmod 644 campus-run.apk version.json

# ---- also refresh the WEBSITE's copy of version.json -----------------------
#
# WARNING: there are TWO version.json on this server and they are served by
# different hosts:
#   apk/version.json      -> the App's API (read by the server on every request)
#   site/version.json     -> the website, which fetches it at runtime from
#                            https://dl.hibiscus.wiki:8443/version.json
#                            to refresh the version badge on the page
#
# deploy-site.ps1 regenerates the site copy, but a release does NOT run that
# script -- so after a release the website kept showing the PREVIOUS version
# (observed: API said 2.3.0 while the site badge still said 2.2.2, because
# release 2.3.0 never touched site/version.json).
#
# Copying it here keeps the two in sync without requiring a site deploy.
# `cp` inside one filesystem is not atomic, so write to a temp then mv.
if [ -d ../site ]; then
  cp -f version.json ../site/version.json.tmp
  mv -f ../site/version.json.tmp ../site/version.json
  chmod 644 ../site/version.json
  echo "site/version.json updated:"
  head -c 120 ../site/version.json
  echo
else
  echo "WARN: ../site not found - the website will keep its old version badge"
fi
ls -la
"@
    if ($r1.Exit -ne 0) { throw "install step failed (exit $($r1.Exit))" }
    if ($r1.Exit -ne 0) { throw "install step failed (exit $($r1.Exit))" }

    Write-Step 'Verify the APK is readable from inside the container'
    $r2 = Invoke-Remote 'D="docker"; docker ps >/dev/null 2>&1 || D="sudo docker"; $D exec campus-run-app sh -c "ls -la /app/apk/ && head -c 4 /app/apk/campus-run.apk | od -An -tx1"'
    if ($r2.Exit -ne 0) { throw "container cannot see /app/apk (exit $($r2.Exit)) - does the compose file mount ./apk?" }

    Write-Step 'Verify the public version endpoint'
    $r3 = Invoke-Remote 'curl -s http://127.0.0.1:8080/api/v1/app/version'
    $body = $r3.Output
    # A release that reports success while the endpoint says apkReady=false is
    # worse than a failed release: the APK is on the server but nobody is told.
    if ($body -notmatch '"apkReady":true') { throw "version endpoint reports apkReady != true" }
    if ($body -notmatch [regex]::Escape($Version)) { throw "version endpoint does not report $Version" }

    Write-Step 'Verify the public download endpoint'
    $r4 = Invoke-Remote 'curl -s -o /dev/null -w "  download -> HTTP %{http_code}, %{size_download} bytes, type=%{content_type}\n" http://127.0.0.1:8080/api/v1/app/download'
    if ($r4.Exit -ne 0) { throw "download check failed (exit $($r4.Exit))" }
}
catch {
    $failed = $true
    Write-Host ""
    Write-Host "!! RELEASE FAILED: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    try { Remove-SSHSession -SessionId $sid | Out-Null } catch { }
}

if ($failed) { exit 1 }

Write-Host ""
Write-Host "=== RELEASE DONE ===" -ForegroundColor Green
Write-Host "Published version: $Version"
Write-Host "Anyone still on an older version gets an update prompt on next launch."
