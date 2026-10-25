@echo off
setlocal
set "LowGearHost=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if defined PROCESSOR_ARCHITEW6432 set "LowGearHost=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%LowGearHost%" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0LowGear.ps1" -Command Status -Pause
exit /b %errorlevel%
