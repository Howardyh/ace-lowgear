function Get-LGPreflight {
    param($Report)
    $checks=[Collections.Generic.List[object]]::new()
    foreach($item in @(Test-LGSourceFiles $script:Project)){$checks.Add($item)}
    $checks.Add([pscustomobject]@{Name='System';State=if([Environment]::Is64BitProcess -and [Environment]::OSVersion.Version.Major -ge 10){'Healthy'}else{'Error'};Code=if([Environment]::Is64BitProcess -and [Environment]::OSVersion.Version.Major -ge 10){'OK'}else{'SYSTEM_UNSUPPORTED'};Message='需要系统自带的 64 位 Windows PowerShell 5.1 与 .NET Framework。'})
    foreach($name in @('Installation','Policy','Startup','Task','Automation','Runtime')){
        $item=$Report.Health.$name;$blocked=$item.State -in @('Error','Conflict','Unknown')
        if($Report.Installed -and $name -in @('Startup','Task','Automation','Runtime') -and $item.State -ne 'Healthy'){$blocked=$true}
        if(-not $Report.Installed -and $name -eq 'Automation' -and $item.State -ne 'Healthy'){$blocked=$true}
        $checks.Add([pscustomobject]@{Name=$name;State=if($blocked){'Error'}elseif(-not $Report.Installed -and $name -in @('Startup','Task','Runtime')){'Healthy'}else{$item.State};Code=$item.Code;Message=if(-not $Report.Installed -and $name -in @('Startup','Task','Runtime') -and -not $blocked){'首次启用时将建立此项配置。'}else{$item.Message}})
    }
    $migration=$false
    if(-not $Report.Installed -and @($checks|Where-Object State -eq 'Error').Count -eq 0){
        try{$baseline=Get-LGBaseline;$migration=$baseline.Origin -eq 'MigratedOriginalBaseline'
            $checks.Add([pscustomobject]@{Name='Baseline';State='Healthy';Code=if($migration){'LEGACY_MIGRATION'}else{'OK'};Message=if($migration){'检测到可迁移旧版；安装时校验并保留最早原始备份，成功后移除旧常驻任务。'}else{'确认安装后保存首次修改前的原始设置。'}})
        }catch{$checks.Add([pscustomobject]@{Name='Baseline';State='Error';Code='BASELINE_CONFLICT';Message='旧版资料或现有配置存在冲突，请先在诊断中检查，不会自动覆盖。'})}
    }
    [pscustomobject]@{Passed=(@($checks|Where-Object State -eq 'Error').Count -eq 0);Migration=$migration;Checks=$checks.ToArray()}
}
