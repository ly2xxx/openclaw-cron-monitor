# Job recommendations — workflow

Ad-hoc evaluations of `../AI-jobs.md`. **This branch is never merged to `main`.**

> **If you are an AI assistant picking this up in a fresh session: read this whole file first.**
> It is the only record of the workflow and the constraints. Do not re-derive them.

## The one rule that matters

**Never modify `../AI-jobs.md` on this branch.**

`main` takes a daily cron commit that rewrites that file wholesale (~186 rows of status churn
per day). Any commit here that touches it makes every future rebase conflict — this was tested,
and it produced 3 conflict hunks in a 585 KB file on the first simulated day. A tooling-only
branch rebases cleanly instead.

So: exclusions are applied **in memory** at generation time, never written back.
`prune-excluded.py` exists for the day the policy is applied to `main` — do not run it here.

## Procedure for each evaluation

```bash
# 1. Sync with main (clean, because nothing here touches AI-jobs.md)
git fetch origin main
git checkout feature/exclude-aggregators-and-jpmc-java
git rebase origin/main

# 2. Generate. Read ../AI-jobs.md (main's latest), parse the live table only --
#    everything between "### All AI Roles by Company" and the first "## Daily Scan".
#    Filter each row through exclusions.is_excluded(role, company). Rank the survivors
#    against the target profile below.

# 3. Write recommendations/YYYY-MM-DD-recommended-jobs.md  (today's date; never overwrite
#    an existing one -- these are a series, kept for comparison over time)

# 4. Commit and push to THIS branch only
git add recommendations/
git commit
git push origin feature/exclude-aggregators-and-jpmc-java
```

Never merge to `main`, never open a PR, never push to `main`.

## Target profile

**AI Platform / AI Enablement engineering and leadership, UK financial services and regulated
industry** — Glasgow area and UK-remote.

Rank on: platform depth (EKS, Helm, Terraform, Prometheus/Grafana/OTEL), LLMOps (model gateway,
vector store, LLM telemetry, agent guardrails), regulated-domain instinct, and technical leadership.

Do **not** rank on: years of ML research, or Java. The Java pivot is explicitly abandoned — a
decade of Java experience exists but is three years stale, and chasing it means live coding screens
for a career direction that was deliberately left behind.

Evidence to anchor recommendations against: the `langgraph_ollama` agent platform (LiteLLM gateway,
Milvus, Langfuse telemetry, namespace isolation, NetworkPolicy, phased rollout with approval gates)
and its execution-based eval harness (Pass@1 / recovery rate).

Four lanes, in this order: **Tier 1** AI platform · **Tier 2** enablement leadership ·
**Tier 3** Forward Deployed Engineer · **Income lane** contract/FTC, run in parallel because
contract placements clear in 1–3 weeks against 6–12 for permanent.

## Constraints — check these every time

| Constraint | Status | Review |
|---|---|---|
| **Barclays — all roles** | **Blocked.** Redundancy restriction; cannot apply. | ~2027-03 |
| **JPMorgan — all roles** | **Deferred by choice.** Strongest personal network; being saved until ready. | on request |
| Java-titled roles | Out of scope | — |
| Aggregator listings | Excluded (see below) | — |

Both blocked employers stay listed in `AI-jobs.md` deliberately, so they resurface when a
constraint lifts. Record why they are absent in every generated file, so a later evaluation
knows what to re-enable rather than silently recommending them again.

## Exclusions policy

Defined in `../exclusions.py`, the single source of truth — used by this workflow and by
`../update-ai-jobs.py` if the policy is ever applied to `main`.

**Aggregators** (recycle a few generic titles daily under rotating jobIds, so every scan books
them as NEW or REFRESHED): Quik Hire Staffing, Hire Feed, Jobs Ai, Jobright.ai, Hired, micro1,
DataAnnotation, Tree Top Staffing LLC. As of 2026-09-15 these were 131 of 374 live rows.

**Company + role rules**: JPMorgan roles with `Java` in the title. `\bJava\b` does not match
`JavaScript`. To change the policy, edit `../exclusions.py`.

## Quality bar for a generated file

- **Verify every cited row** back against `AI-jobs.md`: jobId present, posted date matching,
  stated age consistent with the generation date. Report the check (e.g. "31/31 verified").
- **Flag staleness.** Mark roles 30+ days old and say plainly that a long-refreshed listing
  usually means filled, frozen, or CV-farming — treat those as contact leads, not applications.
- **No blocked employer** may appear in any recommendation table. Check before committing.
- Include direct links, posted date, age, and work mode (Remote / Hybrid / on-site) per row.
- End with a short "today's three" — the smallest actionable next step.

## Files here

| File | |
|---|---|
| `README.md` | this file — the workflow |
| `YYYY-MM-DD-recommended-jobs.md` | one per evaluation, never overwritten |
