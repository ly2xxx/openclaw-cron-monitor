# openclaw-cron-monitor

LinkedIn AI jobs monitoring workflow.

## Current state (2026-09-23)

The daily "AI Enablement" Europe scan is **restored** on a new data source.

On 2026-09-23 LinkedIn moved logged-in job search to the "AI-powered"
`/jobs/search-results/` page. That broke the CDP/DOM scanner (`div[data-job-id]`
gone, new markup) and also changed the results themselves: AI search matches
loosely even on "quoted" keywords, so it would pull in off-scope roles.

The scan now uses LinkedIn's public guest endpoint
(`/jobs-guest/jobs/api/seeMoreJobPostings/search`), which returns server-rendered
job cards with classic keyword matching and an exact posted date. No login,
Chrome or CDP is needed, and the scripts use only the Python standard library.

## Pipeline (`ai-job-monitoring/`)

| File | Role |
|------|------|
| `scan-europe.ps1` | Entry point for the cron: runs the two steps below |
| `fetch-jobs.py` | Pages through the guest endpoint for `BASE_URL`, writes `europe-page1..N.json` |
| `update-jobs.py` | Merges the page JSONs into the tracker (NEW / REFRESHED / REPOST), re-sorts, appends a `## Daily Scan` section, commits + pushes (`JOBS_COMMIT=0` to skip) |
| `AI-Enablement-Europe.md` | The tracker |

Run manually: `pwsh ai-job-monitoring/scan-europe.ps1`, or set `BASE_URL`,
`PAGE_PREFIX` and `JOBS_MD` yourself and call the two Python scripts in turn.
`BASE_URL` can be pasted straight from the browser (old or new search URL).

The guest endpoint rate-limits bursts (HTTP 429); the fetcher waits 2-4s between
pages and backs off on 429s. One scan a day is well within limits.

## History

- 2026-08-15 — Repo created; scripts consolidated.
- 2026-09-19 — Europe tracker `AI-Enablement-Europe.md` added; `linkedin-scan.ps1` + `update-jobs.py` generalised for multiple regions.
- 2026-09-20 — Cron renamed to `daily-ai-jobs-scan-glasgow-and-europe` (combined Glasgow + Europe).
- 2026-09-22 — Legacy `update-ai-jobs.py` deleted (superseded by `update-jobs.py`). Last CDP-based scan.
- 2026-09-23 — CDP scanner broken by LinkedIn's AI-powered search page; Glasgow tracker `AI-jobs.md` dropped and cron disabled.
- 2026-09-23 — Europe scan restored via the guest endpoint (`fetch-jobs.py`); `update-jobs.py` restored.
