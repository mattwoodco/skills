---
name: compliance
description: Generate Architecture Decision Records (ADRs), operational runbooks, and project documentation. Use this skill when the user says "create adr", "document decision", "setup compliance", "add runbook", "architecture decision", or "operational docs".
author: "@mattwoodco"
version: 1.1.0
created: 2026-01-11
---

# Compliance Documentation Setup

Sets up Architecture Decision Records (ADRs), operational runbooks, and project compliance documentation with structured templates and best practices.

## What Gets Created

### Documentation Structure

1. **`docs/adr/`** - Architecture Decision Records directory
2. **`docs/adr/000-template.md`** - ADR template for new decisions
3. **`docs/adr/README.md`** - ADR index and guidelines
4. **`docs/runbook.md`** - Operational runbook with incident playbooks
5. **`docs/CONTRIBUTING.md`** - Contributing guidelines

### CLI Scripts

6. **`scripts/docs/new-adr.ts`** - Interactive ADR creation script
7. **`scripts/docs/list-adrs.ts`** - List all ADRs with status

## Quick Start

```bash
# Create a new ADR interactively
bun run scripts/docs/new-adr.ts

# List all ADRs
bun run scripts/docs/list-adrs.ts
```

## File Structure

```
docs/
├── adr/
│   ├── README.md                           # Index and guidelines
│   ├── 000-template.md                     # ADR template
│   ├── 001-meilisearch-over-algolia.md     # Example ADR
│   └── 002-better-auth-over-nextauth.md    # Example ADR
├── runbook.md                              # Operational runbook
└── CONTRIBUTING.md                         # Contributing guidelines

scripts/
└── docs/
    ├── new-adr.ts                          # Create new ADR
    └── list-adrs.ts                        # List ADRs
```

## ADR Template

### File: `docs/adr/000-template.md`

```markdown
# ADR [NUMBER]: [TITLE]

## Status

[Proposed | Accepted | Deprecated | Superseded by ADR-XXX]

## Context

[What is the issue that we're seeing that is motivating this decision or change?]

## Decision

[What is the change that we're proposing and/or doing?]

## Rationale

### [Chosen Option] Advantages

1. [Advantage 1]
2. [Advantage 2]
3. [Advantage 3]

### [Alternative Option] Advantages (not chosen)

1. [Advantage 1]
2. [Advantage 2]
3. [Advantage 3]

### Why [Chosen Option] Wins

[Explanation of why the chosen option is better for this use case]

## Consequences

### Positive

- [Positive consequence 1]
- [Positive consequence 2]

### Negative

- [Negative consequence 1]
- [Negative consequence 2]

### Mitigations

- [How to address negative consequence 1]
- [How to address negative consequence 2]

## References

- [Link to relevant documentation]
- [Link to related ADRs]
```

## ADR Index

### File: `docs/adr/README.md`

```markdown
# Architecture Decision Records

This directory contains Architecture Decision Records (ADRs) for this project.

## What is an ADR?

An Architecture Decision Record captures an important architectural decision made along with its context and consequences. ADRs help teams:

- **Document decisions** before they're forgotten
- **Communicate** the reasoning to new team members
- **Revisit** decisions when context changes
- **Learn** from past decisions

## ADR Status

| Status | Meaning |
|--------|---------|
| Proposed | Under discussion, not yet decided |
| Accepted | Decision has been made and is active |
| Deprecated | No longer relevant or recommended |
| Superseded | Replaced by a newer ADR |

## Index

| ADR | Title | Status | Date |
|-----|-------|--------|------|
| [001](001-meilisearch-over-algolia.md) | Meilisearch over Algolia | Accepted | 2026-01-11 |
| [002](002-better-auth-over-nextauth.md) | Better Auth over NextAuth | Accepted | 2026-01-11 |

## Creating a New ADR

1. Copy `000-template.md` to `NNN-short-title.md`
2. Fill in the template sections
3. Submit for team review
4. Update this index when accepted

Or use the CLI:

\`\`\`bash
bun run scripts/docs/new-adr.ts
\`\`\`

## Guidelines

1. **One decision per ADR** - Keep them focused
2. **Use past tense** - "We decided" not "We will decide"
3. **Be honest about trade-offs** - Document both pros and cons
4. **Link related ADRs** - Build a knowledge graph
5. **Update status** - Mark deprecated/superseded as needed
```

## Example ADRs

