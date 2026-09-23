#!/usr/bin/env python3
"""Fetch LinkedIn job search results via the public (logged-out) guest endpoint.

Replaces the CDP/DOM scanner (linkedin-scan.ps1), which broke on 2026-09-23 when
LinkedIn moved logged-in search to the "AI-powered" /jobs/search-results/ page.
The guest endpoint returns plain server-rendered HTML job cards, needs no login
or Chrome, and uses classic keyword matching (so "quoted phrases" stay exact).

Config via environment variables:
  BASE_URL     - LinkedIn search URL copied from the browser (required). Either the
                 old /jobs/search/ or the new /jobs/search-results/ form works; only
                 the search params (keywords, geoId, location, f_*, ...) are used.
  PAGE_PREFIX  - output file prefix (default: "linkedin-page")
  OUT_DIR      - output directory (default: AI_JOB_MONITOR_DIR, else script dir)
  MAX_RESULTS  - stop after this many cards (default: 200)

Output: <PAGE_PREFIX>1.json, 2.json, ... one per request, each {"jobs": [...]}
in the format update-jobs.py reads. Stale page files from earlier runs are removed.
Exits 1 if no jobs were fetched, so callers don't record an empty scan.
"""

import html
import json
import os
import random
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

GUEST_URL = "https://www.linkedin.com/jobs-guest/jobs/api/seeMoreJobPostings/search"
USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
)
# Search params worth forwarding; anything else (currentJobId, origin, refresh...) is UI state
KEEP_PARAMS = {"keywords", "location", "geoId", "distance", "sortBy"}
RETRY_DELAYS = (10, 30, 90)  # seconds, on HTTP 429 / 5xx

SCRIPT_DIR = Path(__file__).resolve().parent
OUT_DIR = Path(os.environ.get("OUT_DIR") or os.environ.get("AI_JOB_MONITOR_DIR") or SCRIPT_DIR)
PAGE_PREFIX = os.environ.get("PAGE_PREFIX", "linkedin-page")
MAX_RESULTS = int(os.environ.get("MAX_RESULTS", "200"))

ID_RE = re.compile(r"urn:li:jobPosting:(\d+)")
HREF_ID_RE = re.compile(r"/jobs/view/[^\"?]*?(\d{8,})")
TIME_RE = re.compile(r"<time\b[^>]*\bdatetime=\"([^\"]+)\"[^>]*>(.*?)</time>", re.S)


def search_params(base_url):
    query = urllib.parse.parse_qs(urllib.parse.urlparse(base_url).query)
    return {k: v[0] for k, v in query.items() if k in KEEP_PARAMS or k.startswith("f_")}


def text_of(fragment):
    return " ".join(html.unescape(re.sub(r"<[^>]+>", " ", fragment)).split())


def field(card, css_class, tag):
    m = re.search(
        rf"<{tag}\b[^>]*class=\"[^\"]*\b{css_class}\b[^\"]*\"[^>]*>(.*?)</{tag}>", card, re.S
    )
    return text_of(m.group(1)) if m else ""


def parse_cards(page_html):
    jobs = []
    for card in re.split(r"<li\b[^>]*>", page_html)[1:]:
        m = ID_RE.search(card) or HREF_ID_RE.search(card)
        if not m:
            continue
        job_id = m.group(1)
        t = TIME_RE.search(card)
        flags = [text_of(f) for f in re.findall(
            r"class=\"[^\"]*\bjob-posting-benefits__text\b[^\"]*\"[^>]*>(.*?)</span>", card, re.S
        )]
        jobs.append({
            "jobId": job_id,
            "title": field(card, "base-search-card__title", "h3"),
            "company": field(card, "base-search-card__subtitle", "h4"),
            "location": field(card, "job-search-card__location", "span"),
            "salary": field(card, "job-search-card__salary-info", "span"),
            # Exact YYYY-MM-DD from the datetime attribute; relative text as fallback
            "posted": t.group(1) if t else "",
            "posted_text": text_of(t.group(2)) if t else "",
            "flags": ", ".join(f for f in flags if f),
            "link": f"https://www.linkedin.com/jobs/view/{job_id}/",
        })
    return jobs


def fetch(params):
    url = f"{GUEST_URL}?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept-Language": "en-GB,en;q=0.9"})
    for attempt, delay in enumerate((0,) + RETRY_DELAYS):
        if delay:
            print(f"[WARN] retrying in {delay}s")
            time.sleep(delay)
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                return resp.read().decode("utf-8", errors="replace")
        except urllib.error.HTTPError as e:
            if e.code == 400:  # LinkedIn answers 400 past the last page
                return ""
            if e.code != 429 and e.code < 500:
                raise
            print(f"[WARN] HTTP {e.code} on start={params.get('start')} (attempt {attempt + 1})")
        except urllib.error.URLError as e:
            print(f"[WARN] {e.reason} on start={params.get('start')} (attempt {attempt + 1})")
    raise RuntimeError(f"giving up on start={params.get('start')} after {len(RETRY_DELAYS)} retries")


def main():
    base_url = os.environ.get("BASE_URL")
    if not base_url:
        print("[ERR] BASE_URL env var is required", file=sys.stderr)
        return 1
    params = search_params(base_url)
    print(f"[INFO] Guest search params: {params}")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for stale in OUT_DIR.glob(f"{PAGE_PREFIX}*.json"):
        if re.fullmatch(rf"{re.escape(PAGE_PREFIX)}\d+\.json", stale.name):
            stale.unlink()

    seen = set()
    start = 0
    page = 0
    while start < MAX_RESULTS:
        try:
            body = fetch({**params, "start": start})
        except Exception as e:  # keep what we already have
            print(f"[WARN] stopping early: {e}")
            break
        cards = parse_cards(body)
        fresh = [j for j in cards if j["jobId"] not in seen]
        if not fresh:
            break
        seen.update(j["jobId"] for j in fresh)
        page += 1
        out = OUT_DIR / f"{PAGE_PREFIX}{page}.json"
        with open(out, "w", encoding="utf-8") as f:
            json.dump({"source": GUEST_URL, "start": start, "jobs": fresh}, f, ensure_ascii=False, indent=1)
        print(f"[INFO] start={start}: {len(cards)} cards, {len(fresh)} new -> {out.name}")
        start += len(cards)
        time.sleep(random.uniform(2.0, 4.0))

    print(f"[OK] {len(seen)} unique jobs across {page} page(s)")
    return 0 if seen else 1


if __name__ == "__main__":
    sys.exit(main())
