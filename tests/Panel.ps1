[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'src\LowGear.psm1') -Force -DisableNameChecking
. (Join-Path $root 'ui\Panel.ps1')
$id=[Guid]::NewGuid().ToString('N');$temp=Join-Path ([IO.Path]::GetTempPath()) ('LowGear-panel-tests-'+$id);[void][IO.Directory]::CreateDirectory($temp)
$checks=[Collections.Generic.List[string]]::new();$handle=$null
function Assert {param([bool]$Value,[string]$Name)if(-not $Value){throw ('FAIL: '+$Name)};$checks.Add($Name)}
function Finish-Query {
    param($Handle)
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while($null -ne $Handle.State.Pending -and -not $Handle.State.Pending.IsCompleted -and $watch.Elapsed.TotalSeconds -lt 8){Start-Sleep -Milliseconds 30}
    if($null -ne $Handle.State.Pending -and -not $Handle.State.Pending.IsCompleted){throw 'Panel test query timeout'}
    & $Handle.Tick
}
try{
    $health=[ordered]@{};foreach($section in @('Installation','Policy','Startup','Task','Automation','Runtime','Session','Processes')){$health[$section]=[pscustomobject]@{State='Healthy';Code='OK';Message='正常'}}
    $report=[pscustomobject]@{Version='1.1.0';InstalledVersion='1.1.0';Installed=$true;Mode='Ready';BindLastCpu=$false;Topology=[pscustomobject]@{LogicalProcessors=24;Groups=1;LastCpu=23};FullCheckedUtc=[DateTime]::UtcNow.ToString('o');LastSession=$null;Processes=@();Startup=@();Health=[pscustomobject]$health}
    $handle=Show-LGPanel -PassThru
    & $handle.Update $report
    Assert ($handle.State.Controls.UpgradeButton.Visibility -eq 'Collapsed') 'Current runtime hides the upgrade action'
    Assert ($handle.State.Controls.SummaryText.Text -match '未运行不代表核验通过') 'No running target is displayed as waiting rather than verified'
    $report.InstalledVersion='1.0.0';& $handle.Update $report
    Assert ($handle.State.Controls.UpgradeButton.Visibility -eq 'Visible' -and $handle.State.Controls.VersionText.Text -match '本机 1.0.0') 'UI distinguishes panel and installed versions'
    $handle.State.Child=[pscustomobject]@{HasExited=$false}
    $args=[ComponentModel.CancelEventArgs]::new();& $handle.Closing $null $args
    Assert ($args.Cancel) 'Closing is deferred while a mutation is running'
    & $handle.Start 'Install'
    Assert ($null -eq $handle.State.JobDirectory) 'Repeated action while busy does not start a second command'
    $handle.State.Child=$null
    $handle.State.Runspace=[RunspaceFactory]::CreateRunspace();$handle.State.Runspace.ApartmentState='STA';$handle.State.Runspace.ThreadOptions='ReuseThread';$handle.State.Runspace.Open()
    $setup=[PowerShell]::Create();$setup.Runspace=$handle.State.Runspace
    [void]$setup.AddScript('param($modulePath,$fixture) Import-Module $modulePath -DisableNameChecking;$global:Fixture=$fixture|ConvertFrom-Json;$global:Calls=0;$global:FailQuery=$false;function global:Get-LGStatus {param([switch]$Quick)$global:Calls++;Start-Sleep -Milliseconds 700;if($global:FailQuery){throw "Injected slow failure"};$copy=$global:Fixture|ConvertTo-Json -Depth 20|ConvertFrom-Json;$copy|Add-Member NoteProperty TestQuick ([bool]$Quick);$copy}').AddArgument((Join-Path $root 'src\LowGear.psm1')).AddArgument(($report|ConvertTo-Json -Depth 20))
    [void]$setup.Invoke();if($setup.HadErrors){throw ($setup.Streams.Error|Out-String)};$setup.Dispose()
    $watch=[Diagnostics.Stopwatch]::StartNew();& $handle.Refresh;$elapsed=$watch.ElapsedMilliseconds
    Assert ($elapsed -lt 500 -and -not $handle.State.Pending.IsCompleted) 'Slow system query starts asynchronously without blocking the window thread'
    $pipeline=$handle.State.Pipeline;& $handle.Refresh
    Assert ([object]::ReferenceEquals($pipeline,$handle.State.Pipeline)) 'In-flight status queries never overlap'
    $handle.State.QueryStarted=[DateTime]::UtcNow.AddSeconds(-11);& $handle.Tick
    Assert ($handle.State.Controls.OperationText.Text -match '系统查询较慢') 'Slow reads retain prior results and show a delay hint'
    Finish-Query $handle
    Assert ($null -eq $handle.State.Pipeline -and $handle.State.LastReport.InstalledVersion -eq '1.0.0') 'Asynchronous result updates the existing panel'
    $handle.State.LastRefresh=[DateTime]::UtcNow.AddSeconds(-6);$handle.State.LastFull=[DateTime]::UtcNow;$handle.State.ForceFull=$false;& $handle.Tick
    Finish-Query $handle
    Assert ($handle.State.LastReport.TestQuick) 'Five-second refresh uses the lightweight process query'
    & $handle.Start 'Status';Finish-Query $handle
    Assert (-not $handle.State.LastReport.TestQuick) 'Manual refresh forces the full configuration check'
    $handle.State.LastRefresh=[DateTime]::UtcNow.AddSeconds(-6);$handle.State.LastFull=[DateTime]::UtcNow.AddSeconds(-31);& $handle.Tick;Finish-Query $handle
    Assert (-not $handle.State.LastReport.TestQuick) 'Thirty-second refresh performs a full configuration check'
    $before=$handle.State.LastReport
    $setup=[PowerShell]::Create();$setup.Runspace=$handle.State.Runspace;[void]$setup.AddScript('$global:FailQuery=$true');[void]$setup.Invoke();$setup.Dispose()
    & $handle.Start 'Status';Finish-Query $handle
    Assert ([object]::ReferenceEquals($before,$handle.State.LastReport) -and $handle.State.Controls.OperationText.Text -match '本次读取失败') 'Failed queries retain the last result and release query resources'
    $args=[ComponentModel.CancelEventArgs]::new();& $handle.Closing $null $args
    Assert (-not $args.Cancel) 'Idle window can close normally'
    & $handle.Cleanup
    Assert ($handle.State.Closed) 'Closed panel stops scheduling further status queries'
    & $handle.Refresh
    Assert ($null -eq $handle.State.Pipeline) 'Closed panel cannot create a new query'
    $handle=$null
    foreach($scale in @(1,1.25,1.5,2)){
        $image=Join-Path $temp ('scale-'+$scale+'.png');Show-LGPanel -RenderOnly -ImagePath $image -RenderScale $scale
        $bitmap=[Windows.Media.Imaging.BitmapImage]::new([Uri]$image)
        Assert ($bitmap.PixelWidth -eq [int](1060*$scale) -and $bitmap.PixelHeight -eq [int](800*$scale)) ('Render Chinese panel at scale '+$scale)
        $bitmap=$null
    }
    [pscustomobject]@{Status='Passed';Count=$checks.Count;Checks=$checks.ToArray()}|ConvertTo-Json -Depth 5
}finally{
    if($null -ne $handle){& $handle.Cleanup}
    [GC]::Collect();[GC]::WaitForPendingFinalizers()
    $expected=[IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('LowGear-panel-tests-'+$id)))
    if($id -cnotmatch '^[a-f0-9]{32}$' -or [IO.Path]::GetFullPath($temp) -cne $expected){throw 'Unsafe panel cleanup'}
    if([IO.Directory]::Exists($temp)){[IO.Directory]::Delete($temp,$true)}
}
