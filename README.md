# openclaw-cron-monitor

LinkedIn AI jobs monitoring workflow.

## Current state (2026-09-23)

The automated daily scan has been **retired** as of 2026-09-23. LinkedIn's search
results page redesign (~late Sep 2026) broke the DOM-based extractor
(`div[data-job-id]` selector, obfuscated CSS) and made the SPA virtualized.
Restoring the scan requires either:
- Intercepting LinkedIn's internal `voyager/api/voyagerJobsDashJobCards` calls via CDP Network domain (1-2 hr spike), OR
- Migrating to `jobspy` (Python, no auth, designed for this)

Neither has been implemented yet.

## What remains

- **`ai-job-monitoring/AI-Enablement-Europe.md`** — manually curated tracker for
  "AI Enablement" roles across Europe. Last automated update 2026-09-22 with
  21 roles. Master Yang updates this by hand when new roles appear in his
  LinkedIn browser session.

## History

- 2026-09-23 — Scan pipeline retired. DOM selectors broken by LinkedIn redesign.
- 2026-09-22 — Last successful automated scan: Glasgow 4 NEW / 17 REFRESH, Europe 11 NEW / 10 REFRESH.
- 2026-08-15 — Repo created; scripts consolidated; `linkedin-scan.ps1` + `update-jobs.py` introduced.
- 2026-09-19 — Europe tracker `AI-Enablement-Europe.md` added.
- 2026-09-20 — Cron renamed to `daily-ai-jobs-scan-glasgow-and-europe` (combined Glasgow + Europe).
- 2026-09-22 — Legacy `update-ai-jobs.py` deleted (superseded by `update-jobs.py`).

## If you want to restart automation

1. Spike CDP Network intercept against `voyager/api/voyagerJobsDashJobCards` (fragile).
2. Or install `jobspy`: `pip install jobspy` then run against your target region.
3. Or use a paid LinkedIn Jobs API aggregator (Apify, Bright Data).
