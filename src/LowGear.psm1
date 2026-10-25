Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Version = '1.0.0'
$script:Project = Split-Path $PSScriptRoot -Parent
$script:Common = Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'ACE-LowGear'
$script:Data = Join-Path $script:Common 'v1'
$script:Hive = [Microsoft.Win32.RegistryHive]::LocalMachine
$script:RegistryPath = 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options'
$script:Images = @('SGuard64.exe','SGuardSvc64.exe','ACE-Service64.exe')
$script:TaskName = 'ACE-LowGear'
$script:TaskSource = 'ACE LowGear 1'
$script:EventName = 'ACE-LowGear-ProcessStart'
$script:EventQuery = "SELECT * FROM Win32_ProcessStartTrace WHERE ProcessName='SGuard64.exe' OR ProcessName='SGuardSvc64.exe' OR ProcessName='ACE-Service64.exe'"
. (Join-Path $PSScriptRoot 'State.ps1')
. (Join-Path $PSScriptRoot 'Platform.ps1')
. (Join-Path $PSScriptRoot 'Controller.ps1')
Export-ModuleMember -Function Invoke-LGCommand, Get-LGStatus, Get-LGSummary, Initialize-LGNative, Build-LGRuntime
