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
function Find-RenderedText {
    param($Visual,[string]$Text)
    $queue=[Collections.Generic.Queue[Windows.DependencyObject]]::new();$queue.Enqueue($Visual)
    while($queue.Count){$item=$queue.Dequeue();if($item -is [Windows.Controls.TextBlock] -and $item.Text -ceq $Text){return $item};for($index=0;$index -lt [Windows.Media.VisualTreeHelper]::GetChildrenCount($item);$index++){$queue.Enqueue([Windows.Media.VisualTreeHelper]::GetChild($item,$index))}}
    $null
}
function Measure-Panel {
    param($Handle)
    $visual=$Handle.State.Window.Content;$visual.Measure([Windows.Size]::new(1060,800));$visual.Arrange([Windows.Rect]::new(0,0,1060,800));$visual.UpdateLayout()
}
try{
    $preference=Join-Path $temp 'ui.json'
    $handle=Show-LGPanel -PassThru -PreferencePath $preference
    $report=Get-LGDemoReport;$report.Processes=@();$report.LastSession=$null
    & $handle.Update $report
    Assert ($handle.State.Controls.LiveText.Text -eq '等待启动' -and $handle.State.Controls.LiveStatus.DataContext.Tone -eq 'Neutral') 'Configured automation without running targets is neutral and not verified'
    Assert ($handle.State.Controls.SummaryText.Text -match '未运行不代表核验通过' -and $handle.State.Controls.ManagerText.Text -eq '已启用') 'Configuration and current verification have independent labels'
    Assert (-not $handle.State.Controls.PrimaryButton.IsEnabled) 'One-time action waits for a running target'
    $report.Installed=$false;$report.Mode='NotInstalled';$report.InstalledVersion=$null;& $handle.Update $report
    Assert ($handle.State.Controls.PrimaryButton.Tag -eq 'Install') 'Uninstalled primary action enables management'
    Assert (@($handle.State.Controls.HealthList.ItemsSource|Where-Object {$_.Label -eq '安装与原始备份'})[0].Tone -eq 'Neutral') 'No installation record is not advertised as a verified original backup'
    $report.Installed=$true;$report.InstalledVersion=$report.Version;$report.Mode='Paused';& $handle.Update $report
    Assert ($handle.State.Controls.PrimaryButton.Tag -eq 'Resume' -and $handle.State.Controls.PauseButton.Visibility -eq 'Collapsed') 'Paused state offers resume rather than both conflicting actions'
    $report.InstalledVersion='1.1.0';& $handle.Update $report
    Assert ($handle.State.Controls.PrimaryButton.Tag -eq 'Upgrade' -and $handle.State.Controls.UpgradeButton.Visibility -eq 'Visible') 'Older paused component offers the lossless upgrade action'
    $report.InstalledVersion='9.0.0';& $handle.Update $report
    Assert ($handle.State.Controls.UpgradeButton.Visibility -eq 'Collapsed') 'A newer installed component is never offered a downgrade'
    $report.InstalledVersion=$report.Version;$report.Mode='RecoveryRequired';& $handle.Update $report
    Assert ($handle.State.Controls.PrimaryButton.Tag -eq 'Diagnostics' -and -not $handle.State.Controls.ResumeButton.IsEnabled) 'Incomplete transaction guides diagnosis rather than enabling automation'
    $report=Get-LGDemoReport
    & $handle.Update $report
    Assert ($handle.State.Controls.LiveText.Text -eq '当前实例已核验') 'Matching current instances are verified independently of the last session'
    $handle.State.ProcessGroups[0].Expanded=$true
    $page=$handle.State.Controls.OverviewPage
    & $handle.Navigate 'Settings';& $handle.Update $report;& $handle.Navigate 'Diagnostics';& $handle.Navigate 'Overview'
    Assert ($handle.State.ProcessGroups[0].Expanded -and [object]::ReferenceEquals($page,$handle.State.Controls.OverviewPage)) 'Navigation and refresh preserve process expansion and page objects'
    Assert ($null -eq $handle.State.Runspace) 'Switching pages does not create extra status queries'
    & $handle.Resize 880
    Assert ($handle.State.Controls.SidebarColumn.Width.Value -eq 64 -and $handle.State.Controls.SettingsNavLabel.Visibility -eq 'Collapsed') 'Narrow window uses labelled tooltips and compact icon navigation'
    & $handle.Resize 1060
    Assert ($handle.State.Controls.SidebarColumn.Width.Value -eq 200 -and $handle.State.Controls.SettingsNavLabel.Visibility -eq 'Visible') 'Wide window restores the 200-unit navigation pane'
    $duplicate=$report.Processes[0]|ConvertTo-Json -Depth 8|ConvertFrom-Json;$duplicate.ProcessId=5678;$duplicate.CpuClass=32;$duplicate.Verified=$false
    $report.Processes+=$duplicate;& $handle.Update $report
    Assert ($handle.State.ProcessGroups[0].Instances.Count -eq 2 -and $handle.State.ProcessGroups[0].Tone -eq 'Warning' -and $handle.State.ProcessGroups[0].Cpu -eq '多个读值') 'Multiple instances remain distinct and mixed readings are not hidden'
    Assert ($handle.State.Controls.LiveText.Text -eq '存在未达标实例') 'A single mismatch prevents the live success state'
    $report.Processes[0].CpuClass=$null;$report.Processes[0].Verified=$true;& $handle.Update $report
    Assert ($handle.State.ProcessGroups[0].Instances[0].Cpu -eq '未读取' -and $handle.State.ProcessGroups[0].Instances[0].Tone -eq 'Warning') 'Unknown priority is not converted to zero or success'
    $report.Processes[0].Errors=@('OpenProcess: Win32 5');& $handle.Update $report
    Assert ($handle.State.ProcessGroups[0].Tone -eq 'Error' -and $handle.State.ProcessGroups[0].Instances[0].ErrorText -match 'Win32 5') 'Detailed local errors stay expandable instead of replacing other groups'
    $report.Health.Automation.State='Conflict';$report.Health.Automation.Message='Event conflict';& $handle.Update $report
    Assert (@($handle.State.Controls.HealthList.ItemsSource).Count -eq 8 -and $handle.State.Controls.HealthText.Text -match '1 项') 'One failed health section keeps all independent sections visible'
    $report=Get-LGDemoReport;& $handle.Update $report
    $handle.State.Controls.PersistentAffinity.IsChecked=$true
    Assert ($handle.State.AffinityDirty -and $handle.State.Controls.SaveAffinityButton.IsEnabled -and $null -eq $handle.State.JobDirectory) 'Affinity edit is a draft until the explicit save action'
    & $handle.Update $report
    Assert ($handle.State.Controls.PersistentAffinity.IsChecked -and $handle.State.AffinityDirty) 'Automatic status refresh cannot overwrite a draft affinity choice'
    $report.Mode='Paused';& $handle.Update $report
    Assert ($handle.State.Controls.SaveAffinityButton.IsEnabled) 'Paused installation can save a future-start policy without resuming'
    $arguments=Get-LGPanelArguments 'tool.ps1' 'SetAffinity' 'result.json' 'progress.json' $false
    Assert ($arguments -match '-ClearLastCpu' -and $arguments -notmatch '\$false') 'Clearing affinity uses the Windows PowerShell-compatible switch'
    Assert ((Get-LGPanelArguments 'tool.ps1' 'SetAffinity' 'r' 'p' $true) -match '-BindLastCpu') 'Enabling affinity uses the explicit bind switch'
    $report.Topology.LastCpu=$null;& $handle.Update $report
    Assert (-not $handle.State.Controls.SaveAffinityButton.IsEnabled -and -not $handle.State.Controls.LastButton.IsEnabled) 'Unsupported CPU groups disable bind actions while other functions remain available'
    $report.Installed=$false;$report.Mode='NotInstalled';& $handle.Update $report
    Assert (-not $handle.State.Controls.PrimaryButton.IsEnabled) 'Unsupported pending affinity prevents installing an unusable bind policy'
    $handle.State.Controls.PersistentAffinity.IsChecked=$false
    Assert ($handle.State.Controls.PrimaryButton.IsEnabled) 'Disabling binding does not require a supported last CPU'
    $report=Get-LGDemoReport;& $handle.Update $report
    $handle.State.ConfirmRestoreOverride={return $false};& $handle.Restore
    Assert ($null -eq $handle.State.JobDirectory -and $null -eq $handle.State.Child) 'Cancelling full restore never starts a mutation'
    $restoreDialog=New-LGPanelDialog $handle.State 'Restore'
    Assert ($restoreDialog.Body.Text -match '第一次修改前' -and $restoreDialog.Cancel.IsDefault -and $restoreDialog.Confirm.Content -eq '恢复原设置') 'Restore confirmation explains the earliest baseline and keeps cancel as default'
    $restoreDialog.Window.Close()

    Assert ((Read-LGUiPreference $preference).Theme -eq 'System') 'Missing preference defaults to system theme'
    & $handle.Theme 'Dark' -Persist
    Assert ($handle.State.Appearance.Theme -eq 'Dark' -and (Read-LGUiPreference $preference).Theme -eq 'Dark') 'Dark theme applies immediately and persists locally'
    Measure-Panel $handle;$rendered=Find-RenderedText $handle.State.Window.Content 'SGuard64.exe'
    Assert ($null -ne $rendered -and $rendered.Foreground.Color -eq $handle.State.Window.Resources['TextBrush'].Color) 'Dark process header inside the expander template uses the readable theme foreground'
    $fields=@((Get-Content $preference -Raw|ConvertFrom-Json).PSObject.Properties.Name)
    Assert ($fields.Count -eq 1 -and $fields[0] -ceq 'Theme') 'Preference file contains only the theme selection'
    $dark=$handle.State.Window.Resources['TextBrush'].Color.ToString();& $handle.Theme 'Light' -Persist
    Assert ($handle.State.Appearance.Theme -eq 'Light' -and $handle.State.Window.Resources['TextBrush'].Color.ToString() -ne $dark) 'Light theme replaces live dynamic resources without recreating the window'
    Measure-Panel $handle;$rendered=Find-RenderedText $handle.State.Window.Content 'SGuard64.exe'
    Assert ($null -ne $rendered -and $rendered.Foreground.Color -eq $handle.State.Window.Resources['TextBrush'].Color) 'Existing process templates change back to the light theme foreground'
    [IO.File]::WriteAllText($preference,'{"Theme":"Dark","Command":"untrusted"}')
    Assert ((Read-LGUiPreference $preference).Warning -and (Read-LGUiPreference $preference).Theme -eq 'System') 'Unexpected preference fields fall back to system rather than being consumed'
    [IO.File]::WriteAllText($preference,'invalid')
    Assert ((Read-LGUiPreference $preference).Warning) 'Corrupt preference is recoverable without touching runtime state'
    $environment=[pscustomobject]@{Dark=$true;HighContrast=$false;Transparency=$true;Build=22621;BatterySaver=$false}
    & $handle.Theme 'System' -Environment $environment
    Assert ($handle.State.Appearance.Theme -eq 'Dark') 'System theme follows a dark Windows application preference'
    $environment.Dark=$false;& $handle.Theme 'System' -Environment $environment
    Assert ($handle.State.Appearance.Theme -eq 'Light') 'System theme can update while the same window remains open'
    Assert ((Resolve-LGAppearance 'System' $environment).Mica) 'Supported build and settings permit the native Mica attempt'
    $environment.Build=19045
    Assert ((Resolve-LGAppearance 'Light' $environment).Reason -eq 'Unsupported') 'Windows 10 takes the solid fallback'
    $environment.Build=22621;$environment.Transparency=$false
    Assert ((Resolve-LGAppearance 'Light' $environment).Reason -eq 'TransparencyOff') 'Transparency disabled takes the solid fallback'
    $environment.Transparency=$true;$environment.BatterySaver=$true
    Assert ((Resolve-LGAppearance 'Light' $environment).Reason -eq 'BatterySaver') 'Battery saver takes the solid fallback'
    $environment.BatterySaver=$false;$environment.HighContrast=$true;& $handle.Theme 'Dark' -Environment $environment
    Assert ($handle.State.Appearance.HighContrast -and [object]::ReferenceEquals($handle.State.Window.Resources['TextBrush'],[Windows.SystemColors]::WindowTextBrush)) 'High contrast overrides custom palette using system colours'
    $environment.HighContrast=$false
    $fakeNative=[pscustomobject]@{};$fakeNative|Add-Member ScriptMethod Apply {param($dark,$mica,$contrast)return $false}
    $handle.State.Native=$fakeNative;& $handle.Theme 'Light' -Environment $environment
    Assert ($handle.State.Appearance.Reason -eq 'ApiFailed' -and -not $handle.State.Appearance.Mica -and $handle.State.Window.Background.Opacity -eq 1) 'A failed native backdrop attempt restores a fully opaque usable background'
    $handle.State.Native=$null

    $handle.State.Child=[pscustomobject]@{HasExited=$false};& $handle.Actions
    $closingArgs=[ComponentModel.CancelEventArgs]::new();& $handle.Closing $null $closingArgs
    Assert ($closingArgs.Cancel -and $handle.State.Controls.OperationProgress.IsIndeterminate -eq [Windows.SystemParameters]::ClientAreaAnimation) 'Closing waits for mutations and indeterminate progress respects Windows animation preference'
    & $handle.Start 'Install'
    Assert ($null -eq $handle.State.JobDirectory) 'Repeated action while busy does not start a second command'
    $handle.State.Child=$null;& $handle.Actions
    $handle.State.Runspace=[RunspaceFactory]::CreateRunspace();$handle.State.Runspace.ApartmentState='STA';$handle.State.Runspace.ThreadOptions='ReuseThread';$handle.State.Runspace.Open()
    $setup=[PowerShell]::Create();$setup.Runspace=$handle.State.Runspace
    [void]$setup.AddScript('param($modulePath,$fixture) Import-Module $modulePath -DisableNameChecking;$global:Fixture=$fixture|ConvertFrom-Json;$global:Calls=0;$global:FailQuery=$false;function global:Get-LGStatus {param([switch]$Quick)$global:Calls++;Start-Sleep -Milliseconds 700;if($global:FailQuery){throw "Injected slow failure"};$copy=$global:Fixture|ConvertTo-Json -Depth 20|ConvertFrom-Json;$copy|Add-Member NoteProperty TestQuick ([bool]$Quick);$copy}').AddArgument((Join-Path $root 'src\LowGear.psm1')).AddArgument(($report|ConvertTo-Json -Depth 20))
    [void]$setup.Invoke();if($setup.HadErrors){throw ($setup.Streams.Error|Out-String)};$setup.Dispose()
    $watch=[Diagnostics.Stopwatch]::StartNew();& $handle.Refresh
    Assert ($watch.ElapsedMilliseconds -lt 500 -and -not $handle.State.Pending.IsCompleted) 'Slow query starts without blocking the dispatcher'
    $pipeline=$handle.State.Pipeline;& $handle.Refresh;& $handle.Navigate 'Settings';& $handle.Navigate 'Overview'
    Assert ([object]::ReferenceEquals($pipeline,$handle.State.Pipeline)) 'Refresh and page changes share the same in-flight query'
    $handle.State.QueryStarted=[DateTime]::UtcNow.AddSeconds(-11);& $handle.Tick
    Assert ($handle.State.Stale -and $handle.State.Controls.ReadTimestampText.Text -match '数据可能过期') 'Slow reads retain old data and visibly mark its age'
    & $handle.Start 'Install';& $handle.Start 'Resume'
    Assert ($handle.State.QueuedCommand -eq 'Install' -and $null -eq $handle.State.JobDirectory) 'Only the first mutation queues behind an ongoing read'
    $closingArgs=[ComponentModel.CancelEventArgs]::new();& $handle.Closing $null $closingArgs
    Assert (-not $closingArgs.Cancel -and $null -eq $handle.State.QueuedCommand) 'Closing before mutation begins cancels queued work rather than trapping a slow-query window'
    $handle.State.QueuedCommand=$null
    Finish-Query $handle
    Assert ($null -eq $handle.State.Pipeline -and -not $handle.State.Stale) 'Successful query clears the stale indicator and releases the pipeline'
    $handle.State.LastRefresh=[DateTime]::UtcNow.AddSeconds(-6);$handle.State.LastFull=[DateTime]::UtcNow;$handle.State.ForceFull=$false;& $handle.Tick;Finish-Query $handle
    Assert ($handle.State.LastReport.TestQuick) 'Five-second refresh uses the lightweight read'
    & $handle.Start 'Status';Finish-Query $handle
    Assert (-not $handle.State.LastReport.TestQuick) 'Manual refresh forces a full configuration check'
    $handle.State.LastRefresh=[DateTime]::UtcNow.AddSeconds(-6);$handle.State.LastFull=[DateTime]::UtcNow.AddSeconds(-31);& $handle.Tick;Finish-Query $handle
    Assert (-not $handle.State.LastReport.TestQuick) 'Thirty-second interval performs the full check'
    $before=$handle.State.LastReport
    $setup=[PowerShell]::Create();$setup.Runspace=$handle.State.Runspace;[void]$setup.AddScript('$global:FailQuery=$true');[void]$setup.Invoke();$setup.Dispose()
    & $handle.Start 'Status';Finish-Query $handle
    Assert ([object]::ReferenceEquals($before,$handle.State.LastReport) -and $handle.State.Stale) 'Failed query keeps previous readings with a stale indication'
    $closingArgs=[ComponentModel.CancelEventArgs]::new();& $handle.Closing $null $closingArgs
    Assert (-not $closingArgs.Cancel) 'Idle panel closes normally'
    & $handle.Refresh;$runspace=$handle.State.Runspace;$watch=[Diagnostics.Stopwatch]::StartNew();& $handle.Cleanup
    Assert ($watch.ElapsedMilliseconds -lt 500 -and $handle.State.Closed -and $null -eq $handle.State.Pipeline) 'Close detaches queries and settings listeners without waiting on a slow provider'
    & $handle.Refresh
    Assert ($null -eq $handle.State.Pipeline) 'Closed panel cannot start another refresh'
    Start-Sleep -Milliseconds 900
    Assert ($runspace.RunspaceStateInfo.State -eq 'Closed') 'Background query disposal reaches a terminal closed runspace'
    $handle.State.Window.Close();$handle=$null
    foreach($theme in @('Light','Dark')){foreach($scale in @(1,1.25,1.5,2)){
        $image=Join-Path $temp ($theme+'-'+$scale+'.png');Show-LGPanel -RenderOnly -ThemeMode $theme -ImagePath $image -RenderScale $scale
        $bitmap=[Windows.Media.Imaging.BitmapImage]::new([Uri]$image)
        Assert ($bitmap.PixelWidth -eq [int](1060*$scale) -and $bitmap.PixelHeight -eq [int](800*$scale)) ('Render '+$theme+' Chinese panel at scale '+$scale)
        $bitmap=$null
    }}
    foreach($pageName in @('Settings','Diagnostics')){
        $image=Join-Path $temp ($pageName+'.png');Show-LGPanel -RenderOnly -ThemeMode Dark -PreviewPage $pageName -ImagePath $image -RenderWidth 880 -RenderHeight 600
        Assert ((Get-Item $image).Length -gt 10000) ('Render compact '+$pageName+' page at minimum size')
    }
    [pscustomobject]@{Status='Passed';Count=$checks.Count;Checks=$checks.ToArray()}|ConvertTo-Json -Depth 5
}finally{
    if($null -ne $handle){& $handle.Cleanup;$handle.State.Window.Close()}
    [GC]::Collect();[GC]::WaitForPendingFinalizers()
    $expected=[IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('LowGear-panel-tests-'+$id)))
    if($id -cnotmatch '^[a-f0-9]{32}$' -or [IO.Path]::GetFullPath($temp) -cne $expected){throw 'Unsafe panel cleanup'}
    if([IO.Directory]::Exists($temp)){[IO.Directory]::Delete($temp,$true)}
}
