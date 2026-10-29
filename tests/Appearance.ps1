[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'src\LowGear.psm1') -DisableNameChecking
. (Join-Path $root 'ui\Panel.ps1')
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
Initialize-LGWindowEffects
$id=[Guid]::NewGuid().ToString('N');$temp=Join-Path ([IO.Path]::GetTempPath()) ('LowGear-appearance-tests-'+$id);[void][IO.Directory]::CreateDirectory($temp)
$checks=[Collections.Generic.List[string]]::new();$handle=$null
function Assert {param([bool]$Value,[string]$Name)if(-not $Value){throw ('FAIL: '+$Name)};$checks.Add($Name)}
function Area {param([double]$Left,[double]$Top,[double]$Width,[double]$Height,[bool]$Primary=$false)$a=[LowGear.UI.DisplayArea]::new();$a.Left=$Left;$a.Top=$Top;$a.Width=$Width;$a.Height=$Height;$a.Primary=$Primary;$a}
function Pump {$frame=[Windows.Threading.DispatcherFrame]::new();$timer=[Windows.Threading.DispatcherTimer]::new();$timer.Interval=[TimeSpan]::FromMilliseconds(100);$timer.Add_Tick({param($sender,$eventArgs)$sender.Stop();$frame.Continue=$false}.GetNewClosure());$timer.Start();[Windows.Threading.Dispatcher]::PushFrame($frame)}
function Open-Panel {param([string]$Path)$h=Show-LGPanel -PassThru -Demo -PreferencePath $Path;$h.State.Window.Show();Pump;$h}
try{
    $path=Join-Path $temp 'appearance.json';$themePath=Join-Path $temp 'ui.json'
    $defaults=Read-LGAppearancePreference $path
    Assert ($defaults.Material -eq 'Auto' -and $defaults.RememberWindow -and $null -eq $defaults.Placement -and -not $defaults.Warning) 'First use keeps automatic material, window memory and default geometry'
    Write-LGUiPreference $themePath 'Dark';$themeBytes=[IO.File]::ReadAllText($themePath)
    $defaults.Material='Off';Write-LGAppearancePreference $path $defaults
    Assert ([IO.File]::ReadAllText($themePath) -ceq $themeBytes -and (Read-LGUiPreference $themePath).Theme -eq 'Dark') 'New preferences never alter the legacy theme-only format'
    Assert ((Read-LGAppearancePreference $path).Material -eq 'Off') 'Explicit solid material is remembered locally'
    [IO.File]::WriteAllText($path,'{"Schema":1,"Material":"bad","RememberWindow":false,"Placement":null}')
    $parsed=Read-LGAppearancePreference $path
    Assert ($parsed.Material -eq 'Auto' -and -not $parsed.RememberWindow -and $parsed.Warning) 'An invalid material resets only that field'
    [IO.File]::WriteAllText($path,'{"Schema":1,"Material":"Off","RememberWindow":true,"Placement":{"Width":-1}}')
    $parsed=Read-LGAppearancePreference $path
    Assert ($parsed.Material -eq 'Off' -and $parsed.RememberWindow -and $null -eq $parsed.Placement -and $parsed.Warning) 'Broken geometry leaves valid material and memory choices intact'
    [IO.File]::WriteAllText($path,'not JSON')
    Assert ((Read-LGAppearancePreference $path).Warning -and (Read-LGAppearancePreference $path).Material -eq 'Auto') 'Unreadable JSON falls back without blocking startup'
    [IO.File]::WriteAllText($path,'{"Schema":99,"Material":"Off","RememberWindow":false}')
    Assert ((Read-LGAppearancePreference $path).Warning -and (Read-LGAppearancePreference $path).RememberWindow) 'Unsupported schema uses safe defaults'
    [IO.File]::WriteAllText($path,'{"Schema":"1","Material":"Off","RememberWindow":false}')
    Assert ((Read-LGAppearancePreference $path).Warning -and (Read-LGAppearancePreference $path).RememberWindow) 'Schema types cannot silently coerce strings into supported versions'
    [IO.File]::WriteAllText($path,'{"Schema":1,"Material":"Off","RememberWindow":true,"Command":"untrusted"}')
    $parsed=Read-LGAppearancePreference $path;Write-LGAppearancePreference $path $parsed
    Assert ([IO.File]::ReadAllText($path) -notmatch 'Command|untrusted|Warning') 'Only known settings are written back'
    Assert (@(Get-ChildItem $temp -Filter '*.tmp').Count -eq 0) 'Atomic preference updates leave no temporary files'
    $original=[IO.File]::ReadAllText($path);$locked=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read);$failed=$false
    try{try{Write-LGAppearancePreference $path (New-LGAppearancePreference)}catch{$failed=$true}}finally{$locked.Dispose()}
    Assert ($failed -and [IO.File]::ReadAllText($path) -ceq $original -and @(Get-ChildItem $temp -Filter '*.tmp').Count -eq 0) 'A failed atomic replacement retains the previous complete record and cleans its temporary file'
    $primary=Area 0 0 1920 1040 $true;$secondary=Area -2560 0 2560 1400
    $areas=[LowGear.UI.DisplayArea[]]@($primary,$secondary)
    $normal=[Windows.Rect]::new(-1900,100,960,700)
    $saved=[LowGear.UI.WindowPlacement]::Capture($normal,$false,$areas,1.25,1.25)
    $restored=[LowGear.UI.WindowPlacement]::Resolve($saved,$areas,1.25,1.25)
    Assert ([Math]::Abs($restored.Left-$normal.Left) -lt 0.01 -and [Math]::Abs($restored.Top-$normal.Top) -lt 0.01) 'Negative-coordinate secondary monitor placement round-trips without drift'
    Assert ($restored.Width -eq 960 -and $restored.Height -eq 700) 'Placement stores logical window dimensions'
    for($index=0;$index -lt 20;$index++){$saved=[LowGear.UI.WindowPlacement]::Capture([Windows.Rect]::new($restored.Left,$restored.Top,$restored.Width,$restored.Height),$false,$areas,1.25,1.25);$restored=[LowGear.UI.WindowPlacement]::Resolve($saved,$areas,1.25,1.25)}
    Assert ([Math]::Abs($restored.Left-$normal.Left) -lt 0.01) 'Repeated close and reopen do not accumulate positioning offsets'
    $removed=[LowGear.UI.WindowPlacement]::Resolve($saved,[LowGear.UI.DisplayArea[]]@($primary),1,1)
    Assert ($removed.Recovered -and $removed.Left -ge 0 -and $removed.Top -ge 0 -and $removed.Left+$removed.Width -le 1920) 'A missing display returns the window to the primary work area'
    foreach($scale in @(1,1.25,1.5,2)){
        $result=[LowGear.UI.WindowPlacement]::Resolve($saved,$areas,$scale,$scale)
        Assert ($result.Left -ge -2560/$scale -and $result.Left+$result.Width -le 0 -and $result.Top+$result.Height -le 1400/$scale) ('Saved placement fits current work area at scale '+$scale)
    }
    $small=[LowGear.UI.WindowPlacement]::Resolve($null,[LowGear.UI.DisplayArea[]]@((Area 0 0 700 500 $true)),1,1)
    Assert ($small.Width -le 684 -and $small.Height -le 484 -and $small.MinWidth -lt 880 -and $small.MinHeight -lt 600) 'Small work areas lower minimums and keep the complete window visible'
    $topTaskbar=[LowGear.UI.WindowPlacement]::Resolve($null,[LowGear.UI.DisplayArea[]]@((Area 0 60 1920 980 $true)),1,1)
    Assert ($topTaskbar.Top -ge 68) 'Taskbar work-area offsets are respected'
    $invalid=[LowGear.UI.PanelPlacement]::new();$invalid.Width=[double]::NaN;$invalid.WorkArea=$primary
    $safe=[LowGear.UI.WindowPlacement]::Resolve($invalid,$areas,1,1)
    Assert ($safe.Recovered -and $safe.Width -eq 1060) 'Non-finite geometry is never passed to the window'
    Assert ([LowGear.UI.WindowPlacement]::Reachable($normal,$areas,1.25,1.25) -and -not [LowGear.UI.WindowPlacement]::Reachable([Windows.Rect]::new(-50000,-50000,960,700),$areas,1,1)) 'Visibility recovery distinguishes valid negative coordinates from inaccessible captions'
    $currentDefault=[LowGear.UI.WindowPlacement]::DefaultFor($normal,$areas,1.25,1.25)
    Assert ($currentDefault.Left -lt 0 -and [Math]::Abs(($currentDefault.Left+$currentDefault.Width/2)-(-1280/1.25)) -lt 0.01) 'Appearance defaults centre on the current secondary display rather than always using the primary'
    $defaults.Placement=$saved;$defaults.RememberWindow=$false;Write-LGAppearancePreference $path $defaults
    Assert ($null -eq (Read-LGAppearancePreference $path).Placement) 'Turning off memory removes saved coordinates'

    [IO.File]::WriteAllText($path,((New-LGAppearancePreference)|ConvertTo-Json))
    $handle=Open-Panel $themePath
    Assert ($handle.State.Appearance.Theme -eq 'Dark' -and $handle.State.GeometryInitialized) 'Opening the real panel retains the old theme and initializes geometry'
    $handle.State.Controls.MaterialCombo.SelectedIndex=1;Pump
    Assert (-not $handle.State.Appearance.Mica -and $handle.State.Window.Background.Color.A -eq 255 -and $handle.State.Controls.AppearanceHint.Text -match '你已关闭云母') 'Material off is applied immediately with an opaque background and neutral explanation'
    & $handle.Theme 'Light';Pump
    Assert ($handle.State.VisualPreference.Material -eq 'Off' -and -not $handle.State.Appearance.Mica) 'Theme changes cannot re-enable explicitly disabled material'
    $environment=Get-LGThemeEnvironment;& $handle.Theme 'Dark' -Environment $environment
    Assert ($handle.State.Appearance.Reason -eq 'UserDisabled' -or $environment.HighContrast) 'System appearance changes respect the app material override'
    $contrast=Get-LGThemeEnvironment;$contrast.HighContrast=$true;& $handle.Theme 'Dark' -Environment $contrast
    Assert ($handle.State.Appearance.HighContrast -and -not $handle.State.Appearance.Mica -and $handle.State.Appearance.Reason -eq 'HighContrast') 'High contrast remains authoritative when the app explicitly disables material'
    & $handle.Theme 'Dark'
    $handle.State.Controls.MaterialCombo.SelectedIndex=0;Pump
    Assert ((Read-LGAppearancePreference $path).Material -eq 'Auto') 'Automatic material can be re-enabled and saved independently of theme'
    $window=$handle.State.Window;$window.Width=[Math]::Max($window.MinWidth,[Math]::Min($window.Width,960));$window.Height=[Math]::Max($window.MinHeight,[Math]::Min($window.Height,680));Pump
    $before=Get-LGNormalBounds $window
    $window.Close();Pump;$handle=$null
    Assert ([LowGear.UI.WindowPlacement]::Valid((Read-LGAppearancePreference $path).Placement)) 'Normal close writes a valid window record'
    $handle=Open-Panel $themePath;$window=$handle.State.Window;Pump
    Assert ([Math]::Abs($window.Width-$before.Width) -lt 2 -and [Math]::Abs($window.Height-$before.Height) -lt 2) 'Reopening restores the prior logical size'
    Assert ([Math]::Abs($window.Left-$before.Left) -lt 2 -and [Math]::Abs($window.Top-$before.Top) -lt 2) 'Reopening restores the prior on-screen position'
    $window.WindowState='Maximized';Pump;$window.Close();Pump;$handle=$null
    Assert ((Read-LGAppearancePreference $path).Placement.Maximized) 'Maximized close stores normal bounds plus a separate state'
    $handle=Open-Panel $themePath
    Assert ($handle.State.Window.WindowState -eq 'Maximized') 'Maximized startup retains usable restore bounds'
    $handle.State.Window.WindowState='Normal';Pump
    Assert ([Math]::Abs($handle.State.Window.Width-$before.Width) -lt 2 -and [Math]::Abs($handle.State.Window.Height-$before.Height) -lt 2) 'Restoring after a remembered maximized startup recovers the last normal size'
    $handle.State.Window.WindowState='Maximized';Pump
    $handle.State.Window.WindowState='Minimized';Pump;$handle.State.Window.Close();Pump;$handle=$null
    Assert ((Read-LGAppearancePreference $path).Placement.Maximized) 'Minimizing before close does not replace the last non-minimized state'
    $handle=Open-Panel $themePath;$window=$handle.State.Window
    Assert ($window.WindowState -eq 'Maximized') 'Reopening never starts hidden as a minimized panel'
    $handle.State.Controls.RememberWindow.IsChecked=$false;Pump
    Assert ($window.WindowState -eq 'Maximized' -and $null -eq (Read-LGAppearancePreference $path).Placement) 'Turning off memory does not move the current window'
    $window.Close();Pump;$handle=$null;$handle=Open-Panel $themePath;$window=$handle.State.Window
    Assert ($window.WindowState -eq 'Normal' -and -not $handle.State.VisualPreference.RememberWindow) 'Memory off starts at default normal geometry'
    $handle.State.Controls.MaterialCombo.SelectedIndex=1;& $handle.Theme 'Dark' -Persist;$window.WindowState='Maximized';Pump
    & $handle.ResetAppearance;Pump
    Assert ($handle.State.ThemePreference -eq 'System' -and $handle.State.VisualPreference.Material -eq 'Auto' -and $handle.State.VisualPreference.RememberWindow -and $window.WindowState -eq 'Normal') 'One-click defaults restore theme, material, memory and a normal centred window'
    $window.Left=-50000;$window.Top=-50000;Pump;& $handle.RepairPlacement;Pump
    $current=Get-LGPlacementEnvironment $window
    Assert ([LowGear.UI.WindowPlacement]::Reachable((Get-LGNormalBounds $window),$current.Areas,$current.ScaleX,$current.ScaleY)) 'A live inaccessible panel can return to a reachable work area'
    $left=$window.Left;$top=$window.Top;& $handle.RepairPlacement
    Assert ($window.Left -eq $left -and $window.Top -eq $top) 'Visibility repair leaves normal user placement alone'
    $nativeBounds=[LowGear.UI.WindowPlacement]::CurrentBounds([Windows.Interop.WindowInteropHelper]::new($window).Handle,$current.ScaleX,$current.ScaleY)
    Assert (-not $nativeBounds.IsEmpty -and [Math]::Abs($nativeBounds.Width-$window.ActualWidth) -lt 2) 'Native visible bounds use the current HWND and WPF scale'
    $recordBefore=[IO.File]::ReadAllText($path);$handle.State.Child=[pscustomobject]@{HasExited=$false};$window.Close();Pump
    Assert (-not $handle.State.Closed -and [IO.File]::ReadAllText($path) -ceq $recordBefore) 'Blocked close during a mutation never overwrites geometry'
    $handle.State.Child=$null;$window.Close();Pump;$handle=$null
    $image=Join-Path $temp 'preview.png';$recordBefore=[IO.File]::ReadAllText($path)
    Show-LGPanel -RenderOnly -PreferencePath $themePath -AppearancePath $path -ImagePath $image -ThemeMode Dark -PreviewPage Settings
    Assert ([IO.File]::ReadAllText($path) -ceq $recordBefore) 'Static preview never reads or replaces actual placement memory'
    $safeReport=Get-LGDemoReport;$safeReport|Add-Member NoteProperty AppearancePath 'PRIVATE_SENTINEL';$safeReport|Add-Member NoteProperty WindowPlacement (Read-LGAppearancePreference $path).Placement
    $diagnostic=Get-LGDiagnostic $safeReport|ConvertTo-Json -Depth 8
    Assert ($diagnostic -notmatch 'PRIVATE_SENTINEL|AppearancePath|WindowPlacement|RelativeX|WorkArea') 'Diagnostic whitelist excludes appearance and display geometry'
    [pscustomobject]@{Status='Passed';Count=$checks.Count;Checks=$checks.ToArray();DisplayRemoval='SimulatedGeometry';SettingsChanged='AppOnly'}|ConvertTo-Json -Depth 5
}finally{
    if($null -ne $handle){$handle.State.Child=$null;$handle.State.Window.Close();& $handle.Cleanup}
    $expected=[IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('LowGear-appearance-tests-'+$id)))
    if($id -cnotmatch '^[a-f0-9]{32}$' -or [IO.Path]::GetFullPath($temp) -cne $expected){throw 'Unsafe appearance test cleanup'}
    if([IO.Directory]::Exists($temp)){[IO.Directory]::Delete($temp,$true)}
}
