@echo off
setlocal DisableDelayedExpansion
chcp 65001 >nul
set "LG_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "LG_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%LG_PS%" goto missinghost
if not exist "%~dp0Bootstrap.ps1" goto missingfiles
"%LG_PS%" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Bootstrap.ps1"
set "LG_RESULT=%errorlevel%"
if "%LG_RESULT%"=="0" exit /b 0
echo 启动未完成。请查看上述提示；不会自动重试。
pause
exit /b 1
:missinghost
echo 未找到系统自带 Windows PowerShell。请检查 Windows 系统组件。
pause
exit /b 1
:missingfiles
echo 启动文件不完整。请完整解压 ACE LowGear 源码包后再运行，勿只复制启动入口。
pause
exit /b 1
