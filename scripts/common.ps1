# Shared helpers for build.ps1 and release.ps1.

$script:RepoRoot = Split-Path -Parent $PSScriptRoot

function Import-DotEnv {
    param([string]$Path = (Join-Path $script:RepoRoot '.env'))
    $vars = @{}
    if (Test-Path $Path) {
        foreach ($line in Get-Content $Path) {
            if ($line -match '^\s*#' -or $line -notmatch '=') { continue }
            $k, $v = $line -split '=', 2
            $vars[$k.Trim()] = $v.Trim().Trim('"')
        }
    }
    return $vars
}

function Get-AddonVersion {
    $toc = Join-Path $script:RepoRoot 'Stockist\Stockist.toc'
    $m = Select-String -Path $toc -Pattern '^## Version:\s*(\S+)' | Select-Object -First 1
    if (-not $m) { throw "No '## Version:' line in $toc" }
    return $m.Matches[0].Groups[1].Value
}
