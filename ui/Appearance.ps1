function New-LGAppearancePreference {
    [pscustomobject]@{Schema=1;Material='Auto';RememberWindow=$true;Placement=$null;Warning=$false}
}
function ConvertTo-LGPlacement {
    param($Value)
    if($null -eq $Value){return $null}
    try{
        $result=[LowGear.UI.PanelPlacement]::new()
        foreach($name in @('Width','Height','RelativeX','RelativeY')){if($Value.$name -isnot [ValueType] -or $Value.$name -is [bool]){return $null};$result.$name=[double]$Value.$name}
        if($Value.Maximized -isnot [bool]){return $null};$result.Maximized=$Value.Maximized
        $result.WorkArea=[LowGear.UI.DisplayArea]::new()
        foreach($name in @('Left','Top','Width','Height')){if($Value.WorkArea.$name -isnot [ValueType] -or $Value.WorkArea.$name -is [bool]){return $null};$result.WorkArea.$name=[double]$Value.WorkArea.$name}
        if([LowGear.UI.WindowPlacement]::Valid($result)){return $result}
    }catch{}
    $null
}
function Read-LGAppearancePreference {
    param([string]$Path)
    $result=New-LGAppearancePreference
    if(-not [IO.File]::Exists($Path)){return $result}
    try{
        $item=Get-Item -LiteralPath $Path -Force
        if($item.Length -gt 16384 -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Invalid preference file'}
        $value=[IO.File]::ReadAllText($Path)|ConvertFrom-Json
        $schema=Get-LGUiValue $value 'Schema'
        if($null -eq $value -or $schema -isnot [int] -or $schema -ne 1){throw 'Unsupported preference schema'}
        if((Get-LGUiValue $value 'Material') -cin @('Auto','Off')){$result.Material=$value.Material}else{$result.Warning=$true}
        if((Get-LGUiValue $value 'RememberWindow') -is [bool]){$result.RememberWindow=$value.RememberWindow}else{$result.Warning=$true}
        $placement=Get-LGUiValue $value 'Placement'
        if($result.RememberWindow -and $null -ne $placement){$result.Placement=ConvertTo-LGPlacement $placement;if($null -eq $result.Placement){$result.Warning=$true}}
    }catch{$result.Warning=$true}
    $result
}
function Write-LGAppearancePreference {
    param([string]$Path,$Value)
    if($Value.Material -cnotin @('Auto','Off') -or $Value.RememberWindow -isnot [bool]){throw 'Invalid appearance preference'}
    $placement=if($Value.RememberWindow){ConvertTo-LGPlacement $Value.Placement}else{$null}
    if($Value.RememberWindow -and $null -ne $Value.Placement -and $null -eq $placement){throw 'Invalid placement'}
    $stored=[ordered]@{Schema=1;Material=[string]$Value.Material;RememberWindow=[bool]$Value.RememberWindow;Placement=$placement}
    $directory=Split-Path $Path -Parent
    foreach($candidate in @($directory,$Path)){if((Test-Path -LiteralPath $candidate) -and ((Get-Item -LiteralPath $candidate -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Preference path is not regular'}}
    [void][IO.Directory]::CreateDirectory($directory)
    $temporary=$Path+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
    try{
        $stream=[IO.File]::Open($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try{$bytes=[Text.Encoding]::UTF8.GetBytes(($stored|ConvertTo-Json -Depth 5));$stream.Write($bytes,0,$bytes.Length);$stream.Flush()}finally{$stream.Dispose()}
        if([IO.File]::Exists($Path)){[IO.File]::Replace($temporary,$Path,[Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($temporary,$Path)}
    }finally{if([IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}}
}
function Get-LGPlacementEnvironment {
    param($Window)
    $scaleX=1.0;$scaleY=1.0
    $source=[Windows.PresentationSource]::FromVisual($Window)
    if($null -ne $source -and $null -ne $source.CompositionTarget){$scaleX=$source.CompositionTarget.TransformToDevice.M11;$scaleY=$source.CompositionTarget.TransformToDevice.M22}
    $areas=@([LowGear.UI.WindowPlacement]::GetAreas())
    if($areas.Count -eq 0){$work=[Windows.SystemParameters]::WorkArea;$area=[LowGear.UI.DisplayArea]::new();$area.Left=$work.Left*$scaleX;$area.Top=$work.Top*$scaleY;$area.Width=$work.Width*$scaleX;$area.Height=$work.Height*$scaleY;$area.Primary=$true;$areas=@($area)}
    [pscustomobject]@{Areas=[LowGear.UI.DisplayArea[]]$areas;ScaleX=$scaleX;ScaleY=$scaleY}
}
function Get-LGNormalBounds {
    param($Window)
    if($Window.WindowState -ne 'Normal' -and -not $Window.RestoreBounds.IsEmpty){return $Window.RestoreBounds}
    if([double]::IsNaN($Window.Left) -or [double]::IsNaN($Window.Top)){return [Windows.Rect]::Empty}
    [Windows.Rect]::new($Window.Left,$Window.Top,$Window.Width,$Window.Height)
}
function Set-LGWindowPlacement {
    param($Window,$Placement)
    $Window.WindowStartupLocation='Manual'
    $Window.MinWidth=$Placement.MinWidth;$Window.MinHeight=$Placement.MinHeight
    $Window.Width=$Placement.Width;$Window.Height=$Placement.Height;$Window.Left=$Placement.Left;$Window.Top=$Placement.Top
}
