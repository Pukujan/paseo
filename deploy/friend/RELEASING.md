# Releasing the friend package

The one-liner in the README points at a GitHub release of this repo. By default `install-friend.ps1` runs the launcher installer from the `v1.0.0-windows` release of Pukujan/claude-code-launcher (that release exists, with `install.ps1` attached).

## Before

1. Check the launcher asset is still there:
   `Invoke-WebRequest -Method Head https://github.com/Pukujan/claude-code-launcher/releases/download/v1.0.0-windows/install.ps1`
2. Ideally, on a Windows test account, run from a checkout of this branch:
   `.\deploy\friend\install-friend.ps1 -DryRun -WithAgy`, then a real install, then a rerun (should change nothing), then `-Uninstall`.

To test against another launcher ref (a branch or tag), pass `-LauncherRef <ref>` or `-LauncherInstallerUrl <url>`.

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
pwsh -NoProfile -File deploy/friend/install-friend.checks.ps1
```
