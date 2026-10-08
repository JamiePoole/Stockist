<#
.SYNOPSIS
  Copy the Stockist addon into the WoW AddOns folder for local testing.
.PARAMETER WowPath
  Client folder (contains Interface\AddOns). Default: STOCKIST_WOW_PATH from .env, else the Forever beta client.
.PARAMETER IncludeProbe
  Also copy dev\StockistProbe.
.PARAMETER Watch
  Keep running and re-copy whenever a file changes.
#>
param(
    [string]$WowPath,
    [switch]$IncludeProbe,
    [switch]$Watch
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

if (-not $WowPath) {
    $env = Import-DotEnv
    $WowPath = if ($env['STOCKIST_WOW_PATH']) { $env['STOCKIST_WOW_PATH'] }
               else { 'C:\Program Files (x86)\World of Warcraft\_classic_beta_' }
}
$addons = Join-Path $WowPath 'Interface\AddOns'
if (-not (Test-Path $addons)) { throw "AddOns folder not found: $addons" }

$targets = @(@{ Src = Join-Path $RepoRoot 'Stockist'; Name = 'Stockist' })
if ($IncludeProbe) {
    $targets += @{ Src = Join-Path $RepoRoot 'dev\StockistProbe'; Name = 'StockistProbe' }
}

function Sync-Addons {
    foreach ($t in $targets) {
        $dest = Join-Path $addons $t.Name
        # /MIR mirrors (removes deleted files). Exit codes 0-7 are success for robocopy.
        robocopy $t.Src $dest /MIR /XD Tests .git /XF *.md /NFL /NDL /NJH /NJS /NP | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "robocopy failed ($LASTEXITCODE) copying $($t.Name). Access denied? Try an elevated shell." }
        Write-Host "Copied $($t.Name) -> $dest"
    }
    $global:LASTEXITCODE = 0
}

Sync-Addons
if (-not $Watch) { return }

Write-Host 'Watching for changes. Ctrl+C to stop.'
$watchers = foreach ($t in $targets) {
    $w = New-Object System.IO.FileSystemWatcher $t.Src, '*.*'
    $w.IncludeSubdirectories = $true
    $w.EnableRaisingEvents = $true
    $w
}
try {
    while ($true) {
        $changed = $false
        foreach ($w in $watchers) {
            if ($w.WaitForChanged('All', 500).TimedOut -eq $false) { $changed = $true }
        }
        if ($changed) { Start-Sleep -Milliseconds 300; Sync-Addons }
    }
} finally {
    $watchers | ForEach-Object { $_.Dispose() }
}
