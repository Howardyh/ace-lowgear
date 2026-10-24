[CmdletBinding()]
param(
    [ValidateSet('Apply', 'Check', 'Restore', 'Affinity', 'SelfTest')]
    [string]$Mode = 'Check',
    [switch]$Pause,
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$exitCode = 1
$operationLock = $null

try {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or -not [Environment]::Is64BitOperatingSystem -or [Environment]::OSVersion.Version.Major -lt 10) {
        throw 'ACE LowGear requires 64-bit Windows 10 or Windows 11.'
    }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    try {
        $isAdmin = [Security.Principal.WindowsPrincipal]::new($identity).IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    finally { $identity.Dispose() }

    $needsElevation = $Mode -ne 'Check' -and -not $isAdmin
    # Use the built-in compiler/runtime for the temporary startup probe.
    if ($needsElevation -or -not [Environment]::Is64BitProcess -or $PSVersionTable.PSEdition -ne 'Desktop') {
        $hostPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        if (-not [Environment]::Is64BitProcess) {
            $hostPath = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
        }
        $arguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -Mode {1}' -f $PSCommandPath, $Mode
        if ($Pause) { $arguments += ' -Pause' }
        if ($Json) { $arguments += ' -Json' }
        if ($needsElevation) {
            Write-Host 'Administrator permission is required for this operation.'
            $child = Start-Process -FilePath $hostPath -Verb RunAs -ArgumentList $arguments -Wait -PassThru
            exit $child.ExitCode
        }
        $forward = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-Mode', $Mode)
        if ($Pause) { $forward += '-Pause' }
        if ($Json) { $forward += '-Json' }
        & $hostPath @forward
        exit $LASTEXITCODE
    }

    Import-Module (Join-Path $PSScriptRoot 'src\LowGear.Core.psm1') -Force -DisableNameChecking
    $directory = Get-LowGearDataDirectory
    $operation = $null

    if ($Mode -ne 'Check') {
        Initialize-LowGearDataDirectory $directory
        # All copies of the project use one local lock and one recovery record.
        $operationLock = [IO.File]::Open((Join-Path $directory 'operation.lock'),
            [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        $machineToken = Get-LowGearMachineToken
        switch ($Mode) {
            'Apply' { $operation = Invoke-LowGearApply $directory $machineToken }
            'Restore' { $operation = Invoke-LowGearRestore $directory $machineToken }
            'Affinity' {
                $results = @(Set-LowGearLastCpu)
                $operation = [pscustomobject]@{ Status = 'AffinityAttempted'; Results = $results }
            }
            'SelfTest' {
                $probeDirectory = Join-Path $directory ('probe-' + [Guid]::NewGuid().ToString('N'))
                try { $validation = Test-StartupPriorities $probeDirectory }
                finally { if ([IO.Directory]::Exists($probeDirectory)) { [IO.Directory]::Delete($probeDirectory, $false) } }
                $operation = [pscustomobject]@{ Status = 'SelfTestPassed'; Validation = $validation }
            }
        }
    }

    $status = if ($null -eq $operation) { 'Checked' } else { $operation.Status }
    $report = Get-LowGearReport -Status $status
    if ($null -ne $operation) {
        $report | Add-Member -NotePropertyName Operation -NotePropertyValue $operation
        Save-JsonFile (Join-Path (Join-Path $directory 'reports') ('last-' + $Mode.ToLowerInvariant() + '.json')) $report
    }
    if ($Json) { $report | ConvertTo-Json -Depth 20 | Write-Output }
    else {
        Write-Host ('ACE LowGear 0.1.0 - ' + $report.Status)
        Write-Host ('Logical processors: {0}; processor groups: {1}' -f $report.Topology.LogicalProcessors, $report.Topology.ProcessorGroups)
        $report.Configuration | Format-Table Image, CpuPriorityClass, IoPriority, Configured, HasFilters -AutoSize | Out-Host
        $report.Processes | Format-Table Image, Running, ProcessId, CpuClass, IoPriority, EffectiveIoPriority, Verified, Error -Wrap | Out-Host
        if ($Mode -eq 'Affinity') { $operation.Results | Format-Table -AutoSize | Out-Host }
        if ($Mode -eq 'Apply' -or $Mode -eq 'Restore') {
            Write-Host 'Startup rules take effect on the next normal process start. Running processes are not restarted by this tool.'
        }
        Write-Host 'NotRunning/Running=False means actual ACE behavior has not been verified.'
    }

    $exitCode = 0
    if ($Mode -eq 'Check') {
        if (@($report.Processes | Where-Object { $_.Running -and -not $_.Verified }).Count -gt 0) { $exitCode = 1 }
        elseif (@($report.Configuration | Where-Object { -not $_.Configured }).Count -gt 0 -or
            @($report.Processes | Where-Object { -not $_.Running }).Count -gt 0) { $exitCode = 2 }
    }
    elseif ($Mode -eq 'Affinity') {
        if (@($operation.Results | Where-Object { $_.Status -eq 'Failed' }).Count -gt 0) { $exitCode = 1 }
        elseif (@($operation.Results | Where-Object { $_.Status -eq 'NotRunning' }).Count -gt 0) { $exitCode = 2 }
    }
}
catch {
    Write-Host ('[Failed] ' + $_.Exception.Message) -ForegroundColor Red
    $exitCode = 1
}
finally { if ($null -ne $operationLock) { $operationLock.Dispose() } }

if ($Pause) { [void](Read-Host 'Press Enter to close') }
exit $exitCode
