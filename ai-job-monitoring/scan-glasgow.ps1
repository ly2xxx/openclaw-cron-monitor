# Wrapper for the Greater Glasgow "AI Engineer" scan.
# Calls the generic linkedin-scan.ps1 with the right URL.

$ErrorActionPreference = 'Stop'
$ScriptDir = $PSScriptRoot

# Glasgow uses the default linkedin-page prefix so it overwrites the existing files
$env:PAGE_PREFIX = 'linkedin-page'
$env:OUT_DIR = $ScriptDir
$env:BASE_URL = 'https://www.linkedin.com/jobs/search/?currentJobId=4415524750&f_TPR=r2592000&keywords=AI%20Engineer&location=Greater%20Glasgow%20Area'

& "$ScriptDir\linkedin-scan.ps1"
exit $LASTEXITCODE
