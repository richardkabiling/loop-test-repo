# Agent notes for `backend/`

Rules for this folder. Each block is generated from `.agents/rules/`; edit the source and run `scripts/sdlc/sync-agent-files.sh`.

<!-- sdlc:rule backend (generated from .agents/rules/backend.md) -->
### When editing `backend/**`
Scala 3 + Pekko typed actors. Never block inside actors or streams. Run just test-single <spec> while iterating.

Enforced by: nested AGENTS.md; scalafmt/scalafix.
<!-- /sdlc:rule backend -->
