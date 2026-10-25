[CmdletBinding()]
param([switch]$StartupProbe,[string]$UiPreview)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$module=Import-Module (Join-Path $root 'src\LowGear.psm1') -Force -PassThru -DisableNameChecking
$id=[Guid]::NewGuid().ToString('N')
$temp=Join-Path ([IO.Path]::GetTempPath()) ('LowGear-tests-'+$id)
$registry='SOFTWARE\LowGearTests\'+$id
$checks=[Collections.Generic.List[string]]::new()
$probe=$null;$worker=$null;$other=$null
function Assert {param([bool]$Value,[string]$Name) if(-not $Value){throw ('FAIL: '+$Name)};$checks.Add($Name)}
function Throws {param([scriptblock]$Code,[string]$Name) $caught=$false;try{& $Code | Out-Null}catch{$caught=$true};Assert $caught $Name}
function Wait-Target {
    param($Process,[string]$Image)
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while($watch.Elapsed.TotalSeconds -lt 10){
        $sample=[LowGear.Runtime]::Inspect($Process.Id,$Image,$false,$false)
        if($sample.Verified){return [Math]::Round($watch.Elapsed.TotalSeconds,3)}
        Start-Sleep -Milliseconds 150
    }
    throw ('Worker failed to correct the owned probe: '+($sample | ConvertTo-Json -Depth 5 -Compress))
}
try {
    foreach($file in Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object {$_.Extension -in @('.ps1','.psm1')}){
        $t=$null;$e=$null;[void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$t,[ref]$e)
        Assert ($e.Count -eq 0) ('Syntax '+$file.Name)
    }
    Initialize-LGNative
    [void][IO.Directory]::CreateDirectory($temp)
    & $module {param($temp,$registry)
        $script:Common=$temp;$script:Data=Join-Path $temp 'v1'
        $script:Hive=[Microsoft.Win32.RegistryHive]::CurrentUser;$script:RegistryPath=$registry
        [void][IO.Directory]::CreateDirectory((Join-Path $script:Data 'backups'))
    } $temp $registry
    Throws {& $module {Set-LGImage 'Other.exe'}} 'Reject unrelated executable names'
    $absent=& $module {Get-LGImage 'SGuard64.exe'}
    & $module {Set-LGImage 'SGuard64.exe'}
    Assert (& $module {Test-LGConfigured (Get-LGImage 'SGuard64.exe')}) 'Read back typed startup settings'
    & $module {param($original) Restore-LGImage $original} $absent
    Assert (-not (& $module {Get-LGImage 'SGuard64.exe'}).ImageKeyExists) 'Restore removes only newly created empty keys'
    foreach($fixture in @(
        @{Kind='DWord';Data=[int]-1},@{Kind='QWord';Data=[Int64]::MaxValue},
        @{Kind='String';Data='original'},@{Kind='ExpandString';Data='%UNEXPANDED%\original'},
        @{Kind='Binary';Data=[byte[]]@(0,128,255)},@{Kind='Binary';Data=[byte[]]@()},
        @{Kind='None';Data=[byte[]]@(1,255)},@{Kind='MultiString';Data=[string[]]@('a','','c')},@{Kind='MultiString';Data=[string[]]@()}
    )){
        $before=& $module {param($fixture)
            $base=Open-LGRegistry;$key=$base.CreateSubKey($script:RegistryPath+'\SGuard64.exe\PerfOptions')
            try{
                foreach($name in @('CpuPriorityClass','IoPriority')){$key.SetValue($name,$fixture.Data,[Microsoft.Win32.RegistryValueKind][Enum]::Parse([Microsoft.Win32.RegistryValueKind],$fixture.Kind))}
                $key.SetValue('Untouched','keep',[Microsoft.Win32.RegistryValueKind]::String)
            }finally{$key.Dispose();$base.Dispose()}
            Get-LGImage 'SGuard64.exe'
        } $fixture
        $roundTrip=$before | ConvertTo-Json -Depth 12 | ConvertFrom-Json
        & $module {Set-LGImage 'SGuard64.exe'}
        & $module {param($original) Restore-LGImage $original} $roundTrip
        $after=& $module {Get-LGImage 'SGuard64.exe'}
        Assert (($before | ConvertTo-Json -Depth 12 -Compress) -ceq ($after | ConvertTo-Json -Depth 12 -Compress)) ('Exact JSON restore '+$fixture.Kind)
        $untouched=& $module {$base=Open-LGRegistry;$key=$base.OpenSubKey($script:RegistryPath+'\SGuard64.exe\PerfOptions');try{$key.GetValue('Untouched')}finally{$key.Dispose();$base.Dispose()}}
        Assert ($untouched -ceq 'keep') ('Keep unrelated values '+$fixture.Kind)
    }
    # Exercise installation transactions in HKCU with an in-memory scheduler adapter.
    & $module {
        $script:Task=$null
        $script:RealProbe=(Get-Command Test-LGStartup).ScriptBlock
        function script:Get-LGTaskSnapshot {param([string]$Name=$script:TaskName,[string]$Source=$script:TaskSource) [pscustomobject]@{Name=$Name;Exists=$false;Xml=$null;WasRunning=$false}}
        function script:Restore-LGTask {param($Snapshot,[string]$Source) $script:Task=$null}
        function script:Remove-LGTask {param([string]$Name,[string]$Source) $script:Task=$null}
        function script:Test-LGStartup {[pscustomobject]@{Passed=$true;Mode='IsolatedTransactionDouble'}}
        function script:Register-LGTask {param([string]$Runtime) throw 'Injected scheduler failure'}
        function script:Wait-LGWorker {}
        function script:Get-LGAutomation {[pscustomobject]@{Filter=$null;Consumer=$null;Ready=$true}}
        function script:Register-LGAutomation {}
        function script:Remove-LGAutomation {}
    }
    $before=& $module {@($script:Images | ForEach-Object {Get-LGImage $_})}
    Throws {& $module {Install-LG $false}} 'Injected task registration failure is reported'
    $after=& $module {@($script:Images | ForEach-Object {Get-LGImage $_})}
    Assert (($before | ConvertTo-Json -Depth 12 -Compress) -ceq ($after | ConvertTo-Json -Depth 12 -Compress)) 'Failed installation restores all startup values'
    Assert (-not (Test-Path -LiteralPath (Join-Path $temp 'v1\active.json'))) 'Successful rollback archives the pending journal'
    & $module {
        function script:Get-LGTask {param([string]$Name=$script:TaskName) if($Name -eq $script:TaskName){$script:Task}else{$null}}
        function script:Register-LGTask {
            param([string]$Runtime)
            $script:Task=[pscustomobject]@{State=4;Enabled=$true}
            $script:Task | Add-Member ScriptMethod Stop {param($flags)$this.State=3}
            $script:Task | Add-Member ScriptMethod Run {param($parameters)$this.State=4}
        }
    }
    & $module {Install-LG $false} | Out-Null
    $state=& $module {Read-LGActive}
    Assert ($state.Manifest.Phase -eq 'Active') 'Fresh installation reaches Active'
    $activePath=Join-Path $temp 'v1\active.json'
    $activeHash=(Get-FileHash -LiteralPath $activePath -Algorithm SHA256).Hash
    $backupPath=Join-Path (Join-Path $temp 'v1\backups') $state.Manifest.Backup
    $backupBytes=[IO.File]::ReadAllBytes($backupPath)
    & $module {Install-LG $false} | Out-Null
    $again=& $module {Read-LGActive}
    Assert ($again.Manifest.Backup -ceq $state.Manifest.Backup -and $again.Manifest.BackupHash -ceq $state.Manifest.BackupHash) 'Repeated installation preserves the earliest backup'
    & $module {Pause-LG} | Out-Null
    Assert ((& $module {Read-LGActive}).Manifest.Phase -eq 'Paused' -and -not (& $module {$script:Task.Enabled})) 'Pause disables the worker without dropping startup rules'
    & $module {Resume-LG} | Out-Null
    Assert ((& $module {Read-LGActive}).Manifest.Phase -eq 'Active' -and (& $module {$script:Task.State}) -eq 4) 'Resume verifies the runtime and re-enables the worker'
    [IO.File]::AppendAllText($backupPath,' ')
    Throws {& $module {Read-LGActive}} 'Tampered original backup is rejected'
    [IO.File]::WriteAllBytes($backupPath,$backupBytes)
    $activeBytes=[IO.File]::ReadAllBytes($activePath)
    $wrong=Get-Content -LiteralPath $activePath -Raw | ConvertFrom-Json;$wrong.Machine='wrong-machine'
    & $module {param($path,$value)Write-LGJson $path $value} $activePath $wrong
    Throws {& $module {Read-LGActive}} 'Cross-machine recovery state is rejected'
    [IO.File]::WriteAllBytes($activePath,$activeBytes)
    & $module {Set-LGImage 'SGuardSvc64.exe' 3 2}
    Throws {& $module {Restore-LG}} 'Later changes block automatic restoration'
    & $module {Set-LGImage 'SGuardSvc64.exe'}
    & $module {Restore-LG} | Out-Null
    Assert (-not (Test-Path -LiteralPath $activePath)) 'Restoration completes and archives active state'

    # Import the original pre-0.1.x baseline, never the already lowered values.
    $preLegacy=& $module {@($script:Images | ForEach-Object {Get-LGImage $_})}
    & $module {param($originals)
        [void][IO.Directory]::CreateDirectory((Join-Path $script:Common 'backups'))
        $legacyToken=Get-LGToken -Legacy
        $name='original-'+[Guid]::NewGuid().ToString('N')+'.json'
        $path=Join-Path (Join-Path $script:Common 'backups') $name
        Write-LGJson $path ([pscustomobject]@{SchemaVersion=1;MachineToken=$legacyToken;Originals=$originals})
        Write-LGJson (Join-Path $script:Common 'active.json') ([pscustomobject]@{SchemaVersion=1;Phase='Applied';MachineToken=$legacyToken;BackupFile=$name;BackupSha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash})
        foreach($image in $script:Images){Set-LGImage $image}
    } $preLegacy
    & $module {Install-LG $false} | Out-Null
    $migrated=& $module {Read-LGActive}
    Assert ($migrated.Original.Origin -ceq 'MigratedOriginalBaseline') 'Migration recognizes the earlier version baseline'
    Assert (($migrated.Original.Registry | ConvertTo-Json -Depth 12 -Compress) -ceq ($preLegacy | ConvertTo-Json -Depth 12 -Compress)) 'Migration retains the pre-0.1 original values and types'
    & $module {Restore-LG} | Out-Null
    $afterMigrationRestore=& $module {@($script:Images | ForEach-Object {Get-LGImage $_})}
    Assert (($afterMigrationRestore | ConvertTo-Json -Depth 12 -Compress) -ceq ($preLegacy | ConvertTo-Json -Depth 12 -Compress)) 'Full restore after migration returns to the earliest baseline'
    & $module {Install-LG $false} | Out-Null
    Assert ((& $module {Read-LGActive}).Manifest.Phase -eq 'Active') 'Reinstall after full restoration ignores retired legacy state'
    & $module {Restore-LG} | Out-Null

    # Both distinct core images must be present; duplicate instances cannot substitute.
    $first=[LowGear.Sample]::new();$first.Image='SGuard64.exe';$first.Running=$true;$first.Verified=$true
    $second=[LowGear.Sample]::new();$second.Image='SGuardSvc64.exe';$second.Running=$true;$second.Verified=$true
    Assert (-not [LowGear.Runtime]::SessionMatches(@($first,$first),$false)) 'Duplicate core instances cannot replace the other required image'
    Assert ([LowGear.Runtime]::SessionMatches(@($first,$second),$false)) 'Both verified core images satisfy startup completion'
    $second.Verified=$false
    Assert (-not [LowGear.Runtime]::SessionMatches(@($first,$second),$false)) 'An unverified running core prevents startup completion'
    # Native identity, both priorities, affinity, and bounded worker tests.
    $image='LowGearProbe-'+$id+'.exe';$probePath=Join-Path $temp $image
    Build-LGRuntime $probePath 'public static class Probe { public static void Main(){System.Threading.Thread.Sleep(60000);} }'
    $probe=Start-Process -FilePath $probePath -WindowStyle Hidden -PassThru
    $probe.PriorityClass=[Diagnostics.ProcessPriorityClass]::Normal
    $rejected=[LowGear.Runtime]::Inspect($probe.Id,'Other.exe',$true,$false)
    $probe.Refresh()
    Assert ($rejected.Errors.Count -gt 0 -and $probe.PriorityClass -eq [Diagnostics.ProcessPriorityClass]::Normal) 'Identity check prevents changing a reused or unrelated PID'
    $sample=[LowGear.Runtime]::Inspect($probe.Id,$image,$true,$false)
    Assert ($sample.Verified -and $sample.IoPriority -eq 0) 'Native CPU and I/O correction is read back'
    if($null -ne [LowGear.Runtime]::GetTopology().LastCpu){
        $sample=[LowGear.Runtime]::Inspect($probe.Id,$image,$true,$true)
        Assert ($sample.Verified -and $sample.AffinityMatched) 'Last logical CPU binding is read back'
    }
    $probe.PriorityClass=[Diagnostics.ProcessPriorityClass]::Normal
    $workerPath=Join-Path $temp 'LowGear.Worker.exe';Build-LGRuntime $workerPath
    [LowGear.Runtime]::WriteJson((Join-Path $temp 'policy.json'),[LowGear.Policy]::new())
    $worker=Start-Process -FilePath $workerPath -WindowStyle Hidden -ArgumentList ('--probe "'+$temp+'" '+$image+' 60') -PassThru
    $first=Wait-Target $probe $image
    $checks.Add('Worker corrects a newly started target')
    $probe.PriorityClass=[Diagnostics.ProcessPriorityClass]::Normal
    $repeat=Wait-Target $probe $image
    $checks.Add('Startup session handles an increase during verification')
    Assert ($worker.WaitForExit(10000) -and $worker.ExitCode -eq 0) 'Successful startup session exits automatically'
    $probe.PriorityClass=[Diagnostics.ProcessPriorityClass]::Normal
    Start-Sleep -Seconds 4;$probe.Refresh()
    Assert ($probe.PriorityClass -eq [Diagnostics.ProcessPriorityClass]::Normal) 'No ongoing correction remains after session completion'
    $worker.Dispose();$worker=$null
    $probe.Kill();[void]$probe.WaitForExit(5000);$probe.Dispose();$probe=$null
    $probe=Start-Process -FilePath $probePath -WindowStyle Hidden -PassThru
    $worker=Start-Process -FilePath $workerPath -WindowStyle Hidden -ArgumentList ('--probe "'+$temp+'" '+$image+' 20') -PassThru
    $restart=Wait-Target $probe $image
    $checks.Add('A new startup session corrects CPU and I/O after a restart')
    $other=Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -WindowStyle Hidden -ArgumentList '-NoProfile -NonInteractive -Command "Start-Sleep -Seconds 60"' -PassThru
    $other.PriorityClass=[Diagnostics.ProcessPriorityClass]::Normal
    Start-Sleep -Seconds 4;$other.Refresh()
    Assert ($other.PriorityClass -eq [Diagnostics.ProcessPriorityClass]::Normal) 'Unrelated owned process is unchanged'
    Assert ($worker.WaitForExit(10000) -and $worker.ExitCode -eq 0) 'The second startup session also exits'
    $heartbeat=Get-Content -LiteralPath (Join-Path $temp 'last-run.json') -Raw | ConvertFrom-Json
    Assert ($heartbeat.Corrections -ge 2 -and $heartbeat.SessionState -eq 'Completed') 'Final session report records completion and corrections'

    if($StartupProbe){
        & $module {
            $script:Hive=[Microsoft.Win32.RegistryHive]::LocalMachine
            $script:RegistryPath='SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options'
            Set-Item Function:script:Test-LGStartup $script:RealProbe
        }
        $validation=& $module {Test-LGStartup}
        Assert ($validation.Passed -and $validation.Cleanup) 'Real HKLM baseline and two minimum startup probes pass and clean up'
    }
    if($UiPreview){
        . (Join-Path $root 'ui\Panel.ps1')
        Show-LGPanel -RenderOnly -ImagePath $UiPreview
        Assert ((Get-Item -LiteralPath $UiPreview).Length -gt 10000) 'Chinese WPF panel renders with all named controls'
    }
    [pscustomobject]@{Status='Passed';Count=$checks.Count;Checks=$checks.ToArray();FirstCorrectionSeconds=$first;RepeatedCorrectionSeconds=$repeat;RestartCorrectionSeconds=$restart;StartupProbe=[bool]$StartupProbe} | ConvertTo-Json -Depth 7
}
finally {
    foreach($p in @($worker,$probe,$other)){if($null -ne $p){if(-not $p.HasExited){$p.Kill();[void]$p.WaitForExit(5000)};$p.Dispose()}}
    if($id -cnotmatch '^[a-f0-9]{32}$' -or $registry -cne ('SOFTWARE\LowGearTests\'+$id)){throw 'Unsafe test cleanup identity.'}
    $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser,[Microsoft.Win32.RegistryView]::Registry64)
    try{$base.DeleteSubKeyTree($registry,$false)}finally{$base.Dispose()}
    $expected=[IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('LowGear-tests-'+$id)))
    if([IO.Path]::GetFullPath($temp) -cne $expected){throw 'Unsafe test file cleanup target.'}
    if([IO.Directory]::Exists($temp)){[IO.Directory]::Delete($temp,$true)}
    Remove-Module $module -Force
}
