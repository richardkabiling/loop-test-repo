---
name: charmander-ship
description: Ship phase. Prepare a release of merged work: release notes, flags, progressive rollout plan, health checks and rollback, then stop at the human production gate. Use when a work item's tickets are merged.
disable-model-invocation: true
---

# Ship phase

**Gate:** automated: merged to main through an approved PR; CD pipeline green; deploy health checks; rollback path verified; notify driver; escalate to team when a health check fails or the release touches a critical-tier path. You never pass a human production gate yourself.
**Exit:** Deployed; health checks green; rollback path verified

## Steps

1. **Confirm** every ticket in `tickets.json` is merged, and the trunk is green (the repo's CI if it has one; otherwise `just test` on the trunk).
2. **Ship in dependency order:** adr → infra → ci-cd → db-schema → api-contract → api → api-image → web → user-guide → tech-ops-manual → business-ops-manual → stakeholder-docs. Per deliverable:
   - **adr**: merge = accepted; supersede, never edit
   - **infra**: terraform apply from GitHub Actions on merge to main via AWS OIDC role; the agent never applies
   - **ci-cd**: merge to main
   - **db-schema**: expand -> migrate -> contract; never drop or change a persisted field
   - **api-contract**: merge = published; frontend client regenerated (just gen-client)
   - **api**: CD on merge to main, behind feature flags; rehearsed rollback
   - **api-image**: pushed to ECR and deployed by CD on merge to main
   - **web**: CD on merge to main (S3 + CloudFront), behind feature flags
   - **user-guide**: published with the release
   - **tech-ops-manual**: updated in the same PR as the infra/API change (doc-code drift check)
   - **business-ops-manual**: published with the release
   - **stakeholder-docs**: release notes on deploy
3. **Release notes** from merged PRs and Conventional Commit types; link the spec (and the epic or docs PR, when intent and design live there). Update the user docs if behaviour changed.
4. **Rollout plan:** flag state per environment, ramp steps, the health signals to watch, and the **rollback command**. Rehearse the rollback in a non-production environment where possible.
5. **Run the automated gate.** Check: merged to main through an approved PR; CD pipeline green; deploy health checks; rollback path verified. If all pass and no escalation condition holds, set `Status: approved (automated: <checks>)`, notify driver, and continue in a fresh session. If any check fails or can't run, or an escalation condition holds (a health check fails or the release touches a critical-tier path), stop and ask team. Drive the ramp only within the plan, report health signals at each step, and roll back automatically when a health check fails.

6. **Record:** append `Shipped: <yyyy-mm-dd> <version or commit>` to the work item's `progress.md`. `/charmander` then offers the improve retro.

Done when production runs the release, the `Shipped:` line is recorded, health checks are green, the flag ramp is complete or paused by decision, and the rollback path was verified.

## Local notes

<!-- Team additions. Regeneration keeps this section. -->
