# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Windows-only PowerShell tool that overlays a live [wttr.in](https://wttr.in) weather PNG onto a base image and sets the result as the desktop wallpaper, refreshed by a scheduled task. No build system, tests, or linter; there is no git repo. See `README.md` for user-facing docs.

## Running / testing

- Setup wizard: `start.bat` (runs `scripts\setup_config.ps1`; writes `config.txt` and `wallpaper.<ext>`).
- Manual refresh (the thing the scheduled task runs): `powershell -ExecutionPolicy Bypass -NoProfile -File scripts\wallpaper.ps1`
- Undo everything: `restore.bat` (runs `scripts\restore.ps1`, self-elevates via UAC).
- Register the task: `scripts\create_scheduled_task_wallpaper.ps1` (self-elevates; task name `DynamicWeatherWallpaper`).
- Debug via `scripts\wallpaper.log` (appended by `wallpaper.ps1`; `current_wallpaper.png`/`applied_wallpaper.png` are runtime outputs in `scripts\`).

## Architecture

- Root folder is the data/config dir; `scripts\` holds logic. Every script computes `$RootDir = Split-Path $PSScriptRoot -Parent`, so the folder must stay relocatable. Never hardcode absolute paths. Moving the folder requires re-registering the scheduled task (it points at the `.vbs` under the old path).
- Flow: scheduled task -> `wallpaper_launcher.vbs` (hidden window) -> `wallpaper.ps1`. It reads `config.txt` (`key=value`, `#` comments; missing keys fall back to defaults hardcoded in `wallpaper.ps1`), finds the base image `wallpaper.{jpg,jpeg,png,bmp}` in the root (first match in that order; logs ERROR and exits 1 if none), scales it to the **primary monitor** resolution, downloads the wttr.in PNG (`{CITY}` in `WttrUrlTemplate` is replaced by the URL-encoded city), draws it bottom-right with opacity via a ColorMatrix, saves `scripts\current_wallpaper.png`, and applies it with `SystemParametersInfo` P/Invoke.
- Margins = percent of screen size + fixed px (`MarginRight/BottomPercent` + `MarginRight/BottomPx`).
- The wallpaper applied is the composed PNG, not the base image. `restore.ps1` re-applies the plain `wallpaper.<ext>` and deletes the task.
- The scheduled task is created through `schtasks /Create /XML` because the on-unlock trigger isn't available in the ScheduledTasks module. Triggers: startup, logon, unlock, 30-minute repeat. It needs a one-time UAC elevation but runs unprivileged afterwards.
- `fetch_current_wallpaper.ps1` copies the current desktop wallpaper (registry path or `TranscodedWallpaper`) into the root as `wallpaper.<ext>`, detecting format from content rather than extension.

## Conventions

- Scripts carry a `# Version:` header comment, and the README states the overall version. Update both when changing behavior.
- Default config values are duplicated in `wallpaper.ps1`, `config.txt`, the README, and `setup_config.ps1` (which writes them into `config.txt`). Keep them in sync.
