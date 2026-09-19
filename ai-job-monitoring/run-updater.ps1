# Run the generic updater for a given markdown file.
# Usage: run-updater.ps1 <markdown-path>
# When called with no args, runs for AI-jobs.md (Glasgow scan) by default.

param(
    [string]$JobsMd = "$PSScriptRoot\AI-jobs.md",
    [string]$PagePrefix = "linkedin-page"
)

$ErrorActionPreference = "Stop"

$env:JOBS_MD = (Resolve-Path $JobsMd).Path
$env:PAGE_PREFIX = $PagePrefix
$env:JOBS_COMMIT = "0"  # caller is responsible for committing

Write-Host "[run-updater] JOBS_MD=$env:JOBS_MD"
Write-Host "[run-updater] PAGE_PREFIX=$env:PAGE_PREFIX"

python "$PSScriptRoot\update-jobs.py"
exit $LASTEXITCODE
