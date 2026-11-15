# wallpaper.ps1
# Version: 1.2.0
#
# Generates a desktop wallpaper by overlaying current weather data from
# wttr.in onto a base image, and sets it as the Windows desktop wallpaper.
#
# Settings (city, wttr.in format, margins, opacity) are loaded from
# config.txt, expected in the PARENT folder (next to start.bat). Use
# start.bat / scripts\setup_config.ps1 to generate it interactively, or
# edit config.txt by hand. Any setting missing from config.txt falls back
# to the built-in default shown below.
#
# The base image (wallpaper.jpg / .jpeg / .png / .bmp) is also expected in
# the PARENT folder, next to config.txt.

$RootDir = Split-Path $PSScriptRoot -Parent
$ConfigPath = Join-Path $RootDir "config.txt"

$OutPath = Join-Path $PSScriptRoot "current_wallpaper.png"
$AppliedCopyPath = Join-Path $PSScriptRoot "applied_wallpaper.png"
$LogPath = Join-Path $PSScriptRoot "wallpaper.log"

# Extensions to look for when locating the base image "wallpaper.<ext>" in $RootDir
$SupportedExtensions = @("jpg", "jpeg", "png", "bmp")

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogPath -Value $line
}

# --- Load key=value pairs from config.txt (lines starting with # are comments) ---
function Read-ConfigFile {
    param([string]$Path)
    $config = @{}
    if (-not (Test-Path $Path)) {
        return $config
    }
    Get-Content -Path $Path | ForEach-Object {
        $line = $_.Trim()
        if ($line -eq "" -or $line.StartsWith("#")) { return }
        $idx = $line.IndexOf("=")
        if ($idx -gt 0) {
            $key = $line.Substring(0, $idx).Trim()
            $value = $line.Substring($idx + 1).Trim()
            $config[$key] = $value
        }
    }
    return $config
}

# --- Locate the base image "wallpaper.<ext>" in $RootDir ---
function Find-BaseWallpaperFile {
    foreach ($ext in $SupportedExtensions) {
        $candidate = Join-Path $RootDir "wallpaper.$ext"
        if (Test-Path $candidate) {
            return $candidate
        }
    }
    return $null
}

Write-Log "===== Script start ====="
Write-Log "User: $env:USERNAME | Interactive session: $([Environment]::UserInteractive) | SESSIONNAME: $env:SESSIONNAME"

$Config = Read-ConfigFile -Path $ConfigPath
if ($Config.Count -eq 0) {
    Write-Log "config.txt not found or empty at $ConfigPath - using built-in defaults" "WARN"
}

# --- Settings (config.txt values override these built-in defaults) ---
$City = if ($Config.ContainsKey("City")) { $Config["City"] } else { "Wroclaw" }
$WttrUrlTemplate = if ($Config.ContainsKey("WttrUrlTemplate")) { $Config["WttrUrlTemplate"] } else { "https://v2.wttr.in/{CITY}.png" }
$MarginRightPercent = if ($Config.ContainsKey("MarginRightPercent")) { [double]$Config["MarginRightPercent"] } else { 0.0 }
$MarginBottomPercent = if ($Config.ContainsKey("MarginBottomPercent")) { [double]$Config["MarginBottomPercent"] } else { 0.0 }
$MarginRightPx = if ($Config.ContainsKey("MarginRightPx")) { [int]$Config["MarginRightPx"] } else { 5 }
$MarginBottomPx = if ($Config.ContainsKey("MarginBottomPx")) { [int]$Config["MarginBottomPx"] } else { 55 }
$Opacity = if ($Config.ContainsKey("Opacity")) { [float]$Config["Opacity"] } else { 0.85 }

# {CITY} in the template is replaced with the URL-encoded city name
$CityEncoded = [System.Uri]::EscapeDataString($City)
$WttrUrl = $WttrUrlTemplate.Replace("{CITY}", $CityEncoded)

Write-Log "Config: City=$City | WttrUrlTemplate=$WttrUrlTemplate | MarginRightPercent=$MarginRightPercent | MarginBottomPercent=$MarginBottomPercent | MarginRightPx=$MarginRightPx | MarginBottomPx=$MarginBottomPx | Opacity=$Opacity"
Write-Log "Resolved weather URL: $WttrUrl"

