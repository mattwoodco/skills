---
name: env-from-1password
description: Copy environment variables from 1Password to .env.local. Use when user says "load env from 1password", "copy env from 1password", "get env from 1password", or "1password env".
author: "@mattwoodco"
version: 1.0.1
created: 2026-02-13
updated: 2026-02-13
validated: 2026-02-13
---

# Load Environment Variables from 1Password

Fetches environment variables from a 1Password item and writes them to `.env.local` in the current project.

## Prerequisites

1. **1Password desktop app installed** (download from 1password.com)

2. **1Password CLI installed**:
   ```bash
   brew install --cask 1password-cli
   ```

3. **Enable desktop app integration**:
   - Open 1Password app → Settings → Developer
   - Enable "Connect with 1Password CLI"
   - **Restart the 1Password app** after enabling (important!)
   - This allows the CLI to use your existing 1Password session

4. **Verify CLI access**:
   ```bash
   op whoami
   ```
   Should show your account details if integration is working.

   **Troubleshooting**: If you see "couldn't connect to desktop app":
   - Make sure 1Password app is running
   - Restart the 1Password app
   - Update to latest version if needed

5. **Environment variables stored in 1Password** as a Secure Note with the env vars in the notes field

## How It Works

1. **Check for multiple accounts** (if user has more than one):
   ```bash
   op account list
   ```
   If multiple accounts exist, you'll need to specify `--account` flag in subsequent commands.

2. **List available 1Password items** to help user identify the right one:
   ```bash
   # Single account:
   op item list | grep -i "env"

   # Multiple accounts (specify which one):
   op item list --account=my.1password.com | grep -i "env"
   ```

3. **Ask the user** which item contains their environment variables (by name or ID)

3. **Fetch the item** and extract fields:
   ```bash
   op item get "$ITEM_NAME" --format=json
   ```

4. **Parse fields** and write to `.env.local`:
   - For Secure Notes: Extract from `fields` array where `type` is not `CONCEALED` (skip password fields)
   - For each field: `label=value` format
   - Common patterns:
     - Field with `label` and `value` properties
     - Sections with multiple fields
     - Handle notesPlain for multi-line env content

5. **Write to `.env.local`**:
   ```bash
   # From notes field (recommended - simpler format)
   op item get "$ITEM_NAME" --account=ACCOUNT_NAME --fields label=notesPlain | tr -d '"' > .env.local
   ```

   Or for structured fields:
   ```bash
   op item get "$ITEM_NAME" --account=ACCOUNT_NAME --format=json | jq -r '.fields[] | select(.value != null) | "\(.label)=\(.value)"' > .env.local
   ```

   **Note**: The `tr -d '"'` removes surrounding quotes that `op` adds to field values.

## Example Workflow

```bash
# 1. Check if you have multiple accounts
op account list

# 2. List items to find the right one
op item list --account=my.1password.com | grep -i "env"

# 3. Get env vars from 1Password (from notes field - recommended)
op item get "Dev Environment" --account=my.1password.com --fields label=notesPlain | tr -d '"' > .env.local

# 4. Confirm
cat .env.local
```

## 1Password Item Format

### Option 1: Secure Note with plain text
Store all env vars in the notes field:
```
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/mydb
REDIS_URL=redis://localhost:6379
STRIPE_SECRET_KEY=sk_test_...
NEXT_PUBLIC_APP_URL=http://localhost:3000
```

### Option 2: Structured fields
Create fields for each env var:
- Field: DATABASE_URL, Value: postgresql://...
- Field: REDIS_URL, Value: redis://...
- Field: STRIPE_SECRET_KEY, Type: password/concealed, Value: sk_test_...

## What This Creates

- `.env.local` file with all environment variables from 1Password
- Preserves formatting and comments if using notes field
- Filters out non-value fields if using structured format

## Available Keys

The following environment variables are available in 1Password:

| Variable | Purpose |
|---|---|
| `FAL_KEY` | Fal.ai media generation API |
| `AI_GATEWAY_API_KEY` | AI Gateway routing |
| `EXA_API_KEY` | Exa search API |
| `BLOB_READ_WRITE_TOKEN` | Vercel Blob storage |
| `RESEND_API_KEY` | Resend email API |
| `NEXT_PUBLIC_LIVEBLOCKS_PUBLIC_KEY` | Liveblocks client-side key |
| `LIVEBLOCKS_SECRET_KEY` | Liveblocks server-side key |
| `REPLICATE_API_TOKEN` | Replicate AI models |
| `BETTER_AUTH_SECRET` | Better Auth session signing |
| `PAYLOAD_SECRET` | Payload CMS secret |
| `STRIPE_SECRET_KEY` | Stripe payments |

## Security Notes

- `.env.local` should be in `.gitignore` (Next.js does this by default)
- Never commit `.env.local` to version control
- Rotate secrets if accidentally committed
- Use separate 1Password items for different environments (dev/staging/prod)

## Next Steps

After loading env vars:

1. **Review the file**:
   ```bash
   cat .env.local
   ```

2. **Add any project-specific overrides** manually

3. **Run the app**:
   ```bash
   bun dev
   ```

## Tips

- **Multiple environments**: Create separate 1Password items for dev/staging/prod
- **Team sharing**: Share the 1Password vault with your team
- **Updates**: Re-run this skill to refresh `.env.local` when secrets change
- **Validation**: Use with `/env-config` skill for type-safe env validation
