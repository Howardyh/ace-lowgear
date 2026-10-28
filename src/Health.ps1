function New-LGHealth {
    param([string]$State='Unknown',[string]$Code='NOT_CHECKED',[string]$Message='尚未检查。')
    [pscustomobject]@{State=$State;Code=$Code;Message=$Message}
}
function Get-LGExceptionCode {
    param($ErrorRecord,[string]$Fallback='OPERATION_FAILED')
    $error=$ErrorRecord.Exception
    while($null -ne $error){if($error.Data.Contains('LowGearCode')){return [string]$error.Data['LowGearCode']};$error=$error.InnerException}
    $Fallback
}
function Get-LGRuntimePath {param($State) Join-Path (Join-Path $script:Data $State.Manifest.Runtime) 'LowGear.Worker.exe'}
function Read-LGPolicy {
    $value=Read-LGJson (Join-Path $script:Data 'policy.json')
    if((Get-LGProperty $value 'Schema') -ne 1 -or (Get-LGProperty $value 'BindLastCpu') -isnot [bool] -or
       (Get-LGProperty $value 'IntervalSeconds') -isnot [int] -or $value.IntervalSeconds -lt 2 -or $value.IntervalSeconds -gt 10){Throw-LGError 'POLICY_INVALID' '策略文件格式无效，请先检查。'}
    $value
}
function Get-LGTaskHealth {
    param($State)
    $task=Get-LGTask
    if($null -eq $task){return New-LGHealth 'Missing' 'TASK_MISSING' '自动执行任务缺失。'}
    $definition=$task.Definition
    if($definition.RegistrationInfo.Source -cne $script:TaskSource){return New-LGHealth 'Conflict' 'TASK_FOREIGN' '同名任务归属不明，不能覆盖。'}
    if($null -eq $State){return New-LGHealth 'Conflict' 'TASK_WITHOUT_STATE' '存在任务但没有安装记录。'}
    $expected=Get-LGRuntimePath $State
    $action=if($definition.Actions.Count -eq 1){$definition.Actions.Item(1)}else{$null}
    if($null -eq $action -or $action.Path -ine $expected -or $action.Arguments -cne ('--once "'+$script:Data+'"') -or $action.WorkingDirectory -ine $script:Data -or
       $definition.Principal.UserId -notin @('SYSTEM','S-1-5-18') -or $definition.Principal.RunLevel -ne 1 -or $definition.Triggers.Count -ne 0 -or
       $definition.Settings.ExecutionTimeLimit -ne 'PT2M' -or $definition.Settings.MultipleInstances -ne 2 -or $definition.Settings.RestartCount -ne 0){
        return New-LGHealth 'Conflict' 'TASK_CHANGED' '任务执行路径、身份或执行设置发生变化，已停止覆盖。'
    }
    $shouldEnable=$State.Manifest.Phase -eq 'Active'
    if([bool]$task.Enabled -ne $shouldEnable){return New-LGHealth 'Warning' 'TASK_ENABLE_MISMATCH' '任务启用状态与安装记录不一致。'}
    New-LGHealth 'Healthy' 'OK' '自动执行任务正常。'
}
function Assert-LGManaged {
    param($State,[switch]$AllowMissing)
    if($State.Manifest.Phase -notin @('Active','Paused')){Throw-LGError 'TRANSACTION_PENDING' '事务尚未完成，请先恢复未完成的升级或完整恢复。'}
    [void](Read-LGPolicy)
    $path=Get-LGRuntimePath $State
    if(-not(Test-Path -LiteralPath $path) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne $State.Manifest.RuntimeHash){Throw-LGError 'RUNTIME_HASH_MISMATCH' '执行程序缺失或完整性不匹配，已停止覆盖。'}
    foreach($image in $script:Images){if(-not(Test-LGConfigured (Get-LGImage $image))){Throw-LGError 'STARTUP_CHANGED' '启动规则发生后续修改，请先检查差异。'}}
    $health=Get-LGTaskHealth $State
    if($health.State -eq 'Conflict' -or ($health.State -eq 'Missing' -and -not $AllowMissing)){Throw-LGError $health.Code $health.Message}
    [void](Get-LGAutomation)
}
function Get-LGStatus {
    param([switch]$Quick)
    Initialize-LGNative
    $health=[ordered]@{};$state=$null;$policy=[pscustomobject]@{BindLastCpu=$false;IntervalSeconds=3};$registry=@();$task=$null;$automation=$null;$beat=$null
    if($Quick -and $null -ne $script:FullStatusCache){
        $cached=$script:FullStatusCache
        $health=Get-LGProperty $cached 'Health'
        $policy.BindLastCpu=$cached.BindLastCpu;$registry=$cached.Startup
        $installed=$cached.Installed;$installedVersion=$cached.InstalledVersion;$mode=$cached.Mode;$runtimeGood=$cached.RuntimeIntegrity
        $automatic=$cached.AutomaticRegistered;$checked=$cached.FullCheckedUtc
    }else{
        try{$state=Read-LGActive;$health.Installation=New-LGHealth 'Healthy' 'OK' '安装记录正常。'}catch{$health.Installation=New-LGHealth 'Error' (Get-LGExceptionCode $_ 'STATE_INVALID') '安装记录或备份需要检查。'}
        $installed=$null -ne $state;$installedVersion=if($installed){$state.Manifest.Version}else{$null}
        try{if($installed){$policy=Read-LGPolicy};$health.Policy=New-LGHealth 'Healthy' 'OK' '策略正常。'}catch{$policy=[pscustomobject]@{BindLastCpu=$false;IntervalSeconds=3};$health.Policy=New-LGHealth 'Error' 'POLICY_INVALID' '策略文件需要检查。'}
        try{$registry=@($script:Images|ForEach-Object{$s=Get-LGImage $_;[pscustomobject]@{Image=$_;Configured=(Test-LGConfigured $s)}});$health.Startup=if(@($registry|Where-Object {-not $_.Configured}).Count -gt 0){New-LGHealth 'Warning' 'STARTUP_NOT_CONFIGURED' '部分启动规则尚未配置。'}else{New-LGHealth 'Healthy' 'OK' '启动规则正常。'}}catch{$health.Startup=New-LGHealth 'Error' 'STARTUP_QUERY_FAILED' '无法读取启动规则。'}
        try{$health.Task=Get-LGTaskHealth $state;$task=Get-LGTask}catch{$health.Task=New-LGHealth 'Error' 'TASK_QUERY_FAILED' '无法读取自动执行任务。'}
        try{$automation=Get-LGAutomation;$expected=$installed -and $state.Manifest.Phase -eq 'Active';$isEmpty=$null -eq $automation.Filter -and $null -eq $automation.Consumer
            $health.Automation=if(($expected -and $automation.Ready) -or (-not $expected -and $isEmpty)){New-LGHealth 'Healthy' 'OK' '事件配置符合当前状态。'}else{New-LGHealth 'Warning' 'EVENT_INCOMPLETE' '事件配置与当前状态不一致。'}
        }catch{$health.Automation=New-LGHealth 'Conflict' 'EVENT_CONFLICT' '事件配置无法确认归属或查询失败。'}
        $runtimeGood=$false
        try{if($installed){$exe=Get-LGRuntimePath $state;$runtimeGood=(Test-Path -LiteralPath $exe) -and (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash -ceq $state.Manifest.RuntimeHash};$health.Runtime=if($runtimeGood){New-LGHealth 'Healthy' 'OK' '执行文件完整性正常。'}elseif($installed){New-LGHealth 'Error' 'RUNTIME_HASH_MISMATCH' '执行文件缺失或已改变。'}else{New-LGHealth 'Missing' 'NOT_INSTALLED' '尚未安装本机执行组件。'}}catch{$health.Runtime=New-LGHealth 'Error' 'RUNTIME_QUERY_FAILED' '执行文件无法读取。'}
        $automatic=$null -ne $automation -and $automation.Ready
        $mode=if($health.Installation.State -eq 'Error'){'RecoveryRequired'}elseif(-not $installed){'NotInstalled'}elseif($state.Manifest.Phase -notin @('Active','Paused')){'RecoveryRequired'}elseif(-not $runtimeGood -or $health.Policy.State -eq 'Error'){'RecoveryRequired'}elseif($state.Manifest.Phase -eq 'Paused'){'Paused'}elseif($health.Task.State -ne 'Healthy' -or $health.Automation.State -ne 'Healthy' -or $health.Startup.State -ne 'Healthy'){'WorkerUnavailable'}else{'Ready'}
        $checked=[DateTime]::UtcNow.ToString('o')
    }
    try{if($null -eq $task){$task=Get-LGTask};$running=$null -ne $task -and $task.State -eq 4}catch{$running=$false}
    if($mode -in @('Ready','Running')){$mode=if($running){'Running'}else{'Ready'}}
    try{if(Test-Path -LiteralPath (Join-Path $script:Data 'last-run.json')){
            $beat=Read-LGJson (Join-Path $script:Data 'last-run.json');$at=[DateTime]::MinValue
            if((Get-LGProperty $beat 'SessionState') -notin @('Starting','Verifying','Completed','NoTargets','Incomplete','Failed') -or
               -not [DateTime]::TryParse([string](Get-LGProperty $beat 'TimestampUtc'),[ref]$at)){throw 'Invalid session'}
        };$health.Session=New-LGHealth 'Healthy' 'OK' '会话记录已读取。'
    }catch{$beat=$null;$health.Session=New-LGHealth 'Warning' 'SESSION_RECORD_INVALID' '最近会话记录无法读取。'}
    if($null -ne $beat -and (Get-LGProperty $beat 'SessionState') -eq 'Failed'){$health.Session=New-LGHealth 'Error' (Get-LGProperty $beat 'ErrorCode' 'RUNTIME_FAILURE') '最近一次执行失败。'}
    if($null -ne $beat -and -not $running -and (Get-LGProperty $beat 'SessionState') -in @('Starting','Verifying')){$health.Session=New-LGHealth 'Warning' 'SESSION_INTERRUPTED' '最近会话没有结束记录，任务当前已退出。'}
    try{$processes=@([LowGear.Runtime]::Scan($false,[bool]$policy.BindLastCpu,$null));$active=@($processes|Where-Object Running)
        $health.Processes=if($active.Count -eq 0){New-LGHealth 'Waiting' 'NO_TARGETS' '当前没有运行目标。'}elseif(@($active|Where-Object {-not $_.Verified}).Count -gt 0){New-LGHealth 'Warning' 'LIVE_NOT_VERIFIED' '部分运行实例未达标或无法读取。'}else{New-LGHealth 'Healthy' 'OK' '当前运行实例已核验。'}
    }catch{$processes=@();$health.Processes=New-LGHealth 'Error' 'PROCESS_QUERY_FAILED' '无法查询进程状态。'}
    $fresh=$false;try{if($null -ne $beat){$fresh=([DateTime]::UtcNow-[DateTime]::Parse($beat.TimestampUtc).ToUniversalTime()).TotalSeconds -lt 45}}catch{}
    $report=[pscustomobject]@{Product='ACE LowGear';Version=$script:Version;InstalledVersion=$installedVersion;Mode=$mode;TimestampUtc=[DateTime]::UtcNow.ToString('o');FullCheckedUtc=$checked
        Installed=$installed;SessionRunning=$running;AutomaticRegistered=$automatic;SessionRecent=$fresh;RuntimeIntegrity=$runtimeGood
        BindLastCpu=[bool]$policy.BindLastCpu;Topology=[LowGear.Runtime]::GetTopology();Startup=$registry;Processes=$processes;LastSession=$beat;Health=[pscustomobject]$health}
    if(-not $Quick){$script:FullStatusCache=$report}
    $report
}
function Get-LGDiagnostic {
    param($Report)
    if($null -eq $Report){$Report=Get-LGStatus}
    $sections=[ordered]@{}
    foreach($name in @('Installation','Policy','Startup','Task','Automation','Runtime','Session','Processes')){
        $item=Get-LGProperty $Report.Health $name
        $status=[string](Get-LGProperty $item 'State' 'Unknown');if($status -notin @('Unknown','Healthy','Missing','Waiting','Warning','Conflict','Error')){$status='Unknown'}
        $code=[string](Get-LGProperty $item 'Code' 'NOT_CHECKED');if($code -cnotmatch '^[A-Z][A-Z0-9_]{0,63}$'){$code='UNKNOWN_ERROR'}
        $sections[$name]=[pscustomobject]@{State=$status;Code=$code}
    }
    # Explicit fields only. Never serialize the full report or raw error messages here.
    $installed=[string]$Report.InstalledVersion;if($installed -cnotmatch '^1\.\d+\.\d+$'){$installed=$null}
    $mode=if($Report.Mode -in @('Ready','Running','Paused','NotInstalled','RecoveryRequired','WorkerUnavailable')){$Report.Mode}else{'Unknown'}
    [pscustomobject]@{Product='ACE LowGear';Version=$script:Version;InstalledVersion=$installed;WindowsVersion=[Environment]::OSVersion.Version.ToString()
        LogicalProcessors=[uint32]$Report.Topology.LogicalProcessors;ProcessorGroups=[uint16]$Report.Topology.Groups;Mode=$mode;BindLastCpu=[bool]$Report.BindLastCpu;Health=[pscustomobject]$sections}
}
