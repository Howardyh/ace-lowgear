function Initialize-LGWindowEffects {
    if(-not ('LowGear.UI.WindowEffects' -as [type])){
        $references=@([Windows.Interop.HwndSource].Assembly.Location,[Windows.DependencyObject].Assembly.Location,[PowerShell].Assembly.Location)
        Add-Type -Path @((Join-Path $PSScriptRoot 'WindowEffects.cs'),(Join-Path $PSScriptRoot 'WindowPlacement.cs')) -ReferencedAssemblies $references
    }
}
function Read-LGUiPreference {
    param([string]$Path)
    if(-not [IO.File]::Exists($Path)){return [pscustomobject]@{Theme='System';Warning=$false}}
    try{
        $item=Get-Item -LiteralPath $Path -Force
        if($item.Length -gt 4096 -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Invalid preference file'}
        $value=[IO.File]::ReadAllText($Path)|ConvertFrom-Json
        if($null -eq $value -or @($value.PSObject.Properties).Count -ne 1 -or $value.Theme -cnotin @('System','Light','Dark')){throw 'Invalid theme'}
        [pscustomobject]@{Theme=[string]$value.Theme;Warning=$false}
    }catch{[pscustomobject]@{Theme='System';Warning=$true}}
}
function Write-LGUiPreference {
    param([string]$Path,[ValidateSet('System','Light','Dark')][string]$Theme)
    $directory=Split-Path $Path -Parent
    foreach($candidate in @($directory,$Path)){
        if((Test-Path -LiteralPath $candidate) -and ((Get-Item -LiteralPath $candidate -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Preference path is not a regular file or directory'}
    }
    [void][IO.Directory]::CreateDirectory($directory)
    $temporary=$Path+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
    try{
        $stream=[IO.File]::Open($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try{$bytes=[Text.Encoding]::UTF8.GetBytes((@{Theme=$Theme}|ConvertTo-Json -Compress));$stream.Write($bytes,0,$bytes.Length);$stream.Flush()}finally{$stream.Dispose()}
        if([IO.File]::Exists($Path)){[IO.File]::Replace($temporary,$Path,[Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($temporary,$Path)}
    }finally{if([IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}}
}
function Get-LGThemeEnvironment {
    $dark=$false;$transparency=$false
    $key=$null
    try{
        $key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Themes\Personalize')
        if($null -ne $key){$dark=($key.GetValue('AppsUseLightTheme',1) -eq 0);$transparency=($key.GetValue('EnableTransparency',1) -eq 1)}
    }catch{}finally{if($null -ne $key){$key.Dispose()}}
    [pscustomobject]@{Dark=$dark;Transparency=$transparency;HighContrast=[Windows.SystemParameters]::HighContrast;Build=[LowGear.UI.WindowEffects]::Build;BatterySaver=[LowGear.UI.WindowEffects]::BatterySaver}
}
function Resolve-LGAppearance {
    param([ValidateSet('System','Light','Dark')][string]$Theme,$Environment,[ValidateSet('Auto','Off')][string]$Material='Auto')
    $effective=if($Theme -eq 'System'){if($Environment.Dark){'Dark'}else{'Light'}}else{$Theme}
    $reason=if($Environment.HighContrast){'HighContrast'}elseif($Material -eq 'Off'){'UserDisabled'}elseif($Environment.Build -lt 22621){'Unsupported'}elseif(-not $Environment.Transparency){'TransparencyOff'}elseif($Environment.BatterySaver){'BatterySaver'}else{'Mica'}
    [pscustomobject]@{Theme=$effective;HighContrast=[bool]$Environment.HighContrast;Mica=($reason -eq 'Mica');Reason=$reason}
}
function Set-LGThemeResources {
    param($Window,$Appearance)
    $palette=if($Appearance.Theme -eq 'Dark'){
        @{Canvas='#202020';Surface='#2B2B2B';Subtle='#323232';Text='#F2F2F2';Secondary='#BCBCBC';Stroke='#454545';Accent='#60CDFF';AccentText='#08212D';Hover='#383838';Pressed='#424242';Selected='#253849';Success='#7CDA70';SuccessFill='#263D2A';Warning='#FCE100';WarningFill='#423B21';Error='#FF99A4';ErrorFill='#43292C'}
    }else{
        @{Canvas='#F3F3F3';Surface='#FFFFFF';Subtle='#F9F9F9';Text='#1A1A1A';Secondary='#606060';Stroke='#DFDFDF';Accent='#0F6CBD';AccentText='#FFFFFF';Hover='#F0F0F0';Pressed='#E5E5E5';Selected='#E8F1FA';Success='#107C10';SuccessFill='#EAF4E9';Warning='#805400';WarningFill='#FFF4CE';Error='#B10E1E';ErrorFill='#FDE7E9'}
    }
    foreach($key in $palette.Keys){$Window.Resources[$key+'Brush']=[Windows.Media.SolidColorBrush]::new([Windows.Media.ColorConverter]::ConvertFromString($palette[$key]))}
    if($Appearance.HighContrast){
        foreach($key in @('Canvas','Surface','Subtle','Hover','Pressed')){$Window.Resources[$key+'Brush']=[Windows.SystemColors]::WindowBrush}
        foreach($key in @('Text','Secondary','Success','Warning','Error','Stroke')){$Window.Resources[$key+'Brush']=[Windows.SystemColors]::WindowTextBrush}
        foreach($key in @('Accent','Selected')){$Window.Resources[$key+'Brush']=[Windows.SystemColors]::HighlightBrush}
        $Window.Resources['AccentTextBrush']=[Windows.SystemColors]::HighlightTextBrush
        foreach($key in @('SuccessFill','WarningFill','ErrorFill')){$Window.Resources[$key+'Brush']=[Windows.SystemColors]::WindowBrush}
    }
}
