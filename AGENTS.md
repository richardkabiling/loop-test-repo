<!-- sdlc:begin (managed by /setup-sdlc-loop; edit inside the markers via docs/sdlc/loop.json, or outside them freely) -->
# loop-test-repo

Greenfield monorepo: Scala + Apache Pekko API (sbt, Pekko Persistence on Postgres) in backend/, TypeScript + React + Vite web app (pnpm) in frontend/, OpenAPI contract between them, Terraform on AWS for the API's infrastructure, backend container image in infra/, GitHub PRs + GitHub Actions, root justfile.

## Verify your work

Run these before you say you're done; paste the output as evidence.

| What | Command |
|---|---|
| Install | `just install` |
| Build | `just build` |
| Test (all) | `just test` |
| Test (one file) | `just test-single <path>` |
| Lint | `just lint` |
| Typecheck | `just typecheck` |

## How work flows here

This repo runs **Charmander**, an AI-native SDLC loop: intent → design → plan → build → review → ship → improve. Start or resume with `/charmander` (Codex: `$charmander`). It shows each work item's status and the next step. Phases stop at human gates; you never pass a gate yourself.

- Work items live in `docs/work/<yyyy-mm-dd>-<slug>/` (intent.md → spec.md → plan.md → tickets.json → PR).
- The loop definition is `docs/sdlc/LOOP.md`. The doc index is `docs/sdlc/MAP.md`: read it to find the right doc before searching.
- Tracker: GitHub Issues via `gh`: epics are parent issues (`epic` label, `intent-approved` / `design-approved` gate labels), tickets are sub-issues; agent-ready label `ready-for-agent`.

## Things you can't see from the code

- Nothing yet (greenfield). Add lines here through `/charmander-improve` when something bites.

## Conventions

- **commits**: Conventional Commits 1.0.0 (enforced by commit-msg hook).
- **commands**: run everything through the root justfile (just test, just test-single, just lint, ...) (enforced by AGENTS.md).
- **scala**: Scala 3 LTS; scalafmt + scalafix; -Werror; no null/var/return; never block inside actors or streams (enforced by pre-commit + Stop check (just lint, just typecheck); scoped rule).
- **typescript**: strict tsconfig, no any; ESLint flat config + Prettier; tsc --noEmit (enforced by lint-staged + Stop check typecheck).

Folder-specific rules load from nested `AGENTS.md` files and `.claude/rules` / `.cursor/rules` (generated from `.agents/rules/`; edit the source, then run `scripts/sdlc/sync-agent-files.sh`).

<!-- sdlc:end -->

<!-- sdlc:review-guidelines (generated from REVIEW.md) -->
## Review guidelines

Review against the spec and this repo's standards, not personal taste. Report only issues **introduced by this change**. "No blocking findings" is a valid, welcome result.

- **Important** (blocking; Codex P0–P1; `issue (blocking)`): breaks an acceptance criterion, loses or corrupts data (including a persisted Pekko event that no longer replays), opens a security hole, breaks the public OpenAPI contract, or deploys something unsafe on merge to main
- **Nit** (non-blocking; P2–P3; `nitpick (non-blocking)`): report **at most 5 nits per review**, and summarize the rest as a count.
- **Pre-existing** (`note (non-blocking)`): label it and never block on it.
- **Evidence**: every behaviour claim cites `file:line`, a failing command, or a spec clause. Cross-file impact must name the affected code. Verify before you report.
- **Do not report**: anything CI already enforces (scalafmt, scalafix, the Scala compiler (-Werror), ESLint, Prettier, tsc, tflint, checkov, actionlint, zizmor, hadolint, markdownlint, Vale), generated files, lockfiles, vendored code.
- AI reviewers comment; they never approve or block. Approvals follow the PR's tier (critical: 2, standard: 1, low: 1; never the work item's driver); every conversation must be resolved. This approval is the deploy gate: merge to main deploys.

Full policy: `REVIEW.md`.
<!-- /sdlc:review-guidelines -->

## Scoped rules

Generated from `.agents/rules/`; rules for a specific folder live in that folder's `AGENTS.md`.

<!-- sdlc:rule lockfiles (generated from .agents/rules/lockfiles.md) -->
### When editing `pnpm-lock.yaml`
Change only through pnpm.

Enforced by: protect-paths hook; diff-guard lockfile check.
<!-- /sdlc:rule lockfiles -->

<!-- sdlc:rule persisted-events (generated from .agents/rules/persisted-events.md) -->
### When editing `backend/**/serialization/**`
Persisted events are forever: add a new event version and an event adapter; never change or remove a persisted field; never edit existing golden fixtures.

Enforced by: protect-paths hook on existing fixtures; golden fixture test.
<!-- /sdlc:rule persisted-events -->

<!-- sdlc:rule secrets (generated from .agents/rules/secrets.md) -->
### When editing `.env*`, `**/*.pem`, `**/*.key`
Never read, print or commit (.env.example is fine).

Enforced by: protect-paths hook.
<!-- /sdlc:rule secrets -->
