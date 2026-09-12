
what happened and why does the claude app persist above all my other windows now


Searched the web
Searched the web
Not you — it's a known bug, and a fairly well-documented one.

After the silent auto-update relaunch introduced in the 1.30096.x line, the Claude Desktop main window picks up the WS_EX_TOPMOST extended window style and keeps it permanently. The mechanism is the z-order restore step: before relaunching, the app saves whatever window sits directly above its own as an "anchor," then re-inserts the new window behind that anchor with a SetWindowPos-based moveWindowBehind. If the anchor it grabbed happened to be a topmost window, the flag comes along for the ride and never gets cleared. 
Claude Code Issues

There's no in-app setting to turn it off, and quitting fully from the tray and relaunching doesn't clear it either. It's been reported on macOS (#66516) and Windows (#87084, #87895, #89467), and also filed through claude.ai support. 
GitHub
Claude Code Issues

Workarounds, least to most annoying:

Windows: put Claude on its own virtual desktop (Win+Ctrl+D). Always-on-top is per-desktop, so it stops covering everything on your main one. 
GitHub
Strip the style bit externally — an AHK one-liner (WinSet, AlwaysOnTop, Off, ahk_exe Claude.exe) or PowerToys' Win+Ctrl+T toggle will clear WS_EX_TOPMOST until the next relaunch. You'd have to re-run it after each auto-update.
Minimize when you're not using it, which is what most people are doing.
If you're on macOS instead, the virtual-desktop trick is Mission Control Spaces and works the same way; the AHK option obviously doesn't.

Worth a thumbs-down / bug report from your side too — reports on the Windows variant seem to be what's keeping it alive on the tracker, since the original macOS issue got closed as wrong-repo.

PS C:\WINDOWS\system32> WinSet, AlwaysOnTop, Off, ahk_exe Claude.exe
At line:1 char:7
+ WinSet, AlwaysOnTop, Off, ahk_exe Claude.exe
+       ~
Missing argument in parameter list.
    + CategoryInfo          : ParserError: (:) [], ParentContainsErrorRecordException
    + FullyQualifiedErrorId : MissingArgument


Thought for 7s
Thought for 7s
That's on me — that line is AutoHotkey syntax, not PowerShell. It only works if you have AHK installed and put it in a .ahk script. Here's a PowerShell equivalent that does the same thing directly:

powershell
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
-2 is HWND_NOTOPMOST, and 0x0003 is SWP_NOMOVE|SWP_NOSIZE so it only touches z-order and leaves position and size alone. No elevation needed as long as Claude isn't running elevated.

If Get-Process claude comes back empty, run Get-Process | Where MainWindowTitle -like '*Claude*' to find the actual process name — the MSIX packaging sometimes names it differently.

This clears the flag for the current window only. Next silent auto-update relaunch will set it again, so save it as unpin-claude.ps1 somewhere and re-run when it comes back. If that gets old, PowerToys' Win+Ctrl+T toggle is the same fix with one keystroke.

cool.  can you write me up an *md file explaining this issue with that code fix? i'm saving it in ye olde memory


Created a file, shared files
Created a file, shared files
Symptom, root cause, the PowerShell fix with the constants spelled out, the alternates, and the issue tracker table so you can check whether it's been fixed later without re-deriving any of it.


Claude desktop always on top
Document · MD 





Claude is AI and can make mistakes. Please double-check responses.


Claude desktop always on top · MD
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
 
