function Read-LGOnboarding {
    param([string]$Path)
    try{
        if(-not [IO.File]::Exists($Path)){return $false}
        $file=Get-Item -LiteralPath $Path -Force
        if($file.Length -gt 2048 -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)){return $false}
        $value=[IO.File]::ReadAllText($Path)|ConvertFrom-Json
        $value.Schema -is [int] -and $value.Schema -eq 1 -and $value.Handled -is [bool] -and $value.Handled
    }catch{$false}
}
function Set-LGOnboardingHandled {
    param([string]$Path)
    if(-not $Path){return $false}
    $temporary=$null
    try{
        $directory=Split-Path $Path -Parent
        foreach($item in @($directory,$Path)){if((Test-Path -LiteralPath $item) -and ((Get-Item -LiteralPath $item -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){return $false}}
        [void][IO.Directory]::CreateDirectory($directory);$temporary=$Path+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
        [IO.File]::WriteAllText($temporary,'{"Schema":1,"Handled":true}',[Text.UTF8Encoding]::new($false))
        if([IO.File]::Exists($Path)){[IO.File]::Replace($temporary,$Path,[Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($temporary,$Path)}
        return $true
    }catch{return $false}finally{if($temporary -and [IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}}
}
function Get-LGSetupRoute {
    param($Report,[bool]$Handled)
    if($null -eq $Report){return 'Diagnostics'}
    if($Report.Mode -in @('RecoveryRequired','WorkerUnavailable') -or $Report.Health.Installation.State -ne 'Healthy'){return 'Diagnostics'}
    foreach($name in @('Policy','Startup','Task','Automation')){if($Report.Health.$name.State -in @('Error','Conflict','Unknown')){return 'Diagnostics'}}
    if($Report.Installed -or $Handled){return 'Panel'}
    if($Report.Mode -eq 'NotInstalled'){return 'Wizard'}
    'Diagnostics'
}
function Get-LGOperationOutcome {
    param([string]$Command,$Result)
    if(-not $Result.Success){return [pscustomobject]@{Title='操作未完成';Text='请查看诊断摘要及分项检查。不会自动覆盖冲突配置，也不会重复执行。';Tone='Error'}}
    $report=$Result.Report
    if($Command -eq 'Restore'){return [pscustomobject]@{Title='已恢复原始启动设置';Text="自动触发与任务已移除，最早原始备份保留。`n已有 ACE 实例请正常重启后再核验。";Tone='Success'}}
    if($report.Mode -in @('RecoveryRequired','WorkerUnavailable')){return [pscustomobject]@{Title='操作已返回，配置需要检查';Text='请进入诊断核对分项状态，再判断是否可以正常使用。';Tone='Warning'}}
    $live=@($report.Processes|Where-Object Running);$good=@($live|Where-Object Verified)
    $verification=if($live.Count -eq 0){'等待游戏启动：本次没有运行目标，尚未核验实际 ACE。'}elseif($good.Count -eq $live.Count){'当前运行实例已核验；此结果仅代表当前读值。'}else{'当前部分实例未达标或无法读取，请查看诊断。'}
    $configuration=if($report.Mode -eq 'Paused'){'本机组件已就绪，自动执行保持暂停。需要时在面板恢复。'}else{'自动执行已配置。可以关闭窗口，正常启动游戏；电脑重启后无需重复安装。'}
    [pscustomobject]@{Title=if($report.Mode -eq 'Paused'){'升级完成 · 保持暂停'}else{'配置已完成'};Text=($configuration+"`n`n"+$verification+"`n`n原始备份保留；启动相关性策略按本次确认的操作处理。");Tone=if($live.Count -gt $good.Count){'Warning'}else{'Success'}}
}
function Set-LGSetupBounds {
    param($Window)
    $environment=Get-LGPlacementEnvironment $Window
    $bounds=[LowGear.UI.WindowPlacement]::CurrentBounds([Windows.Interop.WindowInteropHelper]::new($Window).Handle,$environment.ScaleX,$environment.ScaleY)
    $saved=[LowGear.UI.WindowPlacement]::Capture($bounds,$false,$environment.Areas,$environment.ScaleX,$environment.ScaleY)
    $area=if($null -ne $saved){$saved.WorkArea}else{@($environment.Areas|Select-Object -First 1)[0]}
    $width=[Math]::Max(1,$area.Width/$environment.ScaleX-16);$height=[Math]::Max(1,$area.Height/$environment.ScaleY-16)
    $Window.MinWidth=[Math]::Min(720,$width);$Window.MinHeight=[Math]::Min(520,$height);$Window.Width=[Math]::Min(880,$width);$Window.Height=[Math]::Min(640,$height)
    $Window.Left=$area.Left/$environment.ScaleX+($area.Width/$environment.ScaleX-$Window.Width)/2;$Window.Top=$area.Top/$environment.ScaleY+($area.Height/$environment.ScaleY-$Window.Height)/2
}
function New-LGSetupWindow {
    param($Ui,[scriptblock]$Start,[scriptblock]$RequestPreflight,[scriptblock]$Navigate,[string]$OnboardingPath,[switch]$Initial,[ValidateSet('Install','Upgrade','Restore')][string]$Command='Install')
    $window=[Windows.Window]::new();$window.Title=if($Ui.Demo){'ACE LowGear · 安装向导 · 示例数据'}else{'ACE LowGear · 安装与交付'};$window.Width=880;$window.Height=640;$window.MinWidth=720;$window.MinHeight=520;$window.WindowStartupLocation='CenterScreen'
    if($Ui.Window.IsVisible){$window.Owner=$Ui.Window;$window.WindowStartupLocation='CenterOwner'}
    $window.FontFamily='Microsoft YaHei UI';$window.FontSize=14;$window.Background=$Ui.Window.Resources['CanvasBrush'];$window.Foreground=$Ui.Window.Resources['TextBrush'];[void]$window.Resources.MergedDictionaries.Add($Ui.Window.Resources)
    $layout=[Windows.Controls.DockPanel]::new();$layout.Margin=24
    $header=[Windows.Controls.StackPanel]::new();$title=[Windows.Controls.TextBlock]::new();$title.FontSize=26;$title.FontWeight='SemiBold';$title.Margin='0,0,0,8'
    $steps=[Windows.Controls.TextBlock]::new();$steps.Text='1 介绍与策略　›　2 检查与确认　›　3 执行　›　4 结果';$steps.TextWrapping='Wrap';$steps.Foreground=$window.Resources['SecondaryBrush'];$steps.Margin='0,0,0,24'
    if($Ui.Demo){$steps.Text+="`n示例数据 · 不代表本机检查结果，不执行配置修改。"}
    [void]$header.Children.Add($title);[void]$header.Children.Add($steps);[Windows.Controls.DockPanel]::SetDock($header,'Top');[void]$layout.Children.Add($header)
    $footer=[Windows.Controls.StackPanel]::new();$footer.Margin='0,16,0,0';[Windows.Controls.DockPanel]::SetDock($footer,'Bottom')
    $stage=[Windows.Controls.TextBlock]::new();$stage.TextWrapping='Wrap';$stage.Margin='0,0,0,8'
    $progress=[Windows.Controls.ProgressBar]::new();$progress.Height=4;$progress.Margin='0,0,0,12'
    $buttons=[Windows.Controls.WrapPanel]::new();$buttons.HorizontalAlignment='Right'
    $extra=[Windows.Controls.Button]::new();$extra.Content='查看诊断';$extra.MinWidth=100
    $secondary=[Windows.Controls.Button]::new();$secondary.MinWidth=110;$secondary.Margin='8,0,0,0'
    $primary=[Windows.Controls.Button]::new();$primary.MinWidth=120;$primary.Margin='8,0,0,0';$primary.Style=$window.Resources['PrimaryButton']
    foreach($control in @($extra,$secondary,$primary)){[void]$buttons.Children.Add($control)}
    foreach($control in @($stage,$progress,$buttons)){[void]$footer.Children.Add($control)};[void]$layout.Children.Add($footer)
    $scroll=[Windows.Controls.ScrollViewer]::new();$scroll.VerticalScrollBarVisibility='Auto';$body=[Windows.Controls.StackPanel]::new();$body.Margin='0,0,8,0';$scroll.Content=$body
    $card=[Windows.Controls.Border]::new();$card.CornerRadius=8;$card.Padding=24;$card.Background=$window.Resources['SurfaceBrush'];$card.BorderBrush=$window.Resources['StrokeBrush'];$card.BorderThickness=1;$card.Child=$scroll;[void]$layout.Children.Add($card);$window.Content=$layout
    $state=[pscustomobject]@{Window=$window;Step=if($Initial){'Checking'}elseif($Command -eq 'Install'){'Intro'}elseif($Command -eq 'Upgrade'){'Review'}else{'Working'};Command=$Command;Route='Exit';Initial=[bool]$Initial;Closed=$false;Check=$null;Result=$null;Native=$null;Started=$false;OnReport=$null;OnPreflight=$null;OnResult=$null;Progress=$null
        Controls=[pscustomobject]@{Title=$title;Steps=$steps;Body=$body;Primary=$primary;Secondary=$secondary;Extra=$extra;Stage=$stage;Progress=$progress;Affinity=$null};Render=$null}
    $addText={param([string]$Text)
        $block=[Windows.Controls.TextBlock]::new();$block.Text=$Text;$block.TextWrapping='Wrap';$block.LineHeight=24;$block.Margin='0,0,0,16';[void]$body.Children.Add($block)
    }.GetNewClosure()
    $render={
        $body.Children.Clear();$state.Controls.Affinity=$null;$primary.IsEnabled=$true;$secondary.IsEnabled=$true;$extra.Visibility='Collapsed';$progress.Visibility='Collapsed';$progress.IsIndeterminate=$false;$stage.Text=''
        if($null -ne $Ui.LastReport){$window.Title='ACE LowGear '+$Ui.LastReport.Version+' · '+$(if($Ui.Demo){'示例安装向导'}else{'安装与交付'})}
        $labels=@{Checking='正在检查本机状态';Intro='欢迎使用 ACE LowGear';Review=if($state.Command -eq 'Upgrade'){'确认升级本机组件'}else{'确认启用自动管理'};Working='正在执行，请稍候';Result='操作结果'};$title.Text=$labels[$state.Step]
        switch($state.Step){
            Checking {& $addText '正在读取安装记录与配置。尚未修改任何调度设置。';$primary.IsEnabled=$false;$primary.Content='检查中';$secondary.Content='先查看面板'}
            Intro {
                & $addText "每次 ACE 启动时设置低 CPU / 非常低 I/O，回读核验后退出。首次启用会保存最早原始设置。`n`n启用后可以关闭面板，电脑重启后无需重复安装。"
                $affinity=[Windows.Controls.CheckBox]::new();$affinity.Content='启动时绑定最后一个逻辑 CPU（可选）';$affinity.Margin='0,8,0,16';$affinity.IsChecked=[bool]$Ui.Controls.PersistentAffinity.IsChecked
                if($null -ne $Ui.LastReport -and $null -eq $Ui.LastReport.Topology.LastCpu){$affinity.IsEnabled=$false;$affinity.IsChecked=$false}
                $state.Controls.Affinity=$affinity;[void]$body.Children.Add($affinity);& $addText '默认保持相关性不变。下一步仅预检，点击最终确认后才会安装。';$primary.Content='下一步：检查';$secondary.Content='先查看面板'
            }
            Review {
                $report=$Ui.LastReport
                if($state.Command -eq 'Upgrade'){
                    & $addText ('本机版本：'+$report.InstalledVersion+'　→　目标版本：'+$report.Version+"`n保留当前相关性策略、最早原始备份，以及启用或暂停状态。`n当前状态："+$(if($report.Mode -eq 'Paused'){'已暂停，升级后继续暂停。'}else{'已启用。'}))
                }else{& $addText ('将保存最早原始设置并启用自动执行。启动相关性：'+$(if($Ui.Controls.PersistentAffinity.IsChecked){'绑定最后一个逻辑 CPU。'}else{'保持原设置。'}))}
                if($null -eq $state.Check){& $addText '正在只读预检；真实启动自检会在确认安装后执行。';$primary.IsEnabled=$false}
                else{$checkNames=@{Source='源码文件';System='系统环境';Installation='安装记录与原始备份';Policy='启动策略';Startup='启动优先级规则';Task='自动执行任务';Automation='启动事件';Runtime='执行组件';Baseline='原始设置或旧版迁移'};foreach($item in $state.Check.Detail.Checks){$name=if($checkNames.ContainsKey([string]$item.Name)){$checkNames[[string]$item.Name]}else{[string]$item.Name};& $addText ((@{Healthy='✓';Warning='!';Error='×';Missing='·';Waiting='·'}[[string]$item.State])+' '+$name+'：'+$item.Message)};$primary.IsEnabled=[bool]$state.Check.Success}
                $primary.Content=if($state.Command -eq 'Upgrade'){'确认升级'}else{'确认并启用'};$secondary.Content=if($state.Command -eq 'Install'){'上一步'}else{'取消'};$extra.Visibility='Visible'
            }
            Working {& $addText '正在调用本工具统一控制器。修改开始后，请等待结果再关闭窗口。';$primary.Content='执行中';$primary.IsEnabled=$false;$secondary.Content='请稍候';$secondary.IsEnabled=$false;$progress.Visibility=if([Windows.SystemParameters]::ClientAreaAnimation){'Visible'}else{'Collapsed'};$progress.IsIndeterminate=[Windows.SystemParameters]::ClientAreaAnimation}
            Result {
                $outcome=Get-LGOperationOutcome $state.Command $state.Result;$title.Text=$outcome.Title;& $addText $outcome.Text
                if(-not $state.Result.Success){& $addText ('错误码：'+(Get-LGUiValue $state.Result 'Code' 'OPERATION_FAILED'))}
                $primary.Content='返回概览';$secondary.Content='关闭工具';$extra.Content=if($state.Result.Success){'打开本机备份目录'}else{'查看诊断'};$extra.Visibility='Visible'
            }
        }
    }.GetNewClosure();$state.Render=$render
    $onReport={param($report)
        if($state.Closed -or $state.Step -ne 'Checking'){return}
        $route=Get-LGSetupRoute $report (Read-LGOnboarding $OnboardingPath)
        if($route -eq 'Wizard'){$state.Step='Intro';& $render;return}
        if($report.Installed -and $report.Health.Installation.State -eq 'Healthy'){[void](Set-LGOnboardingHandled $OnboardingPath)}
        $state.Route=$route;$window.Close()
    }.GetNewClosure();$state.OnReport=$onReport
    $onPreflight={param($result)if($state.Closed -or $state.Step -ne 'Review'){return};$state.Check=$result;& $render}.GetNewClosure();$state.OnPreflight=$onPreflight
    $onResult={param($result)
        if($state.Closed){return};$state.Result=$result;$state.Step='Result'
        if($result.Success){[void](Set-LGOnboardingHandled $OnboardingPath)};& $render
    }.GetNewClosure();$state.OnResult=$onResult
    $onProgress={
        if($state.Closed){return}
        if($state.Step -eq 'Working'){$stage.Text=$Ui.Controls.OperationText.Text}
        if($null -ne $state.Native){
            if($state.Native.TakeChange()){
                & $Ui.ApplyTheme $Ui.ThemePreference;$appearance=Resolve-LGAppearance $Ui.ThemePreference (Get-LGThemeEnvironment) $Ui.VisualPreference.Material
                $mica=$state.Native.Apply(($appearance.Theme -eq 'Dark'),$appearance.Mica,$appearance.HighContrast)
                $window.Background=if($mica){[Windows.Media.Brushes]::Transparent}else{$Ui.Window.Resources['CanvasBrush']};$window.Foreground=$Ui.Window.Resources['TextBrush'];$steps.Foreground=$Ui.Window.Resources['SecondaryBrush'];$card.Background=$Ui.Window.Resources['SurfaceBrush'];$card.BorderBrush=$Ui.Window.Resources['StrokeBrush']
            }
            if($state.Native.TakeLayoutChange() -and $window.WindowState -ne 'Minimized'){$env=Get-LGPlacementEnvironment $window;$bounds=[LowGear.UI.WindowPlacement]::CurrentBounds([Windows.Interop.WindowInteropHelper]::new($window).Handle,$env.ScaleX,$env.ScaleY);if(-not [LowGear.UI.WindowPlacement]::Reachable($bounds,$env.Areas,$env.ScaleX,$env.ScaleY)){Set-LGSetupBounds $window}}
        }
    }.GetNewClosure();$state.Progress=$onProgress
    $onPrimary={
        switch($state.Step){
            Intro {$Ui.Controls.PersistentAffinity.IsChecked=[bool]$state.Controls.Affinity.IsChecked;$state.Step='Review';$state.Check=$null;& $render;& $RequestPreflight}
            Review {if($null -ne $state.Check -and $state.Check.Success){$state.Step='Working';$state.Started=$true;& $render;& $Start $state.Command -Confirmed}}
            Result {$state.Route='Panel';$window.Close()}
        }
    }.GetNewClosure()
    $onSecondary={
        switch($state.Step){
            Checking {if(-not(Set-LGOnboardingHandled $OnboardingPath)){$Ui.Controls.OperationText.Text='暂缓选择未能保存，下次可能再次显示引导。'};$state.Route='Panel';$window.Close()}
            Intro {if(-not (Set-LGOnboardingHandled $OnboardingPath)){$Ui.Controls.OperationText.Text='暂缓选择未能保存，下次可能再次显示引导。'};$state.Route='Panel';$window.Close()}
            Review {if($state.Command -eq 'Install'){$state.Step='Intro';& $render}else{$state.Route='Panel';$window.Close()}}
            Result {$state.Route='Exit';$window.Close()}
        }
    }.GetNewClosure()
    $onExtra={
        if($state.Step -eq 'Result' -and $state.Result.Success){
            if($Ui.Demo){$stage.Text='示例窗口不会打开真实本机资料。';return}
            $folder=Join-Path $env:ProgramData 'ACE-LowGear\v1\backups'
            if([IO.Directory]::Exists($folder) -and -not((Get-Item -LiteralPath $folder -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){Start-Process -FilePath (Join-Path $env:SystemRoot 'explorer.exe') -ArgumentList ('"'+$folder+'"')}else{$stage.Text='未找到可打开的本机备份目录。'}
        }else{$state.Route='Diagnostics';$window.Close()}
    }.GetNewClosure()
    $loaded={
        Set-LGSetupBounds $window
        $handle=[Windows.Interop.WindowInteropHelper]::new($window).Handle;$state.Native=[LowGear.UI.WindowEffects]::new($handle)
        $appearance=Resolve-LGAppearance $Ui.ThemePreference (Get-LGThemeEnvironment) $Ui.VisualPreference.Material
        if($state.Native.Apply(($appearance.Theme -eq 'Dark'),$appearance.Mica,$appearance.HighContrast)){$window.Background=[Windows.Media.Brushes]::Transparent}
        if($state.Step -eq 'Checking' -and $null -ne $Ui.LastReport){& $onReport $Ui.LastReport}
        elseif($state.Step -eq 'Review'){& $RequestPreflight}
        elseif($state.Step -eq 'Working'){$state.Started=$true;& $Start $state.Command -Confirmed}
    }.GetNewClosure()
    $closing={param($sender,$eventArgs)if($null -ne $Ui.Child){$eventArgs.Cancel=$true;$stage.Text='正在修改本机配置，请等待操作完成。'}elseif($null -ne $Ui.QueuedCommand){$Ui.QueuedCommand=$null;$Ui.QueuedConfirmed=$false;$stage.Text='操作尚未开始，已取消等待。'}}.GetNewClosure()
    $closed={$state.Closed=$true;if($null -ne $state.Native){$state.Native.Dispose();$state.Native=$null}}.GetNewClosure()
    $functions=@(foreach($name in @('Read-LGOnboarding','Set-LGOnboardingHandled','Get-LGSetupRoute','Get-LGOperationOutcome','Get-LGUiValue','Get-LGPlacementEnvironment','Set-LGSetupBounds','Resolve-LGAppearance','Get-LGThemeEnvironment')){Get-Command $name})
    foreach($callback in @($render,$onReport,$onPreflight,$onResult,$onProgress,$onPrimary,$onSecondary,$onExtra,$loaded,$closing,$closed)){& $callback.Module {param($helpers)foreach($helper in $helpers){Set-Item -Path ('Function:script:'+$helper.Name) -Value $helper.ScriptBlock}} $functions}
    $primary.Add_Click($onPrimary);$secondary.Add_Click($onSecondary);$extra.Add_Click($onExtra);$window.Add_Loaded($loaded);$window.Add_Closing($closing);$window.Add_Closed($closed)
    foreach($pair in @(@($primary,'安装向导主要操作'),@($secondary,'安装向导返回或暂缓'),@($extra,'安装诊断或备份'))){[Windows.Automation.AutomationProperties]::SetName($pair[0],$pair[1])}
    & $render
    $state
}
