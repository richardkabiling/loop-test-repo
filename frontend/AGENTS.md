# Agent notes for `frontend/`

Rules for this folder. Each block is generated from `.agents/rules/`; edit the source and run `scripts/sdlc/sync-agent-files.sh`.

<!-- sdlc:rule frontend (generated from .agents/rules/frontend.md) -->
### When editing `frontend/**`
TypeScript strict, no any. Import the API only through the generated client.

Enforced by: nested AGENTS.md; ESLint + tsc.
<!-- /sdlc:rule frontend -->
