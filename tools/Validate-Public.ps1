[CmdletBinding()]
param([switch]$Index)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$manifest=Get-Content -LiteralPath (Join-Path $root 'public-files.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$findings=[Collections.Generic.List[string]]::new()
$unique=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$patterns=@{
    PersonalPath='(?i)\b[A-Z]:[\\/]+(?:Users|Documents and Settings)[\\/]+[^\s\\/<>]+'
    Token='(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-proj-[A-Za-z0-9_-]{20,})'
    PrivateKey='-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----'
    Email='(?i)\b[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}\b'
    UserSid='\bS-1-5-21-\d+-\d+-\d+-\d+\b'
}
foreach($relative in $manifest.Files){
    if(-not $unique.Add($relative) -or [IO.Path]::IsPathRooted($relative) -or $relative -match '(^|/)\.\.(/|$)' -or
       $relative -match '(?i)(^|/)(\.git|backups|reports|state|work|dist|runtime)(/|$)' -or
       $relative -match '(?i)\.(exe|dll|log|pdb|zip|png|reg|dmp|etl)$'){throw ('公开清单中存在禁止项：'+$relative)}
    $file=Get-Item -LiteralPath (Join-Path $root $relative) -Force
    if($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw '公开项不是普通文件。'}
    $text=[IO.File]::ReadAllText($file.FullName)
    foreach($key in $patterns.Keys){if([regex]::IsMatch($text,$patterns[$key])){$findings.Add($relative+': '+$key)}}
    foreach($identifier in @($env:USERNAME,$env:COMPUTERNAME)){
        if($identifier -and $identifier.Length -ge 5 -and [regex]::IsMatch($text,('(?i)(?<![\w-])'+[regex]::Escape($identifier)+'(?![\w-])'))){$findings.Add($relative+': LocalIdentity')}
    }
    if($Index){
        $staged=(& git -C $root show (':'+$relative)) -join "`n"
        if($LASTEXITCODE -ne 0){throw '不能读取暂存内容。'}
        foreach($key in $patterns.Keys){if([regex]::IsMatch($staged,$patterns[$key])){$findings.Add($relative+': Staged'+$key)}}
    }
}
if($Index){
    $files=@(& git -C $root -c core.quotepath=false ls-files)
    if($LASTEXITCODE -ne 0 -or @(Compare-Object @($manifest.Files | Sort-Object) @($files | Sort-Object)).Count -gt 0){throw '暂存区与公开清单不一致。'}
}
if($findings.Count -gt 0){$findings | Select-Object -Unique | Write-Output;throw '隐私扫描未通过；输出不含匹配的敏感值。'}
[pscustomobject]@{Status='Passed';PublicFiles=$unique.Count;Index=[bool]$Index;Findings=0} | ConvertTo-Json
