@echo off
setlocal
set "LowGearPowerShell=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if defined PROCESSOR_ARCHITEW6432 set "LowGearPowerShell=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%~dp0ACE-LowGear.ps1" (
    echo Missing ACE-LowGear.ps1. Extract the complete project first.
    pause
    exit /b 1
)
"%LowGearPowerShell%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0ACE-LowGear.ps1" -Mode Affinity -Pause
exit /b %errorlevel%
