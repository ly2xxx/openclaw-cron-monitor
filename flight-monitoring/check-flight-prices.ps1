# Flight Price Monitoring Script - Browser Automation
# Checks Glasgow to Shanghai flight prices via Google Flights
#
# Configure via environment variables:
#   FLIGHT_TRACKER  - path to flight-tracker.json (default: <script-dir>/flight-tracker.json)
#   FLIGHT_ALERT_PHONE - E.164 phone number to WhatsApp on price alert (required for alerts)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$trackerPath = if ($env:FLIGHT_TRACKER) { $env:FLIGHT_TRACKER } else { Join-Path $ScriptDir 'flight-tracker.json' }
$alertPhone = $env:FLIGHT_ALERT_PHONE  # set this before running, e.g. $env:FLIGHT_ALERT_PHONE = '+44xxxxxxxxxx'
if (-not $alertPhone) { Write-Warning "FLIGHT_ALERT_PHONE env var not set; WhatsApp alerts will be skipped." }
$tracker = Get-Content $trackerPath -Raw | ConvertFrom-Json

# Current date for logging
$checkDate = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

Write-Host "Flight price check starting - $checkDate"

# Search parameters from tracker
$departStart = $tracker.search_parameters.departure_period.start
$departEnd = $tracker.search_parameters.departure_period.end
$returnStart = $tracker.search_parameters.return_period.start
$returnEnd = $tracker.search_parameters.return_period.end

# Search more date combinations to cover June 30 - July 19 range for 10-day trips
# Cover early/mid/late departure x early/mid/late return
$searchCombinations = @(
    @{ depart = "2026-06-30"; return = "2026-07-09" },
    @{ depart = "2026-06-30"; return = "2026-07-10" },
    @{ depart = "2026-07-01"; return = "2026-07-10" },
    @{ depart = "2026-07-01"; return = "2026-07-11" },
    @{ depart = "2026-07-05"; return = "2026-07-14" },
    @{ depart = "2026-07-05"; return = "2026-07-15" },
    @{ depart = "2026-07-10"; return = "2026-07-19" },
    @{ depart = "2026-07-10"; return = "2026-07-20" }
)

$allFlights = @()
$errors = @()

# Start browser once at the beginning
Write-Host "Starting browser..."
$browserStatus = openclaw browser --browser-profile openclaw status 2>&1 | Out-String
if ($browserStatus -notmatch "running") {
    openclaw browser --browser-profile openclaw start | Out-Null
    Start-Sleep -Seconds 3
}

