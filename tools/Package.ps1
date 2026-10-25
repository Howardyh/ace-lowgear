[CmdletBinding()]
param([string]$Destination)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
& (Join-Path $PSScriptRoot 'Validate-Public.ps1') | Out-Host
$manifest=Get-Content -LiteralPath (Join-Path $root 'public-files.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if(-not $Destination){$Destination=Join-Path $root 'dist'}
[void][IO.Directory]::CreateDirectory($Destination)
$path=Join-Path $Destination ('ace-lowgear-'+$manifest.Version+'-source.zip')
if(Test-Path -LiteralPath $path){throw '目标包已存在，拒绝覆盖。'}
Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
$temporary=$path+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
try{
    $archive=[IO.Compression.ZipFile]::Open($temporary,[IO.Compression.ZipArchiveMode]::Create)
    try{foreach($relative in $manifest.Files){[void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,(Join-Path $root $relative),('ace-lowgear/'+$relative),[IO.Compression.CompressionLevel]::Optimal)}}finally{$archive.Dispose()}
    $archive=[IO.Compression.ZipFile]::OpenRead($temporary)
    try{
        $actual=@($archive.Entries | ForEach-Object {$_.FullName.Substring(12)})
        if(@(Compare-Object @($manifest.Files | Sort-Object) @($actual | Sort-Object)).Count -gt 0){throw '归档文件清单不一致。'}
        foreach($entry in $archive.Entries){
            $sha=[Security.Cryptography.SHA256]::Create();$stream=$entry.Open()
            try{$hash=([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','')}finally{$stream.Dispose();$sha.Dispose()}
            if($hash -cne (Get-FileHash -LiteralPath (Join-Path $root $entry.FullName.Substring(12)) -Algorithm SHA256).Hash){throw '归档内容 hash 不一致。'}
        }
    }finally{$archive.Dispose()}
    [IO.File]::Move($temporary,$path)
}finally{if([IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}}
$hash=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
[IO.File]::WriteAllText(($path+'.sha256'),($hash+'  '+[IO.Path]::GetFileName($path)+"`r`n"),[Text.Encoding]::ASCII)
[pscustomobject]@{Package=[IO.Path]::GetFileName($path);Files=$manifest.Files.Count;SHA256=$hash;Verification='Passed'} | ConvertTo-Json
