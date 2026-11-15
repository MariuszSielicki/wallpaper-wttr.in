# Dynamic Weather Wallpaper (wttr.in)

Version: 1.4.0

Overlays live weather from [wttr.in](https://wttr.in) onto a base image of your
choice, sets the result as your Windows desktop wallpaper, and keeps it fresh
with a scheduled task. Windows + PowerShell only, no dependencies.

## Quick start

1. Copy the whole folder anywhere on disk. All scripts resolve paths relative
   to their own location, so nothing needs editing.
2. Double-click **`start.bat`**. The wizard asks for:
   - your city,
   - a wttr.in display format (each option opens in your browser as a preview),
   - a base image: keep the existing `wallpaper.<ext>`, use your current
     desktop wallpaper, or give a path to any image.

   It then offers a test refresh and registration of the scheduled task
   (answer `Y` to both to finish in one go).
3. To undo everything (plain wallpaper restored, task removed), double-click
   **`restore.bat`**.

Re-run `start.bat` whenever you want to change the city, format or base image.

## Folder layout

```
wallpaper+wttr.in/
├── start.bat        setup wizard entry point
├── restore.bat      restore plain wallpaper + remove scheduled task
├── config.txt       settings (written by the wizard, safe to edit by hand)
├── wallpaper.<ext>  base image (jpg / jpeg / png / bmp)
└── scripts/
    ├── setup_config.ps1                    wizard logic
    ├── wallpaper.ps1                       main refresh script
    ├── wallpaper_launcher.vbs              starts wallpaper.ps1 with a hidden window
    ├── create_scheduled_task_wallpaper.ps1 registers the scheduled task
    ├── fetch_current_wallpaper.ps1         saves the current desktop wallpaper as the base image
    ├── restore.ps1                         restore logic
    └── wallpaper.log, current_wallpaper.png, applied_wallpaper.png   (generated at runtime)
```

## How it works

Each refresh (`scripts\wallpaper.ps1`):

1. Reads `config.txt` (missing keys fall back to built-in defaults).
2. Finds the base image in the root folder: `wallpaper.jpg`, `.jpeg`, `.png`,
   `.bmp`, first match wins. If none exists it logs an `ERROR` and exits.
3. Detects the **primary monitor's** real resolution (the process is made
   DPI-aware, so 125% / 150% display scaling does not distort it) and builds a
   canvas of exactly that size.
4. Scales the base image into the canvas in **fill** mode: aspect ratio is
   preserved, the image is centered, and any overflow is cropped.
5. Downloads the weather PNG (30 s timeout, up to 3 attempts 10 s apart — the
   network is often not ready right after boot, logon or unlock) and draws it
   in the bottom-right corner with the configured opacity.
6. Saves `scripts\current_wallpaper.png` and applies it through
   `SystemParametersInfo`.

Everything is logged to `scripts\wallpaper.log`.

## config.txt

Plain `key=value` lines; lines starting with `#` are comments. Default:

```ini
City=Wroclaw
WttrUrlTemplate=https://v2.wttr.in/{CITY}.png
MarginRightPercent=0.0
MarginBottomPercent=0.0
MarginRightPx=5
MarginBottomPx=55
Opacity=0.85
```

| Key | Meaning |
|---|---|
| `City` | City name. Diacritics and spaces are fine; it is URL-encoded at runtime. |
| `WttrUrlTemplate` | Any wttr.in image URL, with `{CITY}` as the placeholder. |
| `MarginRightPercent`, `MarginBottomPercent` | Offset from the right / bottom edge as a % of screen width / height. |
| `MarginRightPx`, `MarginBottomPx` | Additional fixed offset in pixels. Total margin = percent part + pixel part. |
| `Opacity` | Weather overlay opacity, `0.0`–`1.0`. |

### Format presets (offered with live preview by `start.bat`)

```
v2.wttr.in/{CITY}.png        richer view (default)
wttr.in/{CITY}.png?0         single line, compact
wttr.in/{CITY}.png?1         one-day forecast
wttr.in/{CITY}.png?2         two-day forecast
wttr.in/{CITY}.png?F         no "Follow @igor_chubin" footer
wttr.in/{CITY}.png?Fn        no footer, no location name
wttr.in/{CITY}.png?lang=pl&format=...   custom one-line format in Polish
```

All wttr.in options: https://wttr.in/:help

## Scheduled task

`create_scheduled_task_wallpaper.ps1` registers a task named
`DynamicWeatherWallpaper` that runs `wallpaper_launcher.vbs` on:

- system startup,
- logon,
- workstation unlock,
- every 30 minutes (first run snapped to the next :00 or :30).

Notes:

- Registration needs **one UAC prompt** (Windows requires admin rights for any
  task with a startup trigger). The script elevates itself; afterwards the task
  runs unprivileged as the current user, only while that user is logged on.
- Because the task runs as the interactive user, the logon and unlock triggers
  are what actually refresh the wallpaper in practice.
- The XML trigger for "on unlock" is not available in the PowerShell
  `ScheduledTasks` module, so the task is created via `schtasks /Create /XML`.
- **If you move the folder**, register the task again (re-run `start.bat` and
  answer `Y`): the existing task points at the launcher under the old path.

## Base image notes

- Once the task has run, your *current* desktop wallpaper is already the
  weather-overlaid image. Choosing "use my current desktop wallpaper" in the
  wizard at that point would bake the old weather into the base image. Run
  `restore.bat` first, or supply the original image by path.
- Manually finding your wallpaper path:

  ```powershell
  (Get-ItemProperty "HKCU:\Control Panel\Desktop").WallPaper
  "$env:APPDATA\Microsoft\Windows\Themes\TranscodedWallpaper"   # processed copy, usually JPEG
  ```

  `fetch_current_wallpaper.ps1` tries the registry value first, then
  `TranscodedWallpaper`, detects the real format from the content, and saves
  it as `wallpaper.<ext>` (GIF is converted to PNG).

## Limitations

- Only the **primary monitor** is used.
- The wallpaper is regenerated at screen resolution; changing resolution takes
  effect on the next refresh.
- If the weather cannot be downloaded after 3 attempts, the previous wallpaper
  stays in place and the error is written to `wallpaper.log`.

## Troubleshooting

Check `scripts\wallpaper.log` first. To run a refresh by hand:

```
powershell -ExecutionPolicy Bypass -NoProfile -File scripts\wallpaper.ps1
```
