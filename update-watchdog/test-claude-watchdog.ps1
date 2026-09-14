<#
.SYNOPSIS
  Decision tests for claude-watchdog.ps1. They only ever use -DryRun: nothing
  is ended or launched, so it's safe to run while Claude is open (including from
  inside Claude). Each case feeds a synthetic main.log built from real log lines.
#>
$ErrorActionPreference = 'Stop'
$watchdog = Join-Path $PSScriptRoot 'claude-watchdog.ps1'
$work = Join-Path $env:TEMP ("claude-watchdog-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $work | Out-Null

$updateQuit = @(
  '2026-09-13 15:52:25 [info] [CCD] Killing 5 PTY process tree(s) on quit',
  '2026-09-13 15:52:26 [info] beforeQuitForUpdate handler fired, going down for update',
  '2026-09-13 15:52:26 [info] Windows session ending (close-app) - quitting the app'
)
$realStart = @(
  '2026-09-13 19:36:41 [info] Starting app {',
  "  appVersion: '1.52386.6',",
  '}',
  '2026-09-13 19:36:41 [info] [growthbook] next refresh in 60 min'
)
$secondInstance = @(
  '2026-09-13 16:10:05 [info] second-instance: suppressing duplicate argv',
  '2026-09-13 16:10:05 [info] Starting app {',
  "  appVersion: '1.52386.6',",
  '}',
  '2026-09-13 16:10:05 [info] Not main instance, returning early from app ready'
)
$quitAt = [datetime]'2026-09-13 15:52:26'

$failures = 0
function Invoke-Case([string]$name, [string[]]$logLines, [datetime]$now, [string]$expectPrefix, [scriptblock]$seed) {
  $dir = Join-Path $work ($name -replace '[^a-z0-9]', '-')
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $log = Join-Path $dir 'main.log'
  Set-Content -Path $log -Value $logLines -Encoding UTF8
  if ($seed) { & $seed $dir }
  $null = & $watchdog -DryRun -LogPath $log -Now $now -StateDir $dir
  $decision = (Get-Content (Join-Path $dir 'watchdog.last-run.txt') -TotalCount 1).Substring(21)
  if ($decision.StartsWith($expectPrefix)) { Write-Host "PASS  $name  ->  $decision" }
  else { Write-Host "FAIL  $name  ->  got '$decision', expected '$expectPrefix...'"; $script:failures++ }
}

Invoke-Case 'no update-quit at all'            @('2026-09-13 12:00:00 [info] [growthbook] loaded') $quitAt.AddMinutes(30) 'healthy: no update-quit'
Invoke-Case 'relaunched normally after update' ($updateQuit + $realStart)          $quitAt.AddHours(4)     'healthy: started'
Invoke-Case 'relaunch never came (the bug)'    $updateQuit                         $quitAt.AddMinutes(10)  'DRY RUN recover'
Invoke-Case 'inside grace period'              $updateQuit                         $quitAt.AddMinutes(1)   'waiting'
Invoke-Case 'only an icon click after quit'    ($updateQuit + $secondInstance)     $quitAt.AddMinutes(25)  'DRY RUN recover'
Invoke-Case 'cooldown after a recent recovery' $updateQuit                         $quitAt.AddMinutes(20)  'cooldown' {
  param($dir) Set-Content (Join-Path $dir 'watchdog.last-recovery.txt') $quitAt.AddMinutes(15).ToString('yyyy-MM-dd HH:mm:ss')
}

Remove-Item $work -Recurse -Force
if ($failures -gt 0) { Write-Host "$failures case(s) FAILED"; exit 1 }
Write-Host 'All decision cases passed.'
