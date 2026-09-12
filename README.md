# Claude Desktop — window stuck always-on-top (Windows)

## Symptom

The Claude Desktop main chat window floats above every other application. Clicking
or Alt+Tabbing to another window focuses it, but Claude stays painted on top of it.
There is no setting, menu item, or keyboard shortcut in the app to turn this off.

Not caused by PowerToys, DeskPins, AutoHotkey, or any other pinning utility — the
flag originates from the app itself. Quitting fully from the system tray and
relaunching does **not** clear it.

This is about the **main chat window**, not the small "Claude is using your computer"
Cowork overlay. That overlay staying on top during a task is expected behavior and
dismisses itself when the session ends.

## Cause

Introduced by the silent auto-update relaunch ("stealth relaunch") in the
`1.30096.x` line.

The app has a z-order restore step: before relaunching, it records whichever window
sits directly above its own main window as an *anchor*, then re-inserts its new
window behind that anchor afterward via a `SetWindowPos`-based `moveWindowBehind`.

If the anchor it captured happened to be a topmost window, the new Claude window
acquires the `WS_EX_TOPMOST` extended window style — and keeps it permanently.
Every subsequent launch re-acquires it.

## Fix (PowerShell)

Clears `WS_EX_TOPMOST` on the running Claude window. No elevation required unless
Claude itself is running elevated.

```powershell
$sig = @'
[DllImport("user32.dll")]
public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter,
    int X, int Y, int cx, int cy, uint uFlags);
'@
Add-Type -MemberDefinition $sig -Name Win -Namespace Native

Get-Process claude -ErrorAction SilentlyContinue |
  Where-Object { $_.MainWindowHandle -ne 0 } |
  ForEach-Object {
    [Native.Win]::SetWindowPos($_.MainWindowHandle, [IntPtr]-2, 0,0,0,0, 0x0003)
  }
```

**Parameters:**

| Value | Constant | Meaning |
|---|---|---|
| `-2` | `HWND_NOTOPMOST` | Drop out of the topmost band, keep current z-order otherwise |
| `0x0003` | `SWP_NOMOVE \| SWP_NOSIZE` | Touch z-order only; leave window position and size alone |

**If `Get-Process claude` returns nothing**, the MSIX packaging may name the process
differently. Find it with:

```powershell
Get-Process | Where-Object MainWindowTitle -like '*Claude*'
```

**Persistence:** this fixes the current window only. The next silent auto-update
relaunch will set the flag again. Save as `unpin-claude.ps1` and re-run as needed.

## Other workarounds

- **PowerToys** — `Win+Ctrl+T` toggles always-on-top. Same fix, one keystroke,
  if PowerToys is already installed.
- **Virtual desktop** — `Win+Ctrl+D` and move Claude to its own desktop.
  Always-on-top is per-desktop, so it stops covering your main workspace.
  Impractical for frequent switching.
- **Minimize** — what most affected users are doing.
- **AutoHotkey** — `WinSet, AlwaysOnTop, Off, ahk_exe Claude.exe`
  (AHK syntax; must go in a `.ahk` script, will not run in PowerShell).

## Tracking

| Issue | Platform | Notes |
|---|---|---|
| [#66516](https://github.com/anthropics/claude-code/issues/66516) | macOS | Original report, 2026-06-09. Closed as not-Claude-Code / wrong repo. |
| [#85891](https://github.com/anthropics/claude-code/issues/85891) | Windows 11 | 2026-08-11. Rules out external pinning tools. |
| [#87084](https://github.com/anthropics/claude-code/issues/87084) | Windows 11 | 2026-08-16, app 1.30096.5. Identifies the `moveWindowBehind` mechanism. |
| [#87895](https://github.com/anthropics/claude-code/issues/87895) | Windows | Closed as duplicate of #66516. |
| [#88093](https://github.com/anthropics/claude-code/issues/88093) | Windows | App 1.32885.1 — not fixed by updating. |
| [#89467](https://github.com/anthropics/claude-code/issues/89467) | Windows 10 | 2026-08-25, Claude Code 2.1.138. |

The macOS original was closed as out-of-scope; the Windows reports are what's
keeping it on the tracker. Worth adding a repro if it's still happening on your
current build.

## macOS equivalent

Same root behavior. The AHK and PowerShell fixes don't apply. Mission Control
Spaces works the same way as Windows virtual desktops — put Claude in its own
Space and it stops covering the others.
