#!/usr/bin/env python3
"""AI-jobs.md updater — fixed to write clean table rows + dedupe by jobId.

Key fixes vs the legacy version:
1. Status column does NOT embed raw flags text (eliminates embedded `|` chars
   that broke the parser).
2. Dedup the main table by jobId on every run (per MEMORY 2026-07-27 lesson).
3. Paths are resolved relative to this script's directory (location-independent).

Usage:
    python update-ai-jobs.py

Environment overrides (optional):
    AI_JOBS_MD  - path to AI-jobs.md (default: <repo>/../interview-prep/notes/.../AI-jobs.md)
    AI_JOB_MONITOR_DIR - path to scan output dir (default: directory of this script)
"""

import json
import os
import re
import sys
from datetime import date, timedelta
from pathlib import Path

# ---- Paths (resolved relative to this script for portability) ----
SCRIPT_DIR = Path(__file__).resolve().parent
HERE_DIR = Path(os.environ.get("AI_JOB_MONITOR_DIR", str(SCRIPT_DIR)))
# AI-jobs.md lives next to this script by default. Override with AI_JOBS_MD if needed.
JOBS_MD = Path(os.environ.get("AI_JOBS_MD", str(SCRIPT_DIR / "AI-jobs.md")))
if not JOBS_MD.exists():
    print(f"[ERR] AI-jobs.md not found at: {JOBS_MD}", file=sys.stderr)
    print(f"[ERR] Set AI_JOBS_MD env var to its actual location, or place it next to this script.", file=sys.stderr)
    sys.exit(1)
PAGES = [HERE_DIR / f"linkedin-page{i}.json" for i in (1, 2, 3)]

LINK_RE = re.compile(r"https://www\.linkedin\.com/jobs/view/(\d+)/?")
AGO_RE = re.compile(r"(\d+)\s*(hours?|days?|weeks?|months?|years?)", re.IGNORECASE)

TODAY = date.today()
TODAY_ISO = TODAY.isoformat()

# ---- 1. Load today's scan ----
today_jobs = []
for p in PAGES:
    if not p.exists():
        print(f"[WARN] {p.name} missing - skipping page")
        continue
    with open(p, "r", encoding="utf-8") as f:
        data = json.load(f)
    for j in data.get("jobs", []):
        m = LINK_RE.search(j.get("link") or "")
        jid = m.group(1) if m else (j.get("jobId") or "")
        today_jobs.append({
            "jobId": jid,
            "title": (j.get("title") or "").strip().replace(" with verification", "").strip(),
            "company": (j.get("company") or "").strip(),
            "location": (j.get("location") or "").strip(),
            "link": j.get("link") or "",
            "posted_hint": j.get("posted") or "",
            "flags": j.get("flags") or "",
        })

# Dedup today's jobs by jobId
seen = set()
unique_today = []
for j in today_jobs:
    key = j["jobId"] or (j["title"] + "|" + j["company"])
    if key in seen:
        continue
    seen.add(key)
    unique_today.append(j)
print(f"[INFO] {len(today_jobs)} raw -> {len(unique_today)} unique today")

# ---- 2. Read AI-jobs.md ----
if not JOBS_MD.exists():
    print(f"[ERR] {JOBS_MD} not found")
    sys.exit(1)
with open(JOBS_MD, "r", encoding="utf-8") as f:
    md = f.read()
lines = md.split("\n")

# Find main table boundaries (between `### All AI Roles by Company` and the next `## `)
main_header_idx = None
table_start = None  # line with `| Role | ...`
table_end = None    # first `## ` line after the table
for i, line in enumerate(lines):
    if main_header_idx is None and line.startswith("### All AI Roles by Company"):
        main_header_idx = i
        continue
    if main_header_idx is not None and table_start is None and line.startswith("| Role |"):
        table_start = i
        continue
    if table_start is not None and (line.startswith("## ") and not line.startswith("### ")):
        table_end = i
        break

if table_start is None or table_end is None:
    print(f"[ERR] Cannot find main table. start={table_start} end={table_end}")
    sys.exit(1)
print(f"[INFO] Main table: header line {main_header_idx+1}, data rows {table_start+3}..{table_end}")

