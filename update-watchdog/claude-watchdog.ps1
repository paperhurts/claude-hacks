<#
.SYNOPSIS
  Brings Claude Desktop (Windows) back when a silent auto-update quits it and
  never relaunches it.

.DESCRIPTION
  Claude Desktop installs updates by quitting itself and relaunching. main.log
  shows "beforeQuitForUpdate handler fired, going down for update". Usually the
  relaunch takes about 2 seconds. Sometimes it never happens, and a leftover
  process keeps the executable locked, so opening the app fails with
  "something is using the executable" until you reboot.

  This script acts ONLY on that failure. Each run:
    1. Reads the tail of Claude's main.log.
    2. No update-quit, or the app started after its last update-quit: does nothing.
    3. The update-quit is under GraceMinutes old: does nothing, so Claude's own
       relaunch gets its chance.
    4. Otherwise ends leftover Claude Desktop processes. It only touches
       ...\WindowsApps\Claude_*\app\Claude.exe, never the Claude Code CLI
       binaries, which are also named claude.exe. Then it relaunches the app
       and sends its window to the BACK without activating it. That also
       clears the stuck always-on-top flag (see the repo README).

  It does nothing if you quit Claude yourself (there's no update line in the
  log). It never kills a responding Claude window, and relaunches at most once
  per CooldownMinutes. It takes no keep-awake and doesn't wake the PC: the
  scheduled task runs about a second every few minutes, only while you're
  logged on.

.PARAMETER DryRun
  Report the decision; end and launch nothing.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\claude-watchdog.ps1 -DryRun
#>
[CmdletBinding()]
param(
  [switch]$DryRun,
  [string]$LogPath = (Join-Path $env:LOCALAPPDATA 'Claude\Logs\main.log'),
  [int]$GraceMinutes = 3,
  [int]$CooldownMinutes = 15,
  [datetime]$Now = (Get-Date),
  # Not %LOCALAPPDATA%: inside Claude Desktop (an MSIX package), writes there are
  # silently redirected to Packages\Claude_*\LocalCache, where Task Scheduler
  # can't see them. The profile root isn't redirected.
  [string]$StateDir = (Join-Path $env:USERPROFILE '.claude-hacks')
)

$ErrorActionPreference = 'Stop'
$Aumid = 'Claude_pzs8sxrjxfjjc!Claude'                        # Claude Desktop's Store/MSIX app id
$AppExePattern = '\\WindowsApps\\Claude_[^\\]+\\app\\Claude\.exe$' # Desktop only, never Claude Code
$TimeFormat = 'yyyy-MM-dd HH:mm:ss'
$Invariant = [Globalization.CultureInfo]::InvariantCulture

function Write-State([string]$decision) {
  New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
  $line = '{0}  {1}' -f $Now.ToString($TimeFormat), $decision
  # One line, overwritten every run: "is it working?" without a growing file.
  Set-Content -Path (Join-Path $StateDir 'watchdog.last-run.txt') -Value $line -Encoding UTF8
  $line
}

function Add-ActionLog([string]$text) {
  New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
  $log = Join-Path $StateDir 'watchdog.log'
  Add-Content -Path $log -Value ('{0}  {1}' -f (Get-Date).ToString($TimeFormat), $text) -Encoding UTF8
  $lines = @(Get-Content $log)
  if ($lines.Count -gt 500) { $lines | Select-Object -Last 500 | Set-Content $log -Encoding UTF8 }
}

function Read-LogTail([string]$path, [int]$bytes = 524288) {
  if (-not (Test-Path $path)) { return @() }
  # The running app holds main.log open, so share read/write/delete.
  $fs = [System.IO.File]::Open($path, 'Open', 'Read', [System.IO.FileShare]'ReadWrite, Delete')
  try {
    $start = [math]::Max(0, $fs.Length - $bytes)
    [void]$fs.Seek($start, 'Begin')
    $text = (New-Object System.IO.StreamReader($fs)).ReadToEnd()
  } finally { $fs.Dispose() }
  $lines = @($text -split "`r?`n")
  if ($start -gt 0 -and $lines.Count -gt 1) { $lines = $lines[1..($lines.Count - 1)] } # drop the partial first line
  $lines
}