### File: `docs/adr/001-meilisearch-over-algolia.md`

```markdown
# ADR 001: Meilisearch over Algolia for Search

## Status

Accepted

## Context

We need a search solution for the digital store that supports:
- Full-text search with typo tolerance
- Faceted filtering
- Fast response times (<100ms)
- Self-hosted option for local development
- Reasonable cost at scale

## Decision

We will use Meilisearch instead of Algolia.

## Rationale

### Meilisearch Advantages

1. **Self-hosted option**: Docker container for local dev matches production behavior
2. **Cost**: Open-source, pay only for hosting vs. per-search pricing
3. **Performance**: Sub-50ms searches out of the box
4. **Simplicity**: Single binary, minimal configuration
5. **API compatibility**: REST API similar to Algolia, easy migration path

### Algolia Advantages (not chosen)

1. More mature, larger ecosystem
2. Built-in analytics
3. Global CDN infrastructure
4. Better for very large datasets (100M+ records)

### Why Meilisearch Wins

For our use case (<1M products, cost-sensitive, need local dev parity), Meilisearch provides better value. The self-hosted option eliminates vendor lock-in and allows identical local/production environments.

## Consequences

### Positive

- Lower operational costs
- Better local development experience
- No vendor lock-in

### Negative

- Self-managed infrastructure in production
- Less built-in analytics (using Langfuse instead)
- Smaller community than Algolia

### Mitigations

- Use Meilisearch Cloud for production to reduce ops burden
- Implement custom analytics via Langfuse
- Active community and growing ecosystem
```

### File: `docs/adr/002-better-auth-over-nextauth.md`

```markdown
# ADR 002: Better Auth over NextAuth for Authentication

## Status

Accepted

## Context

We need authentication for the digital store supporting:
- Email/password authentication
- Social providers (Google, GitHub, Discord)
- Session management
- Database-backed sessions
- TypeScript-first experience

## Decision

We will use Better Auth with better-auth-harmony instead of NextAuth (Auth.js).

## Rationale

### Better Auth Advantages

1. **TypeScript-first**: Full type safety without workarounds
2. **Simplicity**: Less configuration, more sensible defaults
3. **Plugin ecosystem**: better-auth-harmony adds multi-session support
4. **Better Auth UI**: Pre-built shadcn/ui components
5. **Database flexibility**: Works seamlessly with Drizzle ORM

### NextAuth Advantages (not chosen)

1. Larger community and more examples
2. More OAuth provider adapters
3. Longer track record

### Why Better Auth Wins

Better Auth's TypeScript experience and plugin system (particularly better-auth-harmony) provide a more cohesive developer experience. The Better Auth UI package eliminates the need to build auth forms from scratch while maintaining full customization.

## Consequences

### Positive

- Faster development with pre-built UI
- Better TypeScript support
- Cleaner session management

### Negative

- Smaller community
- Fewer OAuth provider adapters (can be added)
- Less documentation/examples

### Mitigations

- Core providers (Google, GitHub, Discord) are supported
- Growing community and documentation
- better-auth-harmony fills gaps in core functionality
```

## Contributing Guidelines

### File: `docs/CONTRIBUTING.md`

```markdown
# Contributing Guidelines

Thank you for your interest in contributing to this project!

## Getting Started

1. Fork the repository
2. Clone your fork locally
3. Install dependencies: `bun install`
4. Create a feature branch: `git checkout -b feature/your-feature`

## Development Workflow

1. **Write code** following the project's coding standards
2. **Write tests** for new functionality
3. **Run checks** before committing:
   ```bash
   bun run lint
   bun run build
   ```
4. **Commit** with a clear message following [Conventional Commits](https://www.conventionalcommits.org/)
5. **Push** and open a Pull Request

## Commit Message Format

```
type(scope): description

[optional body]
[optional footer]
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`

## Architecture Decisions

When proposing significant changes:

1. Create an ADR using `bun run scripts/docs/new-adr.ts`
2. Include the ADR in your Pull Request
3. Get team review before implementation

See [docs/adr/README.md](adr/README.md) for guidelines.

## Code Review

- All changes require at least one review
- Address all comments before merging
- Squash commits on merge

## Reporting Issues

- Use GitHub Issues for bugs and feature requests
- Include reproduction steps for bugs
- Label issues appropriately
```

## Operational Runbook

### File: `docs/runbook.md`

