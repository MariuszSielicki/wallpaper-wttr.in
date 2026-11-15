# setup_config.ps1
# Version: 1.1.1
#
# Interactive configuration wizard, launched by start.bat. Asks for:
#   - city name
#   - wttr.in display format (with a live browser preview before confirming)
#   - base wallpaper image (keep existing wallpaper.<ext> if one is found,
#     use current desktop wallpaper, or provide a path)
# then writes config.txt in the root folder (next to start.bat).
#
# Fixed default parameters (margins, opacity) are written as-is; edit
# config.txt by hand afterwards if you want to change those.

$RootDir = Split-Path $PSScriptRoot -Parent
$ScriptsDir = $PSScriptRoot
$ConfigPath = Join-Path $RootDir "config.txt"

Write-Host "============================================"
Write-Host "  Dynamic Weather Wallpaper - Setup Wizard"
Write-Host "============================================"
Write-Host ""

# --- Step 1: city name ---
$City = ""
while ($City -eq "") {
    $City = Read-Host "Enter your city name (e.g. Wroclaw)"
    $City = $City.Trim()
    if ($City -eq "") {
        Write-Host "City name cannot be empty." -ForegroundColor Yellow
    }
}

# --- Step 2: wttr.in display format, with browser preview ---
$UrlOptions = @(
    @{ Label = "v2.wttr.in - richer view (default)";               Template = "https://v2.wttr.in/{CITY}.png" }
    @{ Label = "wttr.in ?0  - compact, single line";                Template = "https://wttr.in/{CITY}.png?0" }
    @{ Label = "wttr.in ?1  - one-day forecast";                    Template = "https://wttr.in/{CITY}.png?1" }
    @{ Label = "wttr.in ?2  - two-day forecast";                    Template = "https://wttr.in/{CITY}.png?2" }
    @{ Label = "wttr.in ?F  - no footer line";                      Template = "https://wttr.in/{CITY}.png?F" }
    @{ Label = "wttr.in ?Fn - no footer, no location name";         Template = "https://wttr.in/{CITY}.png?Fn" }
    @{ Label = "wttr.in custom one-line format (Polish labels)";    Template = "https://wttr.in/{CITY}.png?lang=pl&format=%l%20|%20%T%20|%20%C%20|%20%t%20(%f)%20|%20%w%20|%20%p%20|%20%h%20|%20%S%20-%20%s" }
)

$CityEncoded = [System.Uri]::EscapeDataString($City)
$SelectedTemplate = $null

while (-not $SelectedTemplate) {
    Write-Host ""
    Write-Host "Choose a wttr.in display format:"
    for ($i = 0; $i -lt $UrlOptions.Count; $i++) {
        Write-Host ("  {0}. {1}" -f ($i + 1), $UrlOptions[$i].Label)
    }
    Write-Host ""
    $choice = Read-Host ("Enter a number to preview it in your browser (1-{0})" -f $UrlOptions.Count)

    $index = 0
    if ([int]::TryParse($choice, [ref]$index) -and $index -ge 1 -and $index -le $UrlOptions.Count) {
        $template = $UrlOptions[$index - 1].Template
        $previewUrl = $template.Replace("{CITY}", $CityEncoded)

        Write-Host ""
        Write-Host "Opening preview in your browser:"
        Write-Host $previewUrl
        Start-Process $previewUrl

        $confirm = Read-Host "Use this format? (Y/N)"
        if ($confirm -match '^[Yy]') {
            $SelectedTemplate = $template
        }
    } else {
        Write-Host "Invalid choice." -ForegroundColor Yellow
    }
}

# --- Step 3: base wallpaper image ---
$SupportedImageExtensions = @("jpg", "jpeg", "png", "bmp")
$ExistingWallpaper = $null
foreach ($e in $SupportedImageExtensions) {
    $candidate = Join-Path $RootDir "wallpaper.$e"
    if (Test-Path $candidate) {
        $ExistingWallpaper = $candidate
        break
    }
}

