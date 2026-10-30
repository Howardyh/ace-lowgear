[CmdletBinding()]
param([string]$PreviewDirectory)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$module=Import-Module (Join-Path $root 'src\LowGear.psm1') -Force -PassThru -DisableNameChecking
. (Join-Path $root 'ui\Panel.ps1')
$id=[Guid]::NewGuid().ToString('N');$temp=Join-Path ([IO.Path]::GetTempPath()) ('LowGear-delivery-tests-'+$id);[void][IO.Directory]::CreateDirectory($temp)
$checks=[Collections.Generic.List[string]]::new();$handle=$null;$setup=$null;$receipt=$null
function Assert {param([bool]$Value,[string]$Name)if(-not $Value){throw ('FAIL: '+$Name)};$checks.Add($Name)}
function Pump {$frame=[Windows.Threading.DispatcherFrame]::new();$timer=[Windows.Threading.DispatcherTimer]::new();$timer.Interval=[TimeSpan]::FromMilliseconds(100);$timer.Add_Tick({param($sender,$eventArgs)$sender.Stop();$frame.Continue=$false}.GetNewClosure());$timer.Start();[Windows.Threading.Dispatcher]::PushFrame($frame)}
function Click {param($Button)$Button.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent));Pump}
function Save-Preview {param($Window,[string]$Path,[double]$Scale)
    $visual=$Window.Content;$visual.Measure([Windows.Size]::new(880,640));$visual.Arrange([Windows.Rect]::new(0,0,880,640));$visual.UpdateLayout()
    $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new([int](880*$Scale),[int](640*$Scale),96*$Scale,96*$Scale,[Windows.Media.PixelFormats]::Pbgra32)
    $background=[Windows.Media.DrawingVisual]::new();$drawing=$background.RenderOpen();try{$drawing.DrawRectangle($Window.Resources['CanvasBrush'],$null,[Windows.Rect]::new(0,0,880,640))}finally{$drawing.Close()};$bitmap.Render($background);$bitmap.Render($visual)
    $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap));$stream=[IO.File]::Create($Path);try{$encoder.Save($stream)}finally{$stream.Dispose()}
}
try{
    $valid=@(Test-LGSourceFiles $root)
    Assert (@($valid|Where-Object State -eq 'Error').Count -eq 0) 'Complete source package passes its read-only file checks'
    $fixture=Join-Path $temp '完整 源码 &()!';[void][IO.Directory]::CreateDirectory($fixture)
    $manifest=Get-Content (Join-Path $root 'public-files.json') -Raw -Encoding UTF8|ConvertFrom-Json
    foreach($relative in $manifest.Files){$path=Join-Path $fixture $relative;[void][IO.Directory]::CreateDirectory((Split-Path $path -Parent));[IO.File]::WriteAllText($path,'fixture')}
    [IO.File]::WriteAllText((Join-Path $fixture 'public-files.json'),($manifest|ConvertTo-Json -Depth 4))
    Assert (@(Test-LGSourceFiles $fixture|Where-Object State -eq Error).Count -eq 0) 'Unicode, spaces and shell metacharacters in the source directory are accepted'
    [IO.File]::Delete((Join-Path $fixture 'README.md'));$issues=@(Test-LGSourceFiles $fixture)
    Assert (@($issues|Where-Object State -eq Error).Count -eq 0 -and @($issues|Where-Object State -eq Warning).Count -eq 1) 'Missing documentation warns without blocking the runtime'
    [IO.File]::Delete((Join-Path $fixture 'ui\Panel.xaml'));$issues=@(Test-LGSourceFiles $fixture)
    Assert (@($issues|Where-Object Code -eq SOURCE_MISSING).Count -eq 1) 'Missing runtime files stop launch before loading the panel'
    [IO.File]::WriteAllText((Join-Path $fixture 'public-files.json'),'{"Version":"1.4.0","Files":["../../escape"]}')
    Assert (@(Test-LGSourceFiles $fixture|Where-Object Code -eq SOURCE_MANIFEST_INVALID).Count -eq 1) 'Manifest paths cannot escape their source directory'
    Assert (@(Test-LGSourceFiles $temp|Where-Object State -eq Error).Count -eq 1) 'A copied entry without its source manifest requests complete extraction'
    $launchFixture=Join-Path $temp "启动 &()!' 源码";[void][IO.Directory]::CreateDirectory($launchFixture)
    foreach($relative in $manifest.Files){$file=Join-Path $launchFixture $relative;[void][IO.Directory]::CreateDirectory((Split-Path $file -Parent));[IO.File]::WriteAllText($file,'fixture')}
    [IO.File]::WriteAllText((Join-Path $launchFixture 'public-files.json'),($manifest|ConvertTo-Json -Depth 4));[IO.File]::Copy((Join-Path $root 'Bootstrap.ps1'),(Join-Path $launchFixture 'Bootstrap.ps1'),$true)
    $stub=@'
param([string]$Command,[string]$StartupReadyPath)
. (Join-Path $PSScriptRoot 'Bootstrap.ps1')
Write-LGStartupReady $StartupReadyPath
Start-Sleep -Seconds 2
exit 0
'@
    [IO.File]::WriteAllText((Join-Path $launchFixture 'LowGear.ps1'),$stub,[Text.UTF8Encoding]::new($true))
    $launchResult=Invoke-LGBootstrap $launchFixture -NoDialog 6>$null
    Assert ($launchResult -eq 0) 'Real Windows PowerShell child receives a correctly quoted source and receipt path'
    $poison=Join-Path $temp 'other-edition\Microsoft.PowerShell.Security';[void][IO.Directory]::CreateDirectory($poison)
    [IO.File]::WriteAllText((Join-Path $poison 'Microsoft.PowerShell.Security.psd1'),"@{ModuleVersion='99.0';PowerShellVersion='99.0';RootModule='invalid.psm1';FunctionsToExport=@('Get-Acl','Set-Acl')}")
    [IO.File]::WriteAllText((Join-Path $poison 'invalid.psm1'),"throw 'Other edition module must never load'")
    $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe';$info.Arguments='-NoProfile -STA -ExecutionPolicy Bypass -File "'+(Join-Path $launchFixture 'Bootstrap.ps1')+'" -NoDialog';$info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    $info.EnvironmentVariables['PSModulePath']=(Split-Path $poison -Parent)+';'+$env:PSModulePath
    $child=[Diagnostics.Process]::Start($info)
    try{Assert ($child.WaitForExit(15000) -and $child.ExitCode -eq 0) 'Cold startup pins its own built-in security module despite another edition in PSModulePath'}finally{$child.Dispose()}
    [IO.File]::Copy((Join-Path $root 'LowGear.ps1'),(Join-Path $launchFixture 'LowGear.ps1'),$true)
    $moduleStub=@'
function Invoke-LGCommand {param($Command,$Last,$ProgressPath)[pscustomobject]@{Success=$false;Message='预检未完成';Detail=[pscustomobject]@{Passed=$false;Checks=@([pscustomobject]@{Name='System';State='Error';Code='PREFLIGHT_ENVIRONMENT_FAILED';Message='环境检查失败'})};Report=$null}}
Export-ModuleMember -Function Invoke-LGCommand
'@
    [IO.File]::WriteAllText((Join-Path $launchFixture 'src\LowGear.psm1'),$moduleStub,[Text.UTF8Encoding]::new($true))
    $cliResult=Join-Path $temp 'preflight-cli.json';$cliLog=Join-Path $temp 'preflight-cli.log'
    & (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -NoProfile -STA -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $launchFixture 'LowGear.ps1') -Command Preflight -ResultPath $cliResult *> $cliLog
    Assert ($LASTEXITCODE -eq 1 -and (Get-Content $cliResult -Raw -Encoding UTF8|ConvertFrom-Json).Detail.Checks[0].Code -eq 'PREFLIGHT_ENVIRONMENT_FAILED') 'Plain-text Preflight CLI keeps structured failure details with exit code one'
    $argumentStub=@'
function Invoke-LGCommand {param($Command,$Last,$ProgressPath)[pscustomobject]@{Success=$true;Message='Isolated';Detail=[pscustomobject]@{Last=$Last};Report=[pscustomobject]@{Version='1.4.0';Processes=@()}}}
Export-ModuleMember -Function Invoke-LGCommand
'@
    [IO.File]::WriteAllText((Join-Path $launchFixture 'src\LowGear.psm1'),$argumentStub,[Text.UTF8Encoding]::new($true))
    & (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -NoProfile -STA -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $launchFixture 'LowGear.ps1') -Command Install -BindLastCpu -Json -ResultPath $cliResult *> $cliLog
    Assert ($LASTEXITCODE -eq 0 -and (Get-Content $cliResult -Raw -Encoding UTF8|ConvertFrom-Json).Detail.Last -eq $true) 'Explicit BindLastCpu reaches the controller through the real entry and bootstrap scope'
    & (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -NoProfile -STA -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $launchFixture 'LowGear.ps1') -Command Install -ClearLastCpu -Json -ResultPath $cliResult *> $cliLog
    Assert ($LASTEXITCODE -eq 0 -and (Get-Content $cliResult -Raw -Encoding UTF8|ConvertFrom-Json).Detail.Last -eq $false) 'Explicit ClearLastCpu reaches the controller without enabling affinity'
    $capture=[pscustomobject]@{Code=''}
    $cancelResult=& {param($tracker,$fixture)
        function Start-Process {throw [ComponentModel.Win32Exception]::new(1223)}
        function Show-LGStartupError {param($Code,$Message,[switch]$NoDialog)$tracker.Code=$Code}
        Invoke-LGBootstrap $fixture -NoDialog 6>$null
    } $capture $launchFixture
    Assert ($cancelResult -eq 1 -and $capture.Code -eq 'AUTH_CANCELLED') 'Simulated UAC cancellation is reported explicitly without retry'
    $receipt=New-LGStartupPath
    Assert (Test-LGStartupPath $receipt) 'Startup receipt uses a validated unique temporary directory'
    $acl=Get-Acl (Split-Path $receipt -Parent)
    Assert $acl.AreAccessRulesProtected 'Startup receipt directory does not inherit broad temporary-directory access'
    $alternate=Join-Path $temp ('LowGear-start-'+[Guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($alternate);Set-Acl -LiteralPath $alternate -AclObject $acl
    Assert (Test-LGStartupPath (Join-Path $alternate 'ready.json')) 'Protected receipt from another TEMP location is valid across administrator account elevation'
    [IO.Directory]::Delete($alternate,$false)
    $fake=[pscustomobject]@{HasExited=$false};$fake|Add-Member ScriptMethod Refresh {}
    Write-LGStartupReady $receipt;Write-LGStartupReady $receipt 'Error' 'LATE_ERROR'
    Assert ((Wait-LGStartup $receipt $fake 0).State -eq 'Ready') 'The first ready receipt is read and cannot be overwritten by a later writer'
    Remove-LGStartupPath $receipt
    Assert (-not [IO.Directory]::Exists((Split-Path $receipt -Parent))) 'Successful startup removes its receipt directory'
    $receipt=New-LGStartupPath;$fake.HasExited=$true
    Assert ((Wait-LGStartup $receipt $fake 0).Code -eq 'STARTUP_EXITED') 'Exit before readiness returns a visible startup failure'
    $fake.HasExited=$false
    Assert ((Wait-LGStartup $receipt $fake 0).Code -eq 'STARTUP_TIMEOUT' -and -not $fake.HasExited) 'Readiness timeout leaves the original process alone'
    Write-LGStartupReady $receipt 'Error' 'INTERFACE_FAILED'
    Assert ((Wait-LGStartup $receipt $fake 0).Code -eq 'INTERFACE_FAILED') 'Interface initialization failures reach the startup launcher'
    $sentinel=Join-Path (Split-Path $receipt -Parent) 'keep.txt';[IO.File]::WriteAllText($sentinel,'keep');Remove-LGStartupPath $receipt
    Assert ([IO.File]::Exists($sentinel)) 'Receipt cleanup never recursively removes unrelated files'
    [IO.File]::Delete($sentinel);Remove-LGStartupPath $receipt;$receipt=$null
    $outside=Join-Path $temp 'ready.json';Write-LGStartupReady $outside
    Assert (-not [IO.File]::Exists($outside)) 'An arbitrary receipt path cannot be written'

    & $module {param($base,$registry)
        $script:Common=Join-Path $base 'untouched';$script:Data=Join-Path $script:Common 'v1';$script:Hive=[Microsoft.Win32.RegistryHive]::CurrentUser;$script:RegistryPath=$registry
        function script:Get-LGTask {param([string]$Name=$script:TaskName)$null}
        function script:Get-LGAutomation {[pscustomobject]@{Filter=$null;Consumer=$null;Ready=$false}}
        function script:Get-LGTaskSnapshot {param([string]$Name,[string]$Source)[pscustomobject]@{Exists=$false}}
    } $temp ('SOFTWARE\LowGearDeliveryTests\'+$id)
    $preflight=& $module {Invoke-LGCommand Preflight}
    Assert ($preflight.Success -and -not [IO.Directory]::Exists((Join-Path $temp 'untouched'))) 'Preflight on an uninstalled machine does not initialize runtime state or backups'
    Assert ($preflight.Detail.Checks.Count -gt 6 -and -not $preflight.Detail.Migration) 'Preflight returns structured checks through the existing result envelope'
    & $module {function script:Get-LGBaseline {throw 'Injected legacy conflict'}}
    $conflict=& $module {Invoke-LGCommand Preflight}
    Assert (-not $conflict.Success -and @($conflict.Detail.Checks|Where-Object Code -eq BASELINE_CONFLICT).Count -eq 1) 'Conflicting legacy data blocks preflight without migration or cleanup'
    & $module {function script:Initialize-LGNative {throw 'Injected native environment failure'}}
    $environmentFailure=& $module {Invoke-LGCommand Preflight}
    Assert (-not $environmentFailure.Success -and $null -eq $environmentFailure.Report -and $environmentFailure.Detail.Checks[0].Code -eq 'PREFLIGHT_ENVIRONMENT_FAILED' -and -not [IO.Directory]::Exists((Join-Path $temp 'untouched'))) 'Native initialization failure returns a structured read-only preflight error'
    $summary=Get-LGDiagnostic $preflight.Report|ConvertTo-Json -Depth 8
    Assert ($summary -notmatch 'untouched|CreationUtc|ProcessId|Checks|Baseline') 'Preflight details do not widen the diagnostic summary whitelist'

    $onboarding=Join-Path $temp 'onboarding.json'
    Assert (-not(Read-LGOnboarding $onboarding)) 'Missing onboarding preference is safely unhandled'
    Assert (Set-LGOnboardingHandled $onboarding) 'Explicit deferral can be saved'
    Assert (Read-LGOnboarding $onboarding) 'Deferral persists for the next launch'
    [IO.File]::WriteAllText($onboarding,'{"Schema":1,"Handled":"true"}')
    Assert (-not(Read-LGOnboarding $onboarding)) 'Invalid preference types do not silently suppress onboarding'
    [IO.File]::WriteAllText($onboarding,'corrupt')
    Assert (-not(Read-LGOnboarding $onboarding)) 'Corrupt onboarding preferences do not block application startup'
    $report=Get-LGDemoReport;$report.Installed=$false;$report.Mode='NotInstalled';$report.InstalledVersion=$null;$report.Processes=@()
    Assert ((Get-LGSetupRoute $report $false) -eq 'Wizard') 'An explicitly uninstalled healthy machine receives the independent wizard'
    Assert ((Get-LGSetupRoute $report $true) -eq 'Panel') 'Remembered deferral bypasses automatic onboarding'
    $report.Health.Installation.State='Error'
    Assert ((Get-LGSetupRoute $report $false) -eq 'Diagnostics') 'A failed installation query cannot be misclassified as fresh installation'
    $report=Get-LGDemoReport;$report.Mode='Paused'
    Assert ((Get-LGSetupRoute $report $false) -eq 'Panel') 'Existing paused installations go directly to the panel'
    $report.Mode='RecoveryRequired'
    Assert ((Get-LGSetupRoute $report $false) -eq 'Diagnostics') 'Incomplete transactions are routed to diagnosis rather than a new installation'

    $handle=Show-LGPanel -PassThru -Demo -PreferencePath (Join-Path $temp 'ui.json')
    $report=Get-LGDemoReport;$report.Installed=$false;$report.InstalledVersion=$null;$report.Mode='NotInstalled';$report.Processes=@();& $handle.Update $report
    $tracker=[pscustomobject]@{Queries=0;Starts=0;Confirmed=$false;Command=''}
    $request={$tracker.Queries++}.GetNewClosure();$start={param($command,[switch]$Confirmed)$tracker.Starts++;$tracker.Command=$command;$tracker.Confirmed=[bool]$Confirmed}.GetNewClosure()
    [IO.File]::Delete($onboarding)
    $setup=New-LGSetupWindow $handle.State $start $request {} $onboarding -Initial;$setup.Window.Show();Pump;& $setup.OnReport $report
    Assert ($setup.Step -eq 'Intro' -and $tracker.Starts -eq 0) 'A real independent wizard welcomes without installing'
    Assert ($setup.Window.ActualWidth -gt 0 -and $null -ne $setup.Native) 'Wizard has a native themed HWND'
    Assert ($setup.Controls.Steps.Text -match '示例数据') 'Rendered demonstration content visibly identifies itself independently of the native title bar'
    Click $setup.Controls.Primary
    Assert ($setup.Step -eq 'Review' -and $tracker.Queries -eq 1 -and -not $setup.Controls.Primary.IsEnabled) 'Next performs only a preflight request and keeps confirmation disabled'
    & $setup.OnPreflight ([pscustomobject]@{Success=$false;Detail=[pscustomobject]@{Checks=@([pscustomobject]@{State='Error';Name='Conflict';Message='存在外部修改，请进入诊断。'})}})
    Click $setup.Controls.Primary
    Assert ($tracker.Starts -eq 0 -and -not $setup.Controls.Primary.IsEnabled) 'Failed preflight cannot start configuration changes'
    & $setup.OnPreflight ([pscustomobject]@{Success=$true;Detail=[pscustomobject]@{Checks=@([pscustomobject]@{State='Healthy';Name='Baseline';Message='将保留最早原始备份。'})}})
    Click $setup.Controls.Primary;Click $setup.Controls.Primary
    Assert ($setup.Step -eq 'Working' -and $tracker.Starts -eq 1 -and $tracker.Confirmed -and $tracker.Command -eq 'Install') 'Only explicit final confirmation starts one unified Install operation'
    $handle.State.Child=[pscustomobject]@{HasExited=$false};$setup.Window.Close();Pump
    Assert (-not $setup.Closed) 'Closing the wizard waits for an active mutation'
    $handle.State.Child=$null;$report=Get-LGDemoReport;$report.Processes=@()
    & $setup.OnResult ([pscustomobject]@{Success=$true;Report=$report})
    Assert ($setup.Step -eq 'Result' -and (Get-LGOperationOutcome Install $setup.Result).Text -match '等待游戏启动' -and (Read-LGOnboarding $onboarding)) 'NoTargets completion remains waiting and suppresses repeat onboarding'
    Click $setup.Controls.Primary
    Assert ($setup.Closed -and $null -eq $setup.Native -and $setup.Route -eq 'Panel') 'Completion returns to the panel and releases its native hooks'
    $setup=$null
    [IO.File]::Delete($onboarding);$report.Installed=$false;$report.Mode='NotInstalled';& $handle.Update $report
    $setup=New-LGSetupWindow $handle.State $start $request {} $onboarding
    $setup.Window.Show();Pump;Click $setup.Controls.Secondary
    Assert ($setup.Route -eq 'Panel' -and (Read-LGOnboarding $onboarding) -and $tracker.Starts -eq 1) 'View panel persists deferral without starting Install'
    $setup=$null
    $report=Get-LGDemoReport;$report.Mode='Paused';& $handle.Update $report
    $setup=New-LGSetupWindow $handle.State $start $request {} $onboarding -Command Upgrade;$setup.Window.Show();Pump
    & $setup.OnResult ([pscustomobject]@{Success=$true;Report=$report})
    Assert ((Get-LGOperationOutcome Upgrade $setup.Result).Title -match '保持暂停') 'Paused upgrade completion never claims automatic execution is enabled'
    & $setup.OnResult ([pscustomobject]@{Success=$false;Code='UPGRADE_FAILED'})
    Assert ($setup.Controls.Title.Text -eq '操作未完成') 'Failure has its own result instead of a successful completion page'
    $setup.Window.Close();$setup=$null
    $report=Get-LGDemoReport;$report.Installed=$false;$report.Mode='NotInstalled';& $handle.Update $report
    [IO.File]::Delete($onboarding)
    $closer=[Windows.Threading.DispatcherTimer]::new();$closer.Interval=[TimeSpan]::FromMilliseconds(150)
    $closer.Add_Tick({param($sender,$eventArgs)if($null -ne $handle.State.Setup){$sender.Stop();$handle.State.Setup.Controls.Secondary.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))}}.GetNewClosure())
    $closer.Start();$route=& $handle.OpenSetup Install -Initial;$closer.Stop()
    Assert ($route -eq 'Panel' -and (Read-LGOnboarding $onboarding)) 'Panel callback closures can host the independent first-run modal and persist deferral'
    foreach($theme in @('Light','Dark')){
        & $handle.Theme $theme;$report=Get-LGDemoReport;$report.Installed=$false;$report.Mode='NotInstalled';& $handle.Update $report
        $setup=New-LGSetupWindow $handle.State $start $request {} $onboarding;$setup.Window.Show();Pump
        foreach($scale in @(1,1.25,1.5,2)){$image=Join-Path $temp ('wizard-'+$theme+'-'+$scale+'.png');Save-Preview $setup.Window $image $scale;Assert ((Get-Item $image).Length -gt 10000) ('Wizard '+$theme+' renders at scale '+$scale)}
        if($PreviewDirectory){[void][IO.Directory]::CreateDirectory($PreviewDirectory);[IO.File]::Copy((Join-Path $temp ('wizard-'+$theme+'-1.png')),(Join-Path $PreviewDirectory ('LowGear-1.4-wizard-'+$theme+'.png')),$true)}
        $setup.Window.Close();$setup=$null
    }
    $restore=Get-LGOperationOutcome Restore ([pscustomobject]@{Success=$true;Report=$report})
    Assert ($restore.Text -match '原始备份保留' -and $restore.Text -match '重启') 'Restore completion explains retained backup and existing-process restart'
    $handle.State.Demo=$false;$handle.State.Runspace=[RunspaceFactory]::CreateRunspace();$handle.State.Runspace.ApartmentState='STA';$handle.State.Runspace.ThreadOptions='ReuseThread';$handle.State.Runspace.Open()
    $pipeline=[PowerShell]::Create();$pipeline.Runspace=$handle.State.Runspace
    [void]$pipeline.AddScript('param($module,$fixture) Import-Module $module -DisableNameChecking;$global:Fixture=$fixture|ConvertFrom-Json;$global:Reads=0;$global:Preflights=0;function global:Get-LGStatus {param([switch]$Quick)$global:Reads++;Start-Sleep -Milliseconds 300;$global:Fixture};function global:Invoke-LGCommand {param($Command)$global:Preflights++;Start-Sleep -Milliseconds 300;[pscustomobject]@{Success=$true;Detail=@{Checks=@()};Report=$global:Fixture}}').AddArgument((Join-Path $root 'src\LowGear.psm1')).AddArgument(($report|ConvertTo-Json -Depth 20));[void]$pipeline.Invoke();$pipeline.Dispose()
    & $handle.Refresh;$original=$handle.State.Pending;& $handle.RequestPreflight
    Assert ([object]::ReferenceEquals($original,$handle.State.Pending) -and $handle.State.PreflightRequested) 'A preflight request queues behind a read without starting another query'
    $watch=[Diagnostics.Stopwatch]::StartNew();while(($null -ne $handle.State.Pipeline -or $handle.State.PreflightRequested) -and $watch.Elapsed.TotalSeconds -lt 10){Start-Sleep -Milliseconds 50;& $handle.Tick}
    Assert ($null -ne $handle.State.LastPreflight -and $handle.State.LastPreflight.Success -and $null -eq $handle.State.Pipeline) 'Shared read execution delivers the queued structured preflight result'
    $pipeline=[PowerShell]::Create();$pipeline.Runspace=$handle.State.Runspace;[void]$pipeline.AddScript('[pscustomobject]@{Reads=$global:Reads;Preflights=$global:Preflights}');$counts=$pipeline.Invoke()[0];$pipeline.Dispose()
    Assert ($counts.Reads -eq 1 -and $counts.Preflights -eq 1) 'Shared preflight performs one full check without duplicate queries'
    $pipeline=[PowerShell]::Create();$pipeline.Runspace=$handle.State.Runspace;[void]$pipeline.AddScript('function global:Invoke-LGCommand {param($Command)[pscustomobject]@{Success=$false;Detail=@{Checks=@()};Report=$null}}');[void]$pipeline.Invoke();$pipeline.Dispose()
    $prior=$handle.State.LastReport;& $handle.RequestPreflight;$watch=[Diagnostics.Stopwatch]::StartNew()
    while($null -ne $handle.State.Pipeline -and $watch.Elapsed.TotalSeconds -lt 5){Start-Sleep -Milliseconds 30;& $handle.Tick}
    Assert (-not $handle.State.LastPreflight.Success -and $handle.State.Stale -and [object]::ReferenceEquals($prior,$handle.State.LastReport)) 'A preflight failure without a report preserves the previous status and marks it stale'
    [pscustomobject]@{Status='Passed';Count=$checks.Count;Checks=$checks.ToArray();ActualInstallationChanged=$false;AuthorizationCancellation='SimulatedWin32Cancellation; physical UAC cancellation is manual'}|ConvertTo-Json -Depth 5
}finally{
    if($null -ne $handle){$handle.State.Child=$null;$handle.State.QueuedCommand=$null}
    if($null -ne $setup){$setup.Window.Close()}
    if($null -ne $handle){$handle.State.Window.Close();& $handle.Cleanup}
    if($receipt){Remove-LGStartupPath $receipt}
    if($id -cnotmatch '^[a-f0-9]{32}$' -or [IO.Path]::GetFullPath($temp) -cne [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('LowGear-delivery-tests-'+$id)))){throw 'Unsafe test cleanup'}
    if([IO.Directory]::Exists($temp)){[IO.Directory]::Delete($temp,$true)}
    Remove-Module $module -Force
}
