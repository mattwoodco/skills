# Edge Cases and Troubleshooting

This reference covers special scenarios and common issues encountered during skill polish iterations.

## Edge Cases

### Skill Has Dependencies on Other Skills

**Scenario:** The skill markdown declares `dependencies: [auth, docker]` in its frontmatter.

**Solution:** You must first implement those dependency skills in the sandbox before implementing the target skill. Follow each dependency skill's markdown in order.

**Example:**

```yaml
dependencies: [auth, docker]
```

→ First implement `auth` skill, then `docker` skill, then the target skill.

---

### Skill Requires External Services (Database, API Keys)

**Scenario:** The skill needs a database, external APIs, or third-party services.

**Solution:**

- Use Docker Compose if the skill includes a Docker setup
- Use placeholder/mock values for API keys (e.g., `sk-test-1234...`)
- Skip Tier 4 (browser validation) if the feature requires live external services
- Note in the reflection if validation was limited due to external dependencies

**Example reflection note:**

```markdown
<!-- POLISH ITERATION 3
Note: Browser validation skipped because the skill requires live Stripe API keys.
TypeScript and build validation passed.
-->
```

---

### Skill Markdown Has No Code (Config-Only)

**Scenario:** Some skills are configuration-only (e.g., `env-config`, `setup-vercel`).

**Solution:**

- Verify the configuration files are syntactically valid (JSON, YAML, TOML parsing)
- Verify referenced tools/CLIs exist (`which vercel`, etc.)
- Skip TypeScript compilation if no `.ts` files are created
- Use Tier 3 (build) validation if a build process exists

**Example validation:**

```bash
# Verify JSON is valid
cat sandbox/.vercel/config.json | jq . > /dev/null

# Verify CLI exists
which vercel
```

---

### Sandbox Project Type Doesn't Match

**Scenario:** The skill targets a different project type than what's currently in the sandbox (e.g., skill needs Next.js but sandbox has Vite).

**Solution:**

- Wipe the sandbox completely: `rm -rf sandbox/* sandbox/.* 2>/dev/null`
- Re-scaffold with the correct project type (repeat Phase 2)
- Re-initialize git inside sandbox

**Example:**

```bash
# Clean sandbox
rm -rf sandbox/* sandbox/.* 2>/dev/null

# Scaffold new project type
cd sandbox
bunx create-next-app@latest . --typescript --tailwind --eslint --app --src-dir --no-import-alias --use-bun
cd ..

# Re-init git
cd sandbox
git init
git add -A
git commit -m "baseline: scaffold for <FEATURE_NAME>"
cd ..
```

---

## Troubleshooting

### "Sandbox Revert Failed"

**Symptom:** `git checkout` or `git clean` fails inside the sandbox.

**Diagnosis:** The sandbox git repo is in a corrupted or unexpected state.

**Solution:** Nuke the sandbox and re-scaffold from scratch:

```bash
rm -rf sandbox/* sandbox/.* 2>/dev/null
# Then re-run Phase 2 (Initialize Sandbox Project)
```

---

### "Sandbox Has No Git Repo"

**Symptom:** Commands fail because `sandbox/.git` directory doesn't exist.

**Diagnosis:** The sandbox was never initialized as a git repo, or the `.git` directory was deleted.

**Solution:** Re-run Phase 2 (Initialize Sandbox Project). The initialization step must include:

```bash
cd sandbox
git init
git add -A
git commit -m "baseline: scaffold for <FEATURE_NAME>"
cd ..
```

---

### "Max Iterations Reached"

**Symptom:** The loop hit `MAX_ITERATIONS` (10) without achieving a clean validation.

**Diagnosis:** The skill may have fundamental issues that require manual intervention or architectural changes.

**Solution:**

1. Review the iteration comments in the markdown (`<!-- POLISH ITERATION -->`)
2. Look for patterns in the recurring errors
3. Check if errors are the same across iterations (stuck in a loop)
4. Report to the user with a summary of remaining errors
5. Consider whether the skill needs a complete rewrite

**Example report:**

```
Reached maximum iterations (10) without achieving a clean build.

Remaining errors:
- type-error: src/lib/auth.tsx:42 — Property 'user' does not exist on type 'Session'
- missing-dependency: react-hook-form not installed

The current state of the markdown has been saved but may still need manual refinement.
```

---

### "Dependency Skill Failed"

**Symptom:** A prerequisite skill fails during sandbox setup.

**Diagnosis:** The dependency skill itself has errors or is outdated.

**Solution:**

1. Polish the dependency skill first using the same improve-skill workflow
2. Once the dependency skill is polished, retry the target skill
3. Update the target skill's markdown to reference the polished dependency version

**Example:**

```yaml
# Before
dependencies: [auth]

# After polishing the auth skill
dependencies: [auth@1.2.0]
```

---

### "Build Passes But Browser Validation Fails"

**Symptom:** TypeScript and build validation pass cleanly, but Tier 4 (browser) validation shows runtime errors.

**Diagnosis:** The skill's code compiles but has runtime issues specific to the browser environment.

**Solution:** Check for these common issues:

- Missing `"use client"` directives (Next.js)
- Server/client component mismatches
- Missing environment variables at runtime (`process.env` checks)
- Hydration mismatches (SSR vs. client rendering differences)

**Example fixes:**

```typescript
// Missing "use client" directive
'use client'  // Add this at the top of the file

export default function MyComponent() { ... }
```

```typescript
// Missing environment variable check
const apiKey = process.env.NEXT_PUBLIC_API_KEY
if (!apiKey) {
  console.error('Missing NEXT_PUBLIC_API_KEY')
  return null
}
```

---

### playwright-cli Debugging Tips

**Scenario:** Browser validation fails and you need to debug the running app.

**Solution:** Use playwright-cli's debugging commands:

```bash
# Check for runtime JS errors in the console
playwright-cli console

# Inspect the current DOM structure
playwright-cli snapshot

# Evaluate JavaScript to check hydration state
playwright-cli eval "document.querySelector('#app')?.getAttribute('data-reactroot')"

# Check if a specific element exists
playwright-cli eval "!!document.querySelector('.my-component')"

# Debug hydration mismatches — compare server vs client
playwright-cli eval "document.getElementById('__NEXT_DATA__')?.textContent"
```

**Common issues caught by playwright-cli:**

- Missing `"use client"` directives → `playwright-cli console` shows hydration errors
- Server/client component mismatches → `playwright-cli snapshot` shows missing elements
- Runtime env var issues → `playwright-cli eval "window.__ENV__"` returns undefined

> **Note:** playwright-cli runs via Bash — no MCP tool permissions needed.

---

### "TypeScript Errors in Generated Code"

**Symptom:** `tsc --noEmit` fails with errors in code that was copied exactly from the skill markdown.

**Diagnosis:** The skill markdown contains TypeScript errors in its code snippets.

**Solution:**

1. Classify as `type-error` or `code-error`
2. Fix the code snippet in the markdown's Setup Steps section
3. Document the fix in the iteration comment
4. Revert sandbox and retry

This is exactly the scenario the polish loop is designed to catch and fix.