foreach ($combo in $searchCombinations) {
    $departDate = $combo.depart
    $returnDate = $combo.return
    
    # Google Flights URL format
    # https://www.google.com/travel/flights/search?tfs=CBwQAhooEgoyMDI2LTA2LTE1agcIARIDR0xBcgcIARIDUFZHGigSCjIwMjYtMDctMDVqBwgBEgNQVkdyBwgBEgNHTEFwAoIBCwj___________8BQAFIAZgBAQ
    
    # Simpler approach - use the basic query format
    $departFormatted = (Get-Date $departDate).ToString("yyyy-MM-dd")
    $returnFormatted = (Get-Date $returnDate).ToString("yyyy-MM-dd")
    
    # Build Google Flights URL - 1 passenger (companions book separately on their own search)
    $url = "https://www.google.com/travel/flights?q=Flights%20from%20Glasgow%20to%20Shanghai%20departing%20$departFormatted%20returning%20$returnFormatted%201%20passenger"
    
    Write-Host "Searching: Depart $departDate, Return $returnDate"
    
    try {
        # Navigate to Google Flights
        Write-Host "Opening URL: $url"
        openclaw browser --browser-profile openclaw navigate "$url" | Out-Null
        
        # Wait for Google Flights to load and search (JavaScript-heavy, needs time)
        Write-Host "Waiting 45 seconds for Google Flights to load results..."
        Start-Sleep -Seconds 45
        
        # Take screenshot for debugging
        Write-Host "Taking screenshot..."
        openclaw browser --browser-profile openclaw screenshot | Out-Null
        
        # Take snapshot to extract flight data
        Write-Host "Capturing flight results..."
        $snapshotJson = openclaw browser --browser-profile openclaw --json snapshot --format ai | Out-String
        
        # Try to parse JSON, handling potential formatting issues
        try {
            $snapshot = $snapshotJson | ConvertFrom-Json
        } catch {
            # If direct parsing fails, try to extract JSON from the output
            $jsonMatch = [regex]::Match($snapshotJson, '\{.*\}', [System.Text.RegularExpressions.RegexOptions]::Singleline)
            if ($jsonMatch.Success) {
                $snapshot = $jsonMatch.Value | ConvertFrom-Json
            } else {
                throw "Could not parse snapshot JSON"
            }
        }
        
        # Parse snapshot for flight prices
        $snapshotText = $snapshot.snapshot
        
        Write-Host "Snapshot length: $($snapshotText.Length) characters"
        
        # Check if we hit a CAPTCHA or error page
        if ($snapshotText -match "Are you a (robot|bot)" -or $snapshotText -match "unusual traffic" -or $snapshotText -match "CAPTCHA") {
            throw "CAPTCHA or bot detection triggered"
        }
        
        # Extract prices from Google Flights format
        # In the accessibility snapshot, prices appear as "From 1216 British pounds" or "1344 British pounds"
        # Match numbers followed by "British pounds"
        $priceMatches = [regex]::Matches($snapshotText, '(\d{3,5})\s+British pounds')
        
        if ($priceMatches.Count -gt 0) {
            # Get unique prices and sort
            $prices = $priceMatches | ForEach-Object { 
                [int]$_.Groups[1].Value
            } | Where-Object { $_ -gt 0 } | Sort-Object | Select-Object -Unique
            
            Write-Host "Found prices: $($prices -join ', ')"
            
            # Take the lowest reasonable price (skip anything under 200 as likely one-way or error)
            $validPrices = $prices | Where-Object { $_ -ge 200 -and $_ -le 3000 }
            
            if ($validPrices.Count -gt 0) {
                $lowestPrice = $validPrices[0]
                
                # Google Flights shows total for all passengers selected (1 in our case)
                $totalPrice = $lowestPrice
                $pricePerPerson = $lowestPrice  # Already per person since 1 passenger
                
                $allFlights += @{
                    departure_date = $departDate
                    return_date = $returnDate
                    price_per_passenger = $pricePerPerson
                    total_price_1pax = $totalPrice
                    currency = "GBP"
                    source = "Google Flights"
                    search_url = $url
                    check_time = $checkDate
                }
                
                Write-Host "Lowest price: GBP $totalPrice total for 1 passenger"
            } else {
                Write-Host "No valid prices found (filtered out prices outside 200-3000 range)"
            }
        } else {
            Write-Host "No prices found in snapshot"
            # Save snapshot to file for debugging
            $debugPath = Join-Path $ScriptDir ("debug-snapshot-$departFormatted-$returnFormatted.txt")
            $snapshotText | Out-File -FilePath $debugPath -Encoding UTF8
            Write-Host "Debug snapshot saved to: $debugPath"
        }
        
        # Rate limiting - wait 3 seconds between searches
        Start-Sleep -Seconds 3
        
    } catch {
        $errorMsg = $_.Exception.Message
        Write-Host "Error searching $departDate to $returnDate - $errorMsg"
        $errors += @{
            combo = "$departDate to $returnDate"
            error = $errorMsg
        }
    }
}

# Create history entry
$historyEntry = @{
    check_date = $checkDate
    source = "Google Flights (Browser Automation)"
    search_method = "OpenClaw browser automation"
    flights_found = $allFlights
}

if ($errors.Count -gt 0) {
    $historyEntry.errors = $errors
}

# Add notes
if ($allFlights.Count -eq 0) {
    $historyEntry.notes = "No flight prices successfully extracted. Check debug snapshots in flight-monitoring folder. May need to adjust price regex or Google Flights changed their format."
} else {
    $bestFlight = $allFlights | Sort-Object total_price_1pax | Select-Object -First 1
    $historyEntry.notes = "Found $($allFlights.Count) price point(s). Best: GBP $($bestFlight.total_price_1pax) (depart $($bestFlight.departure_date), return $($bestFlight.return_date))."
}

# Update tracker
$tracker.last_check = $checkDate
$tracker.price_history += $historyEntry

