# Agent notes for `backend/src/main/resources/`

Rules for this folder. Each block is generated from `.agents/rules/`; edit the source and run `scripts/sdlc/sync-agent-files.sh`.

<!-- sdlc:rule journal-migrations (generated from .agents/rules/journal-migrations.md) -->
### When editing `backend/src/main/resources/db/**`
Append-only. Never edit an applied journal script; add a new one.

Enforced by: protect-paths hook blocks edits to existing files.
<!-- /sdlc:rule journal-migrations -->
