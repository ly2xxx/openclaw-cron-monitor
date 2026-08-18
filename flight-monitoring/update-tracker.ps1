$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$trackerPath = if ($env:FLIGHT_TRACKER) { $env:FLIGHT_TRACKER } else { Join-Path $ScriptDir 'flight-tracker.json' }
$tracker = Get-Content $trackerPath -Raw | ConvertFrom-Json
$checkDate = "2026-05-02T11:48:00Z"

$flights = @(
    @{
        departure_date = "2026-07-01"
        return_date = "2026-07-11"
        price_per_passenger = 878
        total_price_1pax = 878
        currency = "GBP"
        source = "Google Flights"
        airlines = "British Airways, China Southern"
        stops = "2"
        duration = "23h 35min"
    },
    @{
        departure_date = "2026-07-01"
        return_date = "2026-07-11"
        price_per_passenger = 1253
        total_price_1pax = 1253
        currency = "GBP"
        source = "Google Flights"
        airlines = "Emirates"
        stops = "1"
        duration = "17h 50min"
    },
    @{
        departure_date = "2026-07-10"
        return_date = "2026-07-19"
        price_per_passenger = 1006
        total_price_1pax = 1006
        currency = "GBP"
        source = "Google Flights"
        airlines = "British Airways, China Southern"
        stops = "2"
        duration = "21h 5min"
    },
    @{
        departure_date = "2026-07-10"
        return_date = "2026-07-19"
        price_per_passenger = 1154
        total_price_1pax = 1154
        currency = "GBP"
        source = "Google Flights"
        airlines = "British Airways, China Eastern"
        stops = "1"
        duration = "15h 15min"
    }
)

$historyEntry = @{
    check_date = $checkDate
    source = "Google Flights (Browser Automation)"
    search_method = "OpenClaw browser"
    flights_found = $flights
    notes = "Checked July 1-11 and July 10-19 date windows. Best: £878 (Jul 1-11, BA+China Southern 2 stops). No prices near £600 excellent threshold."
}

$tracker.price_history += $historyEntry
$tracker.last_check = $checkDate

$jsonString = $tracker | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText($trackerPath, $jsonString, [System.Text.UTF8Encoding]::new($false))

Write-Host "Updated tracker with flight prices"
Write-Host "Best price found: £878"