# ---- 3. Parse existing rows ----
def parse_existing_row(line):
    """Extract jobId from any cell containing a /jobs/view/<id> URL."""
    m = LINK_RE.search(line)
    jid = m.group(1) if m else ""
    # Get Role from first cell after the leading |
    parts = [p.strip() for p in line.split("|")]
    # Skip header/separator lines
    if len(parts) < 8 or not parts[1] or parts[1].startswith("---"):
        return None
    # Best-effort: parts[1]=role, [2]=company, [3]=location, [4]=posted, [5]=salary, [6]=status, [7]=link
    return {
        "raw": line,
        "role": parts[1],
        "company": parts[2],
        "location": parts[3],
        "posted": parts[4] if len(parts) > 4 else "",
        "salary": parts[5] if len(parts) > 5 else "-",
        "status": parts[6] if len(parts) > 6 else "",
        "link": parts[7] if len(parts) > 7 else "",
        "jobId": jid,
    }

existing_rows = []
for i in range(table_start + 2, table_end):
    if not lines[i].startswith("|"):
        continue
    row = parse_existing_row(lines[i])
    if row:
        existing_rows.append(row)

# Dedup existing rows by jobId (keep LAST occurrence per MEMORY 2026-07-27)
by_id = {}
no_id = []
for r in existing_rows:
    if r["jobId"]:
        by_id[r["jobId"]] = r  # last wins
    else:
        no_id.append(r)
deduped_existing = list(by_id.values()) + no_id
print(f"[INFO] {len(existing_rows)} raw existing rows -> {len(deduped_existing)} after dedup ({len(by_id)} with jobId)")

# ---- 4. Compute Posted date from hint ----
def posted_from_hint(hint, today):
    """Compute YYYY-MM-DD from a LinkedIn-style hint."""
    h = (hint or "").strip()
    if not h or h in ("Actively reviewing", "Just now", "Today"):
        return today.isoformat()
    if h == "Yesterday":
        return (today - timedelta(days=1)).isoformat()
    if h == "Reposted":
        return today.isoformat()
    m = AGO_RE.search(h)
    if m:
        n = int(m.group(1))
        unit = m.group(2).lower()
        if "hour" in unit:
            return today.isoformat()
        if "day" in unit:
            return (today - timedelta(days=n)).isoformat()
        if "week" in unit:
            return (today - timedelta(weeks=n)).isoformat()
        if "month" in unit:
            return (today - timedelta(days=30 * n)).isoformat()
        if "year" in unit:
            return (today - timedelta(days=365 * n)).isoformat()
    return today.isoformat()

# ---- 5. Update or insert today's jobs ----
new_rows = []
refreshed = []
reposted = []
for j in unique_today:
    jid = j["jobId"]
    if not jid:
        continue
    computed_posted = posted_from_hint(j["posted_hint"], TODAY)
    if jid in by_id:
        # Refresh in place
        row = by_id[jid]
        old_posted = row["posted"]
        # Try to upgrade row's Posted value to today's computed date
        new_posted = old_posted
        try:
            old_dt = date.fromisoformat(old_posted)
        except ValueError:
            old_dt = None
        try:
            new_dt = date.fromisoformat(computed_posted)
        except ValueError:
            new_dt = None
        # If old_posted looks like a date and new is later (re-ago = older post), keep old
        # If new is earlier (today's scan shows it's fresher than yesterday's record), treat as repost
        repost_note = ""
        if old_dt and new_dt and new_dt < old_dt:
            days_fresher = (old_dt - new_dt).days
            repost_note = f", REPOST -{days_fresher}d fresher"
            new_posted = computed_posted
            reposted.append((row, old_posted, new_posted, days_fresher))
        elif old_dt and new_dt and new_dt > old_dt:
            new_posted = computed_posted  # aging correction
        elif not old_dt:
            new_posted = computed_posted
        row["posted"] = new_posted
        # Status: append today's REFRESHED tag (no embedded pipes!)
        existing_status = (row.get("status") or "").strip().rstrip(",").rstrip()
        if existing_status:
            row["status"] = f"{existing_status}, REFRESHED {TODAY_ISO}{repost_note}"
        else:
            row["status"] = f"REFRESHED {TODAY_ISO}{repost_note}"
        # Fix link if it was empty/missing (regression from earlier bad run)
        if not row.get("link") and j.get("link"):
            row["link"] = j["link"]
        refreshed.append((row, old_posted, new_posted, repost_note))
    else:
        # New row
        new_row = {
            "raw": None,
            "role": f"**{j['title']}**",
            "company": f"**{j['company']}**",
            "location": j["location"],
            "posted": computed_posted,
            "salary": "-",
            "status": f"NEW {TODAY_ISO}",
            "link": j["link"],
            "jobId": j["jobId"],
        }
        new_rows.append(new_row)

