# 1Password Secrets Workflow
<!-- markdownlint-disable MD060 -->

Use this workflow in add-project Phase 4.

## Goal

Fetch all project secrets from 1Password into `.env.local` with one biometric prompt, then verify required keys.

## Requirements

- 1Password desktop app unlocked
- Developer setting enabled: Integrate with 1Password CLI
- `op` CLI installed

## Step 1: Sign in

```bash
op signin --account my.1password.com 2>&1
```

If this fails:

1. Open 1Password desktop app
2. Unlock it
3. Enable CLI integration in Developer settings
4. Restart terminal

## Step 2: Dump all env vars in one script

```bash
op signin --account my.1password.com 2>&1 && \
op item get "Dev Environment" --account my.1password.com --fields label=notesPlain 2>/dev/null | \
  tr -d '"' > {PROJECT_NAME}/.env.local && \
echo "SUCCESS: .env.local written with $(wc -l < {PROJECT_NAME}/.env.local) env vars"
```

Use `>` (overwrite). The 1Password item is the source of truth.

## Step 3: Append project-specific overrides

```bash
grep -q "^NEXT_PUBLIC_APP_URL=" {PROJECT_NAME}/.env.local || \
  echo "NEXT_PUBLIC_APP_URL=http://localhost:3000" >> {PROJECT_NAME}/.env.local
grep -q "^BETTER_AUTH_URL=" {PROJECT_NAME}/.env.local || \
  echo "BETTER_AUTH_URL=http://localhost:3000" >> {PROJECT_NAME}/.env.local
```

## Step 4: Verify keys

```bash
MISSING=""
for KEY in DATABASE_URL N8N_SMS_KEY AI_GATEWAY_API_KEY BETTER_AUTH_SECRET; do
  grep -q "^${KEY}=" {PROJECT_NAME}/.env.local 2>/dev/null || MISSING="$MISSING $KEY"
done
if [ -n "$MISSING" ]; then
  echo "WARN: Missing keys in .env.local:$MISSING"
else
  echo "All critical keys present."
fi
```

### Skill-to-key mapping

| Skill | Required Keys |
|-------|--------------|
| db | `DATABASE_URL` |
| auth | `BETTER_AUTH_SECRET`, `DATABASE_URL` |
| payments | `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET` |
| ai-core | `AI_GATEWAY_API_KEY` |
| ai-image-gen | `REPLICATE_API_TOKEN`, `FAL_KEY` |
| ai-video-gen | `REPLICATE_API_TOKEN`, `FAL_KEY` |
| storage | `S3_ENDPOINT`, `S3_ACCESS_KEY`, `S3_SECRET_KEY`, `S3_BUCKET` |
| email | `RESEND_API_KEY` |
| realtime | `LIVEBLOCKS_SECRET_KEY` |
| search | `MEILISEARCH_API_KEY` |
| queue | `REDIS_URL` |
| observability | `OTEL_EXPORTER_OTLP_ENDPOINT` |
| voice-retell | `RETELL_API_KEY` |
| knowledge-sync | `KNOWLEDGE_API_URL`, `KNOWLEDGE_API_KEY` |
| sms/notify | `N8N_SMS_KEY` |

Cross-reference this table with the spec skill list and verify all applicable keys.

## Fallback if `Dev Environment` item is missing

```bash
ITEM=$(op item list --account my.1password.com --format=json | \
  jq -r '.[] | select(.title | test("dev.env|environment"; "i")) | .title' | head -1) && \
if [ -n "$ITEM" ]; then
  op item get "$ITEM" --account my.1password.com --fields label=notesPlain 2>/dev/null | \
    tr -d '"' > {PROJECT_NAME}/.env.local && \
  echo "SUCCESS: Used '$ITEM'" || echo "WARN: Failed to read '$ITEM'"
else
  echo "WARN: No matching 1Password item found - .env.local will need manual setup"
fi
```

## Guardrails

- Never log secret values
- Always use `--account my.1password.com`
- Keep all `op` calls in one chained script where possible
