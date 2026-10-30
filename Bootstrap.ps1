param([switch]$NoDialog)

function Test-LGSourceFiles {
    param([string]$Root)
    $checks=[Collections.Generic.List[object]]::new()
    try{
        $manifest=[IO.File]::ReadAllText((Join-Path $Root 'public-files.json'))|ConvertFrom-Json
        if($manifest.Version -cnotmatch '^1\.\d+\.\d+$' -or @($manifest.Files).Count -eq 0){throw 'Invalid manifest'}
        $base=[IO.Path]::GetFullPath($Root).TrimEnd('\')+'\'
        foreach($relative in $manifest.Files){
            $full=[IO.Path]::GetFullPath((Join-Path $Root $relative))
            if([IO.Path]::IsPathRooted($relative) -or -not $full.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)){throw 'Invalid file list'}
            $required=$relative -match '^(src/|ui/|LowGear\.ps1$|Bootstrap\.ps1$|public-files\.json$)'
            if(-not [IO.File]::Exists($full)){$checks.Add([pscustomobject]@{Name=$relative;State=if($required){'Error'}else{'Warning'};Code=if($required){'SOURCE_MISSING'}else{'OPTIONAL_SOURCE_MISSING'};Message='缺少 '+$relative+'，请完整解压对应版本的源码包。'})}
        }
        foreach($relative in @('LowGear.ps1','Bootstrap.ps1','src/LowGear.psm1','ui/Panel.ps1','ui/Panel.xaml')){if($relative -cnotin $manifest.Files){throw 'Incomplete manifest'}}
        if($checks.Count -eq 0){$checks.Add([pscustomobject]@{Name='Source';State='Healthy';Code='OK';Message='源码文件齐全。'})}
    }catch{$checks.Add([pscustomobject]@{Name='Source';State='Error';Code='SOURCE_MANIFEST_INVALID';Message='源码清单缺失或损坏，请重新下载并完整解压。'})}
    $checks.ToArray()
}
function Initialize-LGStartupSecurity {
    # Pin the current host's built-in module; inherited PSModulePath may list another edition first.
    $path=Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Security\Microsoft.PowerShell.Security.psd1'
    $loaded=Get-Module Microsoft.PowerShell.Security
    if($null -eq $loaded -or $loaded.Path -ine $path){Import-Module -Name $path -ErrorAction Stop}
}
function Test-LGStartupPath {
    param([string]$Path)
    try{
        $folder=Split-Path $Path -Parent;$leaf=Split-Path $folder -Leaf
        if($leaf -cnotmatch '^LowGear-start-[a-f0-9]{32}$' -or [IO.Path]::GetFileName($Path) -cne 'ready.json' -or -not [IO.Path]::IsPathRooted($Path)){return $false}
        foreach($item in @($folder,$Path)){if((Test-Path -LiteralPath $item) -and ((Get-Item -LiteralPath $item -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){return $false}}
        if(-not [IO.Directory]::Exists($folder)){return $false}
        # Another administrator account may have a different TEMP after UAC.
        Initialize-LGStartupSecurity
        $acl=Microsoft.PowerShell.Security\Get-Acl -LiteralPath $folder
        if(-not $acl.AreAccessRulesProtected){return $false}
        $owner=$acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
        if($owner -in @('S-1-1-0','S-1-5-11','S-1-5-32-545')){return $false}
        $full=@{}
        foreach($rule in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])){
            $sid=$rule.IdentityReference.Value
            if($rule.AccessControlType -eq 'Allow'){
                if($sid -notin @($owner,'S-1-5-18','S-1-5-32-544')){return $false}
                if(($rule.FileSystemRights -band [Security.AccessControl.FileSystemRights]::FullControl) -eq [Security.AccessControl.FileSystemRights]::FullControl){$full[$sid]=$true}
            }
        }
        $full.ContainsKey($owner) -and $full.ContainsKey('S-1-5-18') -and $full.ContainsKey('S-1-5-32-544')
    }catch{$false}
}
function New-LGStartupPath {
    Initialize-LGStartupSecurity
    $folder=Join-Path ([IO.Path]::GetTempPath()) ('LowGear-start-'+[Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($folder)
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    try{
        $acl=[Security.AccessControl.DirectorySecurity]::new();$acl.SetAccessRuleProtection($true,$false);$acl.SetOwner($identity.User)
        foreach($sid in @($identity.User.Value,'S-1-5-18','S-1-5-32-544')|Select-Object -Unique){[void]$acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid),'FullControl','ContainerInherit,ObjectInherit','None','Allow'))}
        Microsoft.PowerShell.Security\Set-Acl -LiteralPath $folder -AclObject $acl
    }catch{try{[IO.Directory]::Delete($folder,$false)}catch{};throw}finally{$identity.Dispose()}
    Join-Path $folder 'ready.json'
}
function Write-LGStartupReady {
    param([string]$Path,[ValidateSet('Ready','Error')][string]$State='Ready',[string]$Code='OK')
    if(-not $Path -or -not (Test-LGStartupPath $Path)){return}
    try{
        $stream=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
        try{$bytes=[Text.Encoding]::UTF8.GetBytes((@{State=$State;Code=$Code}|ConvertTo-Json));$stream.Write($bytes,0,$bytes.Length);$stream.Flush()}finally{$stream.Dispose()}
    }catch{}
}
function Remove-LGStartupPath {
    param([string]$Path)
    if(-not(Test-LGStartupPath $Path)){return}
    foreach($file in @($Path,($Path+'.tmp'))){if([IO.File]::Exists($file) -and -not ((Get-Item -LiteralPath $file -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){[IO.File]::Delete($file)}}
    try{[IO.Directory]::Delete((Split-Path $Path -Parent),$false)}catch{}
}
function Wait-LGStartup {
    param([string]$Path,$Process,[int]$TimeoutSeconds=90)
    $watch=[Diagnostics.Stopwatch]::StartNew()
    do{
        if((Test-LGStartupPath $Path) -and [IO.File]::Exists($Path)){
            try{$item=Get-Item -LiteralPath $Path;if($item.Length -gt 1024){throw 'Large receipt'};$value=[IO.File]::ReadAllText($Path)|ConvertFrom-Json
                if($value.State -in @('Ready','Error') -and $value.Code -cmatch '^[A-Z_]{2,64}$'){return $value}
            }catch{}
        }
        $Process.Refresh();if($Process.HasExited){return [pscustomobject]@{State='Error';Code='STARTUP_EXITED'}}
        Start-Sleep -Milliseconds 100
    }while($watch.Elapsed.TotalSeconds -lt $TimeoutSeconds)
    [pscustomobject]@{State='Error';Code='STARTUP_TIMEOUT'}
}
function Show-LGStartupError {
    param([string]$Code,[string]$Message,[switch]$NoDialog)
    Write-Host ('ACE LowGear：'+$Message+' ['+$Code+']') -ForegroundColor Red
    try{
        $directory=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'ACE-LowGear'
        if(-not(Test-Path $directory) -or -not((Get-Item $directory -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){
            [void][IO.Directory]::CreateDirectory($directory);$path=Join-Path $directory 'startup-last.json'
            if(-not(Test-Path $path) -or -not((Get-Item $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){
                $temporary=$path+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
                try{[IO.File]::WriteAllText($temporary,(@{Code=$Code;Stage='Startup';TimestampUtc=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json));if([IO.File]::Exists($path)){[IO.File]::Replace($temporary,$path,[Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($temporary,$path)}}finally{if([IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}}
            }
        }
    }catch{}
    if(-not $NoDialog){try{Add-Type -AssemblyName PresentationFramework;[void][Windows.MessageBox]::Show(($Message+"`n错误码："+$Code),'ACE LowGear · 启动未完成')}catch{}}
}
function Invoke-LGBootstrap {
    param([string]$Root,[switch]$NoDialog)
    $path=$null
    try{
        $issues=@(Test-LGSourceFiles $Root);$blocked=@($issues|Where-Object State -eq 'Error')
        if($blocked.Count){Show-LGStartupError $blocked[0].Code $blocked[0].Message -NoDialog:$NoDialog;return 1}
        foreach($warning in @($issues|Where-Object State -eq 'Warning')){Write-Host $warning.Message -ForegroundColor Yellow}
        if(-not [Environment]::Is64BitOperatingSystem -or [Environment]::OSVersion.Version.Major -lt 10){Show-LGStartupError 'SYSTEM_UNSUPPORTED' '需要 64 位 Windows 10 或 Windows 11。' -NoDialog:$NoDialog;return 1}
        $hostPath=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        if(-not [Environment]::Is64BitProcess){$hostPath=Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'}
        if(-not [IO.File]::Exists($hostPath)){throw 'Host missing'}
        $path=New-LGStartupPath
        $arguments='-NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+(Join-Path $Root 'LowGear.ps1')+'" -Command Panel -StartupReadyPath "'+$path+'"'
        $identity=[Security.Principal.WindowsIdentity]::GetCurrent();try{$admin=[Security.Principal.WindowsPrincipal]::new($identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)}finally{$identity.Dispose()}
        $parameters=@{FilePath=$hostPath;ArgumentList=$arguments;WindowStyle='Hidden';PassThru=$true};if(-not $admin){$parameters.Verb='RunAs'}
        Write-Host '正在检查并打开 ACE LowGear；请完成 Windows 管理员授权。'
        $process=Start-Process @parameters
        try{$receipt=Wait-LGStartup $path $process}finally{$process.Dispose()}
        if($receipt.State -eq 'Ready'){return 0}
        $message=if($receipt.Code -eq 'STARTUP_TIMEOUT'){'启动耗时较长，请先检查是否已有窗口打开，再决定是否重试。'}else{'界面未能打开，请确认完整解压源码包，并检查 Windows PowerShell 与 .NET Framework 环境。'}
        Show-LGStartupError $receipt.Code $message -NoDialog:$NoDialog;return 1
    }catch{
        $cancel=$false;$error=$_.Exception;while($null -ne $error){if($error -is [ComponentModel.Win32Exception] -and $error.NativeErrorCode -eq 1223){$cancel=$true};$error=$error.InnerException}
        Show-LGStartupError $(if($cancel){'AUTH_CANCELLED'}else{'STARTUP_FAILED'}) $(if($cancel){'已取消管理员授权，未启动安装；需要时可重新打开。'}else{'启动器未能打开面板，请检查完整源码包和系统环境。'}) -NoDialog:$NoDialog
        return 1
    }finally{if($path){Remove-LGStartupPath $path}}
}
if($MyInvocation.InvocationName -ne '.') {exit (Invoke-LGBootstrap -Root $PSScriptRoot -NoDialog:$NoDialog)}
