function Write-LGJson {
    param([string]$Path,$Value)
    $temp = $Path + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllText($temp,($Value | ConvertTo-Json -Depth 30),[Text.UTF8Encoding]::new($false))
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temp,$Path,[Management.Automation.Language.NullString]::Value) }
        else { [IO.File]::Move($temp,$Path) }
    }
    finally { if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) } }
}
function Read-LGJson { param([string]$Path) Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
function Throw-LGError {
    param([string]$Code,[string]$Message)
    $error=[InvalidOperationException]::new($Message);$error.Data['LowGearCode']=$Code;throw $error
}
function Get-LGProperty {
    param($Object,[string]$Name,$Default=$null)
    if($null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]){return $Object.$Name}
    $Default
}
function Assert-LGDirectory {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        $item = Get-Item -LiteralPath $Path -Force
        if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw '数据目录必须是普通文件夹。' }
    }
}
function Initialize-LGData {
    Assert-LGDirectory $script:Common
    Assert-LGDirectory $script:Data
    [void][IO.Directory]::CreateDirectory($script:Data)
    $acl = [Security.AccessControl.DirectorySecurity]::new()
    $acl.SetAccessRuleProtection($true,$false)
    $acl.SetOwner([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))
    foreach ($entry in @(@('S-1-5-18','FullControl'),@('S-1-5-32-544','FullControl'),@('S-1-5-32-545','ReadAndExecute'))) {
        $rule = [Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($entry[0]),
            [Security.AccessControl.FileSystemRights]$entry[1],[Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit',
            [Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow)
        [void]$acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $script:Data -AclObject $acl
    foreach ($name in @('backups','reports')) {
        $path = Join-Path $script:Data $name
        Assert-LGDirectory $path
        [void][IO.Directory]::CreateDirectory($path)
    }
}
function Get-LGToken {
    param([switch]$Legacy)
    $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,[Microsoft.Win32.RegistryView]::Registry64)
    $key = $null; $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $key = $base.OpenSubKey('SOFTWARE\Microsoft\Cryptography')
        $id = [string]$key.GetValue('MachineGuid','')
        if (-not $id) { throw '无法读取本机安装标识。' }
        $prefix = if ($Legacy) { 'ACE-LowGear/v1/' } else { 'ACE-LowGear/1/' }
        ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($prefix+$id)))).Replace('-','')
    }
    finally { if ($null -ne $key) { $key.Dispose() }; $base.Dispose(); $sha.Dispose() }
}
function Open-LGRegistry { [Microsoft.Win32.RegistryKey]::OpenBaseKey($script:Hive,[Microsoft.Win32.RegistryView]::Registry64) }
function Assert-LGImage {
    param([string]$Image)
    if ($script:Images -notcontains $Image -and $Image -cnotmatch '^LowGearProbe-[a-f0-9]{32}\.exe$') { throw '程序名超出固定目标范围。' }
}
function Get-LGValue {
    param($Key,[string]$Name)
    if ($null -eq $Key -or $Key.GetValueNames() -notcontains $Name) { return [pscustomobject]@{Exists=$false;Kind=$null;Data=$null} }
    $kind = $Key.GetValueKind($Name).ToString()
    $data = $Key.GetValue($Name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    if ($kind -in @('DWord','QWord')) { $data = ([Int64]$data).ToString([Globalization.CultureInfo]::InvariantCulture) }
    elseif ($kind -in @('Binary','None')) { $data = [Convert]::ToBase64String([byte[]]$data) }
    [pscustomobject]@{Exists=$true;Kind=$kind;Data=$data}
}
function Get-LGImage {
    param([string]$Image)
    Assert-LGImage $Image
    $base = Open-LGRegistry; $key = $null; $perf = $null
    try {
        $key = $base.OpenSubKey($script:RegistryPath+'\'+$Image)
        if ($null -ne $key) { $perf = $key.OpenSubKey('PerfOptions') }
        [pscustomobject]@{ Image=$Image; ImageKeyExists=($null -ne $key); PerfKeyExists=($null -ne $perf)
            HasFilters=($null -ne $key -and $key.GetValue('UseFilter',0) -ne 0)
            CpuPriorityClass=(Get-LGValue $perf 'CpuPriorityClass'); IoPriority=(Get-LGValue $perf 'IoPriority') }
    }
    finally { if ($null -ne $perf) {$perf.Dispose()}; if ($null -ne $key) {$key.Dispose()}; $base.Dispose() }
}
function Test-LGConfigured {
    param($State)
    -not $State.HasFilters -and $State.CpuPriorityClass.Exists -and $State.CpuPriorityClass.Kind -eq 'DWord' -and
        $State.CpuPriorityClass.Data -eq '1' -and $State.IoPriority.Exists -and $State.IoPriority.Kind -eq 'DWord' -and $State.IoPriority.Data -eq '0'
}
function Set-LGImage {
    param([string]$Image,[int]$Cpu=1,[int]$Io=0)
    Assert-LGImage $Image
    $base = Open-LGRegistry; $key = $null
    try {
        $key = $base.CreateSubKey($script:RegistryPath+'\'+$Image+'\PerfOptions')
        $key.SetValue('CpuPriorityClass',$Cpu,[Microsoft.Win32.RegistryValueKind]::DWord)
        $key.SetValue('IoPriority',$Io,[Microsoft.Win32.RegistryValueKind]::DWord)
        $key.Flush()
    }
    finally { if ($null -ne $key) {$key.Dispose()}; $base.Dispose() }
}
function Restore-LGImage {
    param($Original)
    Assert-LGImage $Original.Image
    $base = Open-LGRegistry; $key = $null; $perf = $null
    try {
        $path = $script:RegistryPath+'\'+$Original.Image
        $needed = $Original.CpuPriorityClass.Exists -or $Original.IoPriority.Exists
        $key = $base.OpenSubKey($path,$true)
        if ($null -eq $key -and $needed) {$key=$base.CreateSubKey($path)}
        if ($null -ne $key) {
            $perf=$key.OpenSubKey('PerfOptions',$true)
            if ($null -eq $perf -and $needed) {$perf=$key.CreateSubKey('PerfOptions')}
            if ($null -ne $perf) {
                foreach ($name in @('CpuPriorityClass','IoPriority')) {
                    $saved=$Original.$name
                    if (-not $saved.Exists) {$perf.DeleteValue($name,$false); continue}
                    $data=$saved.Data
                    switch ($saved.Kind) {
                        'DWord' {$data=[int]$data}
                        'QWord' {$data=[long]$data}
                        'Binary' {$data=[Convert]::FromBase64String([string]$data)}
                        'None' {$data=[Convert]::FromBase64String([string]$data)}
                        'MultiString' {$data=[string[]]$data}
                    }
                    $perf.SetValue($name,$data,[Microsoft.Win32.RegistryValueKind][Enum]::Parse([Microsoft.Win32.RegistryValueKind],$saved.Kind))
                }
                $empty=$perf.ValueCount -eq 0 -and $perf.SubKeyCount -eq 0
                $perf.Dispose(); $perf=$null
                if (-not $Original.PerfKeyExists -and $empty) {$key.DeleteSubKey('PerfOptions',$false)}
            }
            $empty=$key.ValueCount -eq 0 -and $key.SubKeyCount -eq 0
            $key.Dispose(); $key=$null
            if (-not $Original.ImageKeyExists -and $empty) {$base.DeleteSubKey($path,$false)}
        }
    }
    finally {if($null -ne $perf){$perf.Dispose()};if($null -ne $key){$key.Dispose()};$base.Dispose()}
    $actual=Get-LGImage $Original.Image
    foreach($name in @('CpuPriorityClass','IoPriority')) {
        if (($actual.$name | ConvertTo-Json -Depth 8 -Compress) -cne ($Original.$name | ConvertTo-Json -Depth 8 -Compress)) {throw ('恢复核验失败：'+$Original.Image+'/'+$name)}
    }
}
function Assert-LGRestore {
    param($Originals)
    foreach($original in $Originals) {
        $now=Get-LGImage $original.Image
        foreach($name in @('CpuPriorityClass','IoPriority')) {
            $desired=if($name -eq 'CpuPriorityClass'){'1'}else{'0'}
            $value=$now.$name
            $managed=$value.Exists -and $value.Kind -eq 'DWord' -and $value.Data -ceq $desired
            $unchanged=($value | ConvertTo-Json -Depth 8 -Compress) -ceq ($original.$name | ConvertTo-Json -Depth 8 -Compress)
            if(-not $managed -and -not $unchanged){throw ('发现后续修改，已保留当前值：'+$original.Image+'/'+$name)}
        }
    }
}
function Read-LGActive {
    $path=Join-Path $script:Data 'active.json'
    if(-not(Test-Path -LiteralPath $path)){return $null}
    $active=Read-LGJson $path
    if($active.Schema -ne 1 -or $active.Machine -cne (Get-LGToken)){throw '恢复记录不属于当前 Windows 安装或格式不受支持。'}
    if($active.Backup -cnotmatch '^original-[a-f0-9]{32}\.json$'){throw '原始备份文件名无效。'}
    $backupPath=Join-Path (Join-Path $script:Data 'backups') $active.Backup
    if((Get-FileHash -LiteralPath $backupPath -Algorithm SHA256).Hash -cne $active.BackupHash){throw '原始备份丢失或完整性核验失败。'}
    $backup=Read-LGJson $backupPath
    if($backup.Schema -ne 1 -or $backup.Machine -cne $active.Machine -or ($backup.Registry.Image -join '|') -cne ($script:Images -join '|')){throw '原始备份内容不匹配。'}
    if($active.Version -cnotmatch '^1\.\d+\.\d+$' -or $active.Runtime -cnotmatch ('^app-'+[regex]::Escape($active.Version)+'-[a-f0-9]{32}$')){Throw-LGError 'STATE_RUNTIME_INVALID' '运行目录与安装版本不匹配。'}
    if($active.Phase -notin @('Installing','Active','Paused','Restoring','Upgrading','RecoveryRequired')){Throw-LGError 'STATE_PHASE_INVALID' '安装事务状态不受支持。'}
    [pscustomobject]@{Manifest=$active;Original=$backup}
}

function Write-LGProgress {
    param([string]$Message)
    if($script:ProgressPath){Write-LGJson $script:ProgressPath ([pscustomobject]@{Message=$Message})}
}
