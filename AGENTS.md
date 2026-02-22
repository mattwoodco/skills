# Agent policy

- **Major features:** Research open-source packages and well-known solutions first. Then consider whether a custom implementation is better. Use this for major feature work.
- **Minor features:** Review for conflicts and duplication. State dependencies clearly.
- **Composition:** Major features are composed of minor features.

## Major feature workflow

1. Search for open-source packages and well-known solutions that address the requirement.
2. Compare trade-offs (maintenance, fit, licensing).
3. Decide: adopt (and document how) or implement custom (and document why).

## Minor feature checks

1. Ensure no duplicate logic or conflicting patterns elsewhere in the codebase.
2. List dependencies (other modules, skills, env) in the change or skill frontmatter.

## Skill frontmatter conventions

Skills follow the [Agent Skills](https://agentskills.io/specification) format.
Use `name`, `description`, and optional `metadata` fields so tooling can parse consistently.

Recommended `metadata` keys:

- `version`
- `dependencies`
- `created`
- `updated`
- `category` (for catalog grouping and drift checks)

`metadata.category` values should use one of:

- `setup`
- `ai`
- `rag`
- `video`
- `debrief`
- `infra`
- `content`
- `graphics`
- `utils`
- `features`
- `dev`

## Specs

Private specifications, design documents, and mockups live in `specs/`.
Contents under `specs/.private/` are gitignored.

## Loop registration

This section is the canonical source of truth for loop directory structure, required artifacts, and sync rules.

Each `loops/<project-name>/` holds **ralph loop** artifacts for projects built with **add-project** and skills. Each subdirectory is a project's loop catalog entry and is used for reuse (e.g. baseline selection) and for **evaluations on loop structure and skill combinations**.

### What lives in a loop dir

Each `loops/<project-name>/` should contain **all relative output** needed to evaluate how the loop behaves over time:

- **Loop structure:** `PLAN.md`, `PROMPT.md`, `AGENT.md` — phases, steps, and instructions.
- **Progress and skill combinations:** `PROGRESS.md` (structured entries: step id, label, skills applied, outcome, timestamp), `progress.json`, `status.json` — so evaluations can track which skills ran in which order and with what outcome.
- **Run output:** `logs/`, `report_*.json`, `report_history_*.jsonl`, `screenshots/` — when present, copied from the project's `.ralph/` after or during a run.

add-project registers the loop here at creation time (Phase 3g). **Update this directory** whenever the ralph loop runs (e.g. CI or local run): sync the same files from the project's `.ralph/` into `loops/<project-name>/` so the catalog stays current for evaluations.

### Evaluating loops

Use the **eval-projects** skill to review all loop evaluation tracking and logs and get **critical** and **nice-to-have** improvement suggestions. See [skills/eval-projects/SKILL.md](skills/eval-projects/SKILL.md).

### Creating a new loop dir

Create a subdir when you add a new project to [GENERATED.md](GENERATED.md). Use this file as the canonical loop registration and sync guide.
