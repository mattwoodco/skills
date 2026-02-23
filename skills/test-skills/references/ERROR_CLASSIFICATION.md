# Error Classification Reference

This reference explains how to classify validation errors and determine the appropriate markdown fixes during skill polish iterations.

## Overview

When validation errors occur, each error should be classified into one of the predefined categories. This classification directs you to the specific section of the skill markdown that needs to be updated.

## Error Classifications

### `missing-dependency`

**What it means:** A package is imported in the code but not listed in the Installation section.

**Markdown fix location:** Installation section

**Example fix:** Add `bun add zod` to the installation commands

**Example error:**

```
Module not found: 'zod'
```

---

### `missing-file`

**What it means:** A file is imported or referenced but not created by the skill's instructions.

**Markdown fix location:** "What Gets Created" section + Setup Steps

**Example fix:** Add the missing file's creation step and list it in "What Gets Created"

**Example error:**

```
Cannot find module '@src/lib/missing-helper'
```

---

### `type-error`

**What it means:** TypeScript type mismatch in the provided code snippets.

**Markdown fix location:** Code snippet in Setup Steps

**Example fix:** Correct the TypeScript types in the code block

**Example error:**

```
Property 'foo' does not exist on type 'Bar'
```

---

### `api-change`

**What it means:** The library API has changed since the skill was written; the code uses outdated syntax.

**Markdown fix location:** Code snippet in Setup Steps

**Example fix:** Update the code to match the current API

**Example error:**

```
'createClient' is deprecated, use 'initClient' instead
```

---

### `missing-config`

**What it means:** A configuration file or environment variable is required but not documented.

**Markdown fix location:** Environment Variables section or Prerequisites

**Example fix:** Add the missing config file or env var documentation

**Example error:**

```
Missing environment variable: DATABASE_URL
```

---

### `wrong-path`

**What it means:** A file path in the markdown doesn't match the actual project structure.

**Markdown fix location:** "What Gets Created" section or code snippets

**Example fix:** Correct the import path to match the project structure

**Example error:**

```
Cannot find module '@/components/ui/button' (should be '@/components/button')
```

---

### `missing-step`

**What it means:** A setup step was assumed but not explicitly documented.

**Markdown fix location:** Setup Steps section

**Example fix:** Add the missing step in the correct order

**Example error:**

```
'next.config.js' not configured for experimental features
```

---

### `code-error`

**What it means:** A bug exists in the code snippet provided by the skill.

**Markdown fix location:** Code snippet in Setup Steps

**Example fix:** Fix the bug in the code block

**Example error:**

```
Unexpected token '}' (syntax error in code)
```

---

## Composition-Specific Error Types

These error types are unique to multi-skill testing where skills are layered on top of each other.

### `composition-conflict`

**What it means:** Two skills create or modify the same file incompatibly. The later skill overwrites or conflicts with changes made by an earlier skill.

**Markdown fix location:** Later skill's Setup Steps — add merge instructions instead of overwrite

**Example error:**

```
# skill "cms" overwrites src/app/layout.tsx, removing providers added by "auth"
```

**Example fix:** Change the later skill to append/merge rather than replace the file. Use comment slots.

---

### `missing-import-from-dep`

**What it means:** A skill imports from a file created by one of its dependencies, but the import path is wrong.

**Markdown fix location:** Code snippet import paths in the dependent skill

**Example error:**

```
Cannot find module '@src/lib/auth' — file was created at '@src/lib/auth/index.ts'
```

---

### `type-mismatch-across-skills`

**What it means:** A type exported by one skill doesn't match what another skill expects when importing it.

**Markdown fix location:** Either skill's type definitions, depending on which is wrong

**Example error:**

```
Type 'Session' from '@src/lib/auth' is missing property 'user.role'
# auth skill exports Session without role, but ai-chat skill expects it
```

---

### `env-var-collision`

**What it means:** Two skills define the same environment variable name for different purposes.

**Markdown fix location:** Environment Variables section of the later skill — rename the variable

**Example error:**

```
# Both "storage" and "media-bunny" define STORAGE_URL with different semantics
```

---

### `route-conflict`

**What it means:** Two skills register the same API route path.

**Markdown fix location:** Later skill's route path — use a different path

**Example error:**

```
# Both "auth" and "payments" define POST /api/webhooks
```

---

## Classification Quick Reference Table

| Classification | Markdown Fix Location | Example |
|---|---|---|
| `missing-dependency` | Installation section | Add `bun add zod` |
| `missing-file` | What Gets Created + Setup Steps | Add the missing file's creation step |
| `type-error` | Code snippet in Setup Steps | Fix the TypeScript in the code block |
| `api-change` | Code snippet in Setup Steps | Update to current API |
| `missing-config` | Environment Variables or Prerequisites | Add the missing config |
| `wrong-path` | What Gets Created or code snippets | Fix the import path |
| `missing-step` | Setup Steps | Add the missing step in order |
| `code-error` | Code snippet in Setup Steps | Fix the bug |
| `composition-conflict` | Later skill's Setup Steps | Add merge instructions |
| `missing-import-from-dep` | Dependent skill's import paths | Fix the import path |
| `type-mismatch-across-skills` | Either skill's type definitions | Align the types |
| `env-var-collision` | Later skill's Environment Variables | Rename the variable |
| `route-conflict` | Later skill's route path | Use a different path |

---

## Reflection Process

For each error:

1. **Classify the error type** using the categories above
2. **Determine the fix:** What specific change to the markdown would prevent this error?
3. **Apply the fix** to the working markdown (`skills/<FEATURE_NAME>/SKILL.md`)

Document your reflection in the markdown:

```markdown
<!-- POLISH ITERATION {N}
Errors found: {count}
Fixes applied:
- {error classification}: {brief description of fix}
- ...
-->
```
