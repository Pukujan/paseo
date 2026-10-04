<#
.SYNOPSIS
  One-command setup of Paseo + Claude Code (InferHub launcher) on Windows.

.DESCRIPTION
  1. Runs the claude-code-launcher installer (Pukujan/claude-code-launcher). It sets
     up the LiteLLM proxy, Claude Code and the `claude-inferhub` command.
  2. Installs Paseo (pinned, default 0.10.3) globally with pnpm and registers a hidden
     logon task that runs the Paseo daemon.
  3. Points Paseo's Claude provider at the launcher, merged into
     %USERPROFILE%\.paseo\config.json (backed up first, nothing else changed).
  4. Optional (-WithAgy): Google's Antigravity CLI and the community Paseo plugin
     paseo-plugin-antigravity-cli, for one Antigravity account (this Windows user).

  Run it again any time; it only changes what's out of date. -Uninstall takes it all
  back out. -DryRun prints what it would do and changes nothing.

.EXAMPLE
  irm https://github.com/Pukujan/paseo/releases/download/friend-v1.0.0/install-friend.ps1 | iex

.EXAMPLE
  & ([scriptblock]::Create((irm https://github.com/Pukujan/paseo/releases/download/friend-v1.0.0/install-friend.ps1))) -WithAgy -Tailscale

.EXAMPLE
  .\install-friend.ps1 -DryRun -WithAgy
#>
[CmdletBinding()]
param(
    # Passed to the launcher installer. If empty, the launcher asks (masked) or uses
    # CCL_INFERHUB_KEY / INFERHUB_API_KEY / the key from an earlier install.
    [string]$InferHubKey = '',
    [string]$TinyFishKey = '',
    [switch]$SkipTinyFish,

    # Which launcher to install. A tag uses the release asset; anything else (a
    # branch, a commit) uses windows/install.ps1 from that ref.
    [string]$LauncherRef = 'v1.0.0-windows',
    # Full URL of the launcher's install.ps1; overrides the one built from -LauncherRef.
    [string]$LauncherInstallerUrl = '',
    [string]$LauncherDir = '',
    # Don't run the launcher installer (it's already set up).
    [switch]$SkipLauncher,
    # With -Uninstall: leave the launcher installed.
    [switch]$KeepLauncher,

    [string]$PaseoVersion = '0.10.3',
    [string]$TaskName = 'Paseo Daemon',
    [int]$Port = 6767,
    # Listen on this computer's Tailscale address instead of only 127.0.0.1.
    [switch]$Tailscale,
    # Listen on this exact address (ip:port). Wins over -Tailscale.
    [string]$ListenAddress = '',

    [switch]$WithAgy,
    [string]$AgyPluginVersion = '0.9.1',
    [string]$AgyInstallerUrl = 'https://antigravity.google/cli/install.ps1',

    # Where the helper files (paseo-config.mjs, start-paseo.ps1) come from when this
    # script isn't run from a folder that already has them.
    [string]$PackageBaseUrl = '',

    [switch]$NonInteractive,
    [switch]$Uninstall,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$script:FriendVersion = '1.0.0'
$script:FriendReleaseTag = 'friend-v1.0.0'
$script:FriendRepo = 'Pukujan/paseo'
$script:LauncherRepo = 'Pukujan/claude-code-launcher'
$script:PaseoPackage = '@getpaseo/cli'
$script:AgyPluginPackage = 'paseo-plugin-antigravity-cli'
$script:AgyPluginId = 'antigravity-cli'
$script:StateSchema = 'paseo-friend.install.v1'
$script:LogFile = $null
$script:DryRunMode = [bool]$DryRun

# ---------------------------------------------------------------- helpers

function Write-Friend {
    param([string]$Message, [string]$Level = 'info')
    switch ($Level) {
        'warn' { Write-Warning $Message }
        'plan' { Write-Host ('[dry-run] would ' + $Message) -ForegroundColor Cyan }
        'step' { Write-Host ('==> ' + $Message) -ForegroundColor Green }
        default { Write-Host ('    ' + $Message) }
    }
    if ($script:LogFile -and -not $script:DryRunMode) {
        try { Add-Content -LiteralPath $script:LogFile -Value ((Get-Date -Format s) + ' ' + $Level + ' ' + $Message) -Encoding UTF8 } catch { }
    }
}

# Runs $Action unless this is a dry run, in which case it only says what it would do.
function Invoke-Change {
    param([string]$What, [scriptblock]$Action)
    if ($script:DryRunMode) { Write-Friend $What 'plan'; return $null }
    Write-Friend $What
    return (& $Action)
}

function Write-Utf8NoBom {
    param([string]$Path, [string]$Text)
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false)))
}

function Update-SessionPath {
    # Pick up PATH changes other installers made (launcher, pnpm setup, agy).
    $parts = @()
    if ($env:PNPM_HOME) { $parts += $env:PNPM_HOME }
    $parts += [Environment]::GetEnvironmentVariable('Path', 'User')
    $parts += [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $parts += $env:Path
    $seen = @{}
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($p in (($parts | Where-Object { $_ }) -join ';').Split(';')) {
        $t = $p.Trim()
        if ($t -and -not $seen.ContainsKey($t.ToLowerInvariant())) { $seen[$t.ToLowerInvariant()] = $true; $out.Add($t) }
    }
    $env:Path = ($out -join ';')
}

function Get-Exe {
    param([string[]]$Names)
    foreach ($n in $Names) {
        $c = Get-Command $n -CommandType Application, ExternalScript -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($c) { return $c.Source }
    }
    return $null
}

# Runs a native command, sends its output to the console, returns the exit code.
function Invoke-Native {
    param([string]$File, [string[]]$Arguments)
    # Windows PowerShell 5.1 turns native stderr into errors under 'Stop'.
    $ErrorActionPreference = 'Continue'
    & $File @Arguments 2>&1 | ForEach-Object { Write-Host ('    ' + $_) }
    return $LASTEXITCODE
}

function Get-FriendPaths {
    $paseoHome = if ($env:PASEO_HOME) { $env:PASEO_HOME } else { Join-Path $env:USERPROFILE '.paseo' }
    $friend = Join-Path $paseoHome 'friend'
    $launcher = $LauncherDir
    if (-not $launcher) { $launcher = if ($env:CCL_INSTALL_DIR) { $env:CCL_INSTALL_DIR } else { Join-Path $env:LOCALAPPDATA 'claude-code-launcher' } }
    return [pscustomobject]@{
        PaseoHome   = $paseoHome
        Config      = Join-Path $paseoHome 'config.json'
        Friend      = $friend
        State       = Join-Path $friend 'install-state.json'
        ConfigState = Join-Path $friend 'config-state.json'
        Helper      = Join-Path $friend 'paseo-config.mjs'
        StartScript = Join-Path $friend 'start-paseo.ps1'
        PluginRoot  = Join-Path $friend ('plugins\' + $script:AgyPluginId)
        PluginDir   = Join-Path $friend ('plugins\' + $script:AgyPluginId + '\node_modules\' + $script:AgyPluginPackage)
        Launcher    = $launcher
        EnvExec     = Join-Path $launcher 'app\shared\integrations\claude-env-exec.mjs'
        LauncherPs1 = Join-Path $launcher 'app\windows\install.ps1'
    }
}

function Read-FriendState {
    param($Paths)
    if (Test-Path -LiteralPath $Paths.State) {
        try { return (Get-Content -LiteralPath $Paths.State -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { }
    }
    return $null
}

function Write-FriendState {
    param($Paths, [hashtable]$State)
    $State['schema'] = $script:StateSchema
    $State['version'] = $script:FriendVersion
    Write-Utf8NoBom -Path $Paths.State -Text (ConvertTo-Json -InputObject $State -Depth 5)
}

function Get-LauncherInstallerUrl {
    if ($LauncherInstallerUrl) { return $LauncherInstallerUrl }
    if ($LauncherRef -match '^v\d') {
        return "https://github.com/$($script:LauncherRepo)/releases/download/$LauncherRef/install.ps1"
    }
    return "https://raw.githubusercontent.com/$($script:LauncherRepo)/$LauncherRef/windows/install.ps1"
}

function Get-PackageBaseUrl {
    if ($PackageBaseUrl) { return $PackageBaseUrl.TrimEnd('/') }
    return "https://github.com/$($script:FriendRepo)/releases/download/$($script:FriendReleaseTag)"
}

function Test-UrlReachable {
    param([string]$Url)
    try {
        $r = Invoke-WebRequest -Uri $Url -Method Head -UseBasicParsing -MaximumRedirection 5 -TimeoutSec 20
        return ([int]$r.StatusCode -lt 400)
    } catch { return $false }
}

# Copies a helper file next to this script, or downloads it, to $Destination.
function Get-HelperFile {
    param([string]$Name, [string]$Destination)
    $here = $PSScriptRoot
    if ($here -and (Test-Path -LiteralPath (Join-Path $here $Name))) {
        $dir = Split-Path -Parent $Destination
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        Copy-Item -Force -LiteralPath (Join-Path $here $Name) -Destination $Destination
        return
    }
    $url = (Get-PackageBaseUrl) + '/' + $Name
    $dir = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    Invoke-WebRequest -Uri $url -OutFile $Destination -UseBasicParsing
}

# The helper to use without installing it (dry runs): the local copy, the
# installed copy, or a temp download that's removed afterwards.
function Get-ReadOnlyHelper {
    param($Paths)
    if ($PSScriptRoot -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'paseo-config.mjs'))) {
        return @{ Path = (Join-Path $PSScriptRoot 'paseo-config.mjs'); Temp = $false }
    }
    if (Test-Path -LiteralPath $Paths.Helper) { return @{ Path = $Paths.Helper; Temp = $false } }
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('paseo-config-' + [guid]::NewGuid().ToString('n') + '.mjs')
    try {
        Invoke-WebRequest -Uri ((Get-PackageBaseUrl) + '/paseo-config.mjs') -OutFile $tmp -UseBasicParsing
        return @{ Path = $tmp; Temp = $true }
    } catch { return $null }
}

function Get-TailscaleIPv4 {
    $ErrorActionPreference = 'Continue'
    $ts = Get-Exe @('tailscale.exe', 'tailscale')
    if (-not $ts) {
        $guess = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
        if (Test-Path -LiteralPath $guess) { $ts = $guess }
    }
    if (-not $ts) { return $null }
    $out = & $ts ip -4 2>$null
    foreach ($line in @($out)) {
        $t = ([string]$line).Trim()
        if ($t -match '^\d{1,3}(\.\d{1,3}){3}$') { return $t }
    }
    return $null
}

function Get-PaseoGlobalVersion {
    param([string]$Pnpm)
    $ErrorActionPreference = 'Continue'
    try {
        $json = & $Pnpm ls -g --depth 0 --json 2>$null | Out-String
        if (-not $json.Trim()) { return $null }
        $data = $json | ConvertFrom-Json
        foreach ($entry in @($data)) {
            if ($entry.dependencies -and $entry.dependencies.PSObject.Properties[$script:PaseoPackage]) {
                return [string]$entry.dependencies.PSObject.Properties[$script:PaseoPackage].Value.version
            }
        }
    } catch { }
    return $null
}

function Test-PortListening {
    param([int]$LocalPort)
    try { return [bool](Get-NetTCPConnection -LocalPort $LocalPort -State Listen -ErrorAction SilentlyContinue) } catch { return $false }
}

function Get-ClaudeProviderSpec {
    param($Paths)
    return [ordered]@{
        label       = 'Claude (InferHub launcher)'
        description = 'Claude Code through the local LiteLLM proxy and the launcher seats (claude-code-launcher non-interactive mode)'
        command     = @('node', $Paths.EnvExec)
        models      = @(
            [ordered]@{ id = 'sonnet'; label = 'Main seat (sonnet)'; description = 'The launcher main seat and its fallback chain'; isDefault = $true },
            [ordered]@{ id = 'opus'; label = 'Advisor seat (opus)'; description = 'The launcher advisor seat (main when the advisor is off)' },
            [ordered]@{ id = 'haiku'; label = 'Fast seat (haiku)'; description = 'The small-fast seat' }
        )
    }
}

function Resolve-ListenAddress {
    if ($ListenAddress) {
        if ($ListenAddress -notmatch '^(\[[0-9a-fA-F:]+\]|[0-9.]+|[A-Za-z0-9.-]+):\d{1,5}$') { throw "-ListenAddress must look like ip:port (got '$ListenAddress')." }
        return $ListenAddress
    }
    if ($Tailscale) {
        $ip = Get-TailscaleIPv4
        if (-not $ip) { throw 'Tailscale is not installed or not connected (tailscale ip -4 gave nothing). Sign in to Tailscale first, or leave out -Tailscale.' }
        return ($ip + ':' + $Port)
    }
    return $null
}

# Builds the scheduled task pieces; returns them so -DryRun can show the command.
function Get-DaemonTaskParts {
    param($Paths)
    $conhost = Join-Path $env:SystemRoot 'System32\conhost.exe'
    $taskArgs = '--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $Paths.StartScript + '"'
    return @{ Execute = $conhost; Arguments = $taskArgs }
}

function Stop-FriendDaemon {
    param($Paths, [string]$Name)
    $task = Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue
    if ($task -and $task.State -eq 'Running') {
        $paseo = Get-Exe @('paseo.cmd', 'paseo')
        if ($paseo) {
            $ErrorActionPreference = 'Continue'
            $null = & $paseo daemon stop 2>&1
            $ErrorActionPreference = 'Stop'
        }
        Stop-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
}

# ---------------------------------------------------------------- install

function Invoke-FriendInstall {
    $paths = Get-FriendPaths
    if (-not $script:DryRunMode) {
        New-Item -ItemType Directory -Force -Path $paths.Friend | Out-Null
        $script:LogFile = Join-Path $paths.Friend 'install.log'
    }
    $old = Read-FriendState $paths
    $state = @{
        paseoInstalledByUs    = $false
        previousPaseoVersion  = $null
        launcherInstalledByUs = $false
        taskName              = $TaskName
        withAgy               = [bool]$WithAgy
        agyCliInstalledByUs   = $false
    }
    if ($old) {
        foreach ($k in @('paseoInstalledByUs', 'previousPaseoVersion', 'launcherInstalledByUs', 'agyCliInstalledByUs')) {
            if ($old.PSObject.Properties[$k]) { $state[$k] = $old.$k }
        }
    }
    if ($script:DryRunMode) { Write-Friend 'Dry run: nothing will be installed or changed.' 'step' }

    # Check the listen address first so a bad flag stops us before any change.
    $listen = Resolve-ListenAddress
    if ($listen) { Write-Friend "Paseo will listen on $listen" } else { Write-Friend 'Paseo listen address: left as it is (local only by default).' }

    # 1. The launcher.
    Write-Friend 'Claude Code + InferHub launcher' 'step'
    if ($SkipLauncher) {
        Write-Friend 'Skipped (-SkipLauncher).'
    } else {
        $url = Get-LauncherInstallerUrl
        # Remember whether the launcher was there before our first run (uninstall leaves it then).
        if (-not $old) { $state.launcherInstalledByUs = -not (Test-Path -LiteralPath (Join-Path $paths.Launcher 'install.json')) }
        $launcherArgs = @('-Ref', $LauncherRef, '-InstallDir', $paths.Launcher)
        if ($SkipTinyFish) { $launcherArgs += '-SkipTinyFish' }
        if ($NonInteractive) { $launcherArgs += '-NonInteractive' }
        $keyNote = if ($InferHubKey) { 'the InferHub key you gave' } else { 'its own key prompt' }
        if ($script:DryRunMode) {
            $ok = Test-UrlReachable $url
            Write-Friend ("download $url (reachable: $ok) and run it with " + ($launcherArgs -join ' ') + " and $keyNote") 'plan'
        } else {
            $tmp = Join-Path ([IO.Path]::GetTempPath()) ('ccl-install-' + [guid]::NewGuid().ToString('n') + '.ps1')
            Write-Friend "Downloading $url"
            Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing
            $saved = @{ CCL_INFERHUB_KEY = $env:CCL_INFERHUB_KEY; CCL_TINYFISH_KEY = $env:CCL_TINYFISH_KEY }
            try {
                # Keys go to the launcher through its environment, never on a command line.
                if ($InferHubKey) { $env:CCL_INFERHUB_KEY = $InferHubKey }
                if ($TinyFishKey) { $env:CCL_TINYFISH_KEY = $TinyFishKey }
                & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tmp @launcherArgs
                $code = $LASTEXITCODE
            } finally {
                $env:CCL_INFERHUB_KEY = $saved.CCL_INFERHUB_KEY
                $env:CCL_TINYFISH_KEY = $saved.CCL_TINYFISH_KEY
                Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
            }
            if ($code -ne 0) { throw "The launcher installer stopped with code $code. Fix that first, then run this again." }
        }
    }
    Update-SessionPath
    if (-not $script:DryRunMode -and -not (Test-Path -LiteralPath $paths.EnvExec)) {
        throw "Can't find $($paths.EnvExec). Is the launcher installed in $($paths.Launcher)? (-LauncherDir changes where to look.)"
    }

    # 2. Paseo.
    Write-Friend "Paseo $PaseoVersion" 'step'
    $node = Get-Exe @('node.exe', 'node')
    $pnpm = Get-Exe @('pnpm.cmd', 'pnpm.exe', 'pnpm')
    if (-not $node -or -not $pnpm) {
        if ($script:DryRunMode) { Write-Friend 'Node.js or pnpm is missing right now; the launcher installer would add them.' 'warn' }
        else { throw 'Node.js and pnpm are needed. The launcher installer normally adds them; open a new PowerShell window and run this again.' }
    }
    $current = $null
    if ($pnpm) { $current = Get-PaseoGlobalVersion $pnpm }
    if ($current -eq $PaseoVersion) {
        Write-Friend "Paseo $current is already installed."
    } else {
        if (-not $current -and -not ($old -and $old.paseoInstalledByUs)) { $state.paseoInstalledByUs = $true }
        if ($current -and -not ($old -and $old.previousPaseoVersion)) { $state.previousPaseoVersion = $current }
        if (-not $env:PNPM_HOME -and -not [Environment]::GetEnvironmentVariable('PNPM_HOME', 'User')) {
            Invoke-Change 'run `pnpm setup` so pnpm has a folder for global commands' {
                $null = Invoke-Native $pnpm @('setup')
            } | Out-Null
        }
        if (-not $env:PNPM_HOME) {
            $h = [Environment]::GetEnvironmentVariable('PNPM_HOME', 'User')
            if ($h) { $env:PNPM_HOME = $h }
        }
        Update-SessionPath
        $from = if ($current) { " (replacing $current)" } else { '' }
        Invoke-Change "install $($script:PaseoPackage)@$PaseoVersion globally with pnpm$from" {
            $code = Invoke-Native $pnpm @('add', '-g', '--save-exact', "$($script:PaseoPackage)@$PaseoVersion")
            if ($code -ne 0) { throw "pnpm add -g $($script:PaseoPackage)@$PaseoVersion failed (code $code)." }
        } | Out-Null
        Update-SessionPath
    }

    # 3. Antigravity (optional).
    $pluginSpec = $null
    if ($WithAgy) {
        Write-Friend 'Antigravity (agy) for this Windows account' 'step'
        $agyExe = Join-Path $env:LOCALAPPDATA 'agy\bin\agy.exe'
        if ((Test-Path -LiteralPath $agyExe) -or (Get-Exe @('agy.exe', 'agy'))) {
            Write-Friend 'The Antigravity CLI (agy) is already installed.'
        } else {
            if (-not ($old -and $old.agyCliInstalledByUs)) { $state.agyCliInstalledByUs = $true }
            Invoke-Change "download Google's Antigravity CLI installer from $AgyInstallerUrl and run it" {
                $tmp = Join-Path ([IO.Path]::GetTempPath()) ('agy-install-' + [guid]::NewGuid().ToString('n') + '.ps1')
                try {
                    Invoke-WebRequest -Uri $AgyInstallerUrl -OutFile $tmp -UseBasicParsing
                    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tmp
                    if ($LASTEXITCODE -ne 0) { throw "The Antigravity CLI installer stopped with code $LASTEXITCODE." }
                } finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
            } | Out-Null
            Update-SessionPath
        }
        $pluginPkgJson = Join-Path $paths.PluginDir 'package.json'
        $haveVersion = $null
        if (Test-Path -LiteralPath $pluginPkgJson) {
            try { $haveVersion = (Get-Content -LiteralPath $pluginPkgJson -Raw -Encoding UTF8 | ConvertFrom-Json).version } catch { }
        }
        if ($haveVersion -eq $AgyPluginVersion) {
            Write-Friend "The Paseo plugin $($script:AgyPluginPackage) $haveVersion is already installed."
        } else {
            Invoke-Change "install $($script:AgyPluginPackage)@$AgyPluginVersion with pnpm into $($paths.PluginRoot)" {
                New-Item -ItemType Directory -Force -Path $paths.PluginRoot | Out-Null
                $pj = Join-Path $paths.PluginRoot 'package.json'
                if (-not (Test-Path -LiteralPath $pj)) { Write-Utf8NoBom -Path $pj -Text "{`n  `"name`": `"paseo-friend-plugins`",`n  `"private`": true`n}`n" }
                # A plain folder (no symlinks), which is what a Paseo directory plugin expects.
                Write-Utf8NoBom -Path (Join-Path $paths.PluginRoot '.npmrc') -Text "node-linker=hoisted`n"
                $code = Invoke-Native $pnpm @('add', '--save-exact', '--dir', $paths.PluginRoot, "$($script:AgyPluginPackage)@$AgyPluginVersion")
                if ($code -ne 0) { throw "pnpm add $($script:AgyPluginPackage)@$AgyPluginVersion failed (code $code)." }
            } | Out-Null
        }
        $pluginSpec = [ordered]@{ id = $script:AgyPluginId; path = $paths.PluginDir }
    }

    # 4. Paseo config.
    Write-Friend "Paseo settings ($($paths.Config))" 'step'
    $spec = [ordered]@{ claudeProvider = (Get-ClaudeProviderSpec $paths); listen = $listen; plugin = $pluginSpec }
    $specFile = Join-Path ([IO.Path]::GetTempPath()) ('paseo-friend-spec-' + [guid]::NewGuid().ToString('n') + '.json')
    Write-Utf8NoBom -Path $specFile -Text (ConvertTo-Json -InputObject $spec -Depth 10)
    try {
        if ($script:DryRunMode) {
            $helper = Get-ReadOnlyHelper $paths
            if ($node -and $helper) {
                try {
                    $out = & $node $helper.Path plan --config $paths.Config --state $paths.ConfigState --spec $specFile | Out-String
                    $plan = $out | ConvertFrom-Json
                    if ($plan.changes.Count -eq 0) { Write-Friend 'config.json is already up to date.' }
                    else {
                        Write-Friend ("back up config.json, then: " + (($plan.changes | ForEach-Object { $_.action + ' ' + $_.key }) -join ', ')) 'plan'
                    }
                } finally { if ($helper.Temp) { Remove-Item -LiteralPath $helper.Path -Force -ErrorAction SilentlyContinue } }
            } else {
                Write-Friend 'merge agents.providers.claude (and the listen address / plugin, if asked) into config.json after backing it up' 'plan'
            }
            Write-Friend ('Claude provider command: node ' + $paths.EnvExec)
        } else {
            Get-HelperFile -Name 'paseo-config.mjs' -Destination $paths.Helper
            $out = & $node $paths.Helper apply --config $paths.Config --state $paths.ConfigState --spec $specFile | Out-String
            if ($LASTEXITCODE -ne 0) { throw "Couldn't update $($paths.Config) (left it as it was)." }
            $result = $out | ConvertFrom-Json
            if ($result.backup) { Write-Friend "Backed up the old file to $($result.backup)" }
            if ($result.changes.Count -eq 0) { Write-Friend 'config.json was already up to date.' }
            foreach ($c in $result.changes) { Write-Friend ("  " + $c.action + ' ' + $c.key) }
        }
    } finally { Remove-Item -LiteralPath $specFile -Force -ErrorAction SilentlyContinue }

    # 5. The daemon, as a hidden logon task.
    Write-Friend "Paseo daemon (scheduled task '$TaskName')" 'step'
    $parts = Get-DaemonTaskParts $paths
    $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Invoke-Change ("install the start script at $($paths.StartScript)") { Get-HelperFile -Name 'start-paseo.ps1' -Destination $paths.StartScript } | Out-Null
    $verb = if ($existing) { 'update' } else { 'register' }
    Invoke-Change ("$verb the logon task '$TaskName': " + $parts.Execute + ' ' + $parts.Arguments) {
        $action = New-ScheduledTaskAction -Execute $parts.Execute -Argument $parts.Arguments
        $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
        $trigger.Delay = 'PT20S'
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
        $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
        $null = Register-ScheduledTask -TaskName $TaskName -Description 'Starts the Paseo daemon hidden at logon (installed by install-friend.ps1)' -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force
    } | Out-Null

    $ourTaskRunning = $existing -and $existing.State -eq 'Running'
    if (-not $ourTaskRunning -and (Test-PortListening $Port)) {
        Write-Friend "Something else is already listening on port $Port (maybe Paseo Desktop or another daemon). Not starting a second daemon; the task will start it at the next sign-in once that's gone." 'warn'
    } else {
        $what = if ($ourTaskRunning) { 'restart the Paseo daemon so it picks up the new settings' } else { 'start the Paseo daemon now (hidden)' }
        Invoke-Change $what {
            Stop-FriendDaemon $paths $TaskName
            Start-ScheduledTask -TaskName $TaskName
            $deadline = (Get-Date).AddSeconds(45)
            while ((Get-Date) -lt $deadline -and -not (Test-PortListening $Port)) { Start-Sleep -Seconds 2 }
            if (Test-PortListening $Port) { Write-Friend "The daemon is up on port $Port." }
            else { Write-Friend "The daemon didn't answer yet. Logs: $($paths.Friend)\logs" 'warn' }
        } | Out-Null
    }

    if (-not $script:DryRunMode) { Write-FriendState $paths $state }

    Write-Friend 'Done' 'step'
    if ($script:DryRunMode) { Write-Friend 'That was a dry run. Nothing changed.'; return 0 }
    Write-Friend 'Next:'
    Write-Friend '  - Pair your phone: open a new PowerShell window and run  paseo daemon pair'
    if ($listen) { Write-Friend "  - Or, over Tailscale: in the Paseo app, Add host -> Direct connection, host $($listen -replace ':\d+$', ''), port $Port, SSL off." }
    if ($WithAgy) { Write-Friend '  - Sign Antigravity in once: open a new PowerShell window, run  agy  and follow the sign-in.' }
    Write-Friend '  - Claude in a terminal: claude-inferhub'
    return 0
}

# ---------------------------------------------------------------- uninstall

function Invoke-FriendUninstall {
    $paths = Get-FriendPaths
    $state = Read-FriendState $paths
    $name = if ($state -and $state.taskName) { [string]$state.taskName } else { $TaskName }
    if ($script:DryRunMode) { Write-Friend 'Dry run: nothing will be removed.' 'step' }

    Write-Friend "Paseo daemon task '$name'" 'step'
    if (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue) {
        Invoke-Change "stop and remove the scheduled task '$name'" {
            Stop-FriendDaemon $paths $name
            Unregister-ScheduledTask -TaskName $name -Confirm:$false
        } | Out-Null
    } else { Write-Friend 'Not registered.' }

    Write-Friend 'Paseo settings' 'step'
    $node = Get-Exe @('node.exe', 'node')
    if (Test-Path -LiteralPath $paths.ConfigState) {
        $helper = if (Test-Path -LiteralPath $paths.Helper) { $paths.Helper } elseif ($PSScriptRoot -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'paseo-config.mjs'))) { Join-Path $PSScriptRoot 'paseo-config.mjs' } else { $null }
        if (-not $node -or -not $helper) {
            Write-Friend "Can't put config.json back automatically (Node or the helper is missing). Backups are next to it: $($paths.Config).bak-*" 'warn'
        } else {
            Invoke-Change 'put back the config.json values from before the install (after a backup)' {
                $out = & $node $helper revert --config $paths.Config --state $paths.ConfigState | Out-String
                if ($LASTEXITCODE -ne 0) { throw "Couldn't restore $($paths.Config)." }
                $r = $out | ConvertFrom-Json
                foreach ($c in $r.changes) { Write-Friend ('  ' + $c.action + ' ' + $c.key) }
            } | Out-Null
        }
    } else { Write-Friend 'Nothing of ours in config.json.' }

    Write-Friend 'Antigravity plugin' 'step'
    if (Test-Path -LiteralPath $paths.PluginRoot) {
        Invoke-Change "delete $($paths.PluginRoot)" { Remove-Item -LiteralPath $paths.PluginRoot -Recurse -Force } | Out-Null
    } else { Write-Friend 'Not installed.' }
    if ($state -and $state.agyCliInstalledByUs) {
        Write-Friend "The Antigravity CLI stays (it's Google's own tool). To remove it, delete $env:LOCALAPPDATA\agy."
    }

    Write-Friend 'Paseo' 'step'
    $pnpm = Get-Exe @('pnpm.cmd', 'pnpm.exe', 'pnpm')
    if ($state -and $state.paseoInstalledByUs -and $pnpm) {
        Invoke-Change "remove $($script:PaseoPackage) (global pnpm package)" { $null = Invoke-Native $pnpm @('remove', '-g', $script:PaseoPackage) } | Out-Null
    } elseif ($state -and $state.previousPaseoVersion -and $pnpm) {
        Invoke-Change "put back Paseo $($state.previousPaseoVersion)" { $null = Invoke-Native $pnpm @('add', '-g', '--save-exact', "$($script:PaseoPackage)@$($state.previousPaseoVersion)") } | Out-Null
    } else { Write-Friend 'Leaving Paseo installed (it was there before, or was never installed by this script).' }
    Write-Friend "Paseo's own data (agents, history) in $($paths.PaseoHome) stays."

    Write-Friend 'Claude Code + InferHub launcher' 'step'
    if ($KeepLauncher) { Write-Friend 'Kept (-KeepLauncher).' }
    elseif ($state -and -not $state.launcherInstalledByUs) { Write-Friend 'Kept (it was installed before this package; remove it with  claude-inferhub --uninstall).' }
    elseif (Test-Path -LiteralPath $paths.LauncherPs1) {
        Invoke-Change "run the launcher's own uninstall ($($paths.LauncherPs1) -Uninstall)" {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $paths.LauncherPs1 -Uninstall -InstallDir $paths.Launcher
            if ($LASTEXITCODE -ne 0) { Write-Friend "The launcher uninstall stopped with code $LASTEXITCODE." 'warn' }
        } | Out-Null
    } else { Write-Friend 'Not installed.' }

    if (Test-Path -LiteralPath $paths.Friend) {
        Invoke-Change "delete $($paths.Friend) (logs, start script, install state)" { Remove-Item -LiteralPath $paths.Friend -Recurse -Force } | Out-Null
    }
    Write-Friend 'Done' 'step'
    return 0
}

# ---------------------------------------------------------------- main

if ($env:PASEO_FRIEND_LIBRARY_ONLY -eq '1') { return }

$friendCode = 1
$onWindows = ($PSVersionTable.PSEdition -eq 'Desktop') -or ((Get-Variable -Name IsWindows -ErrorAction SilentlyContinue) -and $IsWindows)
if (-not $onWindows) {
    Write-Error 'This installer is for Windows.' -ErrorAction Continue
    $friendCode = 2
} else {
    try {
        if ($Uninstall) { $friendCode = Invoke-FriendUninstall } else { $friendCode = Invoke-FriendInstall }
    } catch {
        Write-Error ("Stopped: " + $_.Exception.Message) -ErrorAction Continue
        $friendCode = 1
    }
}
# Through `irm | iex` there's no script path; don't close the friend's window.
if ($PSCommandPath) { exit $friendCode }
