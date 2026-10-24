Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Images = @('SGuard64.exe', 'SGuardSvc64.exe', 'ACE-Service64.exe')
$script:RegistryHive = [Microsoft.Win32.RegistryHive]::LocalMachine
$script:IfeoPath = 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options'
function Save-JsonFile {
    param([string]$Path, $Value)
    $temporary = $Path + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($true))
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temporary, $Path, [System.Management.Automation.Language.NullString]::Value) }
        else { [IO.File]::Move($temporary, $Path) }
    }
    finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
}

function Open-MachineRegistry {
    [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        $script:RegistryHive, [Microsoft.Win32.RegistryView]::Registry64)
}

function Get-RegistryValueState {
    param($Key, [string]$Name)
    if ($null -ne $Key -and $Key.GetValueNames() -contains $Name) {
        $kind = $Key.GetValueKind($Name).ToString()
        $data = $Key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        # String encoding keeps 64-bit integers and binary data lossless in JSON.
        if ($kind -in @('DWord', 'QWord')) { $data = ([Int64]$data).ToString([Globalization.CultureInfo]::InvariantCulture) }
        elseif ($kind -in @('Binary', 'None')) { $data = [Convert]::ToBase64String([byte[]]$data) }
        return [pscustomobject]@{
            Exists = $true
            Kind = $kind
            Data = $data
        }
    }
    [pscustomobject]@{ Exists = $false; Kind = $null; Data = $null }
}

function Assert-AllowedImage {
    param([string]$Image)
    if ($script:Images -notcontains $Image -and $Image -cnotmatch '^AceLowGearProbe-[a-f0-9]{32}\.exe$') {
        throw ('Refusing unrelated image name: ' + $Image)
    }
}