$ImageDone = $false
while (-not $ImageDone) {
    Write-Host ""
    Write-Host "Base wallpaper image:"
    $optionNum = 1
    if ($ExistingWallpaper) {
        Write-Host ("  {0}. Keep existing image ({1})" -f $optionNum, (Split-Path $ExistingWallpaper -Leaf))
        $keepOption = $optionNum
        $optionNum++
    }
    Write-Host ("  {0}. Use my current desktop wallpaper (auto-detect)" -f $optionNum)
    $currentOption = $optionNum
    $optionNum++
    Write-Host ("  {0}. Provide a path to an image file" -f $optionNum)
    $pathOption = $optionNum

    Write-Host ""
    $imgChoice = Read-Host ("Choose an option (1-{0})" -f $optionNum)

    if ($ExistingWallpaper -and $imgChoice -eq "$keepOption") {
        Write-Host ""
        Write-Host "Keeping existing image: $ExistingWallpaper"
        $ImageDone = $true
    }
    elseif ($imgChoice -eq "$currentOption") {
        Write-Host ""
        Write-Host "Fetching current desktop wallpaper..."
        & (Join-Path $ScriptsDir "fetch_current_wallpaper.ps1")
        $ImageDone = $true
    }
    elseif ($imgChoice -eq "$pathOption") {
        $imgPath = Read-Host "Enter full path to the image file"
        $imgPath = $imgPath.Trim('"', ' ')
        if (-not (Test-Path -LiteralPath $imgPath -PathType Leaf)) {
            Write-Host "File not found: $imgPath" -ForegroundColor Yellow
            continue
        }

        $ext = [System.IO.Path]::GetExtension($imgPath).TrimStart('.').ToLower()
        if ($SupportedImageExtensions -notcontains $ext) {
            Write-Host "Unsupported file extension: .$ext (expected: $($SupportedImageExtensions -join ', '))" -ForegroundColor Yellow
            continue
        }

        $dest = Join-Path $RootDir "wallpaper.$ext"

        # Copy to a temp file FIRST: the chosen file may be the existing
        # wallpaper.<ext> itself, which the cleanup below would delete.
        $tmp = Join-Path $RootDir "wallpaper.tmp"
        Copy-Item -LiteralPath $imgPath -Destination $tmp -Force

        foreach ($e in $SupportedImageExtensions) {
            $old = Join-Path $RootDir "wallpaper.$e"
            if (Test-Path $old) { Remove-Item $old -Force }
        }

        Move-Item -LiteralPath $tmp -Destination $dest -Force
        Write-Host "Copied to: $dest"
        $ImageDone = $true
    }
    else {
        Write-Host "Invalid choice." -ForegroundColor Yellow
    }
}

# --- Step 4: write config.txt ---
$configContent = @"
# Dynamic Weather Wallpaper configuration
# Generated by start.bat / setup_config.ps1 - you can also edit this file by hand.
# {CITY} in WttrUrlTemplate is replaced with the URL-encoded city name at runtime.

City=$City
WttrUrlTemplate=$SelectedTemplate
MarginRightPercent=0.0
MarginBottomPercent=0.0
MarginRightPx=5
MarginBottomPx=55
Opacity=0.85
"@

Set-Content -Path $ConfigPath -Value $configContent -Encoding UTF8
Write-Host ""
Write-Host "Configuration saved to: $ConfigPath"

# --- Step 5: optional test run + scheduled task registration ---
Write-Host ""
$testNow = Read-Host "Run wallpaper.ps1 now to test it? (Y/N)"
if ($testNow -match '^[Yy]') {
    & (Join-Path $ScriptsDir "wallpaper.ps1")
    Write-Host "Done - check your desktop, and wallpaper.log in the scripts folder if something looks off."
}

Write-Host ""
$registerNow = Read-Host "Register the scheduled task now (auto-refresh on startup/logon/unlock/every 30 min)? (Y/N)"
if ($registerNow -match '^[Yy]') {
    & (Join-Path $ScriptsDir "create_scheduled_task_wallpaper.ps1")
}

Write-Host ""
Write-Host "Setup complete."
