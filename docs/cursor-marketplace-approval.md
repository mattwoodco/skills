# Cursor Marketplace Approval Guide

Use this guide when you want to submit this plugin to the Cursor Marketplace.

## 1) Prepare the plugin package

- Keep the Cursor manifest in `.cursor-plugin/plugin.json`.
- Ensure the plugin name in `plugin.json` matches any marketplace listing entry.
- Keep version and description aligned with `.claude-plugin/plugin.json` so both channels stay in sync.
- Verify your skill paths are valid (`./skills/add-feature`, `./skills/add-spec`, `./skills/add-project`).

## 2) Validate before submission

- Confirm `plugin.json` is valid JSON.
- Confirm `.cursor-plugin/marketplace.json` is valid JSON if you are publishing a marketplace index.
- Test install from repo:

```text
/add-plugin https://github.com/mattwoodco/skills
```

- Test local install:

```text
/add-plugin /Users/mw/Developer/mattwoodco/skills
```

## 3) Build and submit

Follow Cursor's plugin building/submission documentation:

- Plugins overview: [https://cursor.com/docs/plugins](https://cursor.com/docs/plugins)
- Building plugins: [https://cursor.com/docs/plugins/building](https://cursor.com/docs/plugins/building)
- Official plugin examples: [https://github.com/cursor/plugins](https://github.com/cursor/plugins)

## 4) Review expectations

Marketplace plugins go through manual review for quality and security.

Practical checklist before you submit:

- Clear description and scope in `plugin.json`.
- No broken paths for skills/rules/agents/hooks/MCP config.
- No secrets or credentials in plugin files.
- Reproducible install instructions in `README.md`.
- Version bumped for each resubmission with meaningful changes.

## 5) If review feedback comes back

- Address each reviewer note directly.
- Update the manifest/docs/tests as needed.
- Bump plugin version and resubmit.
- Keep a short changelog in your PR/commit notes to speed up re-review.
