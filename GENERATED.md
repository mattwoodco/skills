# Generated projects log
<!-- markdownlint-disable MD060 -->

Log of projects built with **add-project** and skills. Each project is scaffolded via the pipeline (`add-project` → `ralph-ci` → GitHub Actions); ralph runs the iterative loop from `.ralph/PLAN.md`.

Loop artifacts for each project live under **[loops/](loops/)** (one subdir per project).

New projects must be added here and in `loops/<project>/` per [loops/README.md](loops/README.md).

---

## Entries

## 1. -design-mood-board - Designer inspiration OS

| Field | Value |
|-------|--------|
| **Plan** | [docs/plans/2026-02-22--design-mood-board-design.md](docs/plans/2026-02-22--design-mood-board-design.md) |
| **Ralph loop** | [loops/-design-mood-board/](loops/-design-mood-board/) |
| **Generation git** | `/Users/mw/Developer/mattwoodco/-design-mood-board@bbc018b` |

**Description:**  Mood Board is a production-oriented MVP for design teams to capture visual references from browser/mobile, auto-process them with AI metadata, curate them in clusters, and retrieve them via hybrid semantic and structured search while preserving strict visibility controls.

**Major features:**

- Browser and mobile capture into a shared inbox with `processing`, `ready`, and `needs_attention`
- AI processing pipeline for tags, colors, embeddings, and duplicate checks
- Cluster curation workflows for create/edit/move/remove operations
- Hybrid retrieval blending semantic similarity and structured filters
- Sharing controls enforcing private/team/public boundaries

**Use-cases:** Validate a modular-monolith architecture for creative-reference workflows where ingestion latency, AI enrichment reliability, and privacy-safe collaboration must coexist in an MVP-ready stack.

**Skills used:** `create-next`, `docker`, `env-config`, `add-shadcn`, `db`, `e2e`, `auth`, `auth-dev`, `storage`, `storage-ui`, `queue`, `ai-core`, `ai-rag-vectors`, `search`, `observability`, `analytics`

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