function Get-Lifecycle([string[]]$lines) {
  $lastQuit = $null; $lastStart = $null
  for ($i = 0; $i -lt $lines.Count; $i++) {
    $l = $lines[$i]
    if ($l.Length -lt 19) { continue }
    try {
      if ($l -match 'beforeQuitForUpdate handler fired, going down for update') {
        $lastQuit = [datetime]::ParseExact($l.Substring(0, 19), $TimeFormat, $Invariant)
      } elseif ($l -match '\[info\] Starting app \{') {
        # Clicking the icon while Claude is already open also logs "Starting app"
        # and then "Not main instance" before exiting. That is not a real start.
        $end = [math]::Min($i + 15, $lines.Count - 1)
        $following = ''
        if ($end -gt $i) { $following = $lines[($i + 1)..$end] -join "`n" }
        if ($following -notmatch 'Not main instance') {
          $lastStart = [datetime]::ParseExact($l.Substring(0, 19), $TimeFormat, $Invariant)
        }
      }
    } catch { continue } # an unparseable line is never a reason to act
  }
  @{ LastUpdateQuit = $lastQuit; LastMainStart = $lastStart }
}

$lc = Get-Lifecycle (Read-LogTail $LogPath)

if (-not $lc.LastUpdateQuit) { Write-State 'healthy: no update-quit in the recent log'; return }
if ($lc.LastMainStart -and $lc.LastMainStart -ge $lc.LastUpdateQuit) {
  Write-State ('healthy: started {0} after update-quit {1}' -f $lc.LastMainStart.ToString($TimeFormat), $lc.LastUpdateQuit.ToString($TimeFormat))
  return
}

$minutesDown = ($Now - $lc.LastUpdateQuit).TotalMinutes
if ($minutesDown -lt $GraceMinutes) {
  Write-State ('waiting: update-quit {0:N1} min ago, inside the {1}-min grace' -f $minutesDown, $GraceMinutes)
  return
}

$cooldownFile = Join-Path $StateDir 'watchdog.last-recovery.txt'
if (Test-Path $cooldownFile) {
  try {
    $lastRecovery = [datetime]::ParseExact((Get-Content $cooldownFile -TotalCount 1).Trim(), $TimeFormat, $Invariant)
    if (($Now - $lastRecovery).TotalMinutes -lt $CooldownMinutes) {
      Write-State ('cooldown: last recovery {0}' -f $lastRecovery.ToString($TimeFormat))
      return
    }
  } catch { } # unreadable marker: fall through
}

$leftovers = @(Get-Process -Name Claude -ErrorAction SilentlyContinue | Where-Object { $_.Path -match $AppExePattern })
$responding = @($leftovers | Where-Object { $_.MainWindowHandle -ne 0 -and $_.Responding })
$plan = 'update-quit {0} with no start since ({1:N0} min): end {2} leftover Claude Desktop process(es), relaunch' -f `
  $lc.LastUpdateQuit.ToString($TimeFormat), $minutesDown, $leftovers.Count

if ($DryRun) {
  $note = ''
  if ($responding.Count -gt 0) { $note = ' [a responding Claude window exists, so a real run would skip]' }
  Write-State "DRY RUN recover: $plan$note"
  return
}

if ($responding.Count -gt 0) {
  Write-State 'skip: a responding Claude window exists even though the log shows no start'
  return
}

New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
Set-Content -Path $cooldownFile -Value $Now.ToString($TimeFormat) -Encoding UTF8
Add-ActionLog "RECOVER: $plan"

foreach ($p in $leftovers) {
  try { Stop-Process -Id $p.Id -Force -ErrorAction Stop }
  catch { Add-ActionLog ('  could not end PID {0}: {1}' -f $p.Id, $_.Exception.Message) }
}
Start-Sleep -Seconds 3
Start-Process "shell:AppsFolder\$Aumid"

Add-Type -Namespace ClaudeHacks -Name Win -MemberDefinition @'
[DllImport("user32.dll")]
public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
'@

function Send-ClaudeToBack {
  $w = Get-Process -Name Claude -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -match $AppExePattern -and $_.MainWindowHandle -ne 0 } |
    Select-Object -First 1
  if (-not $w) { return $false }
  # HWND_BOTTOM (1): behind every other window, and drops always-on-top.
  # SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE (0x0013): z-order only, never takes focus.
  [void][ClaudeHacks.Win]::SetWindowPos($w.MainWindowHandle, [IntPtr]1, 0, 0, 0, 0, 0x0013)
  $true
}

$deadline = (Get-Date).AddSeconds(90)
$placed = $false
while (-not $placed -and (Get-Date) -lt $deadline) {
  Start-Sleep -Seconds 2
  $placed = Send-ClaudeToBack
}
if ($placed) {
  # The app's own z-order restore can re-raise the window moments after it
  # appears (the always-on-top bug), so settle it once more.
  Start-Sleep -Seconds 10
  [void](Send-ClaudeToBack)
  Add-ActionLog '  relaunched; window sent to the back without focus'
  Write-State ('recovered: relaunched after update-quit {0}' -f $lc.LastUpdateQuit.ToString($TimeFormat))
} else {
  Add-ActionLog '  launched, but no Claude window appeared within 90s (it may have started to the tray)'
  Write-State 'recovery attempted: no window within 90s'
}