function Get-ImageState {
    param([string]$Image)
    Assert-AllowedImage $Image
    $base = Open-MachineRegistry
    $imageKey = $null
    $perfKey = $null
    try {
        $imageKey = $base.OpenSubKey(($script:IfeoPath + '\' + $Image), $false)
        if ($null -ne $imageKey) { $perfKey = $imageKey.OpenSubKey('PerfOptions', $false) }
        [pscustomobject]@{
            Image = $Image
            ImageKeyExists = ($null -ne $imageKey)
            PerfKeyExists = ($null -ne $perfKey)
            HasFilters = ($null -ne $imageKey -and $imageKey.GetValue('UseFilter', 0) -ne 0)
            CpuPriorityClass = Get-RegistryValueState $perfKey 'CpuPriorityClass'
            IoPriority = Get-RegistryValueState $perfKey 'IoPriority'
        }
    }
    finally {
        if ($null -ne $perfKey) { $perfKey.Dispose() }
        if ($null -ne $imageKey) { $imageKey.Dispose() }
        $base.Dispose()
    }
}

function Set-ImagePriorities {
    param([string]$Image, [int]$CpuValue, [int]$IoValue)
    Assert-AllowedImage $Image
    $base = Open-MachineRegistry
    $key = $null
    try {
        $key = $base.CreateSubKey(($script:IfeoPath + '\' + $Image + '\PerfOptions'))
        $key.SetValue('CpuPriorityClass', $CpuValue, [Microsoft.Win32.RegistryValueKind]::DWord)
        $key.SetValue('IoPriority', $IoValue, [Microsoft.Win32.RegistryValueKind]::DWord)
        $key.Flush()
    }
    finally {
        if ($null -ne $key) { $key.Dispose() }
        $base.Dispose()
    }
}

function Restore-ImageState {
    param($Original)
    Assert-AllowedImage $Original.Image
    $base = Open-MachineRegistry
    $imageKey = $null
    $perfKey = $null
    try {
        $imagePath = $script:IfeoPath + '\' + $Original.Image
        $imageKey = $base.OpenSubKey($imagePath, $true)
        if ($null -eq $imageKey -and ($Original.CpuPriorityClass.Exists -or $Original.IoPriority.Exists)) {
            $imageKey = $base.CreateSubKey($imagePath)
        }
        if ($null -ne $imageKey) {
            $perfKey = $imageKey.OpenSubKey('PerfOptions', $true)
            if ($null -eq $perfKey -and ($Original.CpuPriorityClass.Exists -or $Original.IoPriority.Exists)) {
                $perfKey = $imageKey.CreateSubKey('PerfOptions')
            }
            if ($null -ne $perfKey) {
                foreach ($valueName in @('CpuPriorityClass', 'IoPriority')) {
                    $saved = $Original.$valueName
                    if ($saved.Exists) {
                        $kind = [Microsoft.Win32.RegistryValueKind][Enum]::Parse([Microsoft.Win32.RegistryValueKind], $saved.Kind)
                        $data = $saved.Data
                        switch ($saved.Kind) {
                            'DWord' { $data = [int]$saved.Data }
                            'QWord' { $data = [long]$saved.Data }
                            'Binary' { $data = [Convert]::FromBase64String([string]$saved.Data) }
                            'None' { $data = [Convert]::FromBase64String([string]$saved.Data) }
                            'MultiString' { $data = [string[]]$saved.Data }
                        }
                        $perfKey.SetValue($valueName, $data, $kind)
                    }
                    else { $perfKey.DeleteValue($valueName, $false) }
                }
                $emptyPerfKey = $perfKey.ValueCount -eq 0 -and $perfKey.SubKeyCount -eq 0
                $perfKey.Dispose()
                $perfKey = $null
                if (-not $Original.PerfKeyExists -and $emptyPerfKey) {
                    $imageKey.DeleteSubKey('PerfOptions', $false)
                }
            }
            $emptyImageKey = $imageKey.ValueCount -eq 0 -and $imageKey.SubKeyCount -eq 0
            $imageKey.Dispose()
            $imageKey = $null
            if (-not $Original.ImageKeyExists -and $emptyImageKey) {
                $parent = $base.OpenSubKey($script:IfeoPath, $true)
                try { $parent.DeleteSubKey($Original.Image, $false) }
                finally { $parent.Dispose() }
            }
        }
    }
    finally {
        if ($null -ne $perfKey) { $perfKey.Dispose() }
        if ($null -ne $imageKey) { $imageKey.Dispose() }
        $base.Dispose()
    }
    $actual = Get-ImageState $Original.Image
    foreach ($valueName in @('CpuPriorityClass', 'IoPriority')) {
        if (($actual.$valueName | ConvertTo-Json -Compress) -cne ($Original.$valueName | ConvertTo-Json -Compress)) {
            throw ('Restore verification failed: ' + $Original.Image + '/' + $valueName)
        }
    }
}

function Initialize-PriorityReader {
    if ('AceLowGear.Native' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace AceLowGear {
    public class Snapshot {
        public uint CpuClass;
        public int IoPriority = -1;
        public int EffectiveIoPriority = -1;
        public string Error;
        public string EffectiveIoStatus;
    }
    public static class Native {
        [DllImport("kernel32.dll")]
        public static extern ushort GetActiveProcessorGroupCount();
        [DllImport("kernel32.dll")]
        public static extern uint GetActiveProcessorCount(ushort group);
        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool GetProcessAffinityMask(IntPtr process,
            out UIntPtr processMask, out UIntPtr systemMask);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern uint GetPriorityClass(IntPtr process);
        [DllImport("kernel32.dll")]
        static extern bool CloseHandle(IntPtr handle);
        [DllImport("ntdll.dll")]
        static extern int NtQueryInformationProcess(IntPtr process, int infoClass,
            out int info, uint infoLength, out uint returnedLength);
        public static Snapshot Read(uint pid) {
            var result = new Snapshot();
            IntPtr handle = OpenProcess(0x1400, false, pid);
            if (handle == IntPtr.Zero) handle = OpenProcess(0x1000, false, pid);
            if (handle == IntPtr.Zero) {
                result.Error = "OpenProcess: Win32 " + Marshal.GetLastWin32Error();
                return result;
            }
            try {
                result.CpuClass = GetPriorityClass(handle);
                if (result.CpuClass == 0) result.Error = "GetPriorityClass: Win32 " + Marshal.GetLastWin32Error();
                int value;
                uint length;
                int status = NtQueryInformationProcess(handle, 33, out value, 4, out length);
                if (status >= 0 && length == 4) result.IoPriority = value;
                else result.Error = (result.Error == null ? "" : result.Error + "; ") + "ProcessIoPriority: NTSTATUS 0x" + status.ToString("X8");
                status = NtQueryInformationProcess(handle, 110, out value, 4, out length);
                if (status >= 0 && length == 4) result.EffectiveIoPriority = value;
                else {
                    result.EffectiveIoStatus = "NTSTATUS 0x" + status.ToString("X8");
                    // Only known unsupported-class statuses make this query optional.
                    if (status != unchecked((int)0xC0000003) &&
                        status != unchecked((int)0xC0000002) &&
                        status != unchecked((int)0xC00000BB)) {
                        result.Error = (result.Error == null ? "" : result.Error + "; ") +
                            "ProcessEffectiveIoPriority: " + result.EffectiveIoStatus;
                    }
                }
            }
            finally { CloseHandle(handle); }
            return result;
        }
    }
}
'@
}

function Get-LivePriorities {
    Initialize-PriorityReader
    foreach ($image in $script:Images) {
        $processes = @([Diagnostics.Process]::GetProcessesByName([IO.Path]::GetFileNameWithoutExtension($image)))
        if ($processes.Count -eq 0) {
            [pscustomobject]@{ Image = $image; Running = $false; ProcessId = $null; CpuClass = $null; IoPriority = $null; EffectiveIoPriority = $null; Verified = $false; Error = $null }
        }
        foreach ($targetProcess in $processes) {
            try {
                $snapshot = [AceLowGear.Native]::Read([uint32]$targetProcess.Id)
                [pscustomobject]@{
                    Image = $image
                    Running = $true
                    ProcessId = $targetProcess.Id
                    CpuClass = $snapshot.CpuClass
                    IoPriority = $snapshot.IoPriority
                    EffectiveIoPriority = $snapshot.EffectiveIoPriority
                    EffectiveIoStatus = $snapshot.EffectiveIoStatus
                    Verified = ($snapshot.CpuClass -eq 64 -and $snapshot.IoPriority -eq 0 -and ($snapshot.EffectiveIoPriority -eq 0 -or $snapshot.EffectiveIoPriority -eq -1) -and -not $snapshot.Error)
                    Error = $snapshot.Error
                }
            }
            finally { $targetProcess.Dispose() }
        }
    }
}

function Test-StartupPriorities {
    param([string]$Directory)
    Initialize-PriorityReader
    [void][IO.Directory]::CreateDirectory($Directory)
    $probeImage = 'AceLowGearProbe-' + [Guid]::NewGuid().ToString('N') + '.exe'
    $probePath = Join-Path $Directory $probeImage
    $original = Get-ImageState $probeImage
    if ($original.ImageKeyExists -or (Test-Path -LiteralPath $probePath)) { throw 'Probe identity already exists.' }
    $samples = [Collections.Generic.List[object]]::new()
    try {
        Add-Type -TypeDefinition 'public static class AcePriorityProbe { public static void Main() { System.Threading.Thread.Sleep(60000); } }' -OutputAssembly $probePath -OutputType ConsoleApplication
        foreach ($phase in @('NormalBaseline', 'MinimumFirstStart', 'MinimumSecondStart')) {
            if ($phase -eq 'NormalBaseline') { Set-ImagePriorities $probeImage 2 2; $expectedCpu = 32; $expectedIo = 2 }
            else { Set-ImagePriorities $probeImage 1 0; $expectedCpu = 64; $expectedIo = 0 }
            $child = Start-Process -FilePath $probePath -WindowStyle Hidden -PassThru
            try {
                Start-Sleep -Milliseconds 300
                $sample = [AceLowGear.Native]::Read([uint32]$child.Id)
                if ($sample.CpuClass -ne $expectedCpu -or $sample.IoPriority -ne $expectedIo -or $sample.Error -or ($sample.EffectiveIoPriority -ne -1 -and $sample.EffectiveIoPriority -ne $expectedIo)) {
                    throw ('Startup probe failed (' + $phase + '): ' + ($sample | ConvertTo-Json -Compress))
                }
                $samples.Add([pscustomobject]@{ Phase = $phase; CpuClass = $sample.CpuClass; IoPriority = $sample.IoPriority; EffectiveIoPriority = $sample.EffectiveIoPriority; Passed = $true })
            }
            finally {
                if (-not $child.HasExited) { $child.Kill(); [void]$child.WaitForExit(5000) }
                $child.Dispose()
            }
        }
    }
    finally {
        Restore-ImageState $original
        if (Test-Path -LiteralPath $probePath) { Remove-Item -LiteralPath $probePath -Force }
    }
    if ((Get-ImageState $probeImage).ImageKeyExists) { throw 'Probe registry cleanup failed.' }
    [pscustomobject]@{ Passed = $true; Samples = $samples.ToArray(); ProbeRegistryCleanupPassed = $true }
}

function Get-ConfigurationReport {
    foreach ($image in $script:Images) {
        $state = Get-ImageState $image
        [pscustomobject]@{
            Image = $image
            CpuPriorityClass = $state.CpuPriorityClass.Data
            IoPriority = $state.IoPriority.Data
            HasFilters = $state.HasFilters
            Configured = (-not $state.HasFilters -and $state.CpuPriorityClass.Exists -and $state.CpuPriorityClass.Kind -eq 'DWord' -and $state.CpuPriorityClass.Data -eq 1 -and $state.IoPriority.Exists -and $state.IoPriority.Kind -eq 'DWord' -and $state.IoPriority.Data -eq 0)
        }
    }
}

function Get-LowGearDataDirectory {
    Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'ACE-LowGear'
}

function Get-LowGearMachineToken {
    $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64)
    $key = $null
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $key = $base.OpenSubKey('SOFTWARE\Microsoft\Cryptography', $false)
        if ($null -eq $key) { throw 'Cannot read the local Windows installation identity.' }
        $identity = [string]$key.GetValue('MachineGuid', '')
        if ([string]::IsNullOrWhiteSpace($identity)) { throw 'Local Windows installation identity is unavailable.' }
        ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes('ACE-LowGear/v1/' + $identity)))).Replace('-', '')
    }
    finally {
        $sha.Dispose()
        if ($null -ne $key) { $key.Dispose() }
        $base.Dispose()
    }
}