try {
    Add-Type -AssemblyName System.Drawing

    $BaseWallpaperPath = Find-BaseWallpaperFile
    if (-not $BaseWallpaperPath) {
        $extList = ($SupportedExtensions | ForEach-Object { "wallpaper.$_" }) -join ", "
        Write-Log "Base image not found in $RootDir. Expected one of: $extList" "ERROR"
        exit 1
    }
    Write-Log "Base image found: $BaseWallpaperPath"

    function Draw-ImageWithOpacity {
        param($Graphics, $Image, $X, $Y, $Width, $Height, [float]$Opacity)
        $colorMatrix = New-Object System.Drawing.Imaging.ColorMatrix
        $colorMatrix.Matrix33 = $Opacity
        $imgAttributes = New-Object System.Drawing.Imaging.ImageAttributes
        $imgAttributes.SetColorMatrix($colorMatrix, [System.Drawing.Imaging.ColorMatrixFlag]::Default, [System.Drawing.Imaging.ColorAdjustType]::Bitmap)
        $destRect = New-Object System.Drawing.Rectangle($X, $Y, $Width, $Height)
        $Graphics.DrawImage($Image, $destRect, 0, 0, $Image.Width, $Image.Height, [System.Drawing.GraphicsUnit]::Pixel, $imgAttributes)
    }

    $baseImg = [System.Drawing.Image]::FromFile($BaseWallpaperPath)
    Write-Log "Base image loaded, native size: $($baseImg.Width)x$($baseImg.Height)"

    # --- Make this process DPI-aware, otherwise at 125%/150% scaling
    # Screen.Bounds returns the virtualized (smaller) resolution ---
    Add-Type @"
using System.Runtime.InteropServices;
public class DpiHelper {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
}
"@
    [void][DpiHelper]::SetProcessDPIAware()

    # --- Detect actual desktop resolution (primary monitor) ---
    Add-Type -AssemblyName System.Windows.Forms
    $screenBounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $screenWidth = $screenBounds.Width
    $screenHeight = $screenBounds.Height
    Write-Log "Detected desktop resolution (primary monitor): ${screenWidth}x${screenHeight}"

    # Build the output canvas at the ACTUAL desktop resolution, not the base
    # file's own resolution. The base image is scaled (fill) into this canvas,
    # so Windows does not need to rescale it further, and margins are computed
    # directly against the real screen size.
    $bmp = New-Object System.Drawing.Bitmap $screenWidth, $screenHeight
    $graphics = [System.Drawing.Graphics]::FromImage($bmp)
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    # "Fill" scaling: preserve aspect ratio, cover the whole canvas, center and
    # crop the overflow (no distortion).
    $scale = [Math]::Max($screenWidth / $baseImg.Width, $screenHeight / $baseImg.Height)
    $drawW = [int][Math]::Ceiling($baseImg.Width * $scale)
    $drawH = [int][Math]::Ceiling($baseImg.Height * $scale)
    $drawX = [int](($screenWidth - $drawW) / 2)
    $drawY = [int](($screenHeight - $drawH) / 2)
    $graphics.DrawImage($baseImg, $drawX, $drawY, $drawW, $drawH)
    $baseImg.Dispose()
    Write-Log "Base image scaled (fill) to desktop resolution: $($bmp.Width)x$($bmp.Height) [drawn ${drawW}x${drawH} at ($drawX, $drawY)]"

    # Download with timeout + retries (network is often not ready yet right
    # after startup / logon / unlock). A non-image response also counts as a
    # failed attempt.
    $tempWeatherPath = "$env:TEMP\wttr_overlay.png"
    $maxAttempts = 3
    $weatherImg = $null
    for ($attempt = 1; $attempt -le $maxAttempts -and -not $weatherImg; $attempt++) {
        try {
            Invoke-WebRequest -Uri $WttrUrl -OutFile $tempWeatherPath -UseBasicParsing -TimeoutSec 30
            $weatherImg = [System.Drawing.Image]::FromFile($tempWeatherPath)
        } catch {
            Write-Log "Weather download attempt $attempt/$maxAttempts failed: $($_.Exception.Message)" "WARN"
            if ($attempt -lt $maxAttempts) { Start-Sleep -Seconds 10 }
        }
    }
    if (-not $weatherImg) {
        throw "Could not download a valid weather image from $WttrUrl after $maxAttempts attempts"
    }
    Write-Log "Downloaded weather image: $WttrUrl -> $tempWeatherPath ($($weatherImg.Width)x$($weatherImg.Height))"

    # Margins = percentage of desktop resolution (bmp is now exactly the
    # detected screen size) PLUS a fixed pixel offset.
    $marginRightTotal = [int]($bmp.Width * ($MarginRightPercent / 100.0)) + $MarginRightPx
    $marginBottomTotal = [int]($bmp.Height * ($MarginBottomPercent / 100.0)) + $MarginBottomPx

    $x = $bmp.Width - $weatherImg.Width - $marginRightTotal
    $y = $bmp.Height - $weatherImg.Height - $marginBottomTotal
    Draw-ImageWithOpacity -Graphics $graphics -Image $weatherImg -X $x -Y $y -Width $weatherImg.Width -Height $weatherImg.Height -Opacity $Opacity
    $weatherImg.Dispose()
    Write-Log "Weather image placed at ($x, $y) [margins px: R=$marginRightTotal (pct+fixed), B=$marginBottomTotal (pct+fixed)]"

    if (Test-Path $OutPath) { Remove-Item $OutPath -Force }
    $bmp.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose()
    $bmp.Dispose()
    Remove-Item $tempWeatherPath -ErrorAction SilentlyContinue
    Write-Log "Saved resulting wallpaper: $OutPath"

    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Wallpaper {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@

    $SPI_SETDESKWALLPAPER = 20
    $SPIF_UPDATEINIFILE = 0x01
    $SPIF_SENDWININICHANGE = 0x02

    $result = [Wallpaper]::SystemParametersInfo($SPI_SETDESKWALLPAPER, 0, $OutPath, $SPI_SETDESKWALLPAPER + $SPIF_UPDATEINIFILE + $SPIF_SENDWININICHANGE)
    Write-Log "SystemParametersInfo returned: $result (0 = FAILURE, non-zero = OK)"

    Start-Sleep -Milliseconds 500
    $transcodedPath = "$env:APPDATA\Microsoft\Windows\Themes\TranscodedWallpaper"
    if (Test-Path $transcodedPath) {
        Copy-Item -Path $transcodedPath -Destination $AppliedCopyPath -Force
        Write-Log "Copied applied wallpaper: $AppliedCopyPath"
    } else {
        Write-Log "TranscodedWallpaper not found" "WARN"
    }

    Write-Log "===== Script end (success) ====="
}
catch {
    Write-Log "EXCEPTION: $($_.Exception.Message)" "ERROR"
    Write-Log "Stack: $($_.ScriptStackTrace)" "ERROR"
    Write-Log "===== Script end (failure) ====="
    exit 1
}
