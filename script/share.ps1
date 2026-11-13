param(
    [ValidateSet('server', 'tunnel')][string]$Mode = 'server',
    [ValidateSet('localhost.run', 'pinggy')][string]$Provider = 'localhost.run',
    [ValidateRange(1024, 65535)][int]$Port = 3002,
    [switch]$Local
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot
$savedEnvironment = @{}
try {
    if ($Local -and $Mode -eq 'tunnel') { throw '-Local is only for the server; do not expose local HTTP mode through a tunnel.' }
    if ($Mode -eq 'tunnel') {
        Get-Command ssh -ErrorAction Stop | Out-Null
        $health = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$Port/up" -TimeoutSec 5
        if ($health.StatusCode -ne 200) { throw 'Start the share server first.' }
        if ($health.Headers['X-RPI-Demo-Mode'] -ne 'https-tunnel') { throw 'The server is not in HTTPS tunnel mode. Restart it without -Local before opening a tunnel.' }
        # Keep provider host keys separate from the user's SSH configuration.
        New-Item -ItemType Directory -Force -Path tmp | Out-Null
        $knownHosts = Join-Path $projectRoot 'tmp/share-known-hosts'
        $sshOptions = @('-F', 'none', '-o', "UserKnownHostsFile=$knownHosts", '-o', 'StrictHostKeyChecking=accept-new', '-o', 'ServerAliveInterval=30', '-o', 'ServerAliveCountMax=3', '-o', 'ExitOnForwardFailure=yes', '-o', 'ConnectTimeout=15')
        Write-Host 'Share only the HTTPS URL printed below. Ctrl+C closes the tunnel.'
        if ($Provider -eq 'localhost.run') {
            & ssh @sshOptions -T -R "80:127.0.0.1:$Port" nokey@localhost.run
        } else {
            Write-Host 'If Pinggy asks for a password, press Enter.'
            & ssh @sshOptions -T -p 443 -R "0:127.0.0.1:$Port" free.pinggy.io
        }
        if ($LASTEXITCODE -ne 0) { throw "Tunnel disconnected (exit $LASTEXITCODE). Try the other provider." }
    } else {
        Get-Command ruby -ErrorAction Stop | Out-Null
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
        try { $listener.Start() } finally { $listener.Stop() }
        New-Item -ItemType Directory -Force -Path storage, tmp/pids | Out-Null
        $secretFile = Join-Path $projectRoot 'storage/share-secret-key'
        if (-not (Test-Path -LiteralPath $secretFile)) {
            & ruby -rsecurerandom -e 'File.open(ARGV.fetch(0), File::WRONLY | File::CREAT | File::EXCL, 0600) { |f| f.write(SecureRandom.hex(64)) }' $secretFile
            if ($LASTEXITCODE -ne 0) { throw 'Could not generate the session secret.' }
        }
        $variables = @{
            RAILS_ENV = 'production'
            RPI_PUBLIC_TUNNEL = $(if ($Local) { '0' } else { '1' })
            RPI_LOCAL_DEMO = $(if ($Local) { '1' } else { '0' })
            SECRET_KEY_BASE = (Get-Content -LiteralPath $secretFile -Raw).Trim()
            RAILS_SERVE_STATIC_FILES = '1'
            # Puma uses 0 workers for single-process mode (Windows has no fork).
            WEB_CONCURRENCY = '0'
            SOLID_QUEUE_IN_PUMA = $null
        }
        foreach ($name in $variables.Keys) {
            $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
            if ($null -eq $variables[$name]) {
                Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
            } else {
                [Environment]::SetEnvironmentVariable($name, $variables[$name], 'Process')
            }
        }
        & ruby bin/rails db:prepare assets:precompile
        if ($LASTEXITCODE -ne 0) { throw 'Database/assets preparation failed.' }
        if ($Local) {
            Write-Host "Local HTTP demo: open http://127.0.0.1:$Port . Do not start a tunnel in this mode."
        } else {
            Write-Host "Ready to start. In another PowerShell: .\script\share.ps1 -Mode tunnel -Port $Port"
            Write-Host 'Use the public HTTPS link on this PC too. Local HTTP is only for /up health checks.'
        }
        Write-Host 'This uses storage/production*.sqlite3, not your development save. Ctrl+C stops Rails.'
        & ruby bin/rails server -e production -b 127.0.0.1 -p $Port -P tmp/pids/share.pid
        if ($LASTEXITCODE -ne 0) { throw "Rails exited with code $LASTEXITCODE" }
    }
} finally {
    foreach ($name in $savedEnvironment.Keys) {
        if ($null -eq $savedEnvironment[$name]) {
            Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
        } else {
            [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process')
        }
    }
    Pop-Location
}
