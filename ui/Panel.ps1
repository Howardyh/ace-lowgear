. (Join-Path $PSScriptRoot 'Theme.ps1')
. (Join-Path $PSScriptRoot 'PanelModel.ps1')

function New-LGPanelDialog {
    param($Ui,[ValidateSet('Diagnostic','Restore')][string]$Kind)
    $dialog=[Windows.Window]::new();if($Ui.Window.IsLoaded){$dialog.Owner=$Ui.Window};$dialog.Width=620;$dialog.Height=if($Kind -eq 'Diagnostic'){540}else{300}
    $dialog.MinWidth=480;$dialog.WindowStartupLocation='CenterOwner';$dialog.FontFamily='Microsoft YaHei UI';$dialog.FontSize=14
    $dialog.Background=$Ui.Window.Resources['CanvasBrush'];$dialog.Foreground=$Ui.Window.Resources['TextBrush']
    [void]$dialog.Resources.MergedDictionaries.Add($Ui.Window.Resources)
    $dock=[Windows.Controls.DockPanel]::new();$dock.Margin=24
    $buttons=[Windows.Controls.StackPanel]::new();$buttons.Orientation='Horizontal';$buttons.HorizontalAlignment='Right';$buttons.Margin='0,20,0,0';[Windows.Controls.DockPanel]::SetDock($buttons,'Bottom')
    $cancel=[Windows.Controls.Button]::new();$cancel.Content=if($Kind -eq 'Restore'){'取消'}else{'关闭'};$cancel.IsCancel=$true;$cancel.MinWidth=80
    $confirm=[Windows.Controls.Button]::new();$confirm.MinWidth=100
    if($Kind -eq 'Diagnostic'){
        $dialog.Title='诊断摘要 · 预览后复制';$confirm.Content='复制此摘要';$confirm.Style=$Ui.Window.Resources['PrimaryButton']
        $text=[Windows.Controls.TextBox]::new();$text.Text=$Ui.LastDiagnostic;$text.IsReadOnly=$true;$text.VerticalScrollBarVisibility='Auto';$text.TextWrapping='Wrap';$text.Background=$Ui.Window.Resources['SurfaceBrush'];$text.Foreground=$Ui.Window.Resources['TextBrush'];$text.BorderBrush=$Ui.Window.Resources['StrokeBrush'];$text.Padding=12
        $confirm.Add_Click({try{[Windows.Clipboard]::SetText($Ui.LastDiagnostic);$confirm.Content='已复制，可自行分享'}catch{$confirm.Content='复制失败，请重试'}}.GetNewClosure())
    }else{
        $dialog.Title='完整恢复前确认';$confirm.Content='恢复原设置';$confirm.Style=$Ui.Window.Resources['DangerButton'];$cancel.IsDefault=$true
        $text=[Windows.Controls.TextBlock]::new();$text.Text="将移除本工具的自动触发与任务，恢复第一次修改前的启动设置。原始备份会保留。`n`n当前已经运行的 ACE 实例需要正常重启，才会使用原始启动设置。";$text.TextWrapping='Wrap';$text.LineHeight=24
        $confirm.Add_Click({$dialog.DialogResult=$true}.GetNewClosure())
    }
    $cancel.Add_Click({$dialog.Close()}.GetNewClosure())
    [void]$buttons.Children.Add($cancel);[void]$buttons.Children.Add($confirm);[void]$dock.Children.Add($buttons);[void]$dock.Children.Add($text);$dialog.Content=$dock
    [pscustomobject]@{Window=$dialog;Confirm=$confirm;Cancel=$cancel;Body=$text}
}

