# SMS Notifications
<!-- markdownlint-disable MD060 -->

Send an SMS after each phase. SMS should never block build execution.

## How to send

```bash
N8N_KEY=$(grep "N8N_SMS_KEY" {PROJECT_NAME}/.env.local | cut -d'=' -f2 2>/dev/null) && \
SMS_TO=$(grep "^SMS_TO=" {PROJECT_NAME}/.env.local 2>/dev/null | cut -d'=' -f2) && \
test -n "$SMS_TO" && \
curl -s -X POST "https://n8n.mattwood.co/webhook/surge-sms" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $N8N_KEY" \
  -d "{
    \"body\": \"{PROJECT_NAME} - Phase {N} complete: {PHASE_SUMMARY}\",
    \"to\": \"$SMS_TO\"
  }"
```

## Phase messages

| Phase | Message body |
|-------|--------------|
| 1 | `{PROJECT_NAME} - Phase 1 complete: Spec approved. {skill-count} skills, {step-count} steps.` |
| 2 | `{PROJECT_NAME} - Phase 2 complete: Shell created. {skill-count} skills symlinked, .ralphrc + git ready.` |
| 3 | `{PROJECT_NAME} - Phase 3 complete: Ralph loop generated. PLAN.md has {step-count} steps across 4 phases.` |
| 4 | `{PROJECT_NAME} - Phase 4 complete: Secrets loaded. {key-count} env vars from 1Password.` |
| 5 | `{PROJECT_NAME} - Phase 5 complete: All done! cd {path} && start ralph.` |

## Fallback for early phases

Phases 1-3 run before Phase 4 creates `.env.local`, so `N8N_SMS_KEY` may not be available yet.

```bash
N8N_KEY=$(grep "N8N_SMS_KEY" {PROJECT_NAME}/.env.local 2>/dev/null | cut -d'=' -f2) || \
N8N_KEY=$(op item get "Dev Environment" --account my.1password.com --fields label=notesPlain 2>/dev/null | grep "^N8N_SMS_KEY=" | cut -d'=' -f2 | tr -d '"')
SMS_TO=$(grep "^SMS_TO=" {PROJECT_NAME}/.env.local 2>/dev/null | cut -d'=' -f2)

if [ -n "$N8N_KEY" ]; then
  if [ -n "$SMS_TO" ]; then
    curl -s -X POST "https://n8n.mattwood.co/webhook/surge-sms" \
      -H "Content-Type: application/json" \
      -H "X-API-Key: $N8N_KEY" \
      -d "{
        \"body\": \"{PROJECT_NAME} - Phase {N} complete: {PHASE_SUMMARY}\",
        \"to\": \"$SMS_TO\"
      }"
  else
    echo "WARN: SMS_TO missing - skipping Phase {N} SMS"
  fi
else
  echo "WARN: N8N_SMS_KEY not available - skipping Phase {N} SMS"
fi
```

If SMS fails, log warning and continue.
