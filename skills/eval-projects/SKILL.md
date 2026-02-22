---
name: eval-projects
description: >
  Review evaluation tracking from all ralph loops and their logs, then suggest critical
  and nice-to-have improvements. Uses loops/ catalog, GENERATED.md, PROGRESS.md,
  report history, and logs. Use when the user says "eval projects", "evaluate loops",
  "review ralph loops", "suggest loop improvements", or "analyze project loops".
metadata:
  author: "@mattwoodco"
  version: 1.0.0
  created: 2026-02-22
  updated: 2026-02-22
---

# Eval Projects — Review Ralph Loops and Suggest Improvements

Review the evaluation tracking from all ralph loops and their logs, then produce a report of **critical** and **nice-to-have** improvements for loop structure, skill combinations, tooling, and operations.

## Data sources

1. **GENERATED.md** — List of projects and their loop dirs. Use it to know which `loops/<project>/` entries exist and each project’s Skills used.
2. **loops/** — One subdir per project. In each `loops/<project-name>/` read:
   - **Loop structure:** `PLAN.md`, `PROMPT.md`, `AGENT.md` (phases, steps, instructions).
   - **Progress and skill combinations:** `PROGRESS.md` (parse structured entries: `<!-- STEP step_id="..." label="..." skills="..." outcome="..." at="..." -->`), `progress.json`, `status.json`.
   - **Run output:** `report_*.json`, `report_history_*.jsonl` (iteration, cost, plan_done/plan_pending, exit_code, event), `logs/*.log` when present, `screenshots/` when present.

If a project has no `loops/<project>/` yet or files are missing, note it as a gap (no evaluation data).

## What to analyze

- **Loop structure:** Phase/step layout, step granularity, ordering vs scaffold DAG, redundant or missing steps.
- **Skill combinations:** Which skills run together per step, order across steps, failure hotspots by skill or combination.
- **Outcomes:** PASS/FAIL/PARTIAL from PROGRESS.md; success/failure/circuit_breaker/budget_exceeded from report history; no-progress runs.
- **Cost and iteration count:** From report_history_*.jsonl (cost_usd, iteration, plan_done, plan_total).
- **Logs:** Errors, timeouts, flaky steps, repeated failures in logs.
- **Consistency:** Missing or malformed PROGRESS entries, missing report history, loops not updated after runs (stale catalog).

## Output format

Produce a single report with two sections.

### Critical improvements

Issues that block success, waste budget, or prevent reliable evaluation. Examples:

- Steps that consistently FAIL or trigger circuit breaker; suggest split step, different skill order, or dependency fix.
- Loop dirs never updated after runs (evaluation data stale or missing).
- PROGRESS.md missing structured entries (step_id, skills, outcome, timestamp) so evaluations cannot parse.
- Same error repeated across iterations (same_error circuit breaker); suggest root-cause fix.
- Cost or iteration blow-up on specific steps or skills; suggest smaller steps or different model.
- Missing or broken logs/report files so runs cannot be evaluated.

List each with: **Project** (or “all” / “multiple”), **Finding**, **Suggestion**.

### Nice-to-have improvements

Improvements that would help quality, observability, or reuse but are not blocking. Examples:

- Align PLAN step order with scaffold DAG for a project that diverges.
- Add checkpoint steps (e.g. “Validate Phase N”) to narrow failure scope.
- Standardize PROGRESS entry format across projects.
- Sync loops/ from CI after each run so catalog is always current.
- Add screenshots or log excerpts for failed steps to loops/ for debugging.
- Skill combinations that often run together: consider documenting as a “pack” in SCAFFOLD.md.
- Report history trends: suggest budget or iteration limits per project type.

List each with: **Project** (or “all”), **Idea**, **Benefit**.

## Process

1. Read GENERATED.md and list every project that has a **Ralph loop** link (e.g. `loops/<project>/`).
2. For each such project, read `loops/<project-name>/` if it exists. Parse PLAN.md, PROGRESS.md, report_*.json, report_history_*.jsonl, and logs when present.
3. If `loops/<project-name>/` is missing or empty, record that and treat as “no evaluation data” for that project.
4. Aggregate findings across projects: common failure patterns, skill-combo hotspots, structural issues, missing or stale data.
5. Write the report: **Critical improvements** first, then **Nice-to-have improvements**, with clear project scope and actionable suggestions.

## Acceptance criteria

- [ ] GENERATED.md and all referenced loops/ dirs were read.
- [ ] PROGRESS.md (and report history where present) were used to infer outcomes and skill combinations.
- [ ] Report has a **Critical improvements** section and a **Nice-to-have improvements** section.
- [ ] Each item has project scope and a concrete suggestion.
- [ ] Gaps (missing loop dir, missing files, no runs) are called out.