function Show-LGPanel {
    param([switch]$RenderOnly,[string]$ImagePath,[double]$RenderScale=1,[switch]$PassThru,
        [ValidateSet('System','Light','Dark')][string]$ThemeMode='System',
        [ValidateSet('Overview','Settings','Diagnostics')][string]$PreviewPage='Overview',
        [double]$RenderWidth=1060,[double]$RenderHeight=800,[switch]$Demo,[string]$PreferencePath)
    Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
    Initialize-LGWindowEffects
    $reader=[Xml.XmlReader]::Create([IO.StringReader]::new([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Panel.xaml'))))
    try{$window=[Windows.Markup.XamlReader]::Load($reader)}finally{$reader.Dispose()}
    $names=@('SidebarColumn','BrandText','BrandCaption','OverviewNav','SettingsNav','DiagnosticsNav','OverviewNavLabel','SettingsNavLabel','DiagnosticsNavLabel','OverviewPage','SettingsPage','DiagnosticsPage',
        'PageTitle','PageCaption','VersionText','MaterialText','PreviewBadge','ManagerText','ManagerHint','LiveStatus','LiveText','SummaryText','GuideText','ProcessesList','SessionText','DetailText','HealthText','HealthList',
        'PrimaryButton','ApplyButton','OpenSettingsButton','RefreshButton','InstallButton','UpgradeButton','PauseButton','ResumeButton','RepairButton','DiagnosticButton','LastButton','SelfTestButton','RestoreButton','SaveAffinityButton',
        'PersistentAffinity','AffinityText','AffinitySavedText','SettingsVersionText','ThemeCombo','AppearanceHint','OperationText','OperationProgress','ReadTimestampText')
    $controls=@{};foreach($name in $names){$controls[$name]=$window.FindName($name);if($null -eq $controls[$name]){throw ('界面控件缺失：'+$name)}}
    if(-not $PreferencePath){$PreferencePath=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'ACE-LowGear\ui.json'}
    $preference=if($RenderOnly){[pscustomobject]@{Theme=$ThemeMode;Warning=$false}}else{Read-LGUiPreference $PreferencePath}
    $ui=[pscustomobject]@{Window=$window;Controls=$controls;Child=$null;JobDirectory=$null;LastReport=$null;Initialized=$false;ForceFull=$true;LastFull=[DateTime]::MinValue;LastRefresh=[DateTime]::MinValue;LastSuccess=[DateTime]::MinValue;Stale=$false
        Runspace=$null;Pipeline=$null;Pending=$null;QueryStarted=[DateTime]::MinValue;QueryFull=$true;Closed=$false;QueuedCommand=$null;Entry=(Join-Path (Split-Path $PSScriptRoot -Parent) 'LowGear.ps1');LastDiagnostic=$null
        CurrentPage='Overview';Navigating=$false;Compact=$false;ProcessGroups=@();AffinityDirty=$false;SyncingAffinity=$false;ThemePreference=$preference.Theme;ThemeSyncing=$false;PreferenceWarning=$preference.Warning;PreferencePath=$PreferencePath;Appearance=$null;Native=$null;ApplyTheme=$null
        Demo=([bool]$Demo -or [bool]$RenderOnly);Rendering=[bool]$RenderOnly;ConfirmRestoreOverride=$null;LastCommand=$null;TickHandler=$null}
    $getDiagnostic=Get-Command Get-LGDiagnostic
    $navigate={param([string]$page)
        if($ui.Closed -or $ui.Navigating -or $page -notin @('Overview','Settings','Diagnostics')){return}
        $ui.Navigating=$true
        try{
            $ui.CurrentPage=$page
            foreach($item in @('Overview','Settings','Diagnostics')){$ui.Controls[$item+'Page'].Visibility=if($item -eq $page){'Visible'}else{'Collapsed'};$ui.Controls[$item+'Nav'].IsChecked=$item -eq $page}
            $ui.Controls.PageTitle.Text=@{Overview='概览';Settings='设置';Diagnostics='诊断'}[$page]
            $ui.Controls.PageCaption.Text=@{Overview='查看自动执行与当前进程的实际状态。';Settings='调整本机外观、启动策略和自动执行。';Diagnostics='分别检查配置与读值，按原因处理问题。'}[$page]
        }finally{$ui.Navigating=$false}
    }.GetNewClosure()
    $resize={param([double]$width)
        $ui.Compact=$width -lt 960;$ui.Controls.SidebarColumn.Width=if($ui.Compact){64}else{200}
        foreach($name in @('OverviewNavLabel','SettingsNavLabel','DiagnosticsNavLabel','BrandCaption','VersionText','MaterialText')){$ui.Controls[$name].Visibility=if($ui.Compact){'Collapsed'}else{'Visible'}}
        $ui.Controls.BrandText.Text=if($ui.Compact){'LG'}else{'ACE LowGear'};$ui.Controls.BrandText.FontSize=if($ui.Compact){14}else{18}
    }.GetNewClosure()
    $applyTheme={param([string]$selection,[switch]$Persist,$Environment=$null)
        if($selection -cnotin @('System','Light','Dark')){return}
        $ui.ThemePreference=$selection
        if($null -eq $Environment){$Environment=Get-LGThemeEnvironment}
        $appearance=Resolve-LGAppearance $selection $Environment
        Set-LGThemeResources $ui.Window $appearance
        $mica=$false
        if($null -ne $ui.Native){$mica=$ui.Native.Apply(($appearance.Theme -eq 'Dark'),$appearance.Mica,$appearance.HighContrast)}
        if($mica){$ui.Window.Background=[Windows.Media.Brushes]::Transparent}else{$ui.Window.Background=$ui.Window.Resources['CanvasBrush']}
        $ui.Appearance=[pscustomobject]@{Theme=$appearance.Theme;HighContrast=$appearance.HighContrast;Mica=$mica;Reason=if($appearance.Mica -and -not $mica -and $null -ne $ui.Native){'ApiFailed'}else{$appearance.Reason}}
        $ui.Controls.MaterialText.Text=if($mica){'背景：云母 · 系统管理'}else{'背景：实色'}
        $ui.Controls.AppearanceHint.Text=if($appearance.HighContrast){'已遵循 Windows 高对比度设置。'}elseif($mica){'支持时使用系统云母材质；关闭透明效果或进入节电状态时回退实色。'}elseif($ui.Rendering){'当前为静态预览；云母效果需在实际窗口中验收。'}else{'当前使用实色背景；支持云母且允许透明效果时自动启用。'}
        if($Persist){try{Write-LGUiPreference $ui.PreferencePath $selection;$ui.PreferenceWarning=$false}catch{$ui.PreferenceWarning=$true}}
        if($ui.PreferenceWarning){$ui.Controls.AppearanceHint.Text+=' 外观偏好未能读取或保存，当前选择仅在本次窗口生效。'}
        $ui.ThemeSyncing=$true
        try{foreach($item in $ui.Controls.ThemeCombo.Items){if($item.Tag -ceq $selection){$ui.Controls.ThemeCombo.SelectedItem=$item;break}}}finally{$ui.ThemeSyncing=$false}
    }.GetNewClosure()
    $ui.ApplyTheme=$applyTheme
    $setActions={
        $busy=$null -ne $ui.Child -or $null -ne $ui.QueuedCommand
        foreach($name in @('PrimaryButton','ApplyButton','RefreshButton','InstallButton','UpgradeButton','PauseButton','ResumeButton','RepairButton','DiagnosticButton','LastButton','SelfTestButton','RestoreButton','SaveAffinityButton')){$ui.Controls[$name].IsEnabled=-not $busy -and $null -ne $ui.LastReport}
        $ui.Controls.ThemeCombo.IsEnabled=-not $busy;$ui.Controls.PersistentAffinity.IsEnabled=-not $busy
        $animate=$busy -and [Windows.SystemParameters]::ClientAreaAnimation
        $ui.Controls.OperationProgress.Visibility=if($animate){'Visible'}else{'Collapsed'};$ui.Controls.OperationProgress.IsIndeterminate=$animate
        if($null -eq $ui.LastReport){return}
        $report=$ui.LastReport;$running=@($report.Processes|Where-Object Running).Count
        $installed=[bool]$report.Installed;$upgrade=$false
        try{$upgrade=$installed -and [version]$report.InstalledVersion -lt [version]$report.Version}catch{}
        $action=Get-LGPrimaryAction $report;$ui.Controls.PrimaryButton.Content=$action.Text;$ui.Controls.PrimaryButton.Tag=$action.Command
        $ui.Controls.ApplyButton.Visibility=if($action.Command -eq 'ApplyOnce'){'Collapsed'}else{'Visible'}
        foreach($name in @('ApplyButton','LastButton')){$ui.Controls[$name].IsEnabled=-not $busy -and $running -gt 0}
        if($action.Command -eq 'ApplyOnce'){$ui.Controls.PrimaryButton.IsEnabled=-not $busy -and $running -gt 0}
        $ui.Controls.PrimaryButton.ToolTip=if($action.Command -eq 'ApplyOnce' -and $running -eq 0){'ACE 尚未运行，正常启动游戏后可使用。'}else{$action.Text}
        $ui.Controls.InstallButton.Visibility=if($installed){'Collapsed'}else{'Visible'}
        $ui.Controls.UpgradeButton.Visibility=if($upgrade){'Visible'}else{'Collapsed'}
        $ui.Controls.PauseButton.Visibility=if($installed -and $report.Mode -ne 'Paused'){'Visible'}else{'Collapsed'}
        $ui.Controls.ResumeButton.Visibility=if($installed -and $report.Mode -eq 'Paused'){'Visible'}else{'Collapsed'}
        foreach($name in @('PauseButton','ResumeButton')){$ui.Controls[$name].IsEnabled=-not $busy -and $report.Mode -in @('Ready','Running','Paused')}
        foreach($name in @('RepairButton','RestoreButton')){$ui.Controls[$name].IsEnabled=-not $busy -and $installed}
        $supported=$null -ne $report.Topology.LastCpu
        $ui.Controls.UpgradeButton.IsEnabled=-not $busy -and $upgrade -and $report.Mode -in @('Ready','Running','Paused')
        if($ui.Controls.PersistentAffinity.IsChecked -and -not $supported){$ui.Controls.InstallButton.IsEnabled=$false;if($action.Command -eq 'Install'){$ui.Controls.PrimaryButton.IsEnabled=$false}}
        $ui.Controls.LastButton.IsEnabled=-not $busy -and $running -gt 0 -and $supported
        $ui.Controls.SaveAffinityButton.IsEnabled=-not $busy -and $installed -and $ui.AffinityDirty -and $report.Mode -in @('Ready','Running','Paused') -and (-not $ui.Controls.PersistentAffinity.IsChecked -or $supported)
        $ui.Controls.AffinitySavedText.Text=if(-not $installed){'首次启用时一并保存此选择。'}elseif($ui.AffinityDirty){'尚未保存 · 仅影响下次启动'}else{'已保存 · 下次启动生效'}
    }.GetNewClosure()
    $update={param($report)
        $ui.LastReport=$report;$ui.Stale=$false;$ui.LastSuccess=[DateTime]::UtcNow
        $states=@{Ready='已启用';Running='已启用 · 本次执行中';Paused='已暂停';NotInstalled='尚未启用';RecoveryRequired='需要恢复检查';WorkerUnavailable='触发配置异常'}
        $ui.Controls.ManagerText.Text=if($states.ContainsKey([string]$report.Mode)){$states[$report.Mode]}else{'状态未知'}
        $ui.Controls.ManagerHint.Text=switch($report.Mode){Paused {'启动规则和原始备份保留'};NotInstalled {'首次启用后即可关闭窗口'};RecoveryRequired {'请前往诊断页检查原因'};WorkerUnavailable {'请检查任务与启动事件'};default {'每次启动自动执行一次'}}
        $installedVersion=if($report.InstalledVersion){$report.InstalledVersion}else{'未安装'}
        $ui.Controls.VersionText.Text='面板 '+$report.Version+"`n本机 "+$installedVersion
        $ui.Controls.SettingsVersionText.Text='面板 '+$report.Version+' · 本机执行组件 '+$installedVersion
        if(-not $ui.Initialized -or -not $ui.AffinityDirty){$ui.SyncingAffinity=$true;try{$ui.Controls.PersistentAffinity.IsChecked=[bool]$report.BindLastCpu}finally{$ui.SyncingAffinity=$false}}
        $ui.Controls.AffinityText.Text=if($null -eq $report.Topology.LastCpu){'当前处理器组不支持最后 CPU 绑定；CPU / I/O 管理仍可使用。'}else{'当前最后逻辑 CPU：'+$report.Topology.LastCpu+'。这是逻辑处理器，不是物理核心。'}
        $ui.Controls.GuideText.Text=switch($report.Mode){
            NotInstalled {'首次使用：启用自动管理 → 正常启动游戏 → 查看核验结果。'}
            Paused {'自动执行已暂停。恢复后可关闭窗口，正常启动游戏。'}
            RecoveryRequired {'存在未完成的事务，请前往诊断页核验并处理。'}
            WorkerUnavailable {'自动触发需要检查；当前进程读值仍单独显示。'}
            default {'可关闭窗口正常使用；每次启动核验完成后，执行程序即退出。'}
        }
        $ui.ProcessGroups=@(Get-LGProcessGroups $report $ui.ProcessGroups);$ui.Controls.ProcessesList.ItemsSource=$ui.ProcessGroups
        $running=@($report.Processes|Where-Object Running)
        $good=@($running|Where-Object {$_.Verified -and $null -ne $_.CpuClass -and $null -ne $_.IoPriority -and $null -ne (Get-LGUiValue $_ 'EffectiveIoPriority') -and @($_.Errors).Count -eq 0})
        $processHealth=Get-LGUiValue $report.Health 'Processes'
        $tone='Neutral';$live='等待启动';$summary='未运行不代表核验通过。'
        if((Get-LGUiValue $processHealth 'State') -eq 'Error'){$tone='Error';$live='读值不可用';$summary='请查看诊断页的查询结果。'}
        elseif($running.Count){$tone=if($good.Count -eq $running.Count){'Success'}else{'Warning'};$live=if($good.Count -eq $running.Count){'当前实例已核验'}else{'存在未达标实例'};$summary='运行中 '+$running.Count+' 个实例，符合目标 '+$good.Count+' 个。'}
        $ui.Controls.LiveStatus.DataContext=[pscustomobject]@{Tone=$tone};$ui.Controls.LiveText.Text=$live;$ui.Controls.SummaryText.Text=$summary
        $sessions=@{Starting='本次启动中';Completed='已完成';NoTargets='无运行目标';Incomplete='未能完成';Verifying='核验中';Failed='执行失败'}
        $ui.Controls.SessionText.Text='尚未执行'
        if($null -ne $report.LastSession){
            $session=$report.LastSession;$label=if($sessions.ContainsKey([string]$session.SessionState)){$sessions[$session.SessionState]}else{'未知结果'}
            $time='时间未知';try{$time=[DateTime]::Parse($session.TimestampUtc).ToLocalTime().ToString('MM-dd HH:mm:ss')}catch{}
            $elapsed=Get-LGUiValue $session 'ElapsedMilliseconds';$duration=if($null -ne $elapsed){[Math]::Round($elapsed/1000,1).ToString()+' 秒'}else{'旧版记录'}
            $ui.Controls.SessionText.Text=$label+' · '+$time+' · 耗时 '+$duration
        }
        $checked='时间未知';try{$checked=[DateTime]::Parse($report.FullCheckedUtc).ToLocalTime().ToString('HH:mm:ss')}catch{}
        $ui.Controls.DetailText.Text='逻辑处理器 '+$report.Topology.LogicalProcessors+' · 处理器组 '+$report.Topology.Groups+' · 配置检查 '+$checked
        $labels=@{Installation='安装与原始备份';Policy='启动策略';Startup='启动优先级规则';Task='任务路径与身份';Automation='启动事件订阅';Runtime='执行文件完整性';Session='最近会话';Processes='当前进程读值'}
        $healthRows=@(foreach($property in $report.Health.PSObject.Properties){
            $section=$property.Value;$state=[string]$section.State
            $healthTone=if($state -eq 'Healthy'){'Success'}elseif($state -in @('Error','Conflict')){'Error'}elseif($state -eq 'Warning' -or ($state -eq 'Missing' -and $report.Installed)){'Warning'}else{'Neutral'}
            $status=@{Healthy='正常';Warning='需检查';Error='检查失败';Conflict='存在冲突';Disabled='已暂停';NotInstalled='尚未安装';Unknown='未知';NotRunning='未运行';Running='执行中';Missing='缺失';Waiting='等待启动'}[$state]
            $message=[string]$section.Message
            if(-not $report.Installed -and $state -eq 'Healthy' -and $property.Name -in @('Installation','Policy','Automation')){$healthTone='Neutral';$status='尚未启用';$message='尚未启用自动管理；没有将缺省配置视为已安装核验。'}
            [pscustomobject]@{Label=if($labels.ContainsKey($property.Name)){$labels[$property.Name]}else{$property.Name};Tone=$healthTone;Status=if($status){$status}else{$state};Message=$message;Code=[string]$section.Code}
        })
        $ui.Controls.HealthList.ItemsSource=$healthRows
        $warnings=@($healthRows|Where-Object {$_.Tone -in @('Warning','Error')})
        $ui.Controls.HealthText.Text=if($warnings.Count){$warnings.Count.ToString()+' 项需要检查。只修复归属明确的配置；诊断摘要可先预览再复制。'}else{'各项状态独立显示。自动配置正常不等于当前所有进程已经核验。'}
        $ui.Controls.ReadTimestampText.Text='最近成功读取 '+$ui.LastSuccess.ToLocalTime().ToString('HH:mm:ss')+' · 进程约 5 秒 / 完整配置约 30 秒刷新'
        if(-not $ui.Initialized){$ui.Controls.OperationText.Text=if($ui.Demo){'界面预览 · 示例数据。此窗口不修改本机调度配置。'}else{'就绪。每次 ACE 启动自动执行一次，核验后退出。'}}
        $ui.Initialized=$true
        & $setActions
    }.GetNewClosure()
    $markStale={param([string]$message)
        $ui.Stale=$true;$ui.Controls.OperationText.Text=$message
        $ui.Controls.ReadTimestampText.Text=if($ui.LastSuccess -eq [DateTime]::MinValue){'尚无成功读值 · 请稍后刷新'}else{'数据可能过期 · 上次成功读取 '+$ui.LastSuccess.ToLocalTime().ToString('HH:mm:ss')}
    }.GetNewClosure()
    $refresh={
        if($ui.Closed -or $ui.Demo -or $null -ne $ui.Child -or $null -ne $ui.Pipeline){return}
        if($null -eq $ui.Runspace){$ui.Runspace=[RunspaceFactory]::CreateRunspace();$ui.Runspace.ApartmentState='STA';$ui.Runspace.ThreadOptions='ReuseThread';$ui.Runspace.Open()}
        $ui.QueryFull=$ui.ForceFull -or ([DateTime]::UtcNow-$ui.LastFull).TotalSeconds -ge 30;$ui.ForceFull=$false;$ui.QueryStarted=[DateTime]::UtcNow
        $ui.Pipeline=[PowerShell]::Create();$ui.Pipeline.Runspace=$ui.Runspace
        [void]$ui.Pipeline.AddScript('param($entry,$full) if(-not(Get-Module LowGear)){Import-Module (Join-Path (Split-Path $entry -Parent) "src\LowGear.psm1") -DisableNameChecking};Get-LGStatus -Quick:(-not $full)|ConvertTo-Json -Depth 25').AddArgument($ui.Entry).AddArgument($ui.QueryFull)
        $ui.Pending=$ui.Pipeline.BeginInvoke()
    }.GetNewClosure()
    $start={param([string]$command)
        if($ui.Closed -or $null -ne $ui.Child -or $null -ne $ui.QueuedCommand){return}
        if($command -eq 'Diagnostics'){& $navigate 'Diagnostics';return}
        if($command -eq 'Status'){$ui.ForceFull=$true;if($ui.Demo){& $update $ui.LastReport}elseif($null -eq $ui.Pipeline){& $refresh};return}
        if($ui.Demo){$ui.Controls.OperationText.Text='此窗口使用示例数据，不执行本机配置修改。';return}
        if($null -ne $ui.Pipeline){$ui.QueuedCommand=$command;$ui.Controls.OperationText.Text='正在完成状态读取，随后执行所选操作…';& $setActions;return}
        $ui.JobDirectory=Join-Path ([IO.Path]::GetTempPath()) ('LowGear-ui-'+[Guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($ui.JobDirectory)
        try{
            $acl=[Security.AccessControl.DirectorySecurity]::new();$acl.SetAccessRuleProtection($true,$false);$acl.SetOwner([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))
            foreach($sid in @('S-1-5-18','S-1-5-32-544')){[void]$acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid),'FullControl','ContainerInherit,ObjectInherit','None','Allow'))}
            Set-Acl -LiteralPath $ui.JobDirectory -AclObject $acl
            $arguments=Get-LGPanelArguments $ui.Entry $command (Join-Path $ui.JobDirectory 'result.json') (Join-Path $ui.JobDirectory 'progress.json') ([bool]$ui.Controls.PersistentAffinity.IsChecked)
            $ui.Child=Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -WindowStyle Hidden -ArgumentList $arguments -PassThru
            $ui.LastCommand=$command;$ui.Controls.OperationText.Text='正在检查本机状态…'
        }catch{
            $ui.Controls.OperationText.Text='无法启动操作，请检查本机权限。'
            try{[IO.Directory]::Delete($ui.JobDirectory,$false)}catch{};$ui.JobDirectory=$null
        }
        & $setActions
    }.GetNewClosure()
    $diagnostic={
        if($null -eq $ui.LastReport -or $null -ne $ui.Child){return}
        $ui.LastDiagnostic=(& $getDiagnostic $ui.LastReport)|ConvertTo-Json -Depth 8
        $dialog=New-LGPanelDialog $ui 'Diagnostic';[void]$dialog.Window.ShowDialog()
    }.GetNewClosure()
    $restore={
        if($null -ne $ui.Child -or $null -ne $ui.QueuedCommand){return}
        $confirmed=$false
        if($null -ne $ui.ConfirmRestoreOverride){$confirmed=& $ui.ConfirmRestoreOverride}else{$dialog=New-LGPanelDialog $ui 'Restore';$confirmed=$dialog.Window.ShowDialog() -eq $true}
        if($confirmed){& $start 'Restore'}
    }.GetNewClosure()
    $tick={
        if($ui.Closed){return}
        if($null -ne $ui.Native -and $ui.Native.TakeChange()){& $applyTheme $ui.ThemePreference}
        if($null -ne $ui.Child){
            try{$progress=Join-Path $ui.JobDirectory 'progress.json';if(Test-Path -LiteralPath $progress){$ui.Controls.OperationText.Text=(Get-Content -LiteralPath $progress -Raw -Encoding UTF8|ConvertFrom-Json).Message}}catch{}
            if(-not $ui.Child.HasExited){return}
            try{
                $path=Join-Path $ui.JobDirectory 'result.json'
                if(Test-Path -LiteralPath $path){
                    $result=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json
                    if($result.Success){if($ui.LastCommand -in @('Install','SetAffinity')){$ui.AffinityDirty=$false};& $update $result.Report;$nextStep=switch($ui.LastCommand){Pause {'恢复自动执行后，下次启动才会触发会话。'};Restore {'请正常重启已有目标程序，以使用原始启动设置。'};SetAffinity {'策略在下次 ACE 启动时生效；已有实例保持原相关性。'};default {'可刷新查看结果，或关闭窗口正常启动游戏。'}};$ui.Controls.OperationText.Text=$result.Message+' 下一步：'+$nextStep}
                    else{$ui.Controls.OperationText.Text=$result.Message}
                }else{$ui.Controls.OperationText.Text='操作未返回结果，请查看诊断摘要。'}
            }catch{$ui.Controls.OperationText.Text='操作结果无法读取，请刷新状态。'}finally{
                $ui.Child.Dispose();$ui.Child=$null
                try{foreach($name in @('result.json','progress.json')){$path=Join-Path $ui.JobDirectory $name;if([IO.File]::Exists($path)){[IO.File]::Delete($path)}};[IO.Directory]::Delete($ui.JobDirectory,$false)}catch{}
                $ui.JobDirectory=$null;$ui.ForceFull=$true;& $setActions
            }
        }
        if($null -ne $ui.Pipeline){
            if(-not $ui.Pending.IsCompleted){if(([DateTime]::UtcNow-$ui.QueryStarted).TotalSeconds -gt 10){& $markStale '系统查询较慢；当前显示上次结果，未重复发起查询。'};return}
            try{$output=$ui.Pipeline.EndInvoke($ui.Pending);if($ui.Pipeline.HadErrors){throw 'Query failed'};$report=($output -join "`n")|ConvertFrom-Json;& $update $report;if($ui.QueryFull){$ui.LastFull=[DateTime]::UtcNow}}
            catch{& $markStale '本次读取失败，保留上次结果；可手动刷新或查看诊断摘要。'}
            finally{$ui.Pipeline.Dispose();$ui.Pipeline=$null;$ui.Pending=$null;$ui.LastRefresh=[DateTime]::UtcNow}
        }
        if($null -ne $ui.QueuedCommand){$next=$ui.QueuedCommand;$ui.QueuedCommand=$null;& $start $next;return}
        if($ui.ForceFull -or ([DateTime]::UtcNow-$ui.LastRefresh).TotalSeconds -ge 5){& $refresh}
    }.GetNewClosure()
    $closing={param($sender,$eventArgs)
        if($null -ne $ui.Child){$eventArgs.Cancel=$true;$ui.Controls.OperationText.Text='正在修改本机配置，请等待操作完成后关闭。'}
        elseif($null -ne $ui.QueuedCommand){$ui.QueuedCommand=$null;$ui.Controls.OperationText.Text='所选操作尚未开始，已取消等待中的操作。'}
    }.GetNewClosure()
    $timer=[Windows.Threading.DispatcherTimer]::new();$timer.Interval=[TimeSpan]::FromMilliseconds(250);$ui.TickHandler=[EventHandler]$tick;$timer.Add_Tick($ui.TickHandler)
    $cleanup={
        if($ui.Closed){return}
        $ui.Closed=$true;$timer.Stop();$timer.Remove_Tick($ui.TickHandler)
        if($null -ne $ui.Native){try{$ui.Native.Dispose()}catch{};$ui.Native=$null}
        $pipeline=$ui.Pipeline;$runspace=$ui.Runspace;$ui.Pipeline=$null;$ui.Runspace=$null;$ui.Pending=$null
        if($null -ne $pipeline -or $null -ne $runspace){[LowGear.UI.WindowEffects]::ReleaseQuery($pipeline,$runspace)}
    }.GetNewClosure()
    # Keep helpers private to callbacks, including when invoked from a nested script scope.
    $helpers=@(foreach($name in @('Read-LGUiPreference','Write-LGUiPreference','Get-LGThemeEnvironment','Resolve-LGAppearance','Set-LGThemeResources','Get-LGUiValue','Get-LGPrimaryAction','Get-LGCpuLabel','Get-LGIoLabel','Get-LGAffinityLabel','Get-LGProcessGroups','Get-LGPanelArguments','New-LGPanelDialog')){Get-Command $name})
    foreach($callback in @($navigate,$resize,$applyTheme,$setActions,$update,$markStale,$refresh,$start,$diagnostic,$restore,$tick,$closing,$cleanup)){
        & $callback.Module {param($functions)foreach($function in $functions){Set-Item -Path ('Function:script:'+$function.Name) -Value $function.ScriptBlock}} $helpers
    }
    foreach($page in @('Overview','Settings','Diagnostics')){$controls[$page+'Nav'].Tag=$page;$controls[$page+'Nav'].Add_Checked({param($sender,$eventArgs)& $navigate ([string]$sender.Tag)}.GetNewClosure())}
    $controls.OpenSettingsButton.Add_Click({& $navigate 'Settings'}.GetNewClosure())
    foreach($pair in @(@('InstallButton','Install'),@('UpgradeButton','Upgrade'),@('ApplyButton','ApplyOnce'),@('PauseButton','Pause'),@('ResumeButton','Resume'),@('RepairButton','Repair'),@('RefreshButton','Status'),@('LastButton','LastCpu'),@('SelfTestButton','SelfTest'),@('SaveAffinityButton','SetAffinity'))){$controls[$pair[0]].Tag=$pair[1]}
    foreach($name in @('PrimaryButton','InstallButton','UpgradeButton','ApplyButton','PauseButton','ResumeButton','RepairButton','RefreshButton','LastButton','SelfTestButton','SaveAffinityButton')){
        $controls[$name].Add_Click({param($sender,$eventArgs)try{& $start ([string]$sender.Tag)}catch{$ui.Controls.OperationText.Text='操作无法启动，请检查权限或查看诊断摘要。'}}.GetNewClosure())
    }
    $controls.RestoreButton.Add_Click($restore);$controls.DiagnosticButton.Add_Click($diagnostic)
    $affinityChanged={if(-not $ui.SyncingAffinity -and $null -ne $ui.LastReport){$ui.AffinityDirty=[bool]$ui.Controls.PersistentAffinity.IsChecked -ne [bool]$ui.LastReport.BindLastCpu;& $setActions}}.GetNewClosure()
    $controls.PersistentAffinity.Add_Checked($affinityChanged);$controls.PersistentAffinity.Add_Unchecked($affinityChanged)
    $controls.ThemeCombo.Add_SelectionChanged({if(-not $ui.ThemeSyncing -and $null -ne $ui.Controls.ThemeCombo.SelectedItem){& $applyTheme ([string]$ui.Controls.ThemeCombo.SelectedItem.Tag) -Persist}}.GetNewClosure())
    $window.Add_SourceInitialized({$handle=[Windows.Interop.WindowInteropHelper]::new($ui.Window).Handle;$ui.Native=[LowGear.UI.WindowEffects]::new($handle);& $applyTheme $ui.ThemePreference}.GetNewClosure())
    $window.Add_SizeChanged({param($sender,$eventArgs)& $resize $sender.ActualWidth}.GetNewClosure());$window.Add_Closing($closing);$window.Add_Closed($cleanup)
    & $applyTheme $ui.ThemePreference;& $navigate $PreviewPage;& $resize $RenderWidth;& $setActions
    if($ui.Demo){$window.Title='ACE LowGear · Fluent 预览 · 示例数据';$controls.PreviewBadge.Visibility='Visible';& $update (Get-LGDemoReport)}
    if($PassThru){return [pscustomobject]@{State=$ui;Update=$update;Start=$start;Refresh=$refresh;Tick=$tick;Closing=$closing;Cleanup=$cleanup;Navigate=$navigate;Resize=$resize;Theme=$applyTheme;Restore=$restore;Actions=$setActions}}
    if($RenderOnly){
        $window.Width=$RenderWidth;$window.Height=$RenderHeight
        $visual=$window.Content;$visual.Measure([Windows.Size]::new($RenderWidth,$RenderHeight));$visual.Arrange([Windows.Rect]::new(0,0,$RenderWidth,$RenderHeight));$visual.UpdateLayout()
        $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new([int]($RenderWidth*$RenderScale),[int]($RenderHeight*$RenderScale),96*$RenderScale,96*$RenderScale,[Windows.Media.PixelFormats]::Pbgra32)
        $background=[Windows.Media.DrawingVisual]::new();$drawing=$background.RenderOpen();try{$drawing.DrawRectangle($window.Resources['CanvasBrush'],$null,[Windows.Rect]::new(0,0,$RenderWidth,$RenderHeight))}finally{$drawing.Close()}
        $bitmap.Render($background);$bitmap.Render($visual);$encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap));$stream=[IO.File]::Create($ImagePath);try{$encoder.Save($stream)}finally{$stream.Dispose()};$window.Close();& $cleanup;return
    }
    $window.Height=[Math]::Max(600,[Math]::Min(800,[Windows.SystemParameters]::WorkArea.Height-30));$timer.Start();[void]$window.ShowDialog()
}
