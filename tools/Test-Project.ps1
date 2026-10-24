[CmdletBinding()]
param([switch]$StartupProbe)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$passed = [Collections.Generic.List[string]]::new()
function Assert-Test { param([bool]$Condition, [string]$Name) if (-not $Condition) { throw ('FAIL: ' + $Name) }; $passed.Add($Name) }
function Assert-Throws { param([scriptblock]$Action, [string]$Name) $threw = $false; try { & $Action | Out-Null } catch { $threw = $true }; Assert-Test $threw $Name }

Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object { $_.Extension -in @('.ps1', '.psm1') -and $_.FullName -notmatch '[\\/]artifacts[\\/]' } | ForEach-Object {
    $tokens = $null; $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors)
    Assert-Test ($errors.Count -eq 0) ('Syntax: ' + $_.Name)
}

$module = Import-Module (Join-Path $root 'src\LowGear.Core.psm1') -PassThru -Force -DisableNameChecking
$testId = [Guid]::NewGuid().ToString('N')
$testRegistry = 'SOFTWARE\ACE-LowGear\Tests\' + $testId
$testDirectory = Join-Path ([IO.Path]::GetTempPath()) ('ACE-LowGear-tests-' + $testId)
[void][IO.Directory]::CreateDirectory((Join-Path $testDirectory 'backups'))
$tokenA = 'A' * 64
$tokenB = 'B' * 64

