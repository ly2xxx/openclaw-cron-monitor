"""Single source of truth for rows the AI-jobs monitor should not track.

Imported by BOTH update-ai-jobs.py (so excluded rows are never re-added by the
daily scan) and prune-excluded.py (so rows already in the file get removed).
Keeping one predicate means the live filter and the one-off prune cannot drift.

Why exclude at all: the scan is a decision aid, and a list where two thirds of
the rows are noise is one nobody reads. Excluding is cheaper than re-triaging
the same reposts every morning.
"""
from __future__ import annotations

import re

# Job-board aggregators and lead-gen accounts. These recycle a small set of
# generic titles daily under a rotating jobId, so every scan books them as NEW
# or REFRESHED and they crowd out real employers.
EXCLUDED_COMPANIES: set[str] = {
    "Quik Hire Staffing",
    "Hire Feed",
    "Jobs Ai",
    "Jobright.ai",
    "Hired",
    "micro1",
    "DataAnnotation",
    "Tree Top Staffing LLC",
}

# (company pattern, role pattern) -- both must match for the row to be excluded.
# Scoped deliberately: this drops JPMorgan's Java-titled roles only, and leaves
# their Python / platform / AI / FDE roles in place.
EXCLUDED_COMPANY_ROLE: list[tuple[re.Pattern, re.Pattern]] = [
    (re.compile(r"JPMorgan", re.I), re.compile(r"\bJava\b", re.I)),
]


def _clean(value: str | None) -> str:
    return (value or "").replace("**", "").strip()


def is_excluded(role: str | None, company: str | None) -> bool:
    """True if this row should be kept out of the live table."""
    role_c, company_c = _clean(role), _clean(company)
    if company_c in EXCLUDED_COMPANIES:
        return True
    return any(cp.search(company_c) and rp.search(role_c)
               for cp, rp in EXCLUDED_COMPANY_ROLE)


def reason(role: str | None, company: str | None) -> str:
    """Human-readable justification, for logging."""
    role_c, company_c = _clean(role), _clean(company)
    if company_c in EXCLUDED_COMPANIES:
        return f"aggregator: {company_c}"
    for cp, rp in EXCLUDED_COMPANY_ROLE:
        if cp.search(company_c) and rp.search(role_c):
            return f"company/role rule: {company_c} + {rp.pattern}"
    return ""
