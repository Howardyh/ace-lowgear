[CmdletBinding()]
param(
    [ValidateSet('Panel','Install','Status','ApplyOnce','LastCpu','Pause','Resume','Restore','SelfTest','SetAffinity','Upgrade','Repair','Diagnose')][string]$Command='Panel',
    [switch]$BindLastCpu,
    [switch]$ClearLastCpu,
    [switch]$Json,
    [switch]$Pause,
    [string]$ResultPath,
    [string]$ProgressPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$exitCode=1
function Write-LGResult {
    param($Value,[string]$Path)
    $temp=$Path+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
    try{
        [IO.File]::WriteAllText($temp,($Value|ConvertTo-Json -Depth 30),[Text.UTF8Encoding]::new($false))
        if([IO.File]::Exists($Path)){[IO.File]::Replace($temp,$Path,[Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($temp,$Path)}
    }finally{if([IO.File]::Exists($temp)){[IO.File]::Delete($temp)}}
}
try {
    if($BindLastCpu -and $ClearLastCpu){throw '不能同时启用和取消最后 CPU 绑定。'}
    if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or -not [Environment]::Is64BitOperatingSystem -or [Environment]::OSVersion.Version.Major -lt 10){throw '需要 64 位 Windows 10 或 Windows 11。'}
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    try{$admin=[Security.Principal.WindowsPrincipal]::new($identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)}finally{$identity.Dispose()}
    if(-not $admin -or -not [Environment]::Is64BitProcess -or $PSVersionTable.PSEdition -ne 'Desktop' -or [Threading.Thread]::CurrentThread.ApartmentState -ne 'STA'){
        $hostPath=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        if(-not [Environment]::Is64BitProcess){$hostPath=Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'}
        $arguments='-NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "{0}" -Command {1}' -f $PSCommandPath,$Command
        if($BindLastCpu){$arguments+=' -BindLastCpu'}elseif($ClearLastCpu -or $PSBoundParameters.ContainsKey('BindLastCpu')){$arguments+=' -ClearLastCpu'}
        if($Json){$arguments+=' -Json'}
        if($Pause){$arguments+=' -Pause'}
        if($ResultPath){$arguments+=' -ResultPath "'+$ResultPath+'"'}
        if($ProgressPath){$arguments+=' -ProgressPath "'+$ProgressPath+'"'}
        $parameters=@{FilePath=$hostPath;ArgumentList=$arguments;Wait=$true;PassThru=$true}
        if(-not $admin){$parameters.Verb='RunAs'}
        if($Command -eq 'Panel' -or -not $Pause){$parameters.WindowStyle='Hidden'}
        $child=Start-Process @parameters
        exit $child.ExitCode
    }
    Import-Module (Join-Path $PSScriptRoot 'src\LowGear.psm1') -Force -DisableNameChecking
    if($Command -eq 'Panel'){
        . (Join-Path $PSScriptRoot 'ui\Panel.ps1')
        Show-LGPanel
        exit 0
    }
    $last=if($ClearLastCpu){$false}elseif($PSBoundParameters.ContainsKey('BindLastCpu')){[bool]$BindLastCpu}else{$null}
    $result=Invoke-LGCommand -Command $Command -Last $last -ProgressPath $ProgressPath
    if($ResultPath){Write-LGResult $result $ResultPath}
    if($Command -eq 'Diagnose'){$result|ConvertTo-Json -Depth 8|Write-Output;exit 0}
    if($Json){$result | ConvertTo-Json -Depth 30 | Write-Output}
    else{
        Write-Host ('ACE LowGear '+$result.Report.Version+' · '+$result.Message)
        Write-Host (Get-LGSummary $result.Report)
        $result.Report.Processes | Select-Object Image,ProcessId,Running,CpuClass,IoPriority,Verified,@{N='Reason';E={$_.Errors -join '; '}} | Format-Table -Wrap | Out-Host
    }
    $exitCode=0
    if($Command -eq 'Status' -or $Command -eq 'ApplyOnce' -or $Command -eq 'LastCpu'){
        $samples=if($Command -eq 'Status'){$result.Report.Processes}else{$result.Detail}
        if(@($samples | Where-Object {$_.Running -and -not $_.Verified}).Count -gt 0){$exitCode=1}
        elseif(@($samples | Where-Object {-not $_.Running}).Count -gt 0){$exitCode=2}
        if($result.Report.Mode -in @('RecoveryRequired','WorkerUnavailable') -or $result.Report.Health.Processes.State -eq 'Error'){$exitCode=1}
    }
}
catch{
    $code='OPERATION_FAILED';$cause=$_.Exception
    while($null -ne $cause){if($cause.Data.Contains('LowGearCode')){$code=[string]$cause.Data['LowGearCode'];break};$cause=$cause.InnerException}
    $message=if($Command -eq 'Diagnose'){'诊断未完成。'}else{$_.Exception.Message}
    $result=[pscustomobject]@{Success=$false;Code=$code;Message=$message}
    if($ResultPath){Write-LGResult $result $ResultPath}
    Write-Host ('操作未完成：'+$_.Exception.Message) -ForegroundColor Red
    if($Command -eq 'Panel'){
        Add-Type -AssemblyName PresentationFramework
        [void][Windows.MessageBox]::Show($_.Exception.Message,'ACE LowGear')
    }
}
if($Pause){[void](Read-Host '按回车关闭')}
exit $exitCode
