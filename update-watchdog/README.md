# Claude Desktop doesn't come back after a silent update (Windows)

## Symptom

Claude Desktop quits by itself while you're away or just not typing, and
running Claude Code sessions die with it, mid-task. It never reopens. Launching
it again fails with an error that the executable is in use, and only a reboot
clears it.

## What's actually happening

It's the silent auto-update. From `%LOCALAPPDATA%\Claude\Logs\main.log`:

```
[stealth-update] Triggering stealth update after idle timeout
[CCD] Killing 1 PTY process tree(s) on quit
beforeQuitForUpdate handler fired, going down for update
Windows session ending (close-app) - quitting the app
```

Windows' AppX deployment log (`Microsoft-Windows-AppXDeploymentServer/Operational`)
shows the package update itself **succeeding**: `RegisterByPackageFamilyName`
with `ForceApplicationShutdownOption`, then old version → new version, finishing
with `0x0`. Normally the app relaunches about 2 seconds later. When it doesn't,
nothing restarts it, and a leftover process keeps the executable locked.

Seen on one machine between 2026-09-06 and 09-13 (app `1.52386.3` → `1.52386.6`):

- **5** update-quits, and each one killed the Claude Code sessions running at the time.
- **2** of them never relaunched. Both needed a reboot.
- One fired about **90 seconds** after a session's last activity, so the "idle"
  check doesn't seem to count running agent sessions.

## Fix: the update watchdog

A per-user scheduled task that runs `claude-watchdog.ps1` every 5 minutes while
you're logged on.

**It acts only on this exact failure.** It reads the tail of `main.log`. If the
last `going down for update` has **no successful app start after it**, and that
was more than 3 minutes ago, it:

1. ends leftover Claude Desktop processes. It matches only
   `...\WindowsApps\Claude_*\app\Claude.exe`. It never touches the Claude Code
   CLI binaries, which are also named `claude.exe` and run from
   `%APPDATA%\Claude\claude-code\`.
2. relaunches the app (`shell:AppsFolder\Claude_pzs8sxrjxfjjc!Claude`).
3. sends the new window to the **back** of the z-order **without activating it**
   (`SetWindowPos` with `HWND_BOTTOM` and `SWP_NOACTIVATE`). That also clears the
   stuck [always-on-top](../README.md) flag a relaunch can bring back.

**What it will not do:**

| Concern | Behavior |
|---|---|
| Keep the screen or PC awake | No. It runs about a second every 5 minutes, requests no keep-awake, and "wake the computer to run this task" is off. |
| Flash a console or steal focus | No. It runs through `conhost --headless`, and the relaunched window goes behind your other windows. |
| Relaunch after you quit Claude yourself | No. With no update-quit in the log, it does nothing. |
| Loop | No. At most one relaunch per 15 minutes. |
| Kill a working app | No. If a responding Claude window exists, it leaves everything alone. |
| Need admin | No. It runs as you, not elevated. |

What it can't fix: the update still kills running sessions when it quits the
app. Only Anthropic can change that. The watchdog just means you're back in
minutes instead of after a reboot.

## Install

```powershell
powershell -ExecutionPolicy Bypass -File .\update-watchdog\install.ps1
```

This copies the script to `%USERPROFILE%\.claude-hacks\` and registers
`\claude-hacks\Claude Update Watchdog` in Task Scheduler, where you can see it.

> **Why not `%LOCALAPPDATA%`?** Claude Desktop is an MSIX package, and Windows
> silently redirects packaged apps' writes to `AppData\Local` into
> `AppData\Local\Packages\Claude_pzs8sxrjxfjjc\LocalCache\Local\`. That includes
> anything run from a terminal *inside* Claude, such as Claude Code. Install
> there from inside Claude and the file only exists in Claude's private view.
> Task Scheduler runs outside it, can't find the script, and still reports
> success. The profile root isn't redirected. (`main.log` itself is a real file
> at `AppData\Local\Claude\Logs`, so reading it from outside works.)

## Check on it

- `%USERPROFILE%\.claude-hacks\watchdog.last-run.txt` holds the last decision
  (`healthy`, `waiting`, `cooldown`, `recovered`). It's overwritten each run.
- `%USERPROFILE%\.claude-hacks\watchdog.log` is only written when the watchdog
  actually relaunches the app, and is capped at 500 lines.
- To see what it *would* do right now without changing anything:
  ```powershell
  powershell -ExecutionPolicy Bypass -File .\update-watchdog\claude-watchdog.ps1 -DryRun
  ```

## Uninstall

```powershell
powershell -ExecutionPolicy Bypass -File .\update-watchdog\uninstall.ps1
```

Removes the task and `%USERPROFILE%\.claude-hacks\`.

## Tests

```powershell
powershell -ExecutionPolicy Bypass -File .\update-watchdog\test-claude-watchdog.ps1
```

These run the decision logic against synthetic `main.log` excerpts built from
real log lines: healthy, normal relaunch, the relaunch that never came, the
grace period, a second icon click that doesn't count as a start, and cooldown.
They only use `-DryRun`, so they're safe to run while Claude is open.
