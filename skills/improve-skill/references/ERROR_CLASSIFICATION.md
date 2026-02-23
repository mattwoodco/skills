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