try {
    # All registry transaction tests use a fresh HKCU sandbox, never ACE's HKLM keys.
    & $module { param($path)
        $script:RegistryHive = [Microsoft.Win32.RegistryHive]::CurrentUser
        $script:IfeoPath = $path
        $script:RealProbe = (Get-Command Test-StartupPriorities).ScriptBlock
        $script:RealSetter = (Get-Command Set-ImagePriorities).ScriptBlock
        function script:Test-StartupPriorities { param([string]$Directory) [pscustomobject]@{ Passed = $true; Kind = 'RegistryTransactionTestDouble' } }
    } $testRegistry

    $absent = & $module { Get-ImageState 'SGuard64.exe' }
    & $module { Set-ImagePriorities 'SGuard64.exe' 1 0 }
    $written = & $module { Get-ImageState 'SGuard64.exe' }
    Assert-Test ($written.CpuPriorityClass.Data -eq '1' -and $written.IoPriority.Data -eq '0') 'Registry writes are read back'
    & $module { param($original) Restore-ImageState $original } $absent
    $restored = & $module { Get-ImageState 'SGuard64.exe' }
    Assert-Test (-not $restored.ImageKeyExists) 'Restore removes only newly created empty keys'
    Assert-Throws { & $module { Set-ImagePriorities 'Unrelated.exe' 1 0 } } 'Unrelated executable is rejected'

    $fixtures = @(
        @{ Kind = 'DWord'; Data = [int]-1 },
        @{ Kind = 'QWord'; Data = [Int64]::MaxValue },
        @{ Kind = 'String'; Data = 'original value' },
        @{ Kind = 'ExpandString'; Data = '%UNEXPANDED_EXAMPLE%\original' },
        @{ Kind = 'Binary'; Data = [byte[]]@(0, 127, 255) },
        @{ Kind = 'Binary'; Data = [byte[]]@() },
        @{ Kind = 'None'; Data = [byte[]]@(1, 128, 255) },
        @{ Kind = 'MultiString'; Data = [string[]]@('first', '', 'third') },
        @{ Kind = 'MultiString'; Data = [string[]]@() }
    )
    foreach ($fixture in $fixtures) {
        $before = & $module { param($fixture)
            $base = Open-MachineRegistry
            $key = $base.CreateSubKey($script:IfeoPath + '\SGuard64.exe\PerfOptions')
            try {
                $kind = [Microsoft.Win32.RegistryValueKind][Enum]::Parse([Microsoft.Win32.RegistryValueKind], $fixture.Kind)
                $key.SetValue('CpuPriorityClass', $fixture.Data, $kind)
                $key.SetValue('IoPriority', $fixture.Data, $kind)
                $key.SetValue('UnrelatedSentinel', 'preserve', [Microsoft.Win32.RegistryValueKind]::String)
            }
            finally { $key.Dispose(); $base.Dispose() }
            Get-ImageState 'SGuard64.exe'
        } $fixture
        # Round-trip through JSON to exercise the actual backup format.
        $fromJson = $before | ConvertTo-Json -Depth 12 | ConvertFrom-Json
        & $module { Set-ImagePriorities 'SGuard64.exe' 1 0 }
        & $module { param($original) Restore-ImageState $original } $fromJson
        $after = & $module { Get-ImageState 'SGuard64.exe' }
        Assert-Test (($before | ConvertTo-Json -Depth 12 -Compress) -ceq ($after | ConvertTo-Json -Depth 12 -Compress)) ('Exact restore: ' + $fixture.Kind)
        $sentinel = & $module {
            $base = Open-MachineRegistry; $key = $base.OpenSubKey($script:IfeoPath + '\SGuard64.exe\PerfOptions')
            try { $key.GetValue('UnrelatedSentinel') } finally { $key.Dispose(); $base.Dispose() }
        }
        Assert-Test ($sentinel -ceq 'preserve') ('Unrelated value preserved: ' + $fixture.Kind)
    }

    & $module {
        $base = Open-MachineRegistry; $key = $base.CreateSubKey($script:IfeoPath + '\SGuardSvc64.exe')
        try { $key.SetValue('UseFilter', 1, [Microsoft.Win32.RegistryValueKind]::DWord) }
        finally { $key.Dispose(); $base.Dispose() }
    }
    Assert-Throws { Invoke-LowGearApply $testDirectory $tokenA } 'Existing IFEO path filters block automatic configuration'
    & $module {
        $base = Open-MachineRegistry; $key = $base.OpenSubKey($script:IfeoPath + '\SGuardSvc64.exe', $true)
        try { $key.DeleteValue('UseFilter', $false) }
        finally { $key.Dispose(); $base.Dispose() }
    }

    $applied = Invoke-LowGearApply $testDirectory $tokenA
    Assert-Test ($applied.Status -ceq 'ConfiguredForNextStart') 'Apply transaction completes in HKCU sandbox'
    $activePath = Join-Path $testDirectory 'active.json'
    $originalManifest = Get-Content -LiteralPath $activePath -Raw
    $again = Invoke-LowGearApply $testDirectory $tokenA
    Assert-Test ($again.Status -ceq 'AlreadyConfigured' -and (Get-Content -LiteralPath $activePath -Raw) -ceq $originalManifest) 'Repeated Apply preserves the first backup'
    Assert-Throws { & $module { param($dir, $token) Read-LowGearInstallation $dir $token } $testDirectory $tokenB } 'Cross-computer recovery state is rejected'

    $pending = $originalManifest | ConvertFrom-Json
    $pending.Phase = 'PendingApply'
    Save-JsonFile $activePath $pending
    Assert-Throws { Invoke-LowGearApply $testDirectory $tokenA } 'Interrupted journal blocks a new Apply'
    [IO.File]::WriteAllText($activePath, $originalManifest, [Text.UTF8Encoding]::new($true))

    & $module { Set-ImagePriorities 'SGuardSvc64.exe' 3 2 }
    Assert-Throws { Invoke-LowGearRestore $testDirectory $tokenA } 'Later priority changes block automatic restore'
    Assert-Test (Test-Path -LiteralPath $activePath) 'Blocked restore retains its recovery record'
    & $module { Set-ImagePriorities 'SGuardSvc64.exe' 1 0 }

    $manifest = $originalManifest | ConvertFrom-Json
    $backupPath = Join-Path (Join-Path $testDirectory 'backups') $manifest.BackupFile
    $backupBytes = [IO.File]::ReadAllBytes($backupPath)
    [IO.File]::AppendAllText($backupPath, ' ')
    Assert-Throws { Invoke-LowGearRestore $testDirectory $tokenA } 'Tampered backup is rejected before restore'
    [IO.File]::WriteAllBytes($backupPath, $backupBytes)
    $undo = Invoke-LowGearRestore $testDirectory $tokenA
    Assert-Test ($undo.Status -ceq 'RestoredForNextStart' -and -not (Test-Path -LiteralPath $activePath)) 'Restore transaction completes and archives its manifest'
    Assert-Test ((Invoke-LowGearRestore $testDirectory $tokenA).Status -ceq 'NoActiveInstallation') 'Repeated Restore is harmless'

    # Fail after one target write and confirm the transaction rolls back all targets.
    $beforeFailure = & $module { @($script:Images | ForEach-Object { Get-ImageState $_ }) }
    & $module {
        function script:Set-ImagePriorities {
            param([string]$Image, [int]$CpuValue, [int]$IoValue)
            if ($Image -eq 'SGuardSvc64.exe') { throw 'Intentional transaction-test failure' }
            & $script:RealSetter $Image $CpuValue $IoValue
        }
    }
    Assert-Throws { Invoke-LowGearApply $testDirectory $tokenA } 'Injected partial failure is reported'
    $afterFailure = & $module { @($script:Images | ForEach-Object { Get-ImageState $_ }) }
    Assert-Test (($beforeFailure | ConvertTo-Json -Depth 12 -Compress) -ceq ($afterFailure | ConvertTo-Json -Depth 12 -Compress)) 'Partial failure restores all original registry values'
    Assert-Test (-not (Test-Path -LiteralPath $activePath)) 'Completed rollback archives the pending journal'
    & $module { Set-Item Function:script:Set-ImagePriorities $script:RealSetter }

    # Test actual native readback and affinity on an owned temporary process only.
    & $module { Initialize-PriorityReader }
    $child = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -WindowStyle Hidden -ArgumentList '-NoLogo -NoProfile -NonInteractive -Command "Start-Sleep -Seconds 60"' -PassThru
    try {
        $child.PriorityClass = [Diagnostics.ProcessPriorityClass]::Idle
        $sample = [AceLowGear.Native]::Read([uint32]$child.Id)
        Assert-Test ($sample.CpuClass -eq 64) 'Native CPU readback matches owned process'
        Assert-Test ($sample.IoPriority -ge 0 -and -not $sample.Error) 'Native I/O priority is readable'
        if ((Get-LowGearTopology).ProcessorGroups -eq 1) {
            $last = Get-LowGearLastCpu
            $child.ProcessorAffinity = $last.Mask; $child.Refresh()
            Assert-Test ($child.ProcessorAffinity.ToInt64() -eq $last.Mask.ToInt64()) 'Last available logical CPU works on this machine'
        }
    }
    finally { if (-not $child.HasExited) { $child.Kill(); [void]$child.WaitForExit(5000) }; $child.Dispose() }
    Assert-Test ([IntPtr]::new([Int64]1 -shl 63).ToInt64() -eq [Int64]::MinValue) '64th logical CPU mask preserves the sign bit'

    & $module {
        $script:RegistryHive = [Microsoft.Win32.RegistryHive]::LocalMachine
        $script:IfeoPath = 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options'
        Set-Item Function:script:Test-StartupPriorities $script:RealProbe
    }
    if ($StartupProbe) {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        try { $isAdmin = [Security.Principal.WindowsPrincipal]::new($identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) }
        finally { $identity.Dispose() }
        if (-not $isAdmin) { throw '-StartupProbe requires an administrator Windows PowerShell 5.1 session.' }
        $probe = Test-StartupPriorities (Join-Path $testDirectory 'startup-probe')
        Assert-Test ($probe.Passed -and $probe.ProbeRegistryCleanupPassed) 'HKLM startup priorities pass baseline and two launches, with cleanup'
    }

    [pscustomobject]@{ Status = 'Passed'; CheckCount = $passed.Count; StartupProbeRun = [bool]$StartupProbe; Checks = $passed.ToArray() } | ConvertTo-Json -Depth 6
}
finally {
    # Verify exact, freshly generated cleanup targets before recursive removal.
    if ($testRegistry -cne ('SOFTWARE\ACE-LowGear\Tests\' + $testId) -or $testId -cnotmatch '^[a-f0-9]{32}$') { throw 'Unsafe test registry cleanup target.' }
    $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser, [Microsoft.Win32.RegistryView]::Registry64)
    try { $base.DeleteSubKeyTree($testRegistry, $false) } finally { $base.Dispose() }
    $resolvedDirectory = [IO.Path]::GetFullPath($testDirectory)
    $expectedDirectory = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('ACE-LowGear-tests-' + $testId)))
    if ($resolvedDirectory -cne $expectedDirectory) { throw 'Unsafe test file cleanup target.' }
    if ([IO.Directory]::Exists($resolvedDirectory)) { [IO.Directory]::Delete($resolvedDirectory, $true) }
    Remove-Module $module -Force
}
