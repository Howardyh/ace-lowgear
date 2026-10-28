function Initialize-LGNative {
    if(-not('LowGear.Runtime' -as [type])) {
        Add-Type -TypeDefinition (Get-LGRuntimeSource) -ReferencedAssemblies 'System.Web.Extensions.dll' -ErrorAction Stop
    }
    if([LowGear.Runtime]::Version -cne $script:Version){Throw-LGError 'HOST_VERSION_MISMATCH' '当前窗口已加载其他版本，请关闭后重新打开新版入口。'}
}
function Get-LGRuntimeSource {
    param([string]$Version=$script:Version)
    if($Version -cnotmatch '^1\.\d+\.\d+$'){throw '运行版本格式无效。'}
    [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Runtime.cs')).Replace('__LOWGEAR_VERSION__',$Version)
}
function Build-LGRuntime {
    param([string]$Destination,[string]$Source,[string]$ProductVersion=$script:Version)
    if(-not $Source){$Source=Get-LGRuntimeSource $ProductVersion}
    if(Test-Path -LiteralPath $Destination){throw '拒绝覆盖已有运行程序。'}
    Add-Type -AssemblyName System.Web.Extensions
    $provider=[Microsoft.CSharp.CSharpCodeProvider]::new()
    $options=[CodeDom.Compiler.CompilerParameters]::new()
    $options.GenerateExecutable=$true
    $options.GenerateInMemory=$false
    $options.OutputAssembly=$Destination
    $options.CompilerOptions='/target:winexe /platform:x64 /optimize+'
    [void]$options.ReferencedAssemblies.Add('System.dll')
    [void]$options.ReferencedAssemblies.Add('System.Core.dll')
    [void]$options.ReferencedAssemblies.Add([System.Web.Script.Serialization.JavaScriptSerializer].Assembly.Location)
    try {
        $compiled=$provider.CompileAssemblyFromSource($options,$Source)
        if($compiled.Errors.HasErrors){throw (($compiled.Errors | ForEach-Object {$_.ErrorText}) -join '; ')}
    }
    finally{$provider.Dispose()}
}
function Get-LGService {
    $service=New-Object -ComObject 'Schedule.Service'
    $service.Connect()
    $service
}
function Get-LGTask {
    param([string]$Name=$script:TaskName)
    try {(Get-LGService).GetFolder('\').GetTask($Name)}
    catch {
        $e=$_.Exception;$missing=$false
        while($null -ne $e){if($e.HResult -eq -2147024894){$missing=$true};$e=$e.InnerException}
        if(-not $missing){throw}
        $null
    }
}
function Get-LGTaskSnapshot {
    param([string]$Name=$script:TaskName,[string]$Source=$script:TaskSource)
    $task=Get-LGTask $Name
    if($null -eq $task){return [pscustomobject]@{Name=$Name;Exists=$false;Xml=$null;WasRunning=$false}}
    if($task.Definition.RegistrationInfo.Source -cne $Source){throw ('同名任务不属于本工具，已停止：'+$Name)}
    [pscustomobject]@{Name=$Name;Exists=$true;Xml=$task.Xml;WasRunning=($task.State -eq 4)}
}
function Remove-LGTask {
    param([string]$Name=$script:TaskName,[string]$Source=$script:TaskSource)
    $snapshot=Get-LGTaskSnapshot $Name $Source
    if($snapshot.Exists){
        $task=Get-LGTask $Name
        $task.Enabled=$false
        $task.Stop(0)
        (Get-LGService).GetFolder('\').DeleteTask($Name,0)
    }
}
function Restore-LGTask {
    param($Snapshot,[string]$Source=$script:TaskSource)
    Remove-LGTask $Snapshot.Name $Source
    if($Snapshot.Exists){
        $task=(Get-LGService).GetFolder('\').RegisterTask($Snapshot.Name,$Snapshot.Xml,2,'SYSTEM',$null,5)
        if($Snapshot.WasRunning){[void]$task.Run($null)}
    }
}
function Register-LGTask {
    param([string]$Runtime,[switch]$SkipImmediate,[string]$ProbeImage,[bool]$Enabled=$true)
    if($ProbeImage -and $ProbeImage -cnotmatch '^LowGearProbe-[a-f0-9]{32}\.exe$'){throw '任务测试程序名无效。'}
    [void](Get-LGTaskSnapshot)
    $service=Get-LGService
    $definition=$service.NewTask(0)
    $definition.RegistrationInfo.Source=$script:TaskSource
    $definition.RegistrationInfo.Author='ACE LowGear'
    $definition.RegistrationInfo.Description='Apply low CPU and very low I/O once per ACE startup, verify, then exit.'
    $definition.Principal.UserId='SYSTEM'
    $definition.Principal.RunLevel=1
    $definition.Settings.Enabled=$Enabled
    $definition.Settings.StartWhenAvailable=$true
    $definition.Settings.DisallowStartIfOnBatteries=$false
    $definition.Settings.StopIfGoingOnBatteries=$false
    $definition.Settings.ExecutionTimeLimit='PT2M'
    $definition.Settings.MultipleInstances=2
    $definition.Settings.RestartCount=0
    $definition.Settings.Priority=7
    $action=$definition.Actions.Create(0)
    $action.Path=$Runtime
    $action.Arguments=if($ProbeImage){'--probe "'+$script:Data+'" '+$ProbeImage+' 20'}else{'--once "'+$script:Data+'"'}
    $action.WorkingDirectory=$script:Data
    $task=$service.GetFolder('\').RegisterTaskDefinition($script:TaskName,$definition,6,'SYSTEM',$null,5)
    if($Enabled){Register-LGAutomation}
    if($Enabled -and -not $SkipImmediate){Start-LGTaskSession $task}
}
function Start-LGTaskSession {
    param($Task)
    $before=$null;$path=Join-Path $script:Data 'last-run.json'
    if(Test-Path -LiteralPath $path){try{$before=Read-LGJson $path}catch{}}
    $script:BeforeSessionId=Get-LGProperty $before 'SessionId' ''
    $script:JoinSessionId=''
    $script:SessionRequestedUtc=[DateTime]::UtcNow
    if($Task.State -eq 4 -and (Test-LGLiveSession $Task $before)){$script:JoinSessionId=$before.SessionId;return}
    [void]$Task.Run($null)
}
function Test-LGLiveSession {
    param($Task,$Report)
    if((Get-LGProperty $Report 'SessionId' '') -cnotmatch '^[a-f0-9]{32}$' -or (Get-LGProperty $Report 'Version') -cne $script:Version -or
       (Get-LGProperty $Report 'SessionState') -notin @('Starting','Verifying') -or $Task.State -ne 4){return $false}
    try{
        $process=Get-Process -Id $Report.WorkerId -ErrorAction Stop
        try{$process.Path -ieq $Task.Definition.Actions.Item(1).Path -and [Math]::Abs(($process.StartTime.ToUniversalTime()-[DateTime]::Parse($Report.StartedAtUtc).ToUniversalTime()).TotalSeconds) -lt 2}
        finally{$process.Dispose()}
    }catch{$false}
}
function Test-LGNewSession {
    param($Report,[string]$Before,[DateTime]$Requested)
    $id=Get-LGProperty $Report 'SessionId' ''
    if($id -cnotmatch '^[a-f0-9]{32}$' -or $id -ceq $Before -or (Get-LGProperty $Report 'Version') -cne $script:Version){return $false}
    $started=[DateTime]::MinValue
    if(-not [DateTime]::TryParse([string](Get-LGProperty $Report 'StartedAtUtc'),[ref]$started)){return $false}
    $started.ToUniversalTime() -ge $Requested.AddSeconds(-1)
}
function Wait-LGWorker {
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while($watch.Elapsed.TotalSeconds -lt 15){
        $task=Get-LGTask
        $path=Join-Path $script:Data 'last-run.json'
        if($null -ne $task -and $task.State -in @(3,4) -and (Test-Path -LiteralPath $path)){
            $beat=Read-LGJson $path
            $joined=$script:JoinSessionId -and (Get-LGProperty $beat 'SessionId' '') -ceq $script:JoinSessionId -and (Test-LGLiveSession $task $beat)
            if($joined -or (Test-LGNewSession $beat $script:BeforeSessionId $script:SessionRequestedUtc)){
                if($beat.SessionState -eq 'Failed'){Throw-LGError 'RUNTIME_FAILURE' '本次执行失败，请检查诊断状态。'}
                return
            }
        }
        Start-Sleep -Milliseconds 250
    }
    Throw-LGError 'SESSION_START_TIMEOUT' '一次性任务未能启动或未产生本次执行记录。'
}
function Get-LGAutomation {
    $name=$script:EventName
    $filter=Get-WmiObject -Namespace root\subscription -Class __EventFilter -Filter ("Name='"+$name+"'")
    $consumer=Get-WmiObject -Namespace root\subscription -Class CommandLineEventConsumer -Filter ("Name='"+$name+"'")
    $query=$script:EventQuery
    $executable=Join-Path $env:SystemRoot 'System32\schtasks.exe'
    $command='"'+$executable+'" /Run /TN "'+$script:TaskName+'"'
    if($null -ne $filter -and ($filter.Query -cne $query -or $filter.EventNamespace -ine 'root\cimv2')){throw '同名 WMI 事件过滤器不属于本工具。'}
    if($null -ne $consumer -and ($consumer.ExecutablePath -ine $executable -or $consumer.CommandLineTemplate -cne $command)){throw '同名 WMI 事件动作不属于本工具。'}
    $bindings=@()
    if($null -ne $filter -and $null -ne $consumer){
        $bindings=@(Get-WmiObject -Namespace root\subscription -Class __FilterToConsumerBinding | Where-Object {
            ([string]$_.Filter).EndsWith([string]$filter.__RELPATH,[StringComparison]::OrdinalIgnoreCase) -and
            ([string]$_.Consumer).EndsWith([string]$consumer.__RELPATH,[StringComparison]::OrdinalIgnoreCase)
        })
    }
    [pscustomobject]@{Filter=$filter;Consumer=$consumer;Bindings=$bindings;Query=$query;Command=$command;Executable=$executable;Ready=($bindings.Count -eq 1)}
}
function Register-LGAutomation {
    $state=Get-LGAutomation
    if($state.Ready){return}
    $name=$script:EventName
    $filter=$state.Filter;$consumer=$state.Consumer
    if($null -eq $filter){$filter=Set-WmiInstance -Namespace root\subscription -Class __EventFilter -Arguments @{Name=$name;Query=$state.Query;QueryLanguage='WQL';EventNamespace='root\cimv2'}}
    if($null -eq $consumer){$consumer=Set-WmiInstance -Namespace root\subscription -Class CommandLineEventConsumer -Arguments @{Name=$name;ExecutablePath=$state.Executable;CommandLineTemplate=$state.Command;RunInteractively=$false}}
    # Re-query committed instances: freshly returned WMI objects may omit __PATH.
    $committed=Get-LGAutomation
    [void](Set-WmiInstance -Namespace root\subscription -Class __FilterToConsumerBinding -Arguments @{Filter=[string]$committed.Filter.__PATH;Consumer=[string]$committed.Consumer.__PATH})
    if(-not (Get-LGAutomation).Ready){throw '进程启动事件订阅未通过核验。'}
}
function Remove-LGAutomation {
    $state=Get-LGAutomation
    foreach($binding in $state.Bindings){$binding.Delete() | Out-Null}
    if($null -ne $state.Consumer){$state.Consumer.Delete() | Out-Null}
    if($null -ne $state.Filter){$state.Filter.Delete() | Out-Null}
}
function Test-LGStartup {
    Initialize-LGNative
    $id=[Guid]::NewGuid().ToString('N')
    $directory=Join-Path $script:Data ('probe-'+$id)
    [void][IO.Directory]::CreateDirectory($directory)
    $image='LowGearProbe-'+$id+'.exe'
    $path=Join-Path $directory $image
    $original=Get-LGImage $image
    if($original.ImageKeyExists){throw '临时测试名称已存在。'}
    $samples=[Collections.Generic.List[object]]::new()
    $child=$null
    try {
        Build-LGRuntime $path 'public static class Probe { public static void Main(){ System.Threading.Thread.Sleep(60000); } }'
        foreach($phase in @('Baseline','MinimumFirst','MinimumSecond')) {
            if($phase -eq 'Baseline'){Set-LGImage $image 2 2;$cpu=32;$io=2}else{Set-LGImage $image 1 0;$cpu=64;$io=0}
            $child=Start-Process -FilePath $path -WindowStyle Hidden -PassThru
            try {
                Start-Sleep -Milliseconds 200
                $sample=[LowGear.Runtime]::Inspect($child.Id,$image,$false,$false)
                if($sample.CpuClass -ne $cpu -or $sample.IoPriority -ne $io -or $sample.Errors.Count -gt 0 -or
                    ($null -ne $sample.EffectiveIoPriority -and $sample.EffectiveIoPriority -ne $io)){throw ('启动探测失败：'+$phase)}
                $samples.Add([pscustomobject]@{Phase=$phase;CPU=$sample.CpuClass;IO=$sample.IoPriority;Passed=$true})
            }
            finally {if(-not $child.HasExited){$child.Kill();[void]$child.WaitForExit(5000)};$child.Dispose();$child=$null}
        }
    }
    finally {
        if($null -ne $child){if(-not $child.HasExited){$child.Kill();[void]$child.WaitForExit(5000)};$child.Dispose()}
        Restore-LGImage $original
        if(Test-Path -LiteralPath $path){[IO.File]::Delete($path)}
        if([IO.Directory]::Exists($directory)){[IO.Directory]::Delete($directory,$false)}
    }
    if((Get-LGImage $image).ImageKeyExists){throw '临时测试键未能清理。'}
    [pscustomobject]@{Passed=$true;Samples=$samples.ToArray();Cleanup=$true}
}
