# Wrapper for the Europe-wide "AI Enablement" scan.
# Calls the generic linkedin-scan.ps1 with the right URL + page prefix + output dir.
#
# This file is intentionally thin: the actual scanner is shared (linkedin-scan.ps1)
# so any fixes/updates apply to both Glasgow and Europe scans.

$ErrorActionPreference = 'Stop'
$ScriptDir = $PSScriptRoot

# Page prefix keeps page JSONs separate from the Glasgow scan
$env:PAGE_PREFIX = 'europe-page'
$env:OUT_DIR = $ScriptDir
$env:BASE_URL = 'https://www.linkedin.com/jobs/search/?currentJobId=4463427924&f_TPR=r2592000&geoId=100506914&keywords=%22AI%20Enablement%22&location=Europe'

# Run the generic scanner
& "$ScriptDir\linkedin-scan.ps1"
exit $LASTEXITCODE
