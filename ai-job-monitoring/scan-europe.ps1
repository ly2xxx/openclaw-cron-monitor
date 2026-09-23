# Europe-wide "AI Enablement" daily scan: fetch via LinkedIn's guest endpoint, then
# update AI-Enablement-Europe.md. No Chrome / CDP / login needed.
#
# Commit behaviour is update-jobs.py's: it commits + pushes to origin/main unless
# JOBS_COMMIT=0 is set (e.g. when the caller commits several files together).

$ErrorActionPreference = 'Stop'
$ScriptDir = $PSScriptRoot

# The old /jobs/search/ or new /jobs/search-results/ URL both work; only the
# search params (keywords, geoId, f_TPR, ...) are forwarded to the guest endpoint.
$env:BASE_URL = 'https://www.linkedin.com/jobs/search/?f_TPR=r2592000&geoId=100506914&keywords=%22AI%20Enablement%22&location=Europe'
$env:PAGE_PREFIX = 'europe-page'
$env:OUT_DIR = $ScriptDir
$env:AI_JOB_MONITOR_DIR = $ScriptDir
$env:JOBS_MD = Join-Path $ScriptDir 'AI-Enablement-Europe.md'

python "$ScriptDir\fetch-jobs.py"
if ($LASTEXITCODE -ne 0) { Write-Output '[ERR] fetch-jobs.py failed - tracker not updated'; exit $LASTEXITCODE }

python "$ScriptDir\update-jobs.py"
exit $LASTEXITCODE