```markdown
# Operational Runbook

## Emergency Contacts

- **On-call**: Check PagerDuty rotation
- **Escalation**: engineering-leads@company.com
- **Vercel Support**: https://vercel.com/support (Pro/Enterprise)

## Health Check Endpoints

| Service | Endpoint | Expected |
|---------|----------|----------|
| Application | `/api/health` | `{ status: "healthy" }` |
| Database | `/api/health` | `database: "healthy"` |
| Search | `/api/health` | `meilisearch: "healthy"` |
| Cache | `/api/health` | `redis: "healthy"` |

## Critical Incidents

### 1. Search Service Down

**Symptoms:**
- `/api/search` returns 503
- `/api/health` shows `meilisearch: "unhealthy"`

**Diagnosis:**

\`\`\`bash
# Check Meilisearch status
curl https://your-meilisearch-host/health

# Check recent logs
vercel logs --filter api/search

# Check Redis cache
redis-cli ping
\`\`\`

**Recovery:**

1. If Meilisearch Cloud: Check status.meilisearch.com
2. If self-hosted: Restart container
3. Clear Redis cache: `redis-cli FLUSHDB`
4. Re-index if data corruption: `bun run search:reindex`

---

### 2. AI Rate Limiting All Users

**Symptoms:**
- All AI requests return 429
- Langfuse shows spike in errors

**Diagnosis:**

\`\`\`bash
# Check Upstash Redis
curl https://your-upstash-url/get/@marketplace/ratelimit:*

# Check rate limit configuration
grep -r "RATE_LIMITS" src/lib/rate-limit.ts
\`\`\`

**Recovery:**

1. Verify no DDoS attack in progress
2. Temporarily increase limits in Edge Config
3. Clear rate limit keys: `bun run ratelimit:reset`
4. Monitor Langfuse for anomalies

---

### 3. Database Connection Errors

**Symptoms:**
- `/api/health` shows `database: "unhealthy"`
- Drizzle queries timeout

**Diagnosis:**

\`\`\`bash
# Check Neon status
curl https://console.neon.tech/api/v2/projects/{project_id}

# Check connection pool
psql $DATABASE_URL -c "SELECT count(*) FROM pg_stat_activity;"
\`\`\`

**Recovery:**

1. Check Neon dashboard for maintenance
2. Restart compute endpoint if stuck
3. Scale up compute if connection limit hit
4. Check for connection leaks in application

---

### 4. Stripe Webhook Failures

**Symptoms:**
- Subscriptions not updating
- Stripe dashboard shows failed webhooks

**Diagnosis:**

\`\`\`bash
# Check webhook logs
vercel logs --filter api/stripe/webhook

# Verify webhook secret
echo $STRIPE_WEBHOOK_SECRET | head -c 10
\`\`\`

**Recovery:**

1. Verify webhook URL in Stripe dashboard
2. Check webhook secret matches environment
3. Replay failed webhooks from Stripe dashboard
4. Check for signature verification errors

---

### 5. Authentication Failures

**Symptoms:**
- Users cannot log in
- Sessions not persisting

**Diagnosis:**

\`\`\`bash
# Check auth logs
vercel logs --filter api/auth

# Verify environment variables
echo $BETTER_AUTH_SECRET | head -c 10

# Check database for session table
psql $DATABASE_URL -c "SELECT count(*) FROM session;"
\`\`\`

**Recovery:**

1. Verify `BETTER_AUTH_SECRET` is set
2. Check database connectivity
3. Clear invalid sessions if corrupted
4. Restart application

---

## Monitoring Dashboards

| Service | Dashboard URL |
|---------|---------------|
| Vercel Analytics | `https://vercel.com/your-team/digital-store/analytics` |
| Langfuse | `https://cloud.langfuse.com/project/your-project` |
| Upstash | `https://console.upstash.com` |
| Neon | `https://console.neon.tech` |
| Meilisearch | `https://cloud.meilisearch.com` |
| Stripe | `https://dashboard.stripe.com` |

## Recovery Procedures

### Full Search Reindex

