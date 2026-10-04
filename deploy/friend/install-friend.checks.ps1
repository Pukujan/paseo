# Quick checks for install-friend.ps1 that run anywhere pwsh runs (no Windows needed).
#   pwsh -NoProfile -File deploy/friend/install-friend.checks.ps1
$ErrorActionPreference = 'Stop'
$script:failed = 0
function Check([string]$Name, [bool]$Ok) {
    if ($Ok) { Write-Host "ok   $Name" } else { Write-Host "FAIL $Name"; $script:failed++ }
}
$src = Join-Path $PSScriptRoot 'install-friend.ps1'
$text = Get-Content -LiteralPath $src -Raw

$errs = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($src, [ref]$null, [ref]$errs)
Check 'parses' ($errs.Count -eq 0)

# Keys only travel through the environment: never into the launcher's arguments or a log line.
Check 'no key in launcher args' (-not ($text -match '\$launcherArgs\s*\+=\s*[^\r\n]*(InferHubKey|TinyFishKey)'))
Check 'InferHub key passed via CCL_INFERHUB_KEY' ($text -match '\$env:CCL_INFERHUB_KEY\s*=\s*\$InferHubKey')
Check 'TinyFish key passed via CCL_TINYFISH_KEY' ($text -match '\$env:CCL_TINYFISH_KEY\s*=\s*\$TinyFishKey')
Check 'no Write-Friend prints a key' (-not ($text -match 'Write-Friend[^\r\n]*\$(InferHubKey|TinyFishKey)\b'))
Check '-SkipTinyFish passes through' ($text -match "if \(\`$SkipTinyFish\) \{ \`$launcherArgs \+= '-SkipTinyFish' \}")

$env:PASEO_FRIEND_LIBRARY_ONLY = '1'
. $src
Remove-Item Env:\PASEO_FRIEND_LIBRARY_ONLY

# Launcher URL from the ref.
$LauncherInstallerUrl = ''
$LauncherRef = 'v1.0.0-windows'
Check 'tag -> release asset' ((Get-LauncherInstallerUrl) -eq 'https://github.com/Pukujan/claude-code-launcher/releases/download/v1.0.0-windows/install.ps1')
$LauncherRef = 'some-branch'
Check 'branch -> raw windows/install.ps1' ((Get-LauncherInstallerUrl) -eq 'https://raw.githubusercontent.com/Pukujan/claude-code-launcher/some-branch/windows/install.ps1')

# Key source notes never contain the key.
$InferHubKey = 'IH-SECRET-123'; $TinyFishKey = 'TF-SECRET-456'; $SkipTinyFish = $false; $NonInteractive = $false
$note = Get-KeySourceNote
Check 'key note hides keys' (-not ($note -match 'SECRET'))
$SkipTinyFish = $true
Check 'key note shows -SkipTinyFish' ((Get-KeySourceNote) -match 'SkipTinyFish')

# Detecting other Paseo daemon tasks.
function Get-ScheduledTask {
    @(
        [pscustomobject]@{ TaskName = 'Old Paseo'; TaskPath = '\'; Actions = @([pscustomobject]@{ Execute = 'conhost.exe'; Arguments = '--headless powershell.exe -File "C:\Users\x\.paseo\start-paseo.ps1"' }) },
        [pscustomobject]@{ TaskName = 'Paseo Daemon'; TaskPath = '\'; Actions = @([pscustomobject]@{ Execute = 'conhost.exe'; Arguments = '-File C:\Users\x\.paseo\friend\start-paseo.ps1' }) },
        [pscustomobject]@{ TaskName = 'cmd daemon'; TaskPath = '\'; Actions = @([pscustomobject]@{ Execute = 'cmd.exe'; Arguments = '/c paseo.cmd daemon run' }) },
        [pscustomobject]@{ TaskName = 'unrelated'; TaskPath = '\'; Actions = @([pscustomobject]@{ Execute = 'node.exe'; Arguments = 'server.js' }) },
        [pscustomobject]@{ TaskName = 'windows'; TaskPath = '\Microsoft\Windows\'; Actions = @([pscustomobject]@{ Execute = 'x'; Arguments = 'start-paseo' }) }
    )
}
$others = @(Get-OtherPaseoTask -Exclude 'Paseo Daemon')
Check 'finds other Paseo tasks, skips ours and unrelated ones' (($others -join '|') -eq 'Old Paseo|cmd daemon')

if ($script:failed) { Write-Host "$script:failed check(s) failed"; exit 1 }
Write-Host 'all checks passed'
