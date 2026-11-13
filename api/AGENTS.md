# Agent notes for `api/`

Rules for this folder. Each block is generated from `.agents/rules/`; edit the source and run `scripts/sdlc/sync-agent-files.sh`.

<!-- sdlc:rule api-contract (generated from .agents/rules/api-contract.md) -->
### When editing `api/openapi.yaml`
Contract-first: change the contract before the code. Breaking changes need an ADR and a version bump.

Enforced by: Redocly + oasdiff in pr-checks.sh.
<!-- /sdlc:rule api-contract -->