\`\`\`bash
bun run search:reindex
# Takes ~10 minutes for 100k products
# Search degraded during reindex
\`\`\`

### Database Migration Rollback

\`\`\`bash
bun run db:rollback
# Requires manual data reconciliation
\`\`\`

### Cache Invalidation

\`\`\`bash
bun run cache:clear
# Clears Redis and triggers ISR revalidation
\`\`\`

### Force Redeploy

\`\`\`bash
vercel --prod --force
# Rebuilds from scratch, clears all caches
\`\`\`

## Scheduled Maintenance

| Task | Schedule | Duration | Impact |
|------|----------|----------|--------|
| Database backup | Daily 3am UTC | 5 min | None |
| Search reindex | Weekly Sun 4am UTC | 30 min | Degraded search |
| SSL renewal | Auto (Let's Encrypt) | None | None |
| Dependency updates | Monthly | 1 hour | Deployment |

## Escalation Path

1. **L1**: On-call engineer (PagerDuty)
2. **L2**: Engineering lead
3. **L3**: Platform team
4. **L4**: CTO/VP Engineering

## Post-Incident

After any incident:

1. Update `#incidents` Slack channel
2. Create post-mortem within 48 hours
3. Update this runbook if needed
4. Schedule follow-up actions
```

## CLI Scripts

### File: `scripts/docs/new-adr.ts`

```typescript
import { readdir, readFile, writeFile, mkdir } from "node:fs/promises";
import { join } from "node:path";
import * as readline from "node:readline/promises";

const ADR_DIR = "docs/adr";

async function getNextAdrNumber(): Promise<string> {
  try {
    const files = await readdir(ADR_DIR);
    const adrNumbers = files
      .filter((f) => f.match(/^\d{3}-.*\.md$/))
      .map((f) => parseInt(f.slice(0, 3)))
      .filter((n) => !isNaN(n));

    const nextNumber = adrNumbers.length > 0 ? Math.max(...adrNumbers) + 1 : 1;
    return String(nextNumber).padStart(3, "0");
  } catch {
    await mkdir(ADR_DIR, { recursive: true });
    return "001";
  }
}

async function readTemplate(): Promise<string> {
  const templatePath = join(ADR_DIR, "000-template.md");
  try {
    return await readFile(templatePath, "utf-8");
  } catch {
    // Fallback template
    return `# ADR [NUMBER]: [TITLE]

## Status
Proposed

## Context
[What is the issue that we're seeing that is motivating this decision or change?]

## Decision
[What is the change that we're proposing and/or doing?]

## Rationale

### [Chosen Option] Advantages
1. [Advantage 1]
2. [Advantage 2]

### [Alternative Option] Advantages (not chosen)
1. [Advantage 1]
2. [Advantage 2]

### Why [Chosen Option] Wins
[Explanation]

## Consequences

### Positive
- [Positive consequence]

### Negative
- [Negative consequence]

### Mitigations
- [How to address negatives]
`;
  }
}

async function main() {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  console.log("\n📝 Create New Architecture Decision Record\n");

  const title = await rl.question("Title (e.g., 'PostgreSQL over MySQL'): ");
  if (!title.trim()) {
    console.error("❌ Title is required");
    process.exit(1);
  }

  const context = await rl.question("Brief context (what problem are we solving?): ");
  const decision = await rl.question("What did we decide?: ");
  const chosenOption = await rl.question("Chosen option name: ");
  const alternativeOption = await rl.question("Alternative option name: ");

  rl.close();

  const adrNumber = await getNextAdrNumber();
  const slug = title
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");

  const filename = `${adrNumber}-${slug}.md`;
  const filepath = join(ADR_DIR, filename);

  let template = await readTemplate();

  template = template
    .replace("[NUMBER]", adrNumber)
    .replace("[TITLE]", title)
    .replace("Proposed", "Proposed")
    .replace(
      "[What is the issue that we're seeing that is motivating this decision or change?]",
      context || "[TODO: Add context]"
    )
    .replace(
      "[What is the change that we're proposing and/or doing?]",
      decision || "[TODO: Add decision]"
    )
    .replace(/\[Chosen Option\]/g, chosenOption || "[Chosen Option]")
    .replace(/\[Alternative Option\]/g, alternativeOption || "[Alternative Option]");

  await writeFile(filepath, template, "utf-8");

  console.log(`\n✅ Created: ${filepath}`);
  console.log(`\nNext steps:`);
  console.log(`  1. Edit ${filepath} to add details`);
  console.log(`  2. Submit for team review`);
  console.log(`  3. Update docs/adr/README.md index when accepted`);
}

main().catch(console.error);
```

### File: `scripts/docs/list-adrs.ts`

```typescript
import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";

