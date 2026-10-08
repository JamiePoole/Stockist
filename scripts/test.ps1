<#
.SYNOPSIS
  Run the pure-Lua unit tests (Lua 5.1 via lupa). Creates .venv on first use.
.PARAMETER Filter
  Only run specs whose file name contains this text.
#>
param([string]$Filter = '')

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$py = Join-Path $root '.venv\Scripts\python.exe'

if (-not (Test-Path $py)) {
    python -m venv (Join-Path $root '.venv')
    & $py -m pip install --quiet -r (Join-Path $root 'requirements-dev.txt')
}

& $py (Join-Path $root 'tests\run.py') $Filter
exit $LASTEXITCODE
