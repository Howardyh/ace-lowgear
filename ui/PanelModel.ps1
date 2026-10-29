function Get-LGUiValue {
    param($Object,[string]$Name,$Default=$null)
    if($null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]){return $Object.$Name}
    $Default
}
function Get-LGPrimaryAction {
    param($Report)
    if($Report.Mode -in @('RecoveryRequired','WorkerUnavailable')){return [pscustomobject]@{Command='Diagnostics';Text='查看并处理问题'}}
    if(-not $Report.Installed){return [pscustomobject]@{Command='Install';Text='启用自动管理'}}
    try{if([version]$Report.InstalledVersion -lt [version]$Report.Version){return [pscustomobject]@{Command='Upgrade';Text='升级本机组件'}}}catch{}
    if($Report.Mode -eq 'Paused'){return [pscustomobject]@{Command='Resume';Text='恢复自动执行'}}
    [pscustomobject]@{Command='ApplyOnce';Text='立即应用一次'}
}
function Get-LGCpuLabel {
    param($Value)
    if($null -eq $Value){return '未读取'}
    switch([int]$Value){64 {'低'};32 {'正常'};default {[string]$Value}}
}
function Get-LGIoLabel {
    param($Value)
    if($null -eq $Value){return '未读取'}
    switch([int]$Value){0 {'非常低'};1 {'低'};2 {'正常'};default {[string]$Value}}
}
function Get-LGAffinityLabel {
    param($Process,$Report)
    if(-not $Process.Running){return '—'}
    if($Report.BindLastCpu -and (Get-LGUiValue $Process 'AffinityMatched' $false)){return 'CPU '+$Report.Topology.LastCpu}
    $mask=Get-LGUiValue $Process 'Affinity'
    if(-not $mask){return '未读取'}
    try{
        $bits=[Convert]::ToUInt64(([string]$mask).Replace('0x',''),16)
        if($bits -gt 0 -and ($bits -band ($bits-1)) -eq 0){$cpu=0;while($bits -gt 1){$bits=$bits -shr 1;$cpu++};return 'CPU '+$cpu}
    }catch{}
    '多个 CPU'
}
function Get-LGProcessGroups {
    param($Report,$Previous=@())
    foreach($image in @('SGuard64.exe','SGuardSvc64.exe','ACE-Service64.exe')){
        $instances=@($Report.Processes|Where-Object {$_.Image -ceq $image -and $_.Running})
        $old=@($Previous|Where-Object Image -CEQ $image)
        $expanded=$old.Count -gt 0 -and $old[0].Expanded
        $details=@(foreach($process in $instances){
            $errors=@(Get-LGUiValue $process 'Errors' @())
            $unknown=$null -eq $process.CpuClass -or $null -eq $process.IoPriority -or $null -eq (Get-LGUiValue $process 'EffectiveIoPriority')
            $tone=if($errors.Count -gt 0){'Error'}elseif($unknown){'Warning'}elseif($process.Verified){'Success'}else{'Warning'}
            $outcome=if($errors.Count -gt 0){'读取失败'}elseif($unknown){'读值未完整'}elseif($process.Verified){'已核验'}else{'未达到目标'}
            [pscustomobject]@{Pid='PID '+$process.ProcessId;Cpu=(Get-LGCpuLabel $process.CpuClass);Io=(Get-LGIoLabel $process.IoPriority);Affinity=(Get-LGAffinityLabel $process $Report);Tone=$tone;Outcome=$outcome
                Raw=('原始 CPU：'+$(if($null -eq $process.CpuClass){'未知'}else{$process.CpuClass})+' · I/O：'+$(if($null -eq $process.IoPriority){'未知'}else{$process.IoPriority})+' · 有效 I/O：'+(Get-LGIoLabel (Get-LGUiValue $process 'EffectiveIoPriority'))+' · 相关性：'+$(if($process.Affinity){$process.Affinity}else{'未知'}))
                ErrorText=if($errors.Count){$errors -join [Environment]::NewLine}else{'当前实例无查询错误。'}}
        })
        $tone='Neutral';$status='未运行 · 等待启动';$cpu='—';$io='—';$affinity='—'
        if($instances.Count){
            $good=@($details|Where-Object Tone -eq 'Success').Count
            $tone=if(@($details|Where-Object Tone -eq 'Error').Count){'Error'}elseif($good -eq $instances.Count){'Success'}else{'Warning'}
            $status=if($good -eq $instances.Count){'已核验'}else{$good.ToString()+'/'+$instances.Count+' 个实例达标'}
            foreach($field in @('Cpu','Io','Affinity')){$values=@($details|Select-Object -ExpandProperty $field -Unique);$value=if($values.Count -eq 1){$values[0]}else{'多个读值'};switch($field){Cpu {$cpu=$value};Io {$io=$value};Affinity {$affinity=$value}}}
        }
        [pscustomobject]@{Image=$image;Expanded=$expanded;Tone=$tone;Status=$status;InstanceLabel=if($instances.Count){$instances.Count.ToString()+' 个运行实例'}else{'等待正常启动'};Cpu=$cpu;Io=$io;Affinity=$affinity;Instances=$details;EmptyVisibility=if($instances.Count){'Collapsed'}else{'Visible'}}
    }
}
function Get-LGPanelArguments {
    param([string]$Entry,[string]$Command,[string]$Result,[string]$Progress,[bool]$BindLastCpu)
    $arguments='-NoLogo -NoProfile -STA -NonInteractive -ExecutionPolicy Bypass -File "'+$Entry+'" -Command '+$Command+' -ResultPath "'+$Result+'" -ProgressPath "'+$Progress+'"'
    if($Command -in @('Install','SetAffinity')){$arguments+=if($BindLastCpu){' -BindLastCpu'}else{' -ClearLastCpu'}}
    $arguments
}
function Get-LGDemoReport {
    $version=(Get-Content (Join-Path (Split-Path $PSScriptRoot -Parent) 'public-files.json') -Raw -Encoding UTF8|ConvertFrom-Json).Version
    $health=[ordered]@{};foreach($section in @('Installation','Policy','Startup','Task','Automation','Runtime','Session','Processes')){$health[$section]=[pscustomobject]@{State='Healthy';Code='OK';Message='检查通过'}}
    $report=[pscustomobject]@{Version=$version;InstalledVersion=$version;Mode='Ready';Installed=$true;BindLastCpu=$false;Topology=[pscustomobject]@{LogicalProcessors=24;Groups=1;LastCpu=23};FullCheckedUtc=[DateTime]::UtcNow.ToString('o');LastSession=[pscustomobject]@{SessionState='Completed';TimestampUtc=[DateTime]::UtcNow.ToString('o');ElapsedMilliseconds=11200};Startup=@();Processes=@();Health=[pscustomobject]$health}
    foreach($image in @('SGuard64.exe','SGuardSvc64.exe','ACE-Service64.exe')){
        $running=$image -ne 'ACE-Service64.exe'
        $report.Startup+=[pscustomobject]@{Image=$image;Configured=$true}
        $report.Processes+=[pscustomobject]@{Image=$image;Running=$running;ProcessId=1234;CpuClass=if($running){64}else{$null};IoPriority=if($running){0}else{$null};EffectiveIoPriority=if($running){0}else{$null};Affinity=if($running){'0xFFFFFF'}else{$null};AffinityMatched=$true;Verified=$running;Errors=@()}
    }
    $report
}
