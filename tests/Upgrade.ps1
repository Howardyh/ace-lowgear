[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$module=Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'src\LowGear.psm1') -Force -PassThru -DisableNameChecking
$id=[Guid]::NewGuid().ToString('N');$temp=Join-Path ([IO.Path]::GetTempPath()) ('LowGear-upgrade-tests-'+$id);$registry='SOFTWARE\LowGearTests\'+$id
$checks=[Collections.Generic.List[string]]::new()
function Assert {param([bool]$Value,[string]$Name)if(-not $Value){throw ('FAIL: '+$Name)};$checks.Add($Name)}
function Throws {param([scriptblock]$Code,[string]$Name)$caught=$false;try{& $Code|Out-Null}catch{$caught=$true};Assert $caught $Name}
try{
    Initialize-LGNative
    & $module {param($temp,$registry)
        $script:Common=$temp;$script:Data=Join-Path $temp 'v1';$script:Hive=[Microsoft.Win32.RegistryHive]::CurrentUser;$script:RegistryPath=$registry
        $script:Task=$null;$script:Filter=$false;$script:Consumer=$false;$script:Bound=$false;$script:FailRegister=0;$script:FailWait=$false;$script:AutomationThrows=$false
        Initialize-LGData
        function script:New-TestTask {param([string]$Runtime,[bool]$Enabled=$true)
            $actions=[pscustomobject]@{Count=1;Action=[pscustomobject]@{Path=$Runtime;Arguments='--once "'+$script:Data+'"';WorkingDirectory=$script:Data}}
            $actions|Add-Member ScriptMethod Item {param($index)$this.Action}
            $task=[pscustomobject]@{State=3;Enabled=$Enabled;Definition=[pscustomobject]@{RegistrationInfo=[pscustomobject]@{Source=$script:TaskSource};Principal=[pscustomobject]@{UserId='SYSTEM';RunLevel=1};Triggers=[pscustomobject]@{Count=0};Actions=$actions;Settings=[pscustomobject]@{ExecutionTimeLimit='PT2M';MultipleInstances=2;RestartCount=0}}}
            $task|Add-Member ScriptMethod Stop {param($flags)$this.State=3};$task|Add-Member ScriptMethod Run {param($arg)$this.State=4};$script:Task=$task
        }
        function script:Get-LGTask {param([string]$Name=$script:TaskName)if($Name -eq $script:TaskName){$script:Task}else{$null}}
        function script:Get-LGTaskSnapshot {param([string]$Name=$script:TaskName,[string]$Source=$script:TaskSource)
            if($null -eq $script:Task){return [pscustomobject]@{Name=$Name;Exists=$false;Xml=$null;WasRunning=$false}}
            if($script:Task.Definition.RegistrationInfo.Source -cne $Source){throw 'Foreign task'}
            [pscustomobject]@{Name=$Name;Exists=$true;Xml='isolated';WasRunning=($script:Task.State -eq 4);Runtime=$script:Task.Definition.Actions.Item(1).Path;Enabled=$script:Task.Enabled}
        }
        function script:Remove-LGTask {param([string]$Name=$script:TaskName,[string]$Source=$script:TaskSource)[void](Get-LGTaskSnapshot $Name $Source);$script:Task=$null}
        function script:Restore-LGTask {param($Snapshot)if($Snapshot.Exists){New-TestTask $Snapshot.Runtime $Snapshot.Enabled;if($Snapshot.WasRunning){$script:Task.State=4}}else{$script:Task=$null}}
        function script:Get-LGAutomation {if($script:AutomationThrows){throw 'Injected event provider error'};[pscustomobject]@{Filter=if($script:Filter){[pscustomobject]@{Name='owned'}}else{$null};Consumer=if($script:Consumer){[pscustomobject]@{Name='owned'}}else{$null};Bindings=@();Ready=$script:Bound}}
        function script:Register-LGAutomation {$script:Filter=$true;$script:Consumer=$true;$script:Bound=$true}
        function script:Remove-LGAutomation {if($script:AutomationThrows){throw 'Injected event provider error'};$script:Filter=$false;$script:Consumer=$false;$script:Bound=$false}
        function script:Register-LGTask {param([string]$Runtime,[switch]$SkipImmediate,[string]$ProbeImage,[bool]$Enabled=$true)
            if($script:FailRegister -gt 0){$script:FailRegister--;throw 'Injected registration failure'}
            New-TestTask $Runtime $Enabled
            if($Enabled){Register-LGAutomation;if(-not $SkipImmediate){Start-LGTaskSession $script:Task}}
        }
        function script:Wait-LGWorker {if($script:FailWait){throw 'Injected fresh-session failure'}}
        function script:Test-LGStartup {[pscustomobject]@{Passed=$true;Cleanup=$true}}
        $originals=@($script:Images|ForEach-Object {Get-LGImage $_})
        $backupName='original-'+[Guid]::NewGuid().ToString('N')+'.json';$backupPath=Join-Path (Join-Path $script:Data 'backups') $backupName
        Write-LGJson $backupPath ([pscustomobject]@{Schema=1;Machine=(Get-LGToken);Origin='MigratedOriginalBaseline';Registry=$originals;LegacyTask=[pscustomobject]@{Exists=$false}})
        $script:Baseline=[pscustomobject]@{Backup=$backupName;BackupHash=(Get-FileHash $backupPath -Algorithm SHA256).Hash}
        foreach($image in $script:Images){Set-LGImage $image}
        function script:Seed-Old {param([string]$Phase='Paused')
            $folder='app-1.0.0-'+[Guid]::NewGuid().ToString('N');$directory=Join-Path $script:Data $folder;[void][IO.Directory]::CreateDirectory($directory);$exe=Join-Path $directory 'LowGear.Worker.exe'
            Build-LGRuntime $exe -ProductVersion '1.0.0'
            Write-LGJson (Join-Path $script:Data 'policy.json') ([pscustomobject]@{Schema=1;BindLastCpu=$true;IntervalSeconds=3})
            Write-LGJson (Join-Path $script:Data 'active.json') ([pscustomobject]@{Schema=1;Machine=(Get-LGToken);Version='1.0.0';Phase=$Phase;Runtime=$folder;RuntimeHash=(Get-FileHash $exe -Algorithm SHA256).Hash;Backup=$script:Baseline.Backup;BackupHash=$script:Baseline.BackupHash})
            New-TestTask $exe ($Phase -eq 'Active');$script:Filter=$false;$script:Consumer=$false;$script:Bound=$false
            if($Phase -eq 'Active'){Register-LGAutomation}
        }
        Seed-Old
    } $temp $registry
    $before=& $module {Read-LGActive};$backupHash=$before.Manifest.BackupHash
    & $module {Upgrade-LG}|Out-Null
    $state=& $module {Read-LGActive}
    Assert ($state.Manifest.Version -eq '1.1.0' -and $state.Manifest.Phase -eq 'Paused') 'Upgrade a schema-1 v1.0 installation while retaining pause'
    Assert ($state.Manifest.Backup -ceq $before.Manifest.Backup -and $state.Manifest.BackupHash -ceq $backupHash) 'Upgrade preserves earliest backup bytes and reference'
    Assert ((& $module {Read-LGJson (Join-Path $script:Data 'policy.json')}).BindLastCpu) 'Upgrade retains affinity policy'
    & $module {Invoke-LGCommand -Command SetAffinity}|Out-Null
    Assert (-not (& $module {Read-LGPolicy}).BindLastCpu) 'Legacy SetAffinity command without a switch still disables future binding'
    & $module {Set-LGPolicy $true}
    Assert (-not (& $module {Get-LGTask}).Enabled -and -not (& $module {Get-LGAutomation}).Ready) 'Paused upgrade leaves both task and event inactive'
    & $module {$script:FailWait=$true}
    Throws {& $module {Resume-LG}} 'Resume failure is reported without silently enabling automation'
    & $module {$script:FailWait=$false}
    Assert ((& $module {Read-LGActive}).Manifest.Phase -eq 'Paused' -and -not (& $module {Get-LGTask}).Enabled -and -not (& $module {Get-LGAutomation}).Ready) 'Failed resume restores the paused task and absent event'
    $count=@(Get-ChildItem (Join-Path $temp 'v1') -Directory -Filter 'app-*').Count
    & $module {Upgrade-LG}|Out-Null
    Assert (@(Get-ChildItem (Join-Path $temp 'v1') -Directory -Filter 'app-*').Count -eq $count) 'Repeated same-version upgrade does not deploy again'
    & $module {Resume-LG}|Out-Null
    Assert ((& $module {Read-LGActive}).Manifest.Phase -eq 'Active' -and (& $module {Get-LGAutomation}).Ready) 'Resume after paused upgrade explicitly enables automation'
    & $module {Pause-LG;Remove-LGTask;Repair-LG}|Out-Null
    Assert ((& $module {Read-LGActive}).Manifest.Phase -eq 'Paused' -and -not (& $module {Get-LGTask}).Enabled) 'Repair a missing paused task without enabling it'
    & $module {Seed-Old 'Active';$script:FailRegister=1}
    $old=& $module {Read-LGActive}
    Throws {& $module {Upgrade-LG}} 'Registration failure during upgrade is reported'
    $after=& $module {Read-LGActive}
    Assert ($after.Manifest.Runtime -ceq $old.Manifest.Runtime -and $after.Manifest.Phase -eq 'Active' -and (& $module {Get-LGAutomation}).Ready) 'Failed upgrade restores old runtime, task and event'
    & $module {$script:FailWait=$true}
    Throws {& $module {Upgrade-LG}} 'Fresh-session failure rolls back deployment'
    & $module {$script:FailWait=$false}
    Assert ((& $module {Read-LGActive}).Manifest.Runtime -ceq $old.Manifest.Runtime) 'Startup verification failure keeps prior runtime'
    & $module {Upgrade-LG}|Out-Null
    $current=& $module {Read-LGActive}
    & $module {$s=Read-LGActive;$snapshot=Get-LGDeploymentSnapshot $s;[void](Save-LGDeploymentJournal $s $snapshot);Remove-LGAutomation;Remove-LGTask;Set-LGPolicy $false}
    & $module {Repair-LG}|Out-Null
    $recovered=& $module {Read-LGActive}
    Assert ($recovered.Manifest.Phase -eq 'Active' -and $recovered.Manifest.Runtime -ceq $current.Manifest.Runtime) 'Interrupted upgrade journal restores the prior committed deployment'
    Assert ((& $module {Read-LGJson (Join-Path $script:Data 'policy.json')}).BindLastCpu -and (& $module {Get-LGAutomation}).Ready) 'Interrupted recovery restores policy and event'
    & $module {$script:Task.Definition.Actions.Action.Path='unrelated.exe'}
    Throws {& $module {Repair-LG}} 'Repair refuses a changed task action'
    & $module {$s=Read-LGActive;$script:Task.Definition.Actions.Action.Path=Get-LGRuntimePath $s;$script:Task.Definition.RegistrationInfo.Source='Another tool'}
    Throws {& $module {Repair-LG}} 'Repair refuses a foreign task source'
    & $module {$script:Task.Definition.RegistrationInfo.Source=$script:TaskSource;Set-LGImage 'SGuard64.exe' 3 2}
    Throws {& $module {Repair-LG}} 'Repair refuses later startup value changes'
    & $module {Set-LGImage 'SGuard64.exe';$script:AutomationThrows=$true}
    $report=Get-LGStatus
    Assert ($report.Health.Automation.State -eq 'Conflict' -and $report.Health.Startup.State -eq 'Healthy' -and $report.Processes.Count -gt 0) 'Failed event query does not hide startup or process readings'
    & $module {$script:AutomationThrows=$false}
    & $module {Write-LGJson (Join-Path $script:Data 'policy.json') ([pscustomobject]@{Schema=1;IntervalSeconds=3})}
    $invalidPolicy=Get-LGStatus
    Assert ($invalidPolicy.Health.Policy.Code -eq 'POLICY_INVALID' -and $invalidPolicy.Processes.Count -gt 0) 'Malformed policy leaves independent process readings available'
    Throws {& $module {Repair-LG}} 'Repair refuses invalid policy rather than overwriting it'
    & $module {Set-LGPolicy $true;Write-LGJson (Join-Path $script:Data 'last-run.json') ([pscustomobject]@{SessionState='Completed';TimestampUtc='invalid'})}
    $invalidSession=Get-LGStatus
    Assert ($invalidSession.Health.Session.Code -eq 'SESSION_RECORD_INVALID' -and $null -eq $invalidSession.LastSession) 'Malformed historical session cannot become a current success'
    $backupPath=Join-Path (Join-Path $temp 'v1\backups') $current.Manifest.Backup;$bytes=[IO.File]::ReadAllBytes($backupPath);[IO.File]::AppendAllText($backupPath,' ')
    $bad=Get-LGStatus
    Assert ($bad.Mode -eq 'RecoveryRequired' -and $bad.Health.Installation.State -eq 'Error' -and $bad.Startup.Count -eq 3) 'Damaged backup degrades installation health without hiding other sections'
    Throws {& $module {Repair-LG}} 'Repair refuses a damaged original backup'
    [IO.File]::WriteAllBytes($backupPath,$bytes)
    $id1=[Guid]::NewGuid().ToString('N');$id2=[Guid]::NewGuid().ToString('N');$requested=[DateTime]::UtcNow
    $recent=[pscustomobject]@{SessionId=$id1;Version='1.1.0';StartedAtUtc=$requested.ToString('o');SessionState='Completed'}
    Assert (-not (& $module {param($r,$id,$at)Test-LGNewSession $r $id $at} $recent $id1 $requested)) 'A recent old session cannot satisfy a new start'
    $recent.SessionId=$id2
    Assert (& $module {param($r,$id,$at)Test-LGNewSession $r $id $at} $recent $id1 $requested) 'A new matching-version session acknowledges the requested start'
    $recent.Version='1.0.0'
    Assert (-not (& $module {param($r,$id,$at)Test-LGNewSession $r $id $at} $recent $id1 $requested)) 'A previous runtime version cannot acknowledge the new start'
    $tracker=[LowGear.SessionTracker]::new();$a=[LowGear.Sample]::new();$a.Image='SGuard64.exe';$a.Running=$true;$a.Verified=$true;$a.ProcessId=1;$a.CreationUtc='first'
    $b=[LowGear.Sample]::new();$b.Image='SGuardSvc64.exe';$b.Running=$true;$b.Verified=$true;$b.ProcessId=2;$b.CreationUtc='first'
    Assert ($tracker.Observe(@($a,$b),$false) -eq 1 -and $tracker.Observe(@($a,$b),$false) -eq 2) 'Stable instances accumulate consecutive matching readings'
    $b.ProcessId=3
    Assert ($tracker.Observe(@($a,$b),$false) -eq 1) 'A changed PID resets consecutive verification'
    $b.CreationUtc='reused'
    Assert ($tracker.Observe(@($a,$b),$false) -eq 1) 'A reused PID with a new creation time resets verification'
    $b.Verified=$false
    Assert ($tracker.Observe(@($a,$b),$false) -eq 0) 'A failed reading resets consecutive verification'
    $safe=Get-LGStatus;$safe|Add-Member NoteProperty RawMessage 'PRIVATE_SENTINEL';$safe.LastSession=[pscustomobject]@{ProcessId=99999;Machine='PRIVATE_SENTINEL';Error='PRIVATE_SENTINEL'}
    $safe.Health.Task.Code='PRIVATE_SENTINEL/path';$diagnostic=Get-LGDiagnostic $safe|ConvertTo-Json -Depth 8
    Assert ($diagnostic -notmatch 'PRIVATE_SENTINEL|99999|ProcessId|Machine|RawMessage|[A-Z]:\\') 'Diagnostic whitelist removes messages, identifiers and malformed codes'
    $faultRoot=Join-Path $temp 'fault-session';[void][IO.Directory]::CreateDirectory($faultRoot)
    $workerPath=Join-Path $faultRoot 'LowGear.Worker.exe';Build-LGRuntime $workerPath
    $oldSession=[Guid]::NewGuid().ToString('N')
    [IO.File]::WriteAllText((Join-Path $faultRoot 'fault.json'),([pscustomobject]@{SessionId=$oldSession;Error='old failure'}|ConvertTo-Json))
    [IO.File]::WriteAllText((Join-Path $faultRoot 'policy.json'),'{"Schema":99,"BindLastCpu":false,"IntervalSeconds":3}')
    $worker=Start-Process -FilePath $workerPath -WindowStyle Hidden -ArgumentList ('--probe "'+$faultRoot+'" LowGearProbe-'+$id+'.exe 10') -PassThru
    try{Assert ($worker.WaitForExit(5000) -and $worker.ExitCode -eq 1) 'Runtime policy failure exits with failure rather than remaining resident'}finally{if(-not $worker.HasExited){$worker.Kill();[void]$worker.WaitForExit(5000)};$worker.Dispose()}
    $fault=Get-Content (Join-Path $faultRoot 'fault.json') -Raw|ConvertFrom-Json;$session=Get-Content (Join-Path $faultRoot 'last-run.json') -Raw|ConvertFrom-Json
    Assert ($session.SessionState -eq 'Failed' -and $session.SessionId -cne $oldSession -and $fault.SessionId -ceq $session.SessionId -and $session.EndedAtUtc) 'Failure and final report belong to the same new session'
    & $module {Restore-LG}|Out-Null
    Assert (-not (Test-Path (Join-Path $temp 'v1\active.json')) -and -not (& $module {Get-LGImage 'SGuard64.exe'}).ImageKeyExists) 'Full restoration after upgrades reaches earliest absent baseline'
    [pscustomobject]@{Status='Passed';Count=$checks.Count;Checks=$checks.ToArray()}|ConvertTo-Json -Depth 5
}finally{
    $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser,[Microsoft.Win32.RegistryView]::Registry64)
    try{if($id -cnotmatch '^[a-f0-9]{32}$' -or $registry -cne ('SOFTWARE\LowGearTests\'+$id)){throw 'Unsafe registry cleanup'};$base.DeleteSubKeyTree($registry,$false)}finally{$base.Dispose()}
    $expected=[IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('LowGear-upgrade-tests-'+$id)))
    if([IO.Path]::GetFullPath($temp) -cne $expected){throw 'Unsafe directory cleanup'}
    if([IO.Directory]::Exists($temp)){[IO.Directory]::Delete($temp,$true)}
    Remove-Module $module -Force
}
