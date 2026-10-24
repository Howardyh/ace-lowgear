[CmdletBinding()]
param([string]$OutputDirectory)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
& (Join-Path $PSScriptRoot 'Test-PublicContent.ps1') | Out-Host
$manifest = Get-Content -LiteralPath (Join-Path $root 'public-files.json') -Raw | ConvertFrom-Json
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $root 'dist' }
[void][IO.Directory]::CreateDirectory($OutputDirectory)
$archivePath = Join-Path $OutputDirectory ('ace-lowgear-v' + $manifest.Version + '-source.zip')
if (Test-Path -LiteralPath $archivePath) { throw 'Package already exists; choose another output directory.' }
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$temporaryPath = $archivePath + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
try {
    $stream = [IO.File]::Open($temporaryPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    $archive = $null
    try {
        $archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create, $false)
        foreach ($relative in $manifest.Files) {
            [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, (Join-Path $root $relative),
                ('ace-lowgear/' + $relative), [IO.Compression.CompressionLevel]::Optimal)
        }
    }
    finally { if ($null -ne $archive) { $archive.Dispose() }; $stream.Dispose() }
    $archive = [IO.Compression.ZipFile]::OpenRead($temporaryPath)
    try {
        $actual = @($archive.Entries | ForEach-Object { $_.FullName.Substring('ace-lowgear/'.Length) })
        if (@(Compare-Object @($manifest.Files | Sort-Object) @($actual | Sort-Object)).Count -ne 0) { throw 'Package allowlist verification failed.' }
        foreach ($entry in $archive.Entries) {
            $relative = $entry.FullName.Substring('ace-lowgear/'.Length)
            $sha = [Security.Cryptography.SHA256]::Create()
            $entryStream = $entry.Open()
            try { $entryHash = ([BitConverter]::ToString($sha.ComputeHash($entryStream))).Replace('-', '') }
            finally { $entryStream.Dispose(); $sha.Dispose() }
            if ($entryHash -cne (Get-FileHash -LiteralPath (Join-Path $root $relative) -Algorithm SHA256).Hash) {
                throw ('Package hash mismatch: ' + $relative)
            }
        }
    }
    finally { $archive.Dispose() }
    [IO.File]::Move($temporaryPath, $archivePath)
}
finally { if ([IO.File]::Exists($temporaryPath)) { [IO.File]::Delete($temporaryPath) } }
$hash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
[IO.File]::WriteAllText(($archivePath + '.sha256'), ($hash + '  ' + [IO.Path]::GetFileName($archivePath) + "`r`n"), [Text.Encoding]::ASCII)
[pscustomobject]@{ Package = [IO.Path]::GetFileName($archivePath); SourceFiles = $manifest.Files.Count; SHA256 = $hash; ArchiveHashVerification = 'Passed' } | ConvertTo-Json
