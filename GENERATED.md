# Generated projects log
<!-- markdownlint-disable MD060 -->

Log of projects built with **add-project** and skills. Each project is scaffolded via the pipeline (`add-project` → `ralph-ci` → GitHub Actions); ralph runs the iterative loop from `.ralph/PLAN.md`.

Loop artifacts for each project live under **[loops/](loops/)** (one subdir per project).

New projects must be added here and in `loops/<project>/` per [loops/README.md](loops/README.md).

---

## Entries

Add new project entries below.

---

## Format for each entry

Use this structure so entries are consistent and tooling can compare projects over time. Skill ordering and tier alignment follow [skills/add-project/references/SCAFFOLD.md](skills/add-project/references/SCAFFOLD.md) and [scaffold-dag.json](skills/add-project/references/scaffold-dag.json).

| Field | Required | Description |
|-------|----------|-------------|
| **Plan** | Yes | Link to the plan doc, e.g. `[docs/plans/YYYY-MM-DD-name.md](docs/plans/...)`. |
| **Ralph loop** | Yes | Link to this project’s loop dir: `[loops/<project>/](loops/<project>/)`. |
| **Generation git** | Yes | Where to find this project's git history (repo URL, branch, or commit). Example: `https://github.com/org/repo` or `https://github.com/org/repo tree main` or `repo@abc123`. |
| **Description** | Yes | One short paragraph: what the app is and who it’s for. |
| **Major features** | Yes | Bullet list of main capabilities. |
| **Use-cases** | Yes | Why this project exists; what it validates or demonstrates (e.g. “Four docker services in CI”, “RAG composition chain”). |
| **Skills used** | Yes | Comma-separated list of skill names (e.g. `create-next`, `add-shadcn`, `docker`, `db`, `auth`, …). |

**Optional — scaffold checkpoints:** If you have multiple useful git refs (e.g. “after Phase 1”, “after Phase 2”), add a short list in the entry body: `Scaffold checkpoints: main@abc123 (Phase 1 done), main@def456 (Phase 2 done).`

### Example entry

```markdown
## N. ProjectName — Short tagline

| Field | Value |
|-------|--------|
| **Plan** | [docs/plans/YYYY-MM-DD-example-name.md](docs/plans/...) |
| **Ralph loop** | [loops/projectname/](loops/projectname/) |
| **Generation git** | `https://github.com/org/projectname` (branch: main) |

**Description:** One paragraph describing the project.

**Major features:**

- Feature one
- Feature two

**Use-cases:** What this project validates or demonstrates.

**Skills used:** `create-next`, `add-shadcn`, `docker`, `env-config`, `db`, `auth`, …
```

### When adding an entry

1. Add a numbered section under **Entries** with all required fields.
2. Create the loop dir: `loops/<project>/` (and add any loop artifacts there as needed).
3. Ensure **Skills used** is complete and **Generation git** points to a cloneable ref (branch or tag preferred).