print(f"[INFO] Refreshed: {len(refreshed)}, New: {len(new_rows)}, Reposts: {len(reposted)}")
for r, _, _, note in refreshed:
    if note:
        print(f"   REPOST: {r['company']} {r['role']} {note}")
for r in new_rows:
    print(f"   NEW: {r['company']} {r['role']}")

# ---- 6. Sort main table by Posted DESC, Role ASC ----
all_rows = deduped_existing + new_rows

def sort_key(row):
    try:
        d = date.fromisoformat(row["posted"])
    except (ValueError, KeyError, TypeError):
        d = date(2000, 1, 1)
    return (-d.toordinal(), (row.get("role") or "").lower())

all_rows.sort(key=sort_key)

# ---- 7. Rebuild main table lines ----
def render_row(r):
    """Build a clean 7-column table row. NO pipes inside cells."""
    # All cell values must not contain `|` - strip if needed
    def clean(v):
        return (str(v) if v else "").replace("|", "/").strip()
    return (
        f"| {clean(r['role'])} | {clean(r['company'])} | {clean(r['location'])} | "
        f"{clean(r['posted'])} | {clean(r['salary'])} | {clean(r['status'])} | "
        f"{clean(r['link'])} |"
    )

new_table_lines = []
for i, line in enumerate(lines):
    if main_header_idx <= i < table_end:
        if i <= table_start + 1:
            # Header rows (Role | Company | ...) and separator (|---|---|...)
            new_table_lines.append(line)
        # Skip old data rows
    elif i == table_end:
        for r in all_rows:
            new_table_lines.append(render_row(r))
        new_table_lines.append(line)
    else:
        new_table_lines.append(line)

new_md = "\n".join(new_table_lines)

# ---- 8. Update header ----
new_md = re.sub(
    r"> Last updated: \d{4}-\d{2}-\d{2}",
    f"> Last updated: {TODAY_ISO}",
    new_md,
    count=1,
)

new_md = re.sub(
    r"> daily scan: .+",
    (
        f"> daily scan: full 3-page scan via CDP (Chrome debug port 9222, "
        f"LinkedIn logged in, {len(unique_today)} unique jobs); "
        f"**{len(new_rows)} NEW**; **{len(refreshed)} REFRESHED**; "
        f"**{len(reposted)} REPOSTS**"
    ),
    new_md,
    count=1,
)

# ---- 9. Append Daily Scan section ----
scan_section_lines = [
    "",
    f"## Daily Scan: {TODAY_ISO} - {len(new_rows)} NEW, {len(refreshed)} REFRESHED, {len(reposted)} REPOSTS",
    "",
    f"Scanned at {TODAY_ISO} via Chrome CDP (debug port 9222, --remote-allow-origins=*).",
    f"Got {len(unique_today)} unique jobs across 3 pages. Deduped by jobId.",
    "",
]
if new_rows:
    scan_section_lines.append(f"### New Roles ({len(new_rows)})")
    scan_section_lines.append("| JobId | Role | Company | Location | Posted | Link |")
    scan_section_lines.append("|-------|------|---------|----------|--------|------|")
    for r in new_rows:
        scan_section_lines.append(
            f"| {r['jobId']} | {r['role']} | {r['company']} | {r['location']} | {r['posted']} | {r['link']} |"
        )
    scan_section_lines.append("")
if reposted:
    scan_section_lines.append(f"### Reposts ({len(reposted)})")
    scan_section_lines.append("| JobId | Role | Company | Old Posted | New Posted |")
    scan_section_lines.append("|-------|------|---------|------------|------------|")
    for r, o, n, days in reposted:
        scan_section_lines.append(
            f"| {r['jobId']} | {r['role']} | {r['company']} | {o} | {n} (-{days}d fresher) |"
        )
    scan_section_lines.append("")

scan_section = "\n".join(scan_section_lines)

# Append after the last "## Daily Scan" section (or at end of file)
match = None
for m in re.finditer(r"^## Daily Scan: ", new_md, re.MULTILINE):
    match = m
if match:
    insert_at = len(new_md)  # always append at end
    new_md = new_md.rstrip() + "\n\n" + scan_section
else:
    new_md = new_md.rstrip() + "\n\n" + scan_section

# ---- 10. Write back ----
with open(JOBS_MD, "w", encoding="utf-8", newline="") as f:
    f.write(new_md)
print(f"[OK] Wrote {JOBS_MD} ({len(new_md)} chars)")
print(f"[OK] Main table now has {len(all_rows)} rows (was {len(existing_rows)}, net {len(all_rows)-len(existing_rows):+d})")
