<#
.SYNOPSIS
  Bump the version, build the distributable zip, optionally upload to CurseForge.
.PARAMETER Bump
  patch | minor | major. Omit to rebuild the zip for the current version.
.PARAMETER Upload
  Upload the zip to CurseForge. Needs CURSEFORGE_API_TOKEN and CURSEFORGE_PROJECT_ID in .env.
.PARAMETER ReleaseType
  CurseForge release type: alpha | beta | release.
.PARAMETER GameVersionId
  Numeric CurseForge game-version ID(s). If omitted, lists the available versions and stops.
.PARAMETER DryRun
  Show what would happen without changing files or uploading.
#>
param(
    [ValidateSet('patch', 'minor', 'major')][string]$Bump,
    [switch]$Upload,
    [ValidateSet('alpha', 'beta', 'release')][string]$ReleaseType = 'beta',
    [int[]]$GameVersionId,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$current = Get-AddonVersion
$version = $current
if ($Bump) {
    $p = $current.Split('.') | ForEach-Object { [int]$_ }
    switch ($Bump) {
        'major' { $p = @(($p[0] + 1), 0, 0) }
        'minor' { $p = @($p[0], ($p[1] + 1), 0) }
        'patch' { $p = @($p[0], $p[1], ($p[2] + 1)) }
    }
    $version = $p -join '.'
}
Write-Host "Version: $current -> $version"

$tocPath = Join-Path $RepoRoot 'Stockist\Stockist.toc'
$verLua = Join-Path $RepoRoot 'Stockist\Core\Version.lua'
$changelog = Join-Path $RepoRoot 'CHANGELOG.md'

if ($Bump -and -not $DryRun) {
    (Get-Content $tocPath -Raw) -replace '(?m)^## Version:.*$', "## Version: $version" | Set-Content $tocPath -NoNewline
    (Get-Content $verLua -Raw) -replace 'Stockist\.VERSION = ".*"', "Stockist.VERSION = `"$version`"" | Set-Content $verLua -NoNewline
    $cl = Get-Content $changelog -Raw
    if ($cl -notmatch "(?m)^## $([regex]::Escape($version))\b") {
        $cl = $cl -replace '(?m)^# Changelog\r?\n', "# Changelog`n`n## $version`n- TODO: describe changes.`n"
        Set-Content $changelog $cl -NoNewline
        Write-Host "Added a '## $version' stub to CHANGELOG.md. Edit it before uploading."
    }
}

# Release notes = the changelog section for this version.
$notes = ''
if (Test-Path $changelog) {
    $m = [regex]::Match((Get-Content $changelog -Raw), "(?ms)^## $([regex]::Escape($version))\s*\r?\n(.*?)(?=^## |\z)")
    if ($m.Success) { $notes = $m.Groups[1].Value.Trim() }
}

$dist = Join-Path $RepoRoot 'dist'
$zip = Join-Path $dist "Stockist-$version.zip"
if ($DryRun) {
    Write-Host "[dry run] would build $zip and (if -Upload) upload it as '$ReleaseType'."
    Write-Host "Notes:`n$notes"
    return
}

# Stage as dist\stage\Stockist so the zip has a single top-level Stockist\ folder.
$stage = Join-Path $dist 'stage'
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Force (Join-Path $stage 'Stockist') | Out-Null
robocopy (Join-Path $RepoRoot 'Stockist') (Join-Path $stage 'Stockist') /E /XD Tests /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy failed ($LASTEXITCODE)" }
foreach ($f in 'LICENSE', 'README.md') {
    $src = Join-Path $RepoRoot $f
    if (Test-Path $src) { Copy-Item $src (Join-Path $stage 'Stockist') }
}
if (Test-Path $zip) { Remove-Item $zip -Force }
# Compress-Archive on Windows PowerShell 5.1 writes backslash entry names, which break on some extractors.
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::Open($zip, 'Create')
try {
    $stageFull = (Resolve-Path $stage).Path.TrimEnd('\') + '\'
    Get-ChildItem $stage -Recurse -File | ForEach-Object {
        $entry = $_.FullName.Substring($stageFull.Length).Replace('\', '/')
        [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $_.FullName, $entry)
    }
} finally { $archive.Dispose() }
Remove-Item $stage -Recurse -Force
Write-Host "Built $zip"

if (-not $Upload) { return }

$env = Import-DotEnv
$token = $env['CURSEFORGE_API_TOKEN']; $projectId = $env['CURSEFORGE_PROJECT_ID']
if (-not $token -or -not $projectId) {
    Write-Warning 'CURSEFORGE_API_TOKEN / CURSEFORGE_PROJECT_ID not set in .env. Skipping upload (zip is built).'
    return
}
$api = 'https://wow.curseforge.com/api'
$headers = @{ 'X-Api-Token' = $token }

if (-not $GameVersionId) {
    Write-Host 'No -GameVersionId given. Available game versions (look for WoW: Forever / 1.60):'
    Invoke-RestMethod "$api/game/versions" -Headers $headers |
        Where-Object { $_.name -match '1\.60|Forever|12\.' } |
        Format-Table id, name, gameVersionTypeID | Out-String | Write-Host
    Write-Host 'Re-run with -GameVersionId <id>.'
    return
}

$meta = @{
    changelog     = $notes
    changelogType = 'markdown'
    displayName   = "Stockist $version"
    gameVersions  = @($GameVersionId)
    releaseType   = $ReleaseType
} | ConvertTo-Json -Compress

# curl.exe ships with Windows 10+ and handles multipart; Windows PowerShell 5.1 lacks Invoke-RestMethod -Form.
$out = curl.exe -sS -X POST "$api/projects/$projectId/upload-file" `
    -H "X-Api-Token: $token" `
    -F "metadata=$meta" `
    -F "file=@$zip"
if ($LASTEXITCODE -ne 0) { throw "CurseForge upload failed: $out" }
Write-Host "CurseForge response: $out"
