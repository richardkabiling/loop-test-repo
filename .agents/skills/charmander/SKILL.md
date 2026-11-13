---
name: charmander
description: Show where every work item stands in Charmander (this repo's SDLC loop) and run the next step. Start here for new work, to resume, or when unsure which phase skill to use.
disable-model-invocation: true
---

# Charmander: router

1. Run `bash scripts/sdlc/sdlc-status.sh` and show its output.
2. If the user named a work item or an idea, match it to an existing item. If none matches, it's new work: run the intent phase.
3. Recommend the next step for the chosen item and run that phase skill after the user says yes:

| Next step says | Run |
|---|---|
| No work item yet, or intent in draft | `/charmander-intent` |
| Intent approved; spec or design not done | `/charmander-design` |
| Design approved; no plan or tickets | `/charmander-plan` |
| A ticket with `passes: false` and no blockers | `/charmander-build` |
| A ticket validated (`passes: true`) without a merged PR | `/charmander-review` |
| All tickets merged | `/charmander-ship` |
| Shipped, an incident, or a signals scan | `/charmander-improve` |

4. A ticket goes through `/charmander-build` (local build-validate) and then `/charmander-review` (the PR). Phases end at human gates. When the next step is "awaiting approval", say who approves (any team member except the work item's driver) and how (from `docs/sdlc/LOOP.md`), then stop.

Done when the user has seen the status and the chosen phase has started, or you have reported a gate and stopped.

## Local notes

<!-- Team additions. Regeneration keeps this section. -->
