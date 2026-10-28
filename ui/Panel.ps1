function Show-LGPanel {
    param([switch]$RenderOnly,[string]$ImagePath,[double]$RenderScale=1,[switch]$PassThru)
    Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
    $reader=[Xml.XmlReader]::Create([IO.StringReader]::new([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Panel.xaml'))))
    try{$window=[Windows.Markup.XamlReader]::Load($reader)}finally{$reader.Dispose()}
    $names=@('VersionText','ManagerText','AffinityText','SummaryText','ProcessesGrid','SessionText','DetailText','HealthText','GuideText','OperationText','PersistentAffinity','InstallButton','UpgradeButton','ApplyButton','PauseButton','ResumeButton','RepairButton','RefreshButton','DiagnosticButton','LastButton','SelfTestButton','RestoreButton')
    $controls=@{};foreach($name in $names){$controls[$name]=$window.FindName($name);if($null -eq $controls[$name]){throw ('界面控件缺失：'+$name)}}
    $buttons=@($names|Where-Object {$_ -like '*Button'})
    $ui=[pscustomobject]@{Window=$window;Controls=$controls;Child=$null;JobDirectory=$null;LastReport=$null;Initialized=$false;ForceFull=$true;LastFull=[DateTime]::MinValue;LastRefresh=[DateTime]::MinValue
        Runspace=$null;Pipeline=$null;Pending=$null;QueryStarted=[DateTime]::MinValue;QueryFull=$true;Closed=$false;DiagnosticShown=$false;Entry=(Join-Path (Split-Path $PSScriptRoot -Parent) 'LowGear.ps1');LastDiagnostic=$null}
    $update={param($report)
        $ui.LastReport=$report
        $states=@{Ready='已启用 · 等待启动';Running='本次执行中';Paused='已暂停';NotInstalled='尚未启用';RecoveryRequired='需要恢复检查';WorkerUnavailable='触发配置异常'}
        $ui.Controls.ManagerText.Text=$states[$report.Mode]
        $ui.Controls.VersionText.Text='面板 '+$report.Version+' / 本机 '+$(if($report.InstalledVersion){$report.InstalledVersion}else{'未安装'})
        $ui.Controls.AffinityText.Text=if($report.BindLastCpu){'启动时绑定 CPU '+$report.Topology.LastCpu}else{'保持原设置'}
        if(-not $ui.Initialized){$ui.Controls.PersistentAffinity.IsChecked=$report.BindLastCpu;$ui.Initialized=$true}
        $ui.Controls.UpgradeButton.Visibility=if($report.Installed -and $report.InstalledVersion -ne $report.Version){'Visible'}else{'Collapsed'}
        $ui.Controls.GuideText.Text=switch($report.Mode){
            NotInstalled {'首次使用：启用自动管理 → 正常启动游戏 → 刷新查看结果。'}
            Paused {'自动执行已暂停，启动规则仍保留。恢复后可关闭窗口，正常启动游戏。'}
            RecoveryRequired {'请查看配置原因；未完成的升级可使用“修复自动执行”撤回。'}
            WorkerUnavailable {'自动触发需要检查，可查看诊断摘要并手动修复。'}
            default {'自动管理已启用。可以关闭窗口，正常启动游戏；首次使用后刷新查看读值。'}
        }
        $rows=[Collections.Generic.List[object]]::new()
        foreach($p in $report.Processes){
            $cpu=if($null -eq $p.CpuClass){'未读取'}elseif($p.CpuClass -eq 64){'低'}elseif($p.CpuClass -eq 32){'正常'}else{[string]$p.CpuClass}
            $io=if($null -eq $p.IoPriority){'未读取'}elseif($p.IoPriority -eq 0){'非常低'}elseif($p.IoPriority -eq 2){'正常'}else{[string]$p.IoPriority}
            $outcome=if(-not $p.Running){'未运行 · 等待启动'}elseif($p.Errors.Count -gt 0){$p.Errors -join '; '}elseif($p.Verified){'已核验'}else{'未达到目标'}
            if(-not $p.Running){$cpu='—';$io='—'}
            $startup=@($report.Startup|Where-Object Image -eq $p.Image)
            $rows.Add([pscustomobject]@{Name=if($p.Running){$p.Image+' / '+$p.ProcessId}else{$p.Image};Startup=if($startup.Count -eq 0){'未读取'}elseif($startup[0].Configured){'已配置'}else{'未配置'};Cpu=$cpu;Io=$io;Affinity=if($p.Affinity){$p.Affinity}else{'—'};Outcome=$outcome})
        }
        $ui.Controls.ProcessesGrid.ItemsSource=$rows.ToArray()
        $running=@($report.Processes|Where-Object Running);$good=@($running|Where-Object Verified)
        $ui.Controls.SummaryText.Text=if($report.Health.Processes.State -eq 'Error'){'进程读值暂不可用。'}elseif($running.Count -eq 0){'当前没有 ACE 进程；未运行不代表核验通过。'}else{'运行中 '+$running.Count+' 个实例，符合目标 '+$good.Count+' 个。'}
        $sessions=@{Starting='本次启动中';Completed='已完成';NoTargets='无运行目标';Incomplete='未能完成';Verifying='核验中';Failed='执行失败'}
        if($null -eq $report.LastSession){$ui.Controls.SessionText.Text='最近会话：尚未执行。'}else{
            $session=$report.LastSession;$label=$sessions[$session.SessionState];$time=[DateTime]::Parse($session.TimestampUtc).ToLocalTime().ToString('MM-dd HH:mm:ss')
            $duration=if($null -ne $session.PSObject.Properties['ElapsedMilliseconds']){[Math]::Round($session.ElapsedMilliseconds/1000,1).ToString()+' 秒'}else{'旧版记录'}
            $ui.Controls.SessionText.Text='最近会话：'+$label+' · '+$time+' · 耗时 '+$duration
        }
        $ui.Controls.DetailText.Text='逻辑处理器 '+$report.Topology.LogicalProcessors+' · 处理器组 '+$report.Topology.Groups+' · 配置检查 '+([DateTime]::Parse($report.FullCheckedUtc).ToLocalTime().ToString('HH:mm:ss'))
        $warnings=@($report.Health.PSObject.Properties|Where-Object {$_.Value.State -in @('Error','Conflict','Warning')}|ForEach-Object {$_.Value.Message})
        $ui.Controls.HealthText.Text=$warnings -join ' '
    }.GetNewClosure()
    $refresh={
        if($ui.Closed -or $null -ne $ui.Child -or $null -ne $ui.Pipeline){return}
        if($null -eq $ui.Runspace){$ui.Runspace=[RunspaceFactory]::CreateRunspace();$ui.Runspace.ApartmentState='STA';$ui.Runspace.ThreadOptions='ReuseThread';$ui.Runspace.Open()}
        $ui.QueryFull=$ui.ForceFull -or ([DateTime]::UtcNow-$ui.LastFull).TotalSeconds -ge 30
        $ui.ForceFull=$false;$ui.QueryStarted=[DateTime]::UtcNow
        $ui.Pipeline=[PowerShell]::Create();$ui.Pipeline.Runspace=$ui.Runspace
        [void]$ui.Pipeline.AddScript('param($entry,$full) if(-not(Get-Module LowGear)){Import-Module (Join-Path (Split-Path $entry -Parent) "src\LowGear.psm1") -DisableNameChecking};Get-LGStatus -Quick:(-not $full)|ConvertTo-Json -Depth 25').AddArgument($ui.Entry).AddArgument($ui.QueryFull)
        $ui.Pending=$ui.Pipeline.BeginInvoke()
    }.GetNewClosure()
    $start={param([string]$command)
        if($ui.Closed -or $null -ne $ui.Child){return}
        if($command -eq 'Status'){$ui.ForceFull=$true;if($null -eq $ui.Pipeline){& $refresh};return}
        if($null -ne $ui.Pipeline){$ui.Controls.OperationText.Text='状态读取中，请稍候再执行操作。';return}
        $ui.JobDirectory=Join-Path ([IO.Path]::GetTempPath()) ('LowGear-ui-'+[Guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($ui.JobDirectory)
        $acl=[Security.AccessControl.DirectorySecurity]::new();$acl.SetAccessRuleProtection($true,$false);$acl.SetOwner([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))
        foreach($sid in @('S-1-5-18','S-1-5-32-544')){[void]$acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid),'FullControl','ContainerInherit,ObjectInherit','None','Allow'))}
        Set-Acl -LiteralPath $ui.JobDirectory -AclObject $acl
        $result=Join-Path $ui.JobDirectory 'result.json';$progress=Join-Path $ui.JobDirectory 'progress.json'
        $arguments='-NoLogo -NoProfile -STA -NonInteractive -ExecutionPolicy Bypass -File "'+$ui.Entry+'" -Command '+$command+' -ResultPath "'+$result+'" -ProgressPath "'+$progress+'"'
        if($command -eq 'Install'){$arguments+=if($ui.Controls.PersistentAffinity.IsChecked){' -BindLastCpu'}else{' -ClearLastCpu'}}
        try{$ui.Child=Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -WindowStyle Hidden -ArgumentList $arguments -PassThru}catch{$ui.Controls.OperationText.Text='无法启动操作，请检查本机权限。';return}
        foreach($name in $buttons){$ui.Controls[$name].IsEnabled=$false}
        $ui.Controls.OperationText.Text='正在检查本机状态…'
    }.GetNewClosure()
    foreach($pair in @(@('InstallButton','Install'),@('UpgradeButton','Upgrade'),@('ApplyButton','ApplyOnce'),@('PauseButton','Pause'),@('ResumeButton','Resume'),@('RepairButton','Repair'),@('RefreshButton','Status'),@('LastButton','LastCpu'),@('SelfTestButton','SelfTest'),@('RestoreButton','Restore'))){
        $controls[$pair[0]].Tag=$pair[1];$controls[$pair[0]].Add_Click({param($sender,$eventArgs)try{& $start ([string]$sender.Tag)}catch{$ui.Controls.OperationText.Text='操作无法启动，请检查权限或查看诊断摘要。'}}.GetNewClosure())
    }
    $diagnostic={
        if($null -eq $ui.LastReport -or $null -ne $ui.Child){return}
        $ui.LastDiagnostic=Get-LGDiagnostic $ui.LastReport|ConvertTo-Json -Depth 8
        $dialog=[Windows.Window]::new();$dialog.Title='诊断摘要 · 预览后复制';$dialog.Owner=$ui.Window;$dialog.Width=640;$dialog.Height=540;$dialog.WindowStartupLocation='CenterOwner';$dialog.FontFamily='Microsoft YaHei UI'
        $dock=[Windows.Controls.DockPanel]::new();$dock.Margin=20
        $copy=[Windows.Controls.Button]::new();$copy.Content='复制此摘要';$copy.Height=38;[Windows.Controls.DockPanel]::SetDock($copy,'Bottom')
        $text=[Windows.Controls.TextBox]::new();$text.Text=$ui.LastDiagnostic;$text.IsReadOnly=$true;$text.VerticalScrollBarVisibility='Auto';$text.TextWrapping='Wrap'
        $copy.Add_Click({[Windows.Clipboard]::SetText($ui.LastDiagnostic);$copy.Content='已复制，可自行分享'}.GetNewClosure())
        [void]$dock.Children.Add($copy);[void]$dock.Children.Add($text);$dialog.Content=$dock;$ui.DiagnosticShown=$true;[void]$dialog.ShowDialog()
    }.GetNewClosure()
    $controls.DiagnosticButton.Add_Click($diagnostic)
    $tick={
        if($ui.Closed){return}
        if($null -ne $ui.Child){
            $progress=Join-Path $ui.JobDirectory 'progress.json'
            try{if(Test-Path -LiteralPath $progress){$ui.Controls.OperationText.Text=(Get-Content -LiteralPath $progress -Raw -Encoding UTF8|ConvertFrom-Json).Message}}catch{}
            if(-not $ui.Child.HasExited){return}
            try{
                $path=Join-Path $ui.JobDirectory 'result.json'
                if(Test-Path -LiteralPath $path){$result=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json;$ui.Controls.OperationText.Text=$result.Message;if($result.Success){& $update $result.Report}}
                else{$ui.Controls.OperationText.Text='操作未返回结果，请查看诊断摘要。'}
            }catch{$ui.Controls.OperationText.Text='操作结果无法读取，请刷新状态。'}finally{
                $ui.Child.Dispose();$ui.Child=$null
                foreach($name in $buttons){$ui.Controls[$name].IsEnabled=$true}
                try{foreach($name in @('result.json','progress.json')){$path=Join-Path $ui.JobDirectory $name;if([IO.File]::Exists($path)){[IO.File]::Delete($path)}};[IO.Directory]::Delete($ui.JobDirectory,$false)}catch{}
                $ui.JobDirectory=$null;$ui.ForceFull=$true
            }
        }
        if($null -ne $ui.Pipeline){
            if(-not $ui.Pending.IsCompleted){if(([DateTime]::UtcNow-$ui.QueryStarted).TotalSeconds -gt 10){$ui.Controls.OperationText.Text='系统查询较慢；当前显示上次结果，未重复发起查询。'};return}
            try{$output=$ui.Pipeline.EndInvoke($ui.Pending);if($ui.Pipeline.HadErrors){throw 'Query failed'};$report=($output -join "`n")|ConvertFrom-Json;& $update $report;if($ui.QueryFull){$ui.LastFull=[DateTime]::UtcNow}}
            catch{$ui.Controls.OperationText.Text='本次读取失败，保留上次结果；可手动刷新或查看诊断摘要。'}
            finally{$ui.Pipeline.Dispose();$ui.Pipeline=$null;$ui.Pending=$null;$ui.LastRefresh=[DateTime]::UtcNow}
        }
        if($ui.ForceFull -or ([DateTime]::UtcNow-$ui.LastRefresh).TotalSeconds -ge 5){& $refresh}
    }.GetNewClosure()
    $closing={param($sender,$eventArgs)
        if($null -ne $ui.Child){$eventArgs.Cancel=$true;$ui.Controls.OperationText.Text='正在修改本机配置，请等待操作完成后关闭。'}
    }.GetNewClosure()
    $timer=[Windows.Threading.DispatcherTimer]::new();$timer.Interval=[TimeSpan]::FromMilliseconds(250);$timer.Add_Tick($tick)
    $cleanup={
        $ui.Closed=$true;$timer.Stop()
        if($null -ne $ui.Pipeline){if(-not $ui.Pending.IsCompleted){[void]$ui.Pipeline.BeginStop($null,$null)}else{$ui.Pipeline.Dispose()}}
        if($null -ne $ui.Runspace){$ui.Runspace.CloseAsync()}
    }.GetNewClosure()
    $window.Add_Closing($closing);$window.Add_Closed($cleanup)
    if($PassThru){return [pscustomobject]@{State=$ui;Update=$update;Start=$start;Refresh=$refresh;Tick=$tick;Closing=$closing;Cleanup=$cleanup}}
    if($RenderOnly){
        $demo=[pscustomobject]@{Version=(Get-Content (Join-Path (Split-Path $PSScriptRoot -Parent) 'public-files.json') -Raw|ConvertFrom-Json).Version;InstalledVersion='1.0.0';Mode='Ready';Installed=$true;BindLastCpu=$false;Topology=[pscustomobject]@{LogicalProcessors=24;Groups=1;LastCpu=23};FullCheckedUtc=[DateTime]::UtcNow.ToString('o');LastSession=[pscustomobject]@{SessionState='Completed';TimestampUtc=[DateTime]::UtcNow.ToString('o');ElapsedMilliseconds=11200};Startup=@();Processes=@();Health=[pscustomobject]@{Processes=[pscustomobject]@{State='Healthy';Code='OK';Message='演示数据'}}}
        foreach($image in @('SGuard64.exe','SGuardSvc64.exe','ACE-Service64.exe')){$demo.Startup+=[pscustomobject]@{Image=$image;Configured=$true};$demo.Processes+=[pscustomobject]@{Image=$image;Running=($image -ne 'ACE-Service64.exe');ProcessId=1234;CpuClass=64;IoPriority=0;Affinity=$null;Verified=$true;Errors=@()}}
        & $update $demo;$controls.OperationText.Text='界面预览 · 示例数据。实际状态请在本机启用后查看。'
        $visual=$window.Content;$visual.Measure([Windows.Size]::new(1060,800));$visual.Arrange([Windows.Rect]::new(0,0,1060,800));$visual.UpdateLayout()
        $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new([int](1060*$RenderScale),[int](800*$RenderScale),96*$RenderScale,96*$RenderScale,[Windows.Media.PixelFormats]::Pbgra32)
        $background=[Windows.Media.DrawingVisual]::new();$drawing=$background.RenderOpen();try{$drawing.DrawRectangle($window.Background,$null,[Windows.Rect]::new(0,0,1060,800))}finally{$drawing.Close()}
        $bitmap.Render($background);$bitmap.Render($visual);$encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap));$stream=[IO.File]::Create($ImagePath);try{$encoder.Save($stream)}finally{$stream.Dispose()};$window.Close();return
    }
    $window.Height=[Math]::Max(600,[Math]::Min(800,[Windows.SystemParameters]::WorkArea.Height-30));$timer.Start();[void]$window.ShowDialog()
}
