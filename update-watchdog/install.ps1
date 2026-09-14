<#
.SYNOPSIS
  Installs the Claude Desktop update watchdog as a per-user scheduled task.

.DESCRIPTION
  Copies claude-watchdog.ps1 to %LOCALAPPDATA%\claude-hacks and registers
  "\claude-hacks\Claude Update Watchdog" for the current user:
    - runs at logon and every IntervalMinutes after, only while you're logged on
    - no elevation (RunLevel Limited)
    - never wakes the PC (WakeToRun off), and one instance at a time
    - launched through `conhost --headless`, so no console window flashes
      or takes focus

  Uninstall with uninstall.ps1.
#>
[CmdletBinding()]
param([int]$IntervalMinutes = 5)

$ErrorActionPreference = 'Stop'
$taskName = 'Claude Update Watchdog'
$taskPath = '\claude-hacks\'
$dest = Join-Path $env:LOCALAPPDATA 'claude-hacks'
$user = "$env:USERDOMAIN\$env:USERNAME"

New-Item -ItemType Directory -Force -Path $dest | Out-Null
Copy-Item -Path (Join-Path $PSScriptRoot 'claude-watchdog.ps1') -Destination $dest -Force
$script = Join-Path $dest 'claude-watchdog.ps1'

$action = New-ScheduledTaskAction -Execute 'conhost.exe' `
  -Argument ('--headless powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}"' -f $script)

$repeat = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
  -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) -RepetitionDuration (New-TimeSpan -Days 3650)
$logon = New-ScheduledTaskTrigger -AtLogOn -User $user

$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
  -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 3)
$settings.WakeToRun = $false

Register-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Action $action -Trigger @($logon, $repeat) `
  -Principal $principal -Settings $settings -Force `
  -Description 'Relaunches Claude Desktop only when a silent auto-update quit it and it never came back. https://github.com/paperhurts/claude-hacks' |
  Out-Null

Write-Host "Installed '$taskPath$taskName' (every $IntervalMinutes min while logged on)."
Write-Host "Script:   $script"
Write-Host "Status:   $(Join-Path $dest 'watchdog.last-run.txt')  (last decision, overwritten each run)"
Write-Host "Actions:  $(Join-Path $dest 'watchdog.log')  (only written when it relaunches)"
