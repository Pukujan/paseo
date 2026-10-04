# Paseo + Claude on your Windows PC

This sets up the same thing I use every day: [Paseo](https://paseo.sh) running quietly in the background on your PC, so you can drive coding agents from your phone, with Claude Code going through InferHub. You bring your own InferHub key; nothing of mine is in here.

It's one command. You can run it again whenever you like, and you can take it all back out.

## What you need first

- Windows 10 or 11, signed in as yourself (no admin needed).
- Your InferHub API key. The installer asks for it and hides what you type.
- A TinyFish key, if you want good web search in Claude. It's free: sign up at <https://agent.tinyfish.ai/sign-up>, then make a key at <https://agent.tinyfish.ai/api-keys>. You can skip it (press Enter at the prompt) and add it later with `claude-inferhub --set-tinyfish-key`.
- The Paseo app on your phone, if you want to use it from your phone.
- Optional: [Tailscale](https://tailscale.com/download) on the PC and the phone, if you want a direct connection instead of the Paseo relay.

You don't need to install Node, pnpm, uv, git or Claude Code yourself. The launcher installer adds whatever is missing.

## Install

Open PowerShell (not as admin) and paste:

```powershell
irm https://github.com/Pukujan/paseo/releases/download/friend-v1.0.0/install-friend.ps1 | iex
```

Want options? Use this form and add them at the end:

```powershell
& ([scriptblock]::Create((irm https://github.com/Pukujan/paseo/releases/download/friend-v1.0.0/install-friend.ps1))) -WithAgy -Tailscale
```

The options you might care about:

| Option | What it does |
|---|---|
| `-InferHubKey <key>` | Give the InferHub key up front instead of being asked. |
| `-TinyFishKey <key>` | Give the TinyFish key up front instead of being asked. |
| `-SkipTinyFish` | Don't ask for a TinyFish key at all. |
| `-NonInteractive` | Never ask anything. The InferHub key then has to come from `-InferHubKey` or the environment; a missing TinyFish key just gets a warning. |
| `-WithAgy` | Also set up Google Antigravity (see below). |
| `-Tailscale` | Let Paseo listen on your Tailscale address, so your phone can connect directly. Without it, Paseo only listens on this PC. |
| `-DryRun` | Show what it would do and change nothing. |
| `-Uninstall` | Take it all back out. |
| `-SkipLauncher` | Don't touch the Claude launcher (it's already set up). |

The safest way to give your keys is to let the installer ask. What you type at its prompt is hidden and isn't saved in your PowerShell history (a key typed as `-InferHubKey ...` is). The installer also reads `INFERHUB_API_KEY` and `TINYFISH_API_KEY` (or `CCL_INFERHUB_KEY` and `CCL_TINYFISH_KEY`) if they're already set, which is handy for scripted setups.

However you give them, the installer hands the keys to the launcher through the environment only. They never show up on a command line, in the output, or in a log.

## What it installs

1. **The Claude launcher** (from [claude-code-launcher](https://github.com/Pukujan/claude-code-launcher)). It goes in `%LOCALAPPDATA%\claude-code-launcher`, runs its own small LiteLLM proxy hidden in the background, and gives you a `claude-inferhub` command. Your key stays in a file only your Windows user can read.
2. **Paseo 0.10.3**, installed with pnpm. It's pinned on purpose, so an update can't surprise you.
3. **A hidden logon task** called `Paseo Daemon`. It starts Paseo in the background each time you sign in to Windows. No window ever pops up. The script it runs and its logs are in `%USERPROFILE%\.paseo\friend`.
4. **One setting in Paseo**: the Claude agent in Paseo goes through the launcher, so it uses your InferHub key and the same models as `claude-inferhub`. Your existing `%USERPROFILE%\.paseo\config.json` is copied to `config.json.bak-<date>` first, and nothing else in it is changed.

**Already running Paseo?** If another scheduled task already starts Paseo, or something (say Paseo Desktop) is already using port 6767, the installer doesn't start a second one. It adds `Paseo Daemon` switched off and tells you so. Turn the other one off and run the installer again if you want this one instead.

## Connecting from your phone

**The easy way (Paseo relay).** Open a new PowerShell window and run:

```powershell
paseo daemon pair
```

Say yes when it asks about the relay. It shows a QR code. Scan it with the Paseo app. That's it; it works from anywhere, and the traffic is end-to-end encrypted.

**Over Tailscale (direct, no relay).** Install Tailscale on the PC and phone and sign both in to the same tailnet. Then run the installer again with `-Tailscale`. It prints your Tailscale address at the end. In the Paseo app, go to **Settings → Add host → Direct connection**, type that address as the host, `6767` as the port, leave SSL off, and connect.

Anyone on your tailnet can reach Paseo this way, so only use it on a tailnet you control. (You can also set a Paseo password; see the Paseo docs under Configuration.)

## Antigravity (optional)

Run the installer with `-WithAgy` and it adds two things for your Windows account:

- Google's Antigravity command-line tool, `agy` (if you don't have it yet).
- A community Paseo plugin, `paseo-plugin-antigravity-cli` 0.9.1, so Antigravity shows up as an agent in Paseo.

Then sign in once. Open a new PowerShell window, run:

```powershell
agy
```

and follow the sign-in in your browser. When it's done, close it. In Paseo, pick **Antigravity** when you start a new agent.

This is set up for one Google account: yours. Google treats Antigravity on a Pro plan as a personal account, so please sign in with your own account and don't share it.

## Running it again

Run the same command again any time. It skips what's already right, updates what changed, and doesn't make a second copy of anything. Your settings stay.

## Uninstall

```powershell
& ([scriptblock]::Create((irm https://github.com/Pukujan/paseo/releases/download/friend-v1.0.0/install-friend.ps1))) -Uninstall
```

This stops Paseo, removes the logon task, puts your Paseo settings back the way they were before, removes the Antigravity plugin, removes Paseo (if this installer put it there), and runs the launcher's own uninstall. Add `-KeepLauncher` to keep `claude-inferhub`.

It leaves alone: Node, pnpm, uv, git, Claude Code, the `agy` tool and its sign-in, and Paseo's own data (your agents and history in `%USERPROFILE%\.paseo`).

## If something goes wrong

- **Paseo doesn't show up on the phone.** Check the logs in `%USERPROFILE%\.paseo\friend\logs`. If the installer said it set up `Paseo Daemon` switched off, something else is already running Paseo; only one daemon can use port 6767.
- **Claude in Paseo fails to start.** Run `claude-inferhub` in a terminal first. If that works, Paseo will too.
- **Antigravity says it isn't signed in.** Run `agy` once more and sign in.
- **Want to see what would happen first?** Add `-DryRun`.
