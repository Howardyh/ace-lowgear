function Get-LGBaseline {
    $states=@($script:Images | ForEach-Object {Get-LGImage $_})
    if(@($states | Where-Object HasFilters).Count -gt 0){throw '存在 IFEO 路径过滤规则，已停止自动安装。'}
    $legacy=Get-LGTaskSnapshot 'ACE-LowGear-PriorityGuard' 'ACE LowGear Priority Guard v1'
    $origin='Fresh'
    $registry=$states
    $legacyActive=Join-Path $script:Common 'active.json'
    $retiredPath=Join-Path $script:Common 'retired-by-lowgear-1.json'
    $legacyRetired=Test-Path -LiteralPath $retiredPath
    if($legacyRetired -and (Read-LGJson $retiredPath).Machine -cne (Get-LGToken)){throw '旧版迁移标记不属于当前 Windows 安装。'}
    if($legacyRetired -and $legacy.Exists){throw '旧版任务被重新启用，请先检查版本冲突。'}
    if((Test-Path -LiteralPath $legacyActive) -and -not $legacyRetired){
        $old=Read-LGJson $legacyActive
        if($old.SchemaVersion -ne 1 -or $old.Phase -ne 'Applied' -or $old.MachineToken -cne (Get-LGToken -Legacy) -or
            $old.BackupFile -cnotmatch '^original-[a-f0-9]{32}\.json$'){throw '旧版恢复记录不完整或不属于本机。'}
        $oldPath=Join-Path (Join-Path $script:Common 'backups') $old.BackupFile
        if((Get-FileHash -LiteralPath $oldPath -Algorithm SHA256).Hash -cne $old.BackupSha256){throw '旧版原始备份完整性核验失败。'}
        $saved=Read-LGJson $oldPath
        if($saved.MachineToken -cne $old.MachineToken -or ($saved.Originals.Image -join '|') -cne ($script:Images -join '|')){throw '旧版备份的目标不匹配。'}
        if(@($states | Where-Object {-not (Test-LGConfigured $_)}).Count -gt 0){throw '旧版设置已被后续修改，请先检查差异。'}
        $registry=@($saved.Originals)
        $origin='MigratedOriginalBaseline'
    }
    elseif($legacy.Exists){throw '旧版任务仍存在但缺少原始恢复记录。'}
    [pscustomobject]@{Registry=$registry;Before=$states;LegacyTask=$legacy;Origin=$origin}
}
function Set-LGPolicy {
    param([bool]$Last)
    Initialize-LGNative
    if($Last -and $null -eq [LowGear.Runtime]::GetTopology().LastCpu){throw '当前处理器拓扑不支持单个最后 CPU 绑定；优先级功能仍可使用。'}
    Write-LGJson (Join-Path $script:Data 'policy.json') ([pscustomobject]@{Schema=1;BindLastCpu=$Last;IntervalSeconds=3})
}
function Install-LG {
    param([bool]$Last)
    $existing=Read-LGActive
    if($null -ne $existing){
        if($existing.Manifest.Phase -notin @('Active','Paused')){throw '发现未完成的事务，请使用完整恢复。'}
        $states=@($script:Images | ForEach-Object {Get-LGImage $_})
        if(@($states | Where-Object {-not(Test-LGConfigured $_)}).Count -gt 0){throw '启动值发生后续修改，请先检查。'}
        Set-LGPolicy $Last
        Resume-LG
        return '已启用；原始备份保持不变。'
    }
    $automation=Get-LGAutomation
    if($null -ne $automation.Filter -or $null -ne $automation.Consumer){throw '事件订阅已存在但没有活动恢复记录，已停止覆盖。'}
    $previousTask=Get-LGTaskSnapshot
    if($previousTask.Exists){throw '任务存在但没有本机恢复记录，拒绝覆盖。'}
    $baseline=Get-LGBaseline
    Set-LGPolicy $Last
    $probe=Test-LGStartup
    $current=@($script:Images | ForEach-Object {Get-LGImage $_})
    if(($baseline.Before | ConvertTo-Json -Depth 15 -Compress) -cne ($current | ConvertTo-Json -Depth 15 -Compress)){throw '自检期间设置发生变化，已停止。'}
    $runtimeFolder='app-'+$script:Version+'-'+[Guid]::NewGuid().ToString('N')
    $runtimeDirectory=Join-Path $script:Data $runtimeFolder
    [void][IO.Directory]::CreateDirectory($runtimeDirectory)
    $exe=Join-Path $runtimeDirectory 'LowGear.Worker.exe'
    Build-LGRuntime $exe
    $backupName='original-'+[Guid]::NewGuid().ToString('N')+'.json'
    $backupPath=Join-Path (Join-Path $script:Data 'backups') $backupName
    $machine=Get-LGToken
    Write-LGJson $backupPath ([pscustomobject]@{Schema=1;Machine=$machine;Origin=$baseline.Origin;Registry=$baseline.Registry;LegacyTask=$baseline.LegacyTask;PriorTask=$previousTask})
    $manifest=[pscustomobject]@{
        Schema=1;Machine=$machine;Version=$script:Version;Phase='Installing';Runtime=$runtimeFolder
        RuntimeHash=(Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash
        Backup=$backupName;BackupHash=(Get-FileHash -LiteralPath $backupPath -Algorithm SHA256).Hash
    }
    $activePath=Join-Path $script:Data 'active.json'
    Write-LGJson $activePath $manifest
    try {
        if($baseline.LegacyTask.Exists){Remove-LGTask 'ACE-LowGear-PriorityGuard' 'ACE LowGear Priority Guard v1'}
        foreach($image in $script:Images){Set-LGImage $image}
        if(@($script:Images | ForEach-Object {Get-LGImage $_} | Where-Object {-not(Test-LGConfigured $_)}).Count -gt 0){throw '启动规则写入后核验失败。'}
        Register-LGTask $exe
        Wait-LGWorker
        $manifest.Phase='Active'
        Write-LGJson $activePath $manifest
    }
    catch {
        $failure=$_
        $errors=[Collections.Generic.List[string]]::new()
        try{Remove-LGAutomation;Restore-LGTask $previousTask}catch{$errors.Add($_.Exception.Message)}
        foreach($original in $baseline.Before){try{Restore-LGImage $original}catch{$errors.Add($_.Exception.Message)}}
        try{Restore-LGTask $baseline.LegacyTask 'ACE LowGear Priority Guard v1'}catch{$errors.Add($_.Exception.Message)}
        if($errors.Count -eq 0){
            [IO.File]::Move($activePath,(Join-Path (Join-Path $script:Data 'backups') ('rolled-back-'+[Guid]::NewGuid().ToString('N')+'.json')))
        }else{$manifest.Phase='RecoveryRequired';Write-LGJson $activePath $manifest;throw ('迁移失败且回滚尚未完成：'+($errors -join '; '))}
        throw $failure
    }
    if($baseline.Origin -eq 'MigratedOriginalBaseline'){
        Write-LGJson (Join-Path $script:Common 'retired-by-lowgear-1.json') ([pscustomobject]@{Product='ACE LowGear';Version=$script:Version;Machine=$machine;OriginalBackupImported=$true})
    }
    '启动自动执行已启用；每次 ACE 启动后限时设置、回读，完成即退出。'
}
function Pause-LG {
    $state=Read-LGActive
    if($null -eq $state){return '尚未安装。'}
    if($state.Manifest.Phase -notin @('Active','Paused')){throw '事务尚未完成，请先完整恢复，不能改为暂停状态。'}
    [void](Get-LGTaskSnapshot)
    $task=Get-LGTask
    Remove-LGAutomation
    if($null -ne $task){$task.Enabled=$false;$task.Stop(0)}
    $state.Manifest.Phase='Paused'
    Write-LGJson (Join-Path $script:Data 'active.json') $state.Manifest
    '自动触发已暂停；启动规则保留，不会再自动运行设置程序。'
}
function Resume-LG {
    $state=Read-LGActive
    if($null -eq $state -or $state.Manifest.Phase -notin @('Paused','Active')){throw '请先启用自动管理，或恢复未完成的事务。'}
    $exe=Join-Path (Join-Path $script:Data $state.Manifest.Runtime) 'LowGear.Worker.exe'
    if((Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash -cne $state.Manifest.RuntimeHash){throw '后台程序完整性核验失败。'}
    $task=Get-LGTask
    if($null -eq $task){Register-LGTask $exe}else{[void](Get-LGTaskSnapshot);Register-LGAutomation;$task.Enabled=$true;[void]$task.Run($null)}
    Wait-LGWorker
    $state.Manifest.Phase='Active'
    Write-LGJson (Join-Path $script:Data 'active.json') $state.Manifest
    '启动事件触发已恢复；本次执行完成后程序会退出。'
}
function Restore-LG {
    $state=Read-LGActive
    if($null -eq $state){return '无活动安装记录。'}
    Assert-LGRestore $state.Original.Registry
    [void](Get-LGTaskSnapshot)
    # Stop before registry restoration. Keep a journal until every value verifies.
    $state.Manifest.Phase='Restoring'
    Write-LGJson (Join-Path $script:Data 'active.json') $state.Manifest
    Remove-LGAutomation
    Remove-LGTask
    foreach($original in $state.Original.Registry){Restore-LGImage $original}
    [IO.File]::Move((Join-Path $script:Data 'active.json'),(Join-Path (Join-Path $script:Data 'backups') ('restored-'+[Guid]::NewGuid().ToString('N')+'.json')))
    '已移除后台并恢复最初的启动值；备份保留。当前进程在正常重启后使用原设置。'
}
function Get-LGStatus {
    Initialize-LGNative
    $state=Read-LGActive
    $policy=[pscustomobject]@{BindLastCpu=$false;IntervalSeconds=3}
    if($null -ne $state){$policy=Read-LGJson (Join-Path $script:Data 'policy.json')}
    $task=Get-LGTask
    $beat=$null
    if(Test-Path -LiteralPath (Join-Path $script:Data 'last-run.json')){$beat=Read-LGJson (Join-Path $script:Data 'last-run.json')}
    $fresh=$false
    if($null -ne $beat){$fresh=([DateTime]::UtcNow-[DateTime]::Parse($beat.TimestampUtc).ToUniversalTime()).TotalSeconds -lt 45}
    $running=$null -ne $task -and $task.State -eq 4
    $automation=Get-LGAutomation
    $registry=@($script:Images | ForEach-Object { $s=Get-LGImage $_; [pscustomobject]@{Image=$_;Configured=(Test-LGConfigured $s)} })
    $processes=@([LowGear.Runtime]::Scan($false,[bool]$policy.BindLastCpu,$null))
    $installed=$null -ne $state
    $mode=if(-not $installed){'NotInstalled'}elseif($state.Manifest.Phase -eq 'Paused'){'Paused'}elseif($state.Manifest.Phase -ne 'Active'){'RecoveryRequired'}elseif($null -eq $task -or -not $task.Enabled -or -not $automation.Ready){'WorkerUnavailable'}elseif($running){'Running'}else{'Ready'}
    $runtimeGood=$false
    if($installed){
        $exe=Join-Path (Join-Path $script:Data $state.Manifest.Runtime) 'LowGear.Worker.exe'
        $runtimeGood=(Test-Path -LiteralPath $exe) -and (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash -ceq $state.Manifest.RuntimeHash
        if(-not $runtimeGood){$mode='RecoveryRequired'}
    }
    [pscustomobject]@{
        Product='ACE LowGear';Version=$script:Version;Mode=$mode;TimestampUtc=[DateTime]::UtcNow.ToString('o')
        Installed=$installed;SessionRunning=$running;AutomaticRegistered=$automation.Ready;SessionRecent=$fresh;RuntimeIntegrity=$runtimeGood
        BindLastCpu=[bool]$policy.BindLastCpu;Topology=[LowGear.Runtime]::GetTopology()
        Startup=$registry;Processes=$processes;LastSession=$beat
    }
}
function Get-LGSummary {
    param($Report)
    $running=@($Report.Processes | Where-Object Running)
    $verified=@($running | Where-Object Verified)
    if($running.Count -eq 0){return '当前没有 ACE 进程，等待正常启动后核验。'}
    if($verified.Count -eq $running.Count){return ('当前运行的 '+$running.Count+' 个实例均符合目标。')}
    '存在未达标或无法读取的实例，请查看各项状态和原因。'
}
function Invoke-LGCommand {
    param([ValidateSet('Install','Status','ApplyOnce','LastCpu','Pause','Resume','Restore','SelfTest','SetAffinity')][string]$Command='Status',[bool]$Last=$false)
    Initialize-LGNative
    $lock=$null
    try {
        if($Command -ne 'Status'){
            Initialize-LGData
            $lock=[IO.File]::Open((Join-Path $script:Common 'operation.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        }
        $message='检查完成。';$detail=$null
        switch($Command){
            'Install' {$message=Install-LG $Last}
            'Pause' {$message=Pause-LG}
            'Resume' {$message=Resume-LG}
            'Restore' {$message=Restore-LG}
            'ApplyOnce' {$detail=@([LowGear.Runtime]::Scan($true,$false,$null));$message='已尝试一次性应用低 CPU、非常低 I/O，并回读核验。'}
            'LastCpu' {
                if($null -eq [LowGear.Runtime]::GetTopology().LastCpu){throw '当前处理器组不支持最后 CPU 绑定。'}
                $detail=@([LowGear.Runtime]::Scan($true,$true,$null));$message='已尝试一次性应用低优先级并绑定最后一个逻辑 CPU。'
            }
            'SetAffinity' {
                $state=Read-LGActive
                if($null -eq $state -or $state.Manifest.Phase -notin @('Active','Paused')){throw '请先完成自动管理安装或恢复未完成的事务。'}
                Set-LGPolicy $Last
                $message=if($Last){'已启用每次启动时绑定最后 CPU。'}else{'已停止启动时绑定；已有进程的相关性保持到正常重启。'}
            }
            'SelfTest' {$detail=Test-LGStartup;$message='本机启动规则自检通过，临时进程和测试键已清理。'}
        }
        $report=Get-LGStatus
        [pscustomobject]@{Success=$true;Message=$message;Detail=$detail;Report=$report}
    }
    finally{if($null -ne $lock){$lock.Dispose()}}
}
