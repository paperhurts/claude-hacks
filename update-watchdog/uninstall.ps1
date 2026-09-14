<#
.SYNOPSIS
  Removes the Claude Desktop update watchdog: the scheduled task and its
  %USERPROFILE%\.claude-hacks folder (the script copy, status, and log).
#>
$ErrorActionPreference = 'Stop'
Unregister-ScheduledTask -TaskName 'Claude Update Watchdog' -TaskPath '\claude-hacks\' -Confirm:$false -ErrorAction SilentlyContinue
Remove-Item -Path (Join-Path $env:USERPROFILE '.claude-hacks') -Recurse -Force -ErrorAction SilentlyContinue
Write-Host 'Claude Update Watchdog removed.'
