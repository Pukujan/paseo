# Starts the Paseo daemon in the foreground for the hidden logon task that
# install-friend.ps1 registers. The task runs it through `conhost.exe --headless`,
# so no window ever shows.
#
# Settings (listen address, relay, providers) live in %USERPROFILE%\.paseo\config.json.
# When the listen address is a specific IP (for example a Tailscale address), this
# waits up to -WaitMinutes for that address to come up before starting the daemon.
param(
    [int]$WaitMinutes = 10,
    [string]$PaseoHome = (Join-Path $env:USERPROFILE '.paseo')
)
$ErrorActionPreference = 'Continue'

$logDir = Join-Path $PaseoHome 'friend\logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$log = Join-Path $logDir 'autostart.log'
$consoleLog = Join-Path $logDir 'daemon-console.log'
function Write-StartLog([string]$Message) {
    ((Get-Date -Format s) + ' ' + $Message) | Out-File -Append -Encoding utf8 -FilePath $log
}

# A logon task gets the PATH from when the user signed in. Rebuild it from the
# registry so pnpm, node, claude and agy installed since then are found.
$machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$extra = @()
$pnpmHome = [Environment]::GetEnvironmentVariable('PNPM_HOME', 'User')
if (-not $pnpmHome) { $pnpmHome = Join-Path $env:LOCALAPPDATA 'pnpm' }
$env:PNPM_HOME = $pnpmHome
$extra += $pnpmHome
$extra += (Join-Path $env:LOCALAPPDATA 'agy\bin')
$extra += (Join-Path $env:USERPROFILE '.local\bin')
$extra += (Join-Path $env:ProgramFiles 'Tailscale')
$env:Path = (@($extra) + @($userPath, $machinePath) | Where-Object { $_ }) -join ';'

# Size-cap the console log so it can't grow forever.
if ((Test-Path -LiteralPath $consoleLog) -and ((Get-Item -LiteralPath $consoleLog).Length -gt 10MB)) {
    Move-Item -Force -LiteralPath $consoleLog -Destination ($consoleLog + '.1')
}

$listenIp = $null
try {
    $cfg = Get-Content -LiteralPath (Join-Path $PaseoHome 'config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($cfg.daemon -and $cfg.daemon.listen) {
        $listen = [string]$cfg.daemon.listen
        if ($listen -match '^\[(.+)\]:\d+$') { $listenIp = $Matches[1] }
        elseif ($listen -match '^([^:]+):\d+$') { $listenIp = $Matches[1] }
    }
} catch {
    Write-StartLog "could not read config.json: $($_.Exception.Message)"
}

$skipWait = @('127.0.0.1', 'localhost', '0.0.0.0', '::', '::1')
if ($listenIp -and ($skipWait -notcontains $listenIp) -and ($listenIp -match '^[0-9a-fA-F:.]+$')) {
    $deadline = (Get-Date).AddMinutes($WaitMinutes)
    while ((Get-Date) -lt $deadline) {
        if (Get-NetIPAddress -IPAddress $listenIp -ErrorAction SilentlyContinue) { break }
        Start-Sleep -Seconds 10
    }
    $ready = [bool](Get-NetIPAddress -IPAddress $listenIp -ErrorAction SilentlyContinue)
    Write-StartLog "listen address ready: $ready"
}

$paseo = Get-Command paseo.cmd, paseo -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $paseo) {
    Write-StartLog 'paseo is not on PATH; nothing to start'
    exit 1
}
Write-StartLog "starting: $($paseo.Source) daemon run"
& $paseo.Source daemon run *>> $consoleLog
Write-StartLog "paseo daemon exited with $LASTEXITCODE"
exit $LASTEXITCODE