# Check if we found a new best price and send alerts
if ($allFlights.Count -gt 0) {
    $bestFlight = $allFlights | Sort-Object { [int]$_.total_price_1pax } | Select-Object -First 1
    $bestPrice = [int]$bestFlight.total_price_1pax
    
    Write-Host "Alert check: Best price = GBP $bestPrice"
    Write-Host "Excellent threshold = GBP $($tracker.price_alerts.excellent_price)"
    Write-Host "Good threshold = GBP $($tracker.price_alerts.good_price)"
    
    # Check alert thresholds
    if ($bestPrice -le $tracker.price_alerts.excellent_price) {
        $alertLevel = "EXCELLENT"
        $threshold = $tracker.price_alerts.excellent_price
        Write-Host "EXCELLENT price alert triggered!"
    } elseif ($bestPrice -le $tracker.price_alerts.good_price) {
        $alertLevel = "GOOD"
        $threshold = $tracker.price_alerts.good_price
        Write-Host "GOOD price alert triggered!"
    } else {
        $alertLevel = $null
        Write-Host "No alert triggered (price above thresholds)"
    }
    
    if ($alertLevel) {
        $alertMsg = "$alertLevel PRICE ALERT!`n`nGlasgow to Shanghai flights: GBP $bestPrice (1 passenger)`nBelow GBP $threshold threshold`n`nDepart: $($bestFlight.departure_date)`nReturn: $($bestFlight.return_date)`n`nSource: Google Flights`n`nReview and book:`n$($bestFlight.search_url)`n`nIMPORTANT: Check booking type (codeshare/interline vs separate bookings) before purchasing!"
        
        Write-Host "Sending WhatsApp alert..."
        Write-Host "Message: $($alertMsg.Substring(0, [Math]::Min(100, $alertMsg.Length)))..."
        
        try {
            # Send WhatsApp alert using openclaw message
            if (-not $alertPhone) { Write-Host "Skipping WhatsApp send: FLIGHT_ALERT_PHONE not set"; continue }
            $result = openclaw message send --channel whatsapp --target "$alertPhone" --message "$alertMsg" 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "WhatsApp alert sent successfully!"
            } else {
                Write-Host "ERROR sending WhatsApp alert. Exit code: $LASTEXITCODE. Output: $result"
            }
        } catch {
            Write-Host "ERROR sending WhatsApp alert: $($_.Exception.Message)"
        }
        
        $tracker.alerts_sent += @{
            date = $checkDate
            type = $alertLevel.ToLower() + "_price"
            price = $bestPrice
            threshold = $threshold
            message = $alertMsg
        }
        
        Write-Host "ALERT SENT: $alertLevel price!"
    }
    
    # Update best price if this is better than previous
    $previousBest = if ($tracker.best_price_found) { [int]$tracker.best_price_found.total_price_1pax } else { 999999 }
    if ($bestPrice -lt $previousBest) {
        $tracker.best_price_found = @{
            date = $checkDate
            total_price_1pax = [int]$bestFlight.total_price_1pax
            price_per_passenger = [int]$bestFlight.price_per_passenger
            departure = $bestFlight.departure_date
            return = $bestFlight.return_date
            source = "Google Flights"
            search_url = $bestFlight.search_url
            note = "Automated browser search - verify booking type (codeshare vs separate) before purchasing"
        }
        Write-Host "New best price recorded: GBP $bestPrice (was GBP $previousBest)"
    } else {
        Write-Host "Current best price (GBP $bestPrice) not better than previous (GBP $previousBest)"
    }
}

# Save updated tracker (UTF-8 without BOM)
$jsonString = $tracker | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText($trackerPath, $jsonString, [System.Text.UTF8Encoding]::new($false))

Write-Host "Flight price check completed: $checkDate"
Write-Host "Total flights found: $($allFlights.Count)"

# Return summary for cron job
if ($allFlights.Count -gt 0) {
    $bestFlight = $allFlights | Sort-Object { [int]$_.total_price_1pax } | Select-Object -First 1
    $summaryMsg = "SUCCESS: Found $($allFlights.Count) flight option(s). Best: GBP $($bestFlight.total_price_1pax) (1 passenger)`n`nReview and book:`n$($bestFlight.search_url)"
    
    # Add all other flight options with links
    if ($allFlights.Count -gt 1) {
        $summaryMsg += "`n`nOther options:"
        $otherFlights = $allFlights | Sort-Object { [int]$_.total_price_1pax } | Select-Object -Skip 1
        foreach ($flight in $otherFlights) {
            $summaryMsg += "`n- GBP $($flight.total_price_1pax) (depart $($flight.departure_date), return $($flight.return_date))`n  $($flight.search_url)"
        }
    }
    
    Write-Output $summaryMsg
} else {
    Write-Output "WARNING: No flight prices extracted this run - check debug snapshots or may need adjustment for Google Flights format"
}
