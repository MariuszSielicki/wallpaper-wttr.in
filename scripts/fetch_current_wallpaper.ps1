# fetch_current_wallpaper.ps1
# Version: 1.1.0
#
# Fetches the CURRENTLY set Windows desktop wallpaper and saves it in the
# PARENT folder (next to start.bat / config.txt), named wallpaper.<ext> -
# the file format (jpg/png/bmp) is auto-detected from the actual image
# content.
#
# Usage: just run this script (or choose the "use current wallpaper" option
# in start.bat). Overwrites any existing wallpaper.<ext> file in the parent
# folder (regardless of its extension).

$RootDir = Split-Path $PSScriptRoot -Parent
$SupportedExtensions = @("jpg", "jpeg", "png", "bmp")

Add-Type -AssemblyName System.Drawing

# --- Find the path to the currently set desktop wallpaper ---
function Get-CurrentWallpaperPath {
    $rawRegValue = (Get-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name WallPaper -ErrorAction SilentlyContinue).WallPaper
    Write-Host "Raw registry value (WallPaper): '$rawRegValue'"

    if ($rawRegValue) {
        $candidate = $rawRegValue.Trim('"', "'", ' ')

        # Expand any environment variables (%SystemRoot% etc.), in case the
        # value is of type REG_EXPAND_SZ and wasn't expanded automatically
        $candidate = [System.Environment]::ExpandEnvironmentVariables($candidate)

        # Some older mechanisms store the path as a file:///C:/... URI -
        # this causes "path format not supported" errors in File.ReadAllBytes
        if ($candidate -like "file:///*") {
            try {
                $candidate = [Uri]::UnescapeDataString(([Uri]$candidate).LocalPath)
                Write-Host "Detected file:// URI - converted to: $candidate"
            } catch {
                Write-Host "Failed to convert URI, skipping this entry"
                $candidate = $null
            }
        }

        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            Write-Host "Found wallpaper in registry: $candidate"
            return $candidate
        } elseif ($candidate) {
            Write-Host "Registry path does not point to an existing file: $candidate"
        }
    }

    $transcoded = "$env:APPDATA\Microsoft\Windows\Themes\TranscodedWallpaper"
    if (Test-Path -LiteralPath $transcoded -PathType Leaf) {
        Write-Host "Using TranscodedWallpaper: $transcoded"
        return $transcoded
    }

    return $null
}

try {
    $currentWallpaperPath = Get-CurrentWallpaperPath
    if (-not $currentWallpaperPath) {
        Write-Error "Could not determine the current wallpaper path (neither the registry nor TranscodedWallpaper yielded a result)."
        exit 1
    }

    Write-Output "Reading file: $currentWallpaperPath"

    # Read into memory so we don't hold a lock on a Windows system file
    # (important especially for TranscodedWallpaper, which Windows may
    # want to update in the background).
    $fileBytes = [System.IO.File]::ReadAllBytes($currentWallpaperPath)
    $memStream = New-Object System.IO.MemoryStream(,$fileBytes)
    $img = [System.Drawing.Image]::FromStream($memStream)

    # --- Detect the actual image format (TranscodedWallpaper has no extension) ---
    $formatMap = @{
        [System.Drawing.Imaging.ImageFormat]::Jpeg = "jpg"
        [System.Drawing.Imaging.ImageFormat]::Png  = "png"
        [System.Drawing.Imaging.ImageFormat]::Bmp  = "bmp"
        [System.Drawing.Imaging.ImageFormat]::Gif  = "gif"
    }

    $detectedExt = $null
    foreach ($fmt in $formatMap.Keys) {
        if ($img.RawFormat.Equals($fmt)) {
            $detectedExt = $formatMap[$fmt]
            break
        }
    }

    if (-not $detectedExt) {
        Write-Output "Unrecognized image format - defaulting to .jpg"
        $detectedExt = "jpg"
        $saveFormat = [System.Drawing.Imaging.ImageFormat]::Jpeg
    } elseif ($detectedExt -eq "gif") {
        # gif is not in the extension list supported by wallpaper.ps1 - convert to png
        Write-Output "Detected GIF format - converting to PNG (GIF is not supported by wallpaper.ps1)"
        $detectedExt = "png"
        $saveFormat = [System.Drawing.Imaging.ImageFormat]::Png
    } else {
        $saveFormat = $img.RawFormat
        Write-Output "Detected image format: $detectedExt"
    }

    # --- Remove old wallpaper.<ext> files in the root folder (any supported extension) ---
    foreach ($ext in $SupportedExtensions) {
        $oldFile = Join-Path $RootDir "wallpaper.$ext"
        if (Test-Path $oldFile) {
            Remove-Item $oldFile -Force
            Write-Output "Removed old file: $oldFile"
        }
    }

    $OutPath = Join-Path $RootDir "wallpaper.$detectedExt"
    $img.Save($OutPath, $saveFormat)
    $img.Dispose()
    $memStream.Dispose()

    Write-Output "Saved current wallpaper as: $OutPath"
}
catch {
    Write-Error "Error: $($_.Exception.Message)"
    exit 1
}
