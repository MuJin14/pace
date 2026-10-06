# Deploy the static website + apply the Caddy config, SAFELY.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File campus-run-backend\deploy-site.ps1 -Password 'xxx'
#   powershell -ExecutionPolicy Bypass -File campus-run-backend\deploy-site.ps1 -Password 'xxx' -SiteDir 'C:\path\to\site'
#
# Design notes (each one is paid for by a real incident):
#
#  * Only caddy is recreated, with --no-deps. `docker compose up caddy` also
#    walks the dependency chain (caddy -> app -> mysql) and rebuilds MySQL,
#    which takes it down for ~30s and once left it crash-looping.
#
#  * The Caddyfile is validated in a throwaway container BEFORE it goes live.
#    A bad Caddyfile takes down both the site and the API.
#
#  * The compose file is NOT uploaded by this script. It lives on the server
#    and contains production-specific values; overwriting it from the repo has
#    already broken MySQL once. Only the site files and the Caddyfile move.
#
#  * No here-strings anywhere. PowerShell 5.1's parser mis-handled them in this
#    file repeatedly ("string is missing the terminator" / "missing }"), so the
#    remote shell snippets are built as plain single-quoted strings instead.

param(
    [Parameter(Mandatory = $true)][string]$Password,
    [string]$SiteDir = '',
    [string]$Server = '122.51.191.145',
    [string]$User = 'ubuntu',
    [string]$RemoteDir = '/home/ubuntu/campus-run-backend'
)

$ErrorActionPreference = 'Stop'
Import-Module Posh-SSH

function Write-Step($m) { Write-Host "`n=== $m ===" -ForegroundColor Cyan }

$Root = $PSScriptRoot
if (-not $SiteDir) { $SiteDir = Join-Path $Root 'site' }
if (-not (Test-Path $SiteDir)) { throw "site dir not found: $SiteDir" }
$caddyfile = Join-Path $Root 'docker\Caddyfile'
if (-not (Test-Path $caddyfile)) { throw "missing: $caddyfile" }

Write-Step 'Local files'
Get-ChildItem $SiteDir -Recurse -File | ForEach-Object {
    Write-Host ("  site: {0}  {1:N0} bytes" -f $_.FullName.Substring($SiteDir.Length + 1), $_.Length)
}
Write-Host ("  caddyfile: {0}" -f $caddyfile)

# Generate version.json into the site dir.
#
# Why the site needs its own copy: the page shows an "online vX.Y.Z" badge and
# the APK size. The obvious implementation -- fetch('/api/v1/app/version') from
# the page -- does NOT work on the site domain: Cloudflare's Origin Rule
# (which rewrites the origin port to 8443) covers the site paths but not /api,
# so that request 404s at the edge. Verified: the origin answers 200,
# Cloudflare answers 404.
#
# A local JSON file has no such dependency: same origin, served by file_server,
# and refresh it here on every deploy.
$tmpVer = Join-Path $env:TEMP 'campus-run-site-version.json'
try {
    # Direct server address FIRST. It always works and cannot be affected by
    # Cloudflare / DNS / certificate problems -- every failure this site has had
    # came from one of those. The download host is only a secondary attempt.
    #
    # Use curl, not Invoke-RestMethod: the latter fails on the origin
    # certificate (Cloudflare Origin CA is not publicly trusted), and an
    # earlier version of this block called a function defined further down the
    # file -- it threw, the catch swallowed it, and version.json silently kept
    # its old value (the site badge sat at 1.3.0 through the 1.4.1 release).
    $ver = $null
    foreach ($base in @('http://122.51.191.145:8080', 'https://dl.hibiscus.wiki:8443')) {
        try {
            $raw = & curl.exe -sk --max-time 20 "$base/api/v1/app/version" 2>$null
            if (-not $raw) { continue }
            $parsed = ($raw -join '') | ConvertFrom-Json
            if ($parsed.data.latest) {
                $ver = $parsed
                Write-Host ("  version from {0}: v{1}" -f $base, $ver.data.latest)
                break
            }
        } catch { }
    }
    if ($ver -and $ver.data.latest) {
        $obj = [ordered]@{
            latest       = $ver.data.latest
            apkSizeBytes = $ver.data.apkSizeBytes
            minSupported = $ver.data.minSupported
            changelog    = $ver.data.changelog
        }
        [System.IO.File]::WriteAllText($tmpVer, ($obj | ConvertTo-Json),
            (New-Object System.Text.UTF8Encoding($false)))
        Copy-Item $tmpVer (Join-Path $SiteDir 'version.json') -Force
        Write-Host ("  version.json: v{0}  {1:N1} MB" -f $obj.latest, ($obj.apkSizeBytes / 1MB))
    }
} catch {
    Write-Host ("  WARN: could not fetch version ({0}) - page keeps its previous values" -f $_.Exception.Message) -ForegroundColor Yellow
}

