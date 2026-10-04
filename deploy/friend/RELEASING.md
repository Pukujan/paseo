# Releasing the friend package

The one-liner in the README points at a GitHub release of this repo. Don't make it until the launcher's Windows installer is released, because `install-friend.ps1` downloads that by default.

## Before

1. Launcher PR Pukujan/claude-code-launcher#62 is merged and the `v1.0.0-windows` release exists with `install.ps1` attached. Check:
   `Invoke-WebRequest -Method Head https://github.com/Pukujan/claude-code-launcher/releases/download/v1.0.0-windows/install.ps1`
2. On a Windows test account, run from a checkout of this branch:
   `.\deploy\friend\install-friend.ps1 -DryRun -WithAgy`, then a real install, then a rerun (should change nothing), then `-Uninstall`.

Until the launcher release exists you can still test against the PR branch:

```powershell
.\deploy\friend\install-friend.ps1 -LauncherRef ccl-0061-windows-installer
```

## Release

Tag `friend-v1.0.0` (it matches `$script:FriendReleaseTag` in `install-friend.ps1`) and attach these three files from `deploy/friend/`:

- `install-friend.ps1`
- `paseo-config.mjs`
- `start-paseo.ps1`

```bash
gh release create friend-v1.0.0 -R Pukujan/paseo --title "Friend package 1.0.0" \
  --notes "One-command Windows setup. See deploy/friend/README.md." \
  deploy/friend/install-friend.ps1 deploy/friend/paseo-config.mjs deploy/friend/start-paseo.ps1
```

When the script runs through `irm | iex` it has no folder of its own, so it downloads the other two files from the same release. For a different tag, change `$script:FriendReleaseTag` or pass `-PackageBaseUrl`.

## Tests

```bash
node --check deploy/friend/paseo-config.mjs
node --test deploy/friend/paseo-config.test.mjs
pwsh -NoProfile -c '$e=$null; [void][System.Management.Automation.Language.Parser]::ParseFile("deploy/friend/install-friend.ps1",[ref]$null,[ref]$e); $e.Count'
```
