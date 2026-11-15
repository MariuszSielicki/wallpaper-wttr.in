# restore.ps1
# Version: 1.0.0
#
# Restores the original wallpaper.<ext> as the desktop wallpaper (without
# the weather overlay) and removes the DynamicWeatherWallpaper scheduled
# task, if present. Run via restore.bat (double-click) or directly.

$RootDir = Split-Path $PSScriptRoot -Parent
$TaskName = "DynamicWeatherWallpaper"
$SupportedExtensions = @("jpg", "jpeg", "png", "bmp")

# --- Self-elevate if not already running as administrator ---
# (removing a scheduled task that was registered with a boot trigger
# generally requires the same elevation used to create it)
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Output "Removing the scheduled task requires administrator rights."
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

Write-Output "============================================"
Write-Output "  Dynamic Weather Wallpaper - Restore"
Write-Output "============================================"
Write-Output ""

# --- Step 1: remove the scheduled task, if present ---
schtasks.exe /Query /TN $TaskName 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) {
    schtasks.exe /Delete /TN $TaskName /F | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Output "Scheduled task '$TaskName' removed."
    } else {
        Write-Warning "Failed to remove scheduled task '$TaskName' (schtasks exit code: $LASTEXITCODE)."
    }
} else {
    Write-Output "Scheduled task '$TaskName' not found - nothing to remove."
}

# --- Step 2: find and restore the base wallpaper image ---
Write-Output ""
$BaseWallpaperPath = $null
foreach ($ext in $SupportedExtensions) {
    $candidate = Join-Path $RootDir "wallpaper.$ext"
    if (Test-Path $candidate) {
        $BaseWallpaperPath = $candidate
        break
    }
}

if (-not $BaseWallpaperPath) {
    $extList = ($SupportedExtensions | ForEach-Object { "wallpaper.$_" }) -join ", "
    Write-Warning "Base image not found in $RootDir. Expected one of: $extList"
    Write-Output ""
    Read-Host "Press Enter to continue"
    exit 1
}

Write-Output "Restoring wallpaper from: $BaseWallpaperPath"

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class RestoreWallpaper {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@

$SPI_SETDESKWALLPAPER = 20
$SPIF_UPDATEINIFILE = 0x01
$SPIF_SENDWININICHANGE = 0x02

$result = [RestoreWallpaper]::SystemParametersInfo($SPI_SETDESKWALLPAPER, 0, $BaseWallpaperPath, $SPI_SETDESKWALLPAPER + $SPIF_UPDATEINIFILE + $SPIF_SENDWININICHANGE)

if ($result -ne 0) {
    Write-Output "Wallpaper restored successfully."
} else {
    Write-Warning "SystemParametersInfo failed (returned 0) - the wallpaper may not have been applied."
}

Write-Output ""
Read-Host "Press Enter to continue"
