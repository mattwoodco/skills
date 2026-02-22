---
name: create-next
description: Initialize a new Next.js project with optimal defaults. Use when user says "create next app", "new next project", or "init next".
metadata:
  version: "1.3.0"
  created: "2026-02-13"
  updated: "2026-02-18"
  validated: "2026-02-18"
---

# Initialize Next.js Project

Ask the user for the **app name**, then run:

```bash
bunx create-next-app $APP_NAME --react-compiler --empty --app --src-dir --ts --tailwind --biome --turbopack --use-bun --skip-install --disable-git --import-alias "@/*" </dev/null
```

**Note:** The `</dev/null` stdin redirection prevents interactive prompts from blocking the command.

## What This Creates

- ✅ Next.js 16+ app directory structure
- ✅ TypeScript configured
- ✅ Tailwind CSS v4 with PostCSS
- ✅ Biome for linting/formatting
- ✅ React Compiler enabled
- ✅ Turbopack for faster builds
- ✅ Bun as package manager
- ✅ Path aliases configured (`@/*`)
- ✅ Empty template (minimal boilerplate)

## Next Steps

After scaffolding completes:

```bash
cd $APP_NAME
bun install
```

### Disable Dev Indicators

Update `next.config.ts` to add `devIndicators: false` (keep any existing config options):

```ts
import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  reactCompiler: true,
  devIndicators: false,
};

export default nextConfig;
```

### Configure Biome

The scaffolder generates a valid `biome.json`. Update it to add overrides that suppress known lint issues in shadcn-generated UI components (applied later by the `add-shadcn` skill):

```json
{
  "$schema": "https://biomejs.dev/schemas/2.2.0/schema.json",
  "vcs": {
    "enabled": true,
    "clientKind": "git",
    "useIgnoreFile": true
  },
  "files": {
    "ignoreUnknown": true,
    "includes": ["**", "!node_modules", "!.next", "!dist", "!build"]
  },
  "formatter": {
    "enabled": true,
    "indentStyle": "space",
    "indentWidth": 2
  },
  "linter": {
    "enabled": true,
    "rules": {
      "recommended": true,
      "suspicious": {
        "noUnknownAtRules": "off"
      }
    },
    "domains": {
      "next": "recommended",
      "react": "recommended"
    }
  },
  "assist": {
    "actions": {
      "source": {
        "organizeImports": "on"
      }
    }
  },
  "overrides": [
    {
      "includes": ["src/components/ui/**", "components/ui/**"],
      "linter": {
        "rules": {
          "a11y": {
            "useSemanticElements": "off",
            "noLabelWithoutControl": "off",
            "useKeyWithClickEvents": "off"
          },
          "suspicious": {
            "noArrayIndexKey": "off",
            "noDoubleEquals": "off"
          }
        }
      }
    }
  ]
}
```

> **Why these overrides?** The `noUnknownAtRules: "off"` suppresses false positives from Tailwind v4 custom at-rules (`@theme`, `@apply`, `@layer`, `@reference`). The `overrides` section suppresses known lint issues in shadcn-generated UI components (`field.tsx`, `input-group.tsx`, `label.tsx`) that are vendor code and shouldn't be modified.

### Create AGENTS.md

Create an `AGENTS.md` file at the project root with the following content:

```markdown
# Agent Conventions

Project conventions for AI coding agents. All agents (Claude, Cursor, Copilot, etc.) MUST follow these rules.

## Package Manager

- Use **bun** (not npm, yarn, or pnpm)
- Use `bunx` for one-off commands (not `npx`)
- Lockfile: `bun.lock`

## Linting & Formatting

- Use **Biome** (not ESLint or Prettier)
- Run `bunx biome check --fix .` after generating or modifying files
- Run `bunx biome format --write .` for formatting only
- Config: `biome.json` at project root

## UI Primitives

- shadcn/ui is configured with **Base UI** (not Radix UI)
- Do NOT import from `@radix-ui/*` — use the shadcn component abstractions
- `DropdownMenuTrigger` renders a button by default — do NOT wrap with `<Button asChild>`

## Icon Library

- Use **@phosphor-icons/react** (not lucide-react)
- Import: `import { IconName } from "@phosphor-icons/react"`
- Sizing: use `size={N}` prop or Tailwind classes (`className="h-4 w-4"`)
- Weight variants: `weight="regular"` (default), `"bold"`, `"fill"`, `"duotone"`

## Styling

- **Tailwind CSS v4** — use canonical v4 class names
- Use `bg-linear-to-b` (not `bg-gradient-to-b`)
- Use semantic color tokens: `bg-background`, `text-foreground`, `border-border`
- Do NOT use hardcoded colors like `bg-white`, `text-zinc-900`

## TypeScript

- Never cast to `any`
- Use `import type` for type-only imports
- Use `Number.isNaN()` (not global `isNaN()`)
- Use `?? fallback` or runtime checks instead of non-null assertions (`!`)

## React Patterns

- Use `useId()` for generating keys in lists
- Use `react-hook-form` with loading spinners for forms
- Prefer API routes over server components for dynamic data

## Environment Variables

- Access via `@/env` (validated with `@t3-oss/env-nextjs`)
- Use `?? fallback` or runtime check — never `process.env.VAR!`

## Database

- Use **Drizzle ORM** with PostgreSQL
- Schema files in `db/schema/` or `lib/db/schema/`

## Authentication

- Use **better-auth** — see `lib/auth.tsx` and `lib/auth-client.ts`
```

### Start Dev Server

```bash
bun dev
```

## Recommended Setup

Once the project is created, consider:

- **Git hooks**: Run `/setup-lefthook` to configure pre-commit linting and type checking
- **Design system**: Run `/add-shadcn` to add shadcn/ui components