const ADR_DIR = "docs/adr";

type AdrInfo = {
  number: string;
  title: string;
  status: string;
  filename: string;
};

async function extractAdrInfo(filepath: string): Promise<AdrInfo | null> {
  try {
    const content = await readFile(filepath, "utf-8");
    const filename = filepath.split("/").pop() ?? "";

    // Extract number from filename
    const numberMatch = filename.match(/^(\d{3})-/);
    if (!numberMatch) return null;

    // Extract title from first heading
    const titleMatch = content.match(/^# ADR \d+: (.+)$/m);
    const title = titleMatch?.[1] ?? "Unknown";

    // Extract status
    const statusMatch = content.match(/^## Status\s*\n+([^\n#]+)/m);
    const status = statusMatch?.[1]?.trim() ?? "Unknown";

    return {
      number: numberMatch[1],
      title,
      status,
      filename,
    };
  } catch {
    return null;
  }
}

async function main() {
  try {
    const files = await readdir(ADR_DIR);
    const adrFiles = files
      .filter((f) => f.match(/^\d{3}-.*\.md$/) && f !== "000-template.md")
      .sort();

    if (adrFiles.length === 0) {
      console.log("\n📋 No ADRs found.\n");
      console.log("Create one with: bun run scripts/docs/new-adr.ts\n");
      return;
    }

    console.log("\n📋 Architecture Decision Records\n");
    console.log("| # | Title | Status |");
    console.log("|---|-------|--------|");

    for (const file of adrFiles) {
      const info = await extractAdrInfo(join(ADR_DIR, file));
      if (info) {
        const statusEmoji =
          info.status === "Accepted"
            ? "✅"
            : info.status === "Proposed"
              ? "🟡"
              : info.status === "Deprecated"
                ? "❌"
                : "➡️";
        console.log(
          `| ${info.number} | ${info.title} | ${statusEmoji} ${info.status} |`
        );
      }
    }

    console.log(`\nTotal: ${adrFiles.length} ADR(s)\n`);
  } catch (error) {
    console.error("❌ Error reading ADRs:", error);
  }
}

main();
```

## Usage Examples

### Create an ADR for Technology Choices

```bash
# Run interactive script
bun run scripts/docs/new-adr.ts

# Or manually create from template
cp docs/adr/000-template.md docs/adr/003-prisma-over-drizzle.md
```

### Common ADR Topics

- **Database**: PostgreSQL vs MySQL vs MongoDB
- **ORM**: Drizzle vs Prisma vs TypeORM
- **Authentication**: Better Auth vs NextAuth vs Clerk
- **Search**: Meilisearch vs Algolia vs Elasticsearch
- **Hosting**: Vercel vs AWS vs Cloudflare
- **State Management**: Zustand vs Redux vs Jotai
- **Styling**: Tailwind vs CSS Modules vs styled-components

### Document Operational Procedures

1. **Identify critical paths** - What can break?
2. **Create playbooks** - Step-by-step recovery
3. **Test procedures** - Run fire drills
4. **Keep updated** - Review quarterly

## Acceptance Criteria Checklist

### For ADRs

- [ ] Decision context clearly stated
- [ ] Alternatives evaluated with pros/cons
- [ ] Decision and rationale documented
- [ ] Consequences understood (positive and negative)
- [ ] Mitigations for negatives identified
- [ ] Status set (Proposed/Accepted/Deprecated)
- [ ] Added to README.md index

### For Runbooks

- [ ] All critical incidents have playbooks
- [ ] Contact information current
- [ ] Escalation paths defined
- [ ] Recovery procedures tested
- [ ] Dashboards linked
- [ ] Scheduled maintenance documented

## Best Practices

1. **Write ADRs early** - Document decisions when context is fresh
2. **Keep them concise** - 1-2 pages maximum
3. **Be honest about trade-offs** - Future you will thank you
4. **Update status** - Don't leave stale "Proposed" ADRs
5. **Link related decisions** - Build institutional knowledge
6. **Test runbook procedures** - Before you need them in production
7. **Review quarterly** - Keep documentation current

## Resources

- [ADR GitHub Organization](https://adr.github.io/)
- [Michael Nygard's Original ADR Article](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions)
- [ADR Tools](https://github.com/npryce/adr-tools)
- [Google SRE Runbook Best Practices](https://sre.google/workbook/table-of-contents/)
