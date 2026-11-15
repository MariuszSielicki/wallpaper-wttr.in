@echo off
REM start.bat
REM Version: 1.0.0
REM Double-click entry point for configuring Dynamic Weather Wallpaper.
REM Runs the interactive setup wizard (scripts\setup_config.ps1) in PowerShell.

chcp 65001 >nul
title Dynamic Weather Wallpaper - Setup

powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0scripts\setup_config.ps1"

echo.
pause
