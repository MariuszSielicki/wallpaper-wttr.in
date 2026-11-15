# create_scheduled_task_wallpaper.ps1
# Version: 1.1.0
#
# Run ONCE. Registering the task requires a one-time ADMINISTRATOR
# elevation (a UAC prompt) - this is a Windows Task Scheduler restriction
# for any task that has a boot trigger, regardless of what account the
# task actually runs as afterward. This script detects if it's already
# elevated and, if not, relaunches itself elevated automatically.
#
# The registered task itself still runs as the regular user afterwards
# ("Run only when user is logged on", RunLevel LeastPrivilege) - no admin
# rights are needed for normal day-to-day operation, only for this
# one-time setup step.
#
# Creates a scheduled task that refreshes the wallpaper on:
#   - system startup (reboot)
#   - logon
#   - workstation unlock
#   - plus periodically every $IntervalMinutes (first run snapped to the
#     next half/full hour)
#
# Uses schtasks.exe /Create /XML instead of plain Register-ScheduledTask,
# because the "on unlock" trigger (SessionStateChangeTrigger) is not exposed
# by New-ScheduledTaskTrigger in the ScheduledTasks module - it has to be
# defined manually in the task XML.

# --- Self-elevate if not already running as administrator ---
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Output "Registering a task with a startup trigger requires administrator rights."
    Write-Output "Relaunching this script elevated (a UAC prompt will appear)..."

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-ExecutionPolicy Bypass -NoProfile -File `"$PSCommandPath`""
    $psi.Verb = "runas"

    try {
        $proc = [System.Diagnostics.Process]::Start($psi)
        $proc.WaitForExit()
        exit $proc.ExitCode
    } catch {
        Write-Error "Elevation was cancelled or failed: $($_.Exception.Message)"
        exit 1
    }
}

$TaskName = "DynamicWeatherWallpaper"
$LauncherPath = Join-Path $PSScriptRoot "wallpaper_launcher.vbs"
$IntervalMinutes = 30
$UserId = "$env:USERDOMAIN\$env:USERNAME"

# Snap the first periodic run to the nearest half hour (xx:00 or xx:30) -
# the Boot/Logon/Unlock triggers already refresh the wallpaper immediately
# on their respective events, so this only affects the background cycle.
$now = Get-Date
if ($now.Minute -lt 30) {
    $firstRun = Get-Date -Hour $now.Hour -Minute 30 -Second 0 -Millisecond 0
} else {
    $firstRun = (Get-Date -Hour $now.Hour -Minute 0 -Second 0 -Millisecond 0).AddHours(1)
}
$firstRunIso = $firstRun.ToString("yyyy-MM-ddTHH:mm:ss")

# ISO 8601 duration format required by Task Scheduler
$repetitionInterval = "PT${IntervalMinutes}M"
$repetitionDuration = "P3650D"

$xmlContent = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Refreshes the desktop wallpaper with weather data from wttr.in (system startup, logon, unlock, every $IntervalMinutes min)</Description>
  </RegistrationInfo>
  <Triggers>
    <BootTrigger>
      <Enabled>true</Enabled>
    </BootTrigger>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <UserId>$UserId</UserId>
    </LogonTrigger>
    <SessionStateChangeTrigger>
      <Enabled>true</Enabled>
      <StateChange>SessionUnlock</StateChange>
      <UserId>$UserId</UserId>
    </SessionStateChangeTrigger>
    <TimeTrigger>
      <Repetition>
        <Interval>$repetitionInterval</Interval>
        <Duration>$repetitionDuration</Duration>
        <StopAtDurationEnd>false</StopAtDurationEnd>
      </Repetition>
      <StartBoundary>$firstRunIso</StartBoundary>
      <Enabled>true</Enabled>
    </TimeTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>$UserId</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT5M</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>wscript.exe</Command>
      <Arguments>"$LauncherPath"</Arguments>
    </Exec>
  </Actions>
</Task>
"@

$tempXmlPath = Join-Path $env:TEMP "DynamicWeatherWallpaper_task.xml"
# Task Scheduler XML requires UTF-16 encoding (matches the header above)
[System.IO.File]::WriteAllText($tempXmlPath, $xmlContent, [System.Text.Encoding]::Unicode)

# Remove an existing task with the same name, if present
schtasks.exe /Query /TN $TaskName 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Output "Task '$TaskName' already exists - removing old version..."
    schtasks.exe /Delete /TN $TaskName /F | Out-Null
}

schtasks.exe /Create /TN $TaskName /XML $tempXmlPath /F

if ($LASTEXITCODE -eq 0) {
    Write-Output "Task '$TaskName' created."
    Write-Output "Triggers: system startup, logon, screen unlock, and every $IntervalMinutes min (first cycle: $firstRunIso)"
    Write-Output "Launcher: $LauncherPath"
} else {
    Write-Error "Task creation failed (schtasks exit code: $LASTEXITCODE)"
}

Remove-Item $tempXmlPath -ErrorAction SilentlyContinue

# If elevation spawned a brand new console window, pause so the result
# above stays visible instead of the window closing immediately.
Write-Output ""
Read-Host "Press Enter to continue"
