# Reuse Scoring Algorithm (Dormant)

Activate this only when `GENERATED.md` has one or more entries and add-project is switched back to reuse support.

## Inputs

- Required foundation skills for a new project
- Parsed candidates from `GENERATED.md`:
  - `generation_git`
  - normalized `skills_used`

## Scoring

1. `required_foundation` = all skills in the project's shared substrate set.
2. `foundation_set` = `{ create-next, env-config, docker, add-shadcn, db, storage, ai-core, auth, payments }`.
3. For each candidate:
   - `baseline_skills` = candidate `skills_used` (normalized)
   - `covered` = `required_foundation ∩ baseline_skills`
   - `foundation_covered` = `covered ∩ foundation_set`
   - `score` = `10 * |foundation_covered| + |covered|`
   - Candidate is valid only if `create-next` is present in `baseline_skills`
4. Minimum threshold: `score >= 10`.
5. Choose highest score; tie-break by first appearance in `GENERATED.md`.

## Outcome mapping

- No valid candidate above threshold:
  - scaffold strategy = `fresh`
  - selected baseline git = none
  - skills already covered = none
- Valid candidate selected:
  - scaffold strategy = `reuse`
  - selected baseline git = candidate `generation_git`
  - skills already covered = `covered`
  - delta skills = all required skills minus covered, in dependency order

## Integration points

- Phase 2 shell generation (baseline hydrate vs fresh)
- Phase 3 PLAN generation (baseline validation step + delta-only steps)
