@echo off
REM restore.bat
REM Version: 1.0.0
REM Double-click entry point for restoring the original wallpaper.<ext>
REM (without the weather overlay) and removing the scheduled task.

chcp 65001 >nul
title Dynamic Weather Wallpaper - Restore

powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0scripts\restore.ps1"

echo.
pause
