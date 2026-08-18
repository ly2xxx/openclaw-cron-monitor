# Simple flight check script for cron jobs
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$trackerPath = if ($env:FLIGHT_TRACKER) { $env:FLIGHT_TRACKER } else { Join-Path $ScriptDir 'flight-tracker.json' }
$tracker = Get-Content $trackerPath -Raw | ConvertFrom-Json
$lastCheck = $tracker.last_check
$bestPrice = if ($tracker.best_price_found) { $tracker.best_price_found.total_price_2pax } else { "Not found" }
Write-Output "Last check: $lastCheck. Best price: $bestPrice. Browser automation not available in isolated session - need main session for flight checks."