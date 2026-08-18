# Flight Price Monitoring

**Route:** Glasgow (GLA) → Shanghai (PVG/SHA)  
**Passengers:** 1 (companions book separately on their own searches)  
**Period:** Mid-June to Mid-July  
**Duration:** ~3 weeks stay

## Setup

### Files
- `flight-tracker.json` — Tracking database (gitignored)
- `check-flight-prices.ps1` — Daily check script
- `check-flight-prices-with-retry.ps1` — Same, with retry wrapper
- `simple-check.ps1` — Lightweight summary for cron jobs
- `update-tracker.ps1` — Manual helper to append a history entry
- `README.md` — This file

### Price Alerts
- **Excellent:** ≤ £600 (1 passenger)
- **Good:** ≤ £700
- **Acceptable:** ≤ £800

### Monitoring Schedule
Daily checks via cron job.

### Current Baseline
Established mid-March 2026.
- Market rate: £625–£673 one-way (~£1,250–£1,350 return)
- Sources: Skyscanner, Google Flights, Expedia

## Price History

Updated daily with:
- Date of check
- Best price found
- Source/airline
- Route details (direct/connections)

## Alerts

When a **good or excellent** price is found:
1. WhatsApp notification to the configured phone number
2. Logged in `flight-tracker.json`
3. Details saved for booking reference

## Recommended Booking Sites

1. **Skyscanner** — Best for comparison
2. **Google Flights** — Price tracking & calendar view
3. **Kayak** — Multi-city options
4. **Direct airlines:**
   - Air China
   - China Eastern
   - British Airways (via London)
   - KLM (via Amsterdam)
   - Lufthansa (via Frankfurt)

## Tips for Best Prices

- **Book 3-4 months in advance** (optimal: Late Feb – Early March)
- **Flexible dates** can save £200–300
- **Mid-week flights** (Tue–Thu) often cheaper
- **Avoid peak summer** (late June – early Aug)
- **Consider one-stop** vs direct (can be £300–400 cheaper)

## Notes

- Prices for the target window should be available by late Feb / early March
- Peak booking season: March–April
- Chinese holidays to avoid: Dragon Boat Festival (early June)
- School holidays: Consider return before mid-July rush

## Environment Variables

| Variable | Purpose | Required for |
|----------|---------|--------------|
| `FLIGHT_TRACKER` | Path to `flight-tracker.json` | All scripts |
| `FLIGHT_ALERT_PHONE` | E.164 phone number for WhatsApp alerts | Price alerts |

Example:
```powershell
$env:FLIGHT_TRACKER = "C:\path\to\flight-tracker.json"
$env:FLIGHT_ALERT_PHONE = "+44xxxxxxxxxx"
.\check-flight-prices.ps1
```

---

**Monitoring started:** 2026-03-16  
**Next check:** Daily via cron