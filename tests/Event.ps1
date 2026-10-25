[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$module=Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'src\LowGear.psm1') -Force -PassThru -DisableNameChecking
$id=[Guid]::NewGuid().ToString('N')
$root=Join-Path ([IO.Path]::GetTempPath()) ('LowGear-event-test-'+$id)
$image='LowGearProbe-'+$id+'.exe'
$probe=$null
$checks=[Collections.Generic.List[string]]::new()
function Wait-Correct {
    param($Process)
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while($watch.Elapsed.TotalSeconds -lt 20){
        $sample=[LowGear.Runtime]::Inspect($Process.Id,$image,$false,$false)
        if($sample.Verified){return [Math]::Round($watch.Elapsed.TotalSeconds,3)}
        Start-Sleep -Milliseconds 200
    }
    throw ('Event did not correct the owned probe: '+($sample | ConvertTo-Json -Depth 5 -Compress))
}
function Wait-Exit {
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while($watch.Elapsed.TotalSeconds -lt 15){
        $task=& $module {Get-LGTask}
        if($task.State -eq 3){
            $report=Get-Content -LiteralPath (Join-Path $root 'v1\last-run.json') -Raw | ConvertFrom-Json
            if($report.SessionState -eq 'Completed'){return}
        }
        Start-Sleep -Milliseconds 200
    }
    throw 'One-shot task did not exit after verification.'
}
try {
    Initialize-LGNative
    & $module {param($root,$id,$image)
        $script:Common=$root;$script:Data=Join-Path $root 'v1'
        $script:TaskName='LowGear-Test-'+$id;$script:TaskSource='ACE LowGear Isolated Event Test'
        $script:EventName='LowGear-Test-'+$id
        $script:EventQuery="SELECT * FROM Win32_ProcessStartTrace WHERE ProcessName='"+$image+"'"
        Initialize-LGData
        Set-LGPolicy $false
    } $root $id $image
    $workerPath=Join-Path $root 'v1\LowGear.Worker.exe'
    $probePath=Join-Path $root ('v1\'+$image)
    Build-LGRuntime $workerPath
    Build-LGRuntime $probePath 'public static class Probe { public static void Main(){System.Threading.Thread.Sleep(60000);} }'
    & $module {param($runtime,$image)Register-LGTask $runtime -SkipImmediate -ProbeImage $image} $workerPath $image
    if(-not (& $module {Get-LGAutomation}).Ready){throw 'Isolated event subscription is not ready.'}
    $checks.Add('Register unique process-start subscription and demand-start task')
    Start-Sleep -Seconds 2
    $probe=Start-Process -FilePath $probePath -WindowStyle Hidden -PassThru
    $first=Wait-Correct $probe
    Wait-Exit
    $checks.Add('A process-start event applies CPU and I/O and the task exits')
    $probe.PriorityClass=[Diagnostics.ProcessPriorityClass]::Normal
    Start-Sleep -Seconds 4;$probe.Refresh()
    if($probe.PriorityClass -ne [Diagnostics.ProcessPriorityClass]::Normal){throw 'Unexpected continuing correction after exit.'}
    $checks.Add('No continuing correction after successful completion')
    $probe.Kill();[void]$probe.WaitForExit(5000);$probe.Dispose();$probe=$null
    $probe=Start-Process -FilePath $probePath -WindowStyle Hidden -PassThru
    $second=Wait-Correct $probe
    Wait-Exit
    $checks.Add('A new PID triggers a new single execution')
    & $module {Remove-LGAutomation}
    if((& $module {Get-LGAutomation}).Ready){throw 'Event subscription was not removed.'}
    $checks.Add('Remove the exact test event registration')
    [pscustomobject]@{Status='Passed';Checks=$checks.ToArray();FirstEventSeconds=$first;RestartEventSeconds=$second} | ConvertTo-Json -Depth 6
}
finally {
    if($null -ne $probe){if(-not $probe.HasExited){$probe.Kill();[void]$probe.WaitForExit(5000)};$probe.Dispose()}
    try{& $module {Remove-LGAutomation;Remove-LGTask}}finally{
        $expected=[IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('LowGear-event-test-'+$id)))
        if($id -cnotmatch '^[a-f0-9]{32}$' -or [IO.Path]::GetFullPath($root) -cne $expected){throw 'Unsafe cleanup identity.'}
        if([IO.Directory]::Exists($root)){[IO.Directory]::Delete($root,$true)}
    }
    Remove-Module $module -Force
}
