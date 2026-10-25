function Show-LGPanel {
    param([switch]$RenderOnly,[string]$ImagePath)
    Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
    $xaml=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Panel.xaml'))
    $reader=[Xml.XmlReader]::Create([IO.StringReader]::new($xaml))
    try{$window=[Windows.Markup.XamlReader]::Load($reader)}finally{$reader.Dispose()}
    $names=@('ManagerText','AffinityText','SummaryText','ProcessesGrid','DetailText','OperationText','PersistentAffinity','InstallButton','ApplyButton','PauseButton','ResumeButton','RefreshButton','LastButton','SelfTestButton','RestoreButton')
    $controls=@{}
    foreach($name in $names){$controls[$name]=$window.FindName($name);if($null -eq $controls[$name]){throw ('界面控件缺失：'+$name)}}
    $ui=[pscustomobject]@{Window=$window;Controls=$controls;Child=$null;Result=$null;LastRefresh=[DateTime]::MinValue;Initialized=$false;Entry=(Join-Path (Split-Path $PSScriptRoot -Parent) 'LowGear.ps1')}
    $update={
        param($report)
        $states=@{Ready='已启用 · 等待启动';Running='本次执行中';Paused='已暂停';NotInstalled='尚未启用';RecoveryRequired='需要恢复检查';WorkerUnavailable='触发配置异常'}
        $ui.Controls.ManagerText.Text=$states[$report.Mode]
        $ui.Controls.AffinityText.Text=if($report.BindLastCpu){'启动时绑定 CPU '+$report.Topology.LastCpu}else{'保持原设置'}
        if(-not $ui.Initialized){$ui.Controls.PersistentAffinity.IsChecked=$report.BindLastCpu;$ui.Initialized=$true}
        $rows=[Collections.Generic.List[object]]::new()
        foreach($p in $report.Processes){
            $cpu=if($null -eq $p.CpuClass){'未读取'}elseif($p.CpuClass -eq 64){'低'}elseif($p.CpuClass -eq 32){'正常'}else{[string]$p.CpuClass}
            $io=if($null -eq $p.IoPriority){'未读取'}elseif($p.IoPriority -eq 0){'非常低'}elseif($p.IoPriority -eq 2){'正常'}else{[string]$p.IoPriority}
            $outcome=if(-not $p.Running){'未运行 · 等待启动'}elseif($p.Errors.Count -gt 0){$p.Errors -join '; '}elseif($p.Verified){'已核验'}else{'未达到目标'}
            if(-not $p.Running){$cpu='—';$io='—'}
            $startup=@($report.Startup | Where-Object Image -eq $p.Image)[0].Configured
            $rows.Add([pscustomobject]@{Name=if($p.Running){$p.Image+' / '+$p.ProcessId}else{$p.Image};Startup=if($startup){'已配置'}else{'未配置'};Cpu=$cpu;Io=$io;Affinity=if($p.Affinity){$p.Affinity}else{'—'};Outcome=$outcome})
        }
        $ui.Controls.ProcessesGrid.ItemsSource=$rows.ToArray()
        $running=@($report.Processes | Where-Object Running);$good=@($running | Where-Object Verified)
        $ui.Controls.SummaryText.Text=if($running.Count -gt 0){'运行中 '+$running.Count+' 个实例，符合目标 '+$good.Count+' 个。'}elseif($report.Mode -eq 'Paused'){'当前没有 ACE 进程；自动执行已暂停，启动规则仍保留。'}elseif($report.Mode -eq 'NotInstalled'){'当前没有 ACE 进程；尚未启用自动执行。'}elseif($report.Mode -in @('RecoveryRequired','WorkerUnavailable')){'当前没有 ACE 进程；请先处理自动执行配置异常。'}else{'当前没有 ACE 进程；等待下一次启动时自动执行。'}
        $sessions=@{Completed='已完成并退出';NoTargets='无运行目标，已退出';Incomplete='未能完成，请检查读值';Verifying='启动核验中'}
        $last=if($null -eq $report.LastSession){'尚未执行'}else{$sessions[$report.LastSession.SessionState]}
        $ui.Controls.DetailText.Text='逻辑处理器 '+$report.Topology.LogicalProcessors+' · 处理器组 '+$report.Topology.Groups+' · 最近一次：'+$last+' · 版本 '+$report.Version
    }.GetNewClosure()
    $start={
        param([string]$command)
        if($null -ne $ui.Child){return}
        $ui.Result=Join-Path ([IO.Path]::GetTempPath()) ('lowgear-ui-'+[Guid]::NewGuid().ToString('N')+'.json')
        $args='-NoLogo -NoProfile -STA -NonInteractive -ExecutionPolicy Bypass -File "'+$ui.Entry+'" -Command '+$command+' -ResultPath "'+$ui.Result+'"'
        if($ui.Controls.PersistentAffinity.IsChecked -and $command -eq 'Install'){$args+=' -BindLastCpu'}
        $ui.Child=Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -WindowStyle Hidden -ArgumentList $args -PassThru
        foreach($name in $names | Where-Object {$_ -like '*Button'}){$ui.Controls[$name].IsEnabled=$false}
        $ui.Controls.OperationText.Text='正在执行 '+$command+'，请稍候…'
    }.GetNewClosure()
    foreach($pair in @(@('InstallButton','Install'),@('ApplyButton','ApplyOnce'),@('PauseButton','Pause'),@('ResumeButton','Resume'),@('RefreshButton','Status'),@('LastButton','LastCpu'),@('SelfTestButton','SelfTest'),@('RestoreButton','Restore'))){
        $button=$controls[$pair[0]];$button.Tag=$pair[1]
        $button.Add_Click({param($sender,$eventArgs) & $start ([string]$sender.Tag)}.GetNewClosure())
    }
    $timer=[Windows.Threading.DispatcherTimer]::new();$timer.Interval=[TimeSpan]::FromMilliseconds(400)
    $timer.Add_Tick({
        try{
            if($null -ne $ui.Child){
                if(-not $ui.Child.HasExited){return}
                if(Test-Path -LiteralPath $ui.Result){
                    $result=Get-Content -LiteralPath $ui.Result -Raw -Encoding UTF8 | ConvertFrom-Json
                    $ui.Controls.OperationText.Text=$result.Message
                    if($result.Success){& $update $result.Report}
                    [IO.File]::Delete($ui.Result)
                }else{$ui.Controls.OperationText.Text='操作未返回结果，请使用命令行检查原因。'}
                $ui.Child.Dispose();$ui.Child=$null;$ui.LastRefresh=[DateTime]::UtcNow
                foreach($name in $names | Where-Object {$_ -like '*Button'}){$ui.Controls[$name].IsEnabled=$true}
            }
            elseif(([DateTime]::UtcNow-$ui.LastRefresh).TotalSeconds -ge 5){& $update (Get-LGStatus);$ui.LastRefresh=[DateTime]::UtcNow}
        }catch{$ui.Controls.OperationText.Text=$_.Exception.Message}
    }.GetNewClosure())
    if($RenderOnly){
        $demo=[pscustomobject]@{Version='1.0.0';Mode='Ready';BindLastCpu=$false;Topology=[pscustomobject]@{LogicalProcessors=24;Groups=1;LastCpu=23};LastSession=[pscustomobject]@{SessionState='Completed'};Startup=@();Processes=@()}
        foreach($image in @('SGuard64.exe','SGuardSvc64.exe','ACE-Service64.exe')){
            $demo.Startup+= [pscustomobject]@{Image=$image;Configured=$true}
            $demo.Processes+= [pscustomobject]@{Image=$image;Running=($image -ne 'ACE-Service64.exe');ProcessId=1234;CpuClass=64;IoPriority=0;Affinity=if($image -ne 'ACE-Service64.exe'){'0xFFFFFF'}else{$null};Verified=$true;Errors=@()}
        }
        & $update $demo
        $ui.Controls.OperationText.Text='界面预览 · 示例数据。每次 ACE 启动自动执行一次，设置并确认后退出。'
        $visual=$window.Content
        $visual.Measure([Windows.Size]::new(1060,760));$visual.Arrange([Windows.Rect]::new(0,0,1060,760));$visual.UpdateLayout()
        $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new(1060,760,96,96,[Windows.Media.PixelFormats]::Pbgra32)
        $background=[Windows.Media.DrawingVisual]::new();$drawing=$background.RenderOpen()
        try{$drawing.DrawRectangle($window.Background,$null,[Windows.Rect]::new(0,0,1060,760))}finally{$drawing.Close()}
        $bitmap.Render($background)
        $bitmap.Render($visual)
        $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
        $stream=[IO.File]::Create($ImagePath);try{$encoder.Save($stream)}finally{$stream.Dispose()}
        $window.Close();return
    }
    $window.Add_Closed({$timer.Stop()}.GetNewClosure())
    $timer.Start()
    [void]$window.ShowDialog()
}
