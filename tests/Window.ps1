[CmdletBinding()]
param([switch]$RequireMica)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'src\LowGear.psm1') -Force -DisableNameChecking
. (Join-Path $root 'ui\Panel.ps1')
$id=[Guid]::NewGuid().ToString('N');$temp=Join-Path ([IO.Path]::GetTempPath()) ('LowGear-window-tests-'+$id)
$checks=[Collections.Generic.List[string]]::new();$handle=$null;$initialMica=$false
function Assert {param([bool]$Value,[string]$Name)if(-not $Value){throw ('FAIL: '+$Name)};$checks.Add($Name)}
function Pump {
    $frame=[Windows.Threading.DispatcherFrame]::new();$wait=[Windows.Threading.DispatcherTimer]::new();$wait.Interval=[TimeSpan]::FromMilliseconds(120)
    $stop={param($sender,$eventArgs)$sender.Stop();$frame.Continue=$false}.GetNewClosure();$wait.Add_Tick($stop);$wait.Start();[Windows.Threading.Dispatcher]::PushFrame($frame)
}
try{
    $handle=Show-LGPanel -PassThru -Demo -PreferencePath (Join-Path $temp 'ui.json')
    $window=$handle.State.Window;$window.Width=1060;$window.Height=800;$window.Show();Pump
    Assert ($window.IsVisible -and $null -ne $handle.State.Native) 'A real WPF HWND is created with native appearance hooks'
    $initialMica=$handle.State.Appearance.Mica
    if($RequireMica){Assert ($initialMica -and $handle.State.Native.BackdropType -eq 2) 'Local supported Windows window applies the real DWM main-window backdrop'}
    else{Assert (($initialMica -and $handle.State.Native.BackdropType -eq 2) -or (-not $initialMica -and $window.Background.Opacity -eq 1)) 'Native backdrop either succeeds or leaves an opaque solid window'}
    $handle.State.Controls.ThemeCombo.SelectedIndex=2;Pump
    Assert ($handle.State.Appearance.Theme -eq 'Dark' -and $window.Resources['TextBrush'].Color.A -eq 255) 'Actual window switches to opaque readable dark controls'
    $handle.State.Controls.ThemeCombo.SelectedIndex=1;Pump
    Assert ($handle.State.Appearance.Theme -eq 'Light') 'Actual window switches back to light without recreating its HWND'
    $originalLeft=$window.Left;$originalTop=$window.Top;$window.Left=$originalLeft+32;$window.Top=$originalTop+24;Pump
    Assert ([Math]::Abs($window.Left-$originalLeft-32) -lt 2 -and [Math]::Abs($window.Top-$originalTop-24) -lt 2) 'Native window accepts position changes while retaining appearance'
    $window.WindowState='Maximized';Pump
    Assert ($window.WindowState -eq 'Maximized' -and $window.ActualWidth -ge $window.MinWidth) 'Native maximize preserves a usable content layout'
    $window.WindowState='Normal';$window.Width=880;Pump
    Assert ($window.WindowState -eq 'Normal' -and $handle.State.Compact) 'Restore and resize produce the compact navigation layout'
    $window.Width=1060;Pump
    Assert (-not $handle.State.Compact) 'Widening the real window restores labelled navigation'
    & $handle.Navigate 'Settings';$window.Height=600;Pump;$handle.State.Controls.SettingsPage.ScrollToVerticalOffset(120);Pump
    Assert ($handle.State.Controls.SettingsPage.VerticalOffset -gt 0) 'Settings remain scrollable at the minimum window height with the themed scrollbar'
    & $handle.Navigate 'Overview'
    $environment=Get-LGThemeEnvironment;$environment.Transparency=$false
    & $handle.Theme 'Dark' -Environment $environment;Pump
    Assert (-not $handle.State.Appearance.Mica -and $window.Background.Color.A -eq 255) 'Disabling material restores a solid background on an existing HWND'
    & $handle.Theme 'System';Pump
    Assert ($handle.State.ThemePreference -eq 'System') 'Same native window can resume following Windows appearance'
    $handle.State.Controls.PersistentAffinity.IsChecked=$true
    $handle.State.Controls.SaveAffinityButton.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
    Assert ($null -eq $handle.State.Child -and $handle.State.Controls.OperationText.Text -match '示例数据') 'Interactive preview blocks policy mutations'
    $restore=New-LGPanelDialog $handle.State 'Restore'
    Assert ([object]::ReferenceEquals($restore.Window.Owner,$window)) 'Confirmation dialog is owned by the real panel window'
    $restore.Window.Close()
    $window.Close();Pump
    Assert ($handle.State.Closed -and $null -eq $handle.State.Native -and $null -eq $handle.State.Pipeline) 'Native close removes hooks and query ownership'
    [pscustomobject]@{Status='Passed';Count=$checks.Count;Checks=$checks.ToArray();NativeMica=$initialMica;VisualDesktopReview='Separate';PhysicalDrag='NotTested'}|ConvertTo-Json -Depth 5
}finally{
    if($null -ne $handle){if(-not $handle.State.Closed){$handle.State.Window.Close()};& $handle.Cleanup}
    $expected=[IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('LowGear-window-tests-'+$id)))
    if($id -cnotmatch '^[a-f0-9]{32}$' -or [IO.Path]::GetFullPath($temp) -cne $expected){throw 'Unsafe window test cleanup'}
    if([IO.Directory]::Exists($temp)){[IO.Directory]::Delete($temp,$true)}
}
