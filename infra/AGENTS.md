# Agent notes for `infra/`

Rules for this folder. Each block is generated from `.agents/rules/`; edit the source and run `scripts/sdlc/sync-agent-files.sh`.

<!-- sdlc:rule infra (generated from .agents/rules/infra.md) -->
### When editing `infra/**`
Plan, never apply. Attach terraform plan output to the PR.

Enforced by: permissions deny terraform apply; tflint + checkov.
<!-- /sdlc:rule infra -->
