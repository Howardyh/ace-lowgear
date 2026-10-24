[CmdletBinding()]
param([switch]$CheckIndex)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$manifest = Get-Content -LiteralPath (Join-Path $root 'public-files.json') -Raw | ConvertFrom-Json
$findings = [Collections.Generic.List[string]]::new()
$seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$rules = [ordered]@{
    PersonalWindowsPath = '(?i)\b[A-Z]:[\\/]+(?:Users|Documents and Settings)[\\/]+[^\s\\/<>]+'
    GitHubCredential = '(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})'
    PrivateKey = '-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----'
    Email = '(?i)\b[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}\b'
    LocalSid = '\bS-1-5-21-\d+-\d+-\d+-\d+\b'
}
foreach ($relative in $manifest.Files) {
    if (-not $seen.Add($relative)) { throw 'Duplicate public manifest entry.' }
    if ([IO.Path]::IsPathRooted($relative) -or $relative -match '(^|/)\.\.(/|$)' -or
        $relative -match '(?i)(^|/)(backups|state|reports|runtime|dist|artifacts|work|\.git)(/|$)' -or
        $relative -match '(?i)\.(exe|dll|pdb|log|dmp|etl|reg|zip)$') { throw ('Disallowed public file: ' + $relative) }
    $path = [IO.Path]::GetFullPath((Join-Path $root $relative))
    if (-not $path.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Public manifest path escaped the repository.' }
    $item = Get-Item -LiteralPath $path -Force
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw ('Non-regular public file: ' + $relative) }
    $text = [IO.File]::ReadAllText($path)
    foreach ($rule in $rules.Keys) {
        foreach ($match in [regex]::Matches($text, $rules[$rule])) {
            if ($rule -eq 'Email' -and $match.Value -match '(?i)@users\.noreply\.github\.com$') { continue }
            $findings.Add($relative + ': ' + $rule)
        }
    }
    foreach ($localIdentifier in @($env:USERNAME, $env:COMPUTERNAME)) {
        if ($localIdentifier -and $localIdentifier.Length -ge 5 -and
            [regex]::IsMatch($text, ('(?i)(?<![\w-])' + [regex]::Escape($localIdentifier) + '(?![\w-])'))) {
            $findings.Add($relative + ': LocalAccountOrComputerName')
        }
    }
}
if ($CheckIndex) {
    $tracked = @(& git -C $root ls-files)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect the Git index.' }
    $difference = @(Compare-Object @($manifest.Files | Sort-Object) @($tracked | Sort-Object))
    if ($difference.Count -ne 0) { throw 'The Git index differs from the public allowlist.' }
    # Scan the exact staged bytes too; working-tree checks alone are insufficient.
    foreach ($relative in $tracked) {
        $staged = (& git -C $root show (':' + $relative)) -join "`n"
        if ($LASTEXITCODE -ne 0) { throw 'Cannot read staged public content.' }
        foreach ($rule in $rules.Keys) {
            foreach ($match in [regex]::Matches($staged, $rules[$rule])) {
                if ($rule -eq 'Email' -and $match.Value -match '(?i)@users\.noreply\.github\.com$') { continue }
                $findings.Add($relative + ': Staged' + $rule)
            }
        }
    }
}
if ($findings.Count -ne 0) {
    $findings | Select-Object -Unique | Write-Output
    throw 'Public-content privacy checks failed. Findings omit matched sensitive values.'
}
[pscustomobject]@{ Status = 'Passed'; PublicFiles = $manifest.Files.Count; IndexChecked = [bool]$CheckIndex; Findings = 0 } | ConvertTo-Json