function Assert-LowGearPlainDirectory {
    param([string]$Directory)
    if (Test-Path -LiteralPath $Directory) {
        $item = Get-Item -LiteralPath $Directory -Force
        if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'The local state directory must be a regular directory, not a link.'
        }
    }
}

function Initialize-LowGearDataDirectory {
    param([string]$Directory)
    Assert-LowGearPlainDirectory $Directory
    [void][IO.Directory]::CreateDirectory($Directory)
    $acl = [Security.AccessControl.DirectorySecurity]::new()
    $acl.SetAccessRuleProtection($true, $false)
    $admins = [Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
    $acl.SetOwner($admins)
    foreach ($entry in @(
        @{ Sid = 'S-1-5-18'; Rights = 'FullControl' },
        @{ Sid = 'S-1-5-32-544'; Rights = 'FullControl' },
        @{ Sid = 'S-1-5-32-545'; Rights = 'ReadAndExecute' }
    )) {
        $rule = [Security.AccessControl.FileSystemAccessRule]::new(
            [Security.Principal.SecurityIdentifier]::new($entry.Sid),
            [Security.AccessControl.FileSystemRights]$entry.Rights,
            [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit',
            [Security.AccessControl.PropagationFlags]::None,
            [Security.AccessControl.AccessControlType]::Allow)
        [void]$acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $Directory -AclObject $acl
    foreach ($name in @('backups', 'reports')) {
        $childPath = Join-Path $Directory $name
        Assert-LowGearPlainDirectory $childPath
        [void][IO.Directory]::CreateDirectory($childPath)
    }
}

function Get-LowGearTopology {
    Initialize-PriorityReader
    [pscustomobject]@{
        LogicalProcessors = [AceLowGear.Native]::GetActiveProcessorCount([UInt16]::MaxValue)
        ProcessorGroups = [AceLowGear.Native]::GetActiveProcessorGroupCount()
        Is64Bit = [Environment]::Is64BitProcess
    }
}

function Get-LowGearLastCpu {
    $topology = Get-LowGearTopology
    if ($topology.ProcessorGroups -ne 1 -or -not $topology.Is64Bit) {
        throw 'Last-CPU affinity requires a 64-bit process and a single processor group (up to 64 logical processors). CPU/I/O startup priorities do not have this affinity restriction.'
    }
    $processMask = [UIntPtr]::Zero
    $systemMask = [UIntPtr]::Zero
    $current = [Diagnostics.Process]::GetCurrentProcess()
    try {
        if (-not [AceLowGear.Native]::GetProcessAffinityMask($current.Handle, [ref]$processMask, [ref]$systemMask)) {
            throw [ComponentModel.Win32Exception]::new([Runtime.InteropServices.Marshal]::GetLastWin32Error())
        }
    }
    finally { $current.Dispose() }
    $remaining = $systemMask.ToUInt64()
    $index = -1
    while ($remaining -ne 0) { $index++; $remaining = $remaining -shr 1 }
    if ($index -lt 0) { throw 'The system processor mask is empty.' }
    [pscustomobject]@{ Index = $index; Mask = [IntPtr]::new([Int64]1 -shl $index) }
}

function Set-LowGearLastCpu {
    $cpu = Get-LowGearLastCpu
    foreach ($image in $script:Images) {
        $processes = @([Diagnostics.Process]::GetProcessesByName([IO.Path]::GetFileNameWithoutExtension($image)))
        if ($processes.Count -eq 0) {
            [pscustomobject]@{ Image = $image; Cpu = $cpu.Index; Status = 'NotRunning' }
        }
        foreach ($process in $processes) {
            try {
                $process.ProcessorAffinity = $cpu.Mask
                $process.Refresh()
                if ($process.ProcessorAffinity.ToInt64() -ne $cpu.Mask.ToInt64()) { throw 'Affinity readback did not match.' }
                [pscustomobject]@{ Image = $image; Cpu = $cpu.Index; Status = 'Matched' }
            }
            catch { [pscustomobject]@{ Image = $image; Cpu = $cpu.Index; Status = 'Failed'; Error = $_.Exception.Message } }
            finally { $process.Dispose() }
        }
    }
}

function Read-LowGearInstallation {
    param([string]$Directory, [string]$MachineToken)
    $activePath = Join-Path $Directory 'active.json'
    if (-not (Test-Path -LiteralPath $activePath)) { return $null }
    $manifest = Get-Content -LiteralPath $activePath -Raw | ConvertFrom-Json
    if ($manifest.SchemaVersion -ne 1 -or $manifest.MachineToken -cne $MachineToken) {
        throw 'State belongs to another Windows installation, or has an unsupported schema. Do not copy runtime state between computers.'
    }
    if ($manifest.BackupFile -cnotmatch '^original-[a-f0-9]{32}\.json$') { throw 'Invalid backup filename.' }
    if ($manifest.Phase -notin @('PendingApply', 'Applied', 'RecoveryRequired')) { throw 'Invalid installation phase.' }
    $backupPath = Join-Path (Join-Path $Directory 'backups') $manifest.BackupFile
    if ((Get-FileHash -LiteralPath $backupPath -Algorithm SHA256).Hash -cne $manifest.BackupSha256) {
        throw 'The original backup is missing or its integrity check failed.'
    }
    $backup = Get-Content -LiteralPath $backupPath -Raw | ConvertFrom-Json
    if ($backup.SchemaVersion -ne 1 -or $backup.MachineToken -cne $MachineToken -or
        ($backup.Originals.Image -join '|') -cne ($script:Images -join '|')) {
        throw 'Original backup identity or target list did not match.'
    }
    [pscustomobject]@{ Manifest = $manifest; Backup = $backup }
}

function Assert-LowGearRestoreConflictFree {
    param($Originals)
    foreach ($original in $Originals) {
        $current = Get-ImageState $original.Image
        foreach ($name in @('CpuPriorityClass', 'IoPriority')) {
            $desired = if ($name -eq 'CpuPriorityClass') { '1' } else { '0' }
            $value = $current.$name
            $isManaged = $value.Exists -and $value.Kind -eq 'DWord' -and $value.Data -ceq $desired
            $isOriginal = ($value | ConvertTo-Json -Depth 8 -Compress) -ceq ($original.$name | ConvertTo-Json -Depth 8 -Compress)
            if (-not $isManaged -and -not $isOriginal) {
                throw ('A later change was detected in ' + $original.Image + '/' + $name + '. Restore stopped to preserve that change; inspect the local backup before proceeding.')
            }
        }
    }
}

function Invoke-LowGearApply {
    param([string]$Directory, [string]$MachineToken)
    $installation = Read-LowGearInstallation $Directory $MachineToken
    if ($null -ne $installation) {
        if ($installation.Manifest.Phase -ne 'Applied') { throw 'An interrupted installation exists. Run Restore before Apply.' }
        if (@(Get-ConfigurationReport | Where-Object { -not $_.Configured }).Count -ne 0) {
            throw 'Settings changed after the previous installation. Inspect Check and Restore before applying again.'
        }
        return [pscustomobject]@{ Status = 'AlreadyConfigured'; OriginalBackupPreserved = $true }
    }
    $originals = @($script:Images | ForEach-Object { Get-ImageState $_ })
    if (@($originals | Where-Object { $_.HasFilters }).Count -ne 0) {
        throw 'An existing IFEO path filter was found. Automatic configuration stopped to preserve its behavior.'
    }
    # Validate this Windows version before changing any ACE key.
    $probeDirectory = Join-Path $Directory ('probe-' + [Guid]::NewGuid().ToString('N'))
    try { $validation = Test-StartupPriorities $probeDirectory }
    finally { if ([IO.Directory]::Exists($probeDirectory)) { [IO.Directory]::Delete($probeDirectory, $false) } }
    $now = @($script:Images | ForEach-Object { Get-ImageState $_ })
    if (($originals | ConvertTo-Json -Depth 12 -Compress) -cne ($now | ConvertTo-Json -Depth 12 -Compress)) {
        throw 'ACE registry settings changed during validation. No ACE settings were written.'
    }
    $backupFile = 'original-' + [Guid]::NewGuid().ToString('N') + '.json'
    $backupPath = Join-Path (Join-Path $Directory 'backups') $backupFile
    Save-JsonFile $backupPath ([pscustomobject]@{ SchemaVersion = 1; MachineToken = $MachineToken; Originals = $originals })
    $activePath = Join-Path $Directory 'active.json'
    $manifest = [pscustomobject]@{
        SchemaVersion = 1; MachineToken = $MachineToken; BackupFile = $backupFile
        BackupSha256 = (Get-FileHash -LiteralPath $backupPath -Algorithm SHA256).Hash
        Phase = 'PendingApply'
    }
    # Journal before the first ACE write so a crash still has a recovery record.
    Save-JsonFile $activePath $manifest
    try {
        foreach ($image in $script:Images) { Set-ImagePriorities $image 1 0 }
        if (@(Get-ConfigurationReport | Where-Object { -not $_.Configured }).Count -ne 0) { throw 'ACE registry readback failed.' }
        $manifest.Phase = 'Applied'
        Save-JsonFile $activePath $manifest
    }
    catch {
        $failure = $_
        $rollbackErrors = [Collections.Generic.List[string]]::new()
        foreach ($original in $originals) {
            try { Restore-ImageState $original }
            catch { $rollbackErrors.Add($_.Exception.Message) }
        }
        if ($rollbackErrors.Count -eq 0) {
            [IO.File]::Move($activePath, (Join-Path (Join-Path $Directory 'backups') ('rolled-back-' + [Guid]::NewGuid().ToString('N') + '.json')))
        }
        else {
            $manifest.Phase = 'RecoveryRequired'
            Save-JsonFile $activePath $manifest
            throw ('Apply failed and recovery is incomplete. Run Restore. ' + ($rollbackErrors -join '; '))
        }
        throw $failure
    }
    [pscustomobject]@{ Status = 'ConfiguredForNextStart'; Validation = $validation; OriginalBackupPreserved = $true }
}

function Invoke-LowGearRestore {
    param([string]$Directory, [string]$MachineToken)
    $installation = Read-LowGearInstallation $Directory $MachineToken
    if ($null -eq $installation) { return [pscustomobject]@{ Status = 'NoActiveInstallation' } }
    Assert-LowGearRestoreConflictFree $installation.Backup.Originals
    foreach ($original in $installation.Backup.Originals) { Restore-ImageState $original }
    [IO.File]::Move((Join-Path $Directory 'active.json'),
        (Join-Path (Join-Path $Directory 'backups') ('restored-' + [Guid]::NewGuid().ToString('N') + '.json')))
    [pscustomobject]@{ Status = 'RestoredForNextStart'; OriginalBackupPreserved = $true }
}

function Get-LowGearReport {
    param([string]$Status = 'Checked')
    [pscustomobject]@{
        Product = 'ACE LowGear'; Version = '0.1.0'; Status = $Status
        TimestampUtc = [DateTime]::UtcNow.ToString('o')
        Topology = Get-LowGearTopology
        Configuration = @(Get-ConfigurationReport)
        Processes = @(Get-LivePriorities)
    }
}

Export-ModuleMember -Function Get-LowGear*, Set-LowGearLastCpu, Initialize-LowGearDataDirectory, Assert-LowGearPlainDirectory, Invoke-LowGearApply, Invoke-LowGearRestore, Save-JsonFile, Test-StartupPriorities