# Bake the version into the HTML and cache-bust the assets.
#
# Embedded (not fetched): the site domain cannot reach /api or /version.json --
# Cloudflare's edge serves 404 for every path that needs an origin fetch, while
# already-cached files serve fine. So the page must not make any request.
#
# Cache-busted: Cloudflare caches this HTML and css/webp aggressively, and we
# have no API token to purge with. Appending ?v=<version> to the asset URLs
# makes every release a fresh URL, so the edge picks up the new files without a
# manual purge. (The HTML itself still needs ONE manual purge -- after that,
# setting a Cache Rule of "Bypass cache for text/html" keeps it fresh.)
Write-Step 'Bake version into HTML + cache-bust assets'
# The embed script lives at the REPOSITORY root, not inside campus-run-backend.
#
# NOTE: this used to be `Join-Path $Root 'tools\...'` where $Root is
# campus-run-backend -- so Test-Path was false, the whole block was skipped
# SILENTLY, and the version badge + asset ?v= never got updated. That is why
# the site kept showing an old version (a symptom documented earlier as
# "version.json is stale" and mis-attributed to the fetch step).
#
# Never let this fail silently again: warn loudly when the script is missing.
$embedCandidates = @(
    (Join-Path (Split-Path $Root -Parent) 'tools\embed_site_version.py'),
    (Join-Path $Root 'tools\embed_site_version.py')
)
$embed = $embedCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $embed) {
    Write-Host '  WARN: embed_site_version.py not found - the page version badge' -ForegroundColor Yellow
    Write-Host '        and asset ?v= will stay at the previous release.' -ForegroundColor Yellow
    foreach ($c in $embedCandidates) { Write-Host "        looked for: $c" -ForegroundColor Yellow }
} else {
    Write-Host "  embed script: $embed"
    # Never resolve python from PATH: on Windows that often hits the
    # Microsoft Store stub, which opens the Store instead of running.
    $py = @(
        (Join-Path $env:USERPROFILE 'AppData\Local\Programs\Python\Python312\python.exe'),
        (Join-Path $env:USERPROFILE 'AppData\Local\Programs\Python\Python311\python.exe'),
        'C:\Program Files\Python312\python.exe',
        'C:\Program Files\Python311\python.exe',
        'C:\Python312\python.exe',
        'C:\Python311\python.exe'
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1

    if ($py) {
        Write-Host "  python: $py"
        & $py $embed
        if ($LASTEXITCODE -ne 0) { Write-Host '  WARN: embed script failed' -ForegroundColor Yellow }
    } else {
        Write-Host '  WARN: python not found - version badge keeps its previous value' -ForegroundColor Yellow
    }
}

Write-Step 'Connect'
$sec = ConvertTo-SecureString $Password -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential($User, $sec)
$session = New-SSHSession -ComputerName $Server -Credential $cred -AcceptKey -Force
if (-not $session) { throw 'SSH failed' }
$sid = $session.SessionId

# Run a command remotely. Returns @{ Exit = int; Output = text }.
# Returns a hashtable rather than a bare int because in PowerShell 5.1
# Write-Host output also lands in the function's output stream, so
# `return [int]$r.ExitStatus` came back as Object[] and `-ne 0` was always
# false -- which silently turned failures into "success".
function Invoke-Remote($cmd) {
    $r = Invoke-SSHCommand -SessionId $sid -Command $cmd -TimeOut 3600
    Write-Host ("  --- remote (exit {0}) ---" -f $r.ExitStatus)
    if ($r.Output) { $r.Output | ForEach-Object { Write-Host "  $_" } }
    if ($r.Error) {
        $r.Error | Where-Object { $_ -and $_.Trim() } | ForEach-Object { Write-Host "  ERR: $_" }
    }
    return @{ Exit = [int]$r.ExitStatus; Output = (($r.Output | Out-String).Trim()) }
}

# Plain docker ps output. Avoids --format (PowerShell reads "--" as an operator)
# and its default table already has NAMES and STATUS.
$PS_ALL = 'docker ps -a 2>/dev/null || sudo docker ps -a'
$PS_CADDY = 'docker ps 2>/dev/null | grep campus-run-caddy || sudo docker ps | grep campus-run-caddy'

$failed = $false
$stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')

try {
    Write-Step 'Backup current Caddyfile on the server'
    $b = Invoke-Remote ("cd $RemoteDir && cp -f docker/Caddyfile docker/Caddyfile.bak-$stamp && ls -la docker/Caddyfile.bak-$stamp")
    if ($b.Exit -ne 0) { throw "backup failed ($($b.Exit))" }

    Write-Step 'Pack the site and upload into a staging dir'
    $r0 = Invoke-Remote ("rm -rf $RemoteDir/staging && mkdir -p $RemoteDir/staging/site $RemoteDir/staging/docker")
    if ($r0.Exit -ne 0) { throw "staging failed ($($r0.Exit))" }

    # The APK lives inside the site so downloading it is a plain static file
    # request. That removes every runtime dependency -- no /api passthrough, no
    # Caddy reverse proxy, no Cloudflare Origin Rule. Those were the parts that
    # kept breaking; a static file just works.
    #
    # It is 54 MB though, so do NOT re-upload it every deploy. Compare the
    # sha256 against a manifest kept next to it on the server.
    $apkLocal = Join-Path $SiteDir 'downloads\campus-run.apk'
    $apkManifest = "$RemoteDir/site/downloads/.campus-run.apk.sha256"
    $skipApk = $false
    $apkHash = ''
    if (Test-Path $apkLocal) {
        $apkHash = (Get-FileHash $apkLocal -Algorithm SHA256).Hash
        $remoteHash = (Invoke-Remote "cat $apkManifest 2>/dev/null || true").Output
        if ($remoteHash -and ($remoteHash.Trim() -eq $apkHash)) {
            $skipApk = $true
            Write-Host ("  APK unchanged ({0}...) - skipping the 54 MB upload" -f $apkHash.Substring(0, 12))
        } else {
            Write-Host ("  APK changed ({0}...) - will upload" -f $apkHash.Substring(0, 12))
        }
    }

    # Set-SCPItem has no -Recurse, so a folder cannot be uploaded directly.
    # bsdtar writes forward slashes; Compress-Archive writes backslashes, which
    # Linux unpacks as literal filename characters.
    $siteTar = Join-Path $env:TEMP 'campus-run-site.tar.gz'
    if (Test-Path $siteTar) { Remove-Item $siteTar -Force }
    Push-Location $SiteDir
    try {
        if ($skipApk) {
            & tar -czf $siteTar --exclude "./downloads" .
        } else {
            & tar -czf $siteTar .
        }
        if ($LASTEXITCODE -ne 0) { throw "tar failed ($LASTEXITCODE)" }
    } finally { Pop-Location }

    $listing = & tar -tzf $siteTar
    if (-not $listing) { throw 'site tar is empty' }
    Write-Host ("  packed {0} entries  {1:N0} KB" -f $listing.Count, ((Get-Item $siteTar).Length / 1KB))

    Set-SCPItem -ComputerName $Server -Credential $cred -AcceptKey -Path $siteTar -Destination "$RemoteDir/staging" -Force | Out-Null
    Set-SCPItem -ComputerName $Server -Credential $cred -AcceptKey -Path $caddyfile -Destination "$RemoteDir/staging/docker" -Force | Out-Null
    Write-Host '  uploaded'

    $x = Invoke-Remote ("cd $RemoteDir/staging && tar -xzf campus-run-site.tar.gz -C site && rm -f campus-run-site.tar.gz && find site -type f | head -40")
    if ($x.Exit -ne 0) { throw "extract failed ($($x.Exit))" }

    if (-not $skipApk -and (Test-Path $apkLocal)) {
        Write-Step 'Upload the APK (54 MB, once per version)'
        $rA = Invoke-Remote ("mkdir -p $RemoteDir/staging/site/downloads && ls -la $RemoteDir/staging/site/")
        if ($rA.Exit -ne 0) { throw "apk staging failed ($($rA.Exit))" }
        # Destination is a DIRECTORY for Set-SCPItem.
        Set-SCPItem -ComputerName $Server -Credential $cred -AcceptKey -Path $apkLocal -Destination "$RemoteDir/staging/site/downloads" -Force | Out-Null
        $rB = Invoke-Remote ("ls -la $RemoteDir/staging/site/downloads/")
        if ($rB.Exit -ne 0) { throw "apk upload failed ($($rB.Exit))" }
    }

    Write-Step 'Validate the new Caddyfile BEFORE touching the live one'
    # Throws away container, same image the service uses (plain caddy:2 -- no
    # cloudflare plugin needed because TLS uses the Cloudflare ORIGIN
    # certificate from /certs).
    $vc = "cd $RemoteDir && D='docker'; docker ps >/dev/null 2>&1 || D='sudo docker'; " +
          "`$D run --rm -v '$RemoteDir/staging/docker/Caddyfile:/etc/caddy/Caddyfile:ro' " +
          "-v '$RemoteDir/certs:/certs:ro' -v '$RemoteDir/staging/site:/srv/site:ro' " +
          "caddy:2 caddy validate --config /etc/caddy/Caddyfile"
    $v = Invoke-Remote $vc
    if ($v.Exit -ne 0) { throw 'caddy validate FAILED - aborting, live config untouched' }

    Write-Step 'Install live'
    # mkdir -p site/downloads: tar extracts the staged tree, but when the APK
    # was skipped the downloads dir may be absent and `cp -rf` would not create
    # it -- leaving the download link broken until someone notices.
    $i1 = Invoke-Remote ("cd $RemoteDir && mkdir -p site/downloads && cp -rf staging/site/. site/ && cp -f staging/docker/Caddyfile docker/Caddyfile && rm -rf staging && chmod -R a+r site && chmod 755 site site/downloads && ls -la site && ls -la site/downloads")
    if ($i1.Exit -ne 0) { throw "install failed ($($i1.Exit))" }

    # Record the APK hash so the next deploy can skip the 54 MB upload.
    if ($apkHash) {
        $m = Invoke-Remote ("echo '$apkHash' > $apkManifest && cat $apkManifest")
        if ($m.Exit -ne 0) { Write-Host '  WARN: could not write the APK manifest (will re-upload next time)' -ForegroundColor Yellow }
        else { Write-Host ("  APK manifest written: {0}..." -f $apkHash.Substring(0, 12)) }
    }

    Write-Step 'Recreate caddy only (--no-deps keeps mysql/app untouched)'
    # --force-recreate, not a plain up: a NEW site block in the Caddyfile is
    # NOT picked up by Caddy's config watcher (adding dl.hibiscus.wiki returned
    # HTTP 200 with a 0-byte body, while the blocks that already existed kept
    # working). Only a full recreate applies it. --no-deps still protects
    # mysql/app from being pulled in by the dependency chain.
    $c = Invoke-Remote ("cd $RemoteDir && D='docker'; docker ps >/dev/null 2>&1 || D='sudo docker'; `$D compose -f docker-compose.deploy.yml up -d --no-build --no-deps --force-recreate caddy")
    if ($c.Exit -ne 0) { throw "recreate failed ($($c.Exit))" }

    Start-Sleep -Seconds 12

    Write-Step 'Assert the other services were NOT disturbed'
    # This check exists because the previous version reported success while
    # MySQL was crash-looping after being pulled in by the dependency chain.
    $st = Invoke-Remote $PS_ALL
    Write-Host $st.Output
    $nl = [char]10
    foreach ($name in @('campus-run-mysql', 'campus-run-app')) {
        $line = (($st.Output -split $nl) | Where-Object { $_ -match $name }) -join ' '
        if ($line -notmatch 'Healthy|healthy|Up') {
            throw "$name is not Up after the site deploy: '$line'"
        }
    }

    $cs = Invoke-Remote $PS_CADDY
    if ($cs.Output -notmatch 'Up') { throw "caddy is not Up: '$($cs.Output)'" }

    Write-Step 'Verify from inside the server'
    $s1 = Invoke-Remote 'curl -sk -o /dev/null -w "  site -> HTTP %{http_code}, %{size_download} bytes\n" --resolve hibiscus.wiki:8443:127.0.0.1 https://hibiscus.wiki:8443/'
    $s2 = Invoke-Remote 'curl -sk -o /dev/null -w "  api  -> HTTP %{http_code}\n" --resolve api.hibiscus.wiki:8443:127.0.0.1 https://api.hibiscus.wiki:8443/api/v1/app/version'
    $s3 = Invoke-Remote 'curl -sk -o /dev/null -w "  site api passthrough -> HTTP %{http_code}\n" --resolve hibiscus.wiki:8443:127.0.0.1 https://hibiscus.wiki:8443/api/v1/app/version'
    if ($s3.Output -notmatch 'HTTP 200') {
        Write-Host '  WARN: /api/* on the site domain is not 200 - the version badge will stay static' -ForegroundColor Yellow
    }

    # The download is now a plain static file, so assert it is actually served
    # and has a sane size. Reporting success while the download 404s is exactly
    # the failure mode this script already hit once.
    Write-Step 'Assert the APK download works'
    $d1 = Invoke-Remote 'curl -sk -o /dev/null -w "%{http_code} %{size_download} %{content_type}" --resolve hibiscus.wiki:8443:127.0.0.1 https://hibiscus.wiki:8443/downloads/campus-run.apk'
    Write-Host ("  /downloads/campus-run.apk -> {0}" -f $d1.Output)
    $dParts = ($d1.Output -split '\s+')
    if ($dParts.Count -lt 2 -or $dParts[0] -ne '200') {
        throw "APK is not downloadable (got: $($d1.Output))"
    }
    $apkBytes = [int64]$dParts[1]
    if ($apkBytes -lt 10MB) {
        throw "APK looks truncated: only $apkBytes bytes served"
    }
    Write-Host ("  OK: {0:N1} MB served" -f ($apkBytes / 1MB))
}
catch {
    $failed = $true
    Write-Host ''
    Write-Host "!! DEPLOY FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "   Caddyfile backup on the server: docker/Caddyfile.bak-$stamp"
}
finally {
    try { Remove-SSHSession -SessionId $sid | Out-Null } catch { }
}

if ($failed) { exit 1 }

Write-Host ''
Write-Host '=== SITE DEPLOY DONE ===' -ForegroundColor Green
