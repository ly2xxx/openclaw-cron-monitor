#!/usr/bin/env python3
"""One-off prune of rows matching exclusions.py from the AI-jobs.md live table.

update-ai-jobs.py filters on every scan, so this is only needed once to clean
rows already committed. It is idempotent -- running it again is a no-op.

Only the live "### All AI Roles by Company" table is touched. The historical
"## Daily Scan:" sections are left intact: they are the audit trail that repost
detection and time-in-market analysis depend on, and rewriting history would
corrupt both.

    python prune-excluded.py --dry-run   # report only
    python prune-excluded.py             # apply
"""
from __future__ import annotations

import argparse
import sys
from collections import Counter
from pathlib import Path

from exclusions import is_excluded, reason

JOBS_MD = Path(__file__).resolve().parent / "AI-jobs.md"
TABLE_HEADER = "All AI Roles by Company"
SCAN_HEADER = "## Daily Scan"


def find_live_table(lines: list[str]) -> tuple[int, int]:
    try:
        start = next(i for i, l in enumerate(lines) if TABLE_HEADER in l)
    except StopIteration:
        sys.exit(f"error: '{TABLE_HEADER}' header not found in {JOBS_MD.name}")
    end = next((i for i, l in enumerate(lines)
                if i > start and l.startswith(SCAN_HEADER)), len(lines))
    return start, end


def cells(line: str) -> list[str]:
    return [c.strip().replace("**", "") for c in line.split("|")[1:-1]]


def is_data_row(line: str) -> bool:
    return (line.startswith("| ") and not line.startswith("|---")
            and "| Role " not in line and len(cells(line)) >= 3)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true", help="report without writing")
    args = ap.parse_args()

    text = JOBS_MD.read_text(encoding="utf-8")
    lines = text.split("\n")
    start, end = find_live_table(lines)

    kept, dropped, reasons = [], 0, Counter()
    for i, line in enumerate(lines):
        if start <= i < end and is_data_row(line):
            c = cells(line)
            if is_excluded(c[0], c[1]):
                dropped += 1
                reasons[reason(c[0], c[1])] += 1
                continue
        kept.append(line)

    total = sum(1 for i in range(start, end) if is_data_row(lines[i]))
    print(f"live table rows : {total}")
    print(f"to drop         : {dropped}")
    print(f"remaining       : {total - dropped}")
    if reasons:
        print("\nby reason:")
        for why, n in reasons.most_common():
            print(f"  {n:4d}  {why}")

    if args.dry_run:
        print("\n(dry run -- nothing written)")
        return 0
    if not dropped:
        print("\nnothing to do")
        return 0

    JOBS_MD.write_text("\n".join(kept), encoding="utf-8")
    print(f"\nwrote {JOBS_MD.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
