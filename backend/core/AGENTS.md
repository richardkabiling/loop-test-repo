# Agent notes for `backend/core/`

Rules for this folder. Each block is generated from `.agents/rules/`; edit the source and run `scripts/sdlc/sync-agent-files.sh`.

<!-- sdlc:rule core-data-driven-tests (generated from .agents/rules/core-data-driven-tests.md) -->
### When editing `backend/core/**`
Domain core. Every behaviour change ships a table-driven ScalaTest (TableDrivenPropertyChecks) covering the cases.

Enforced by: pr-checks.sh fails when backend/core/src/main changes without backend/core/src/test; test-quality lens.
<!-- /sdlc:rule core-data-driven-tests -->
