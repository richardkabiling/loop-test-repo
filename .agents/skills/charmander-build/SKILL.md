---
name: charmander-build
description: Build-validate phase. Implement the next unblocked ticket test-first on a local branch and validate it with the ticket's tests and the repo's checks, recording evidence. No PR and, by default, no review here; /charmander-review opens the PR next. Use after the plan gate passes.
disable-model-invocation: true
---

# Build → validate phase

Everything here is local, one ticket at a time. Nothing is pushed for review until `/charmander-review`.

**Input:** an approved `plan.md` and its `tickets.json`. **Output:** a local branch per ticket, with validation evidence in `progress.md`.
**Gate:** automated: validate checks green; ticket verify command passes; evidence recorded in progress.md; notify driver; escalate to team when validation still fails after 3 attempts, or an existing test had to change.
**Exit:** Every acceptance criterion of the ticket has a passing test; validate checks green; evidence in progress.md; nothing pushed for review yet

## Loop, once per ticket

1. **Pick** the first ticket with `"passes": false` whose `blocked_by` tickets all pass. Read `progress.md` and `git log` first. Work one ticket per session on its own branch (`work/<slug>-<ticket id>`); for parallel tickets use one worktree each.
2. **Red.** Write a failing test at the seam named in the spec, one per acceptance criterion of the ticket. For a bug, reproduce it first. Don't edit existing tests to make them pass.
   If the ticket carries eval cases from the spec, add them to the named product suite now, alongside the tests. Review runs the suite.
3. **Green.** Write the smallest change that passes. Then **refactor** with tests green. Use `/tdd`, `/diagnosing-bugs`, `/codebase-design`.
4. **Validate.** Run, in order, and stop at the first failure:
   1. `just typecheck`
   2. `just test-single <changed specs/files>`, then `just test` for the touched package
   3. `bash scripts/sdlc/diff-guard.sh --worktree`
   4. the ticket's `verify` command
   - adr: markdownlint + link check
   - infra: terraform fmt -check, validate, tflint, checkov, terraform test
   - ci-cd: actionlint + zizmor
   - db-schema: golden fixtures of every past event version must deserialize; journal replay against Testcontainers Postgres
   - api-contract: Redocly lint + oasdiff breaking-change check
   - api: ScalaTest table-driven tests (required in backend/core/), ScalaCheck properties, ActorTestKit, Testcontainers Postgres integration, contract test against api/openapi.yaml
   - api-image: hadolint, Trivy, container smoke test
   - web: testing trophy: Vitest + Testing Library, Playwright E2E with toHaveScreenshot, axe (WCAG 2.2 AA)
   - user-guide: markdownlint, link check, Vale
   - tech-ops-manual: link check; runbook commands dry-run where possible
   - business-ops-manual: markdownlint, Vale (plain language)
5. **Review here?** No review here: validation is tests and checks. Review happens in `/charmander-review`.
6. **Record.** Set the ticket's `"passes": true` (validated locally; `merged` stays false until review; change nothing else in `tickets.json`). Append to `progress.md`: what changed, the validation commands with their output, screenshots for UI. This becomes the PR's evidence. Commit (Conventional Commits). Don't push for review.
7. **Gate.** Run the automated build gate (the checks above). If they pass, hand off: "Ticket <id> validated. Next: `/charmander-review <id>` opens the PR." If a check fails after 3 attempts, or an existing test has to change, stop and ask.

Done when every acceptance criterion of the ticket has a passing test, all validation checks pass, the evidence is in `progress.md`, and the ticket is committed on its branch.

## Guardrails

- **test-tampering**: Block skipped/deleted tests and net assertion loss unless a human approves (ScalaTest ignore/pending, Vitest .skip/.only) (diff-guard.sh in the Stop hook, the pre-commit hook and pr-checks.sh).
- **premature-completion**: Exit criteria per phase; Stop hook runs typecheck + tests; validation evidence required before the PR (stop-check.sh + PR template).
- **scope-creep**: plan.md names files; one ticket per session; warn above 400 changed lines / 30 files (diff-guard.sh --max-lines 400 --max-files 30 --size warn).
- **nit-flood**: Cap nits at 5; review for correctness and spec gaps only; skip what linters enforce (REVIEW.md + reviewer prompt + dedupe-findings.py; one summary comment updated in place).
- **self-approval**: Fresh-context reviewer; AI never approves; approver is a team member other than the driver, via branch protection/rulesets (branch protection or rulesets; validator requires a human gate on the review phase and a human approval in every PR tier).
- **hallucinated-deps**: New dependencies must exist in their registry; typecheck catches fake APIs (diff-guard.sh --check-registry in pr-checks.sh (review phase)).
- **runaway**: 120 turns, $25 budget, 3 failed validations; Stop-hook block cap 3 (loops.autonomy.limits; stop-check.sh --max-blocks 3).
- **secret-leak**: Block reads of .env (not .env.example); secret scanning (forge setting or the existing CI) (protect-paths.sh (protect: read); permissions.deny).
- **event-schema-break**: Golden fixtures for every past event version; append-only serialization folder (golden fixture test in just test; protect-paths hook).
- **silent-errors**: No swallowed failures; explicit supervision; validate only at boundaries (silent-failure lens + scalafix rules).
- **doc-drift**: Infra/API change must touch docs/ops/tech/ in the same PR (doc-code drift check in pr-checks.sh).
- **unreviewed-dep-bump**: Flag lockfile-only diffs (diff-guard.sh lockfile check).
- **review-loop**: Max 3 review rounds, then escalate to a human (REVIEW.md + loops.autonomy).
- **instruction-bloat**: Root AGENTS.md <= 200 lines; scoped rules and nested AGENTS.md (check-loop.sh).

## Autonomy

- Interactive: plan mode for intent, design and plan; `acceptEdits` for build-validate.
- Unattended (AFK): all ready-for-agent tickets with executable acceptance criteria: build-validate and review, up to merge to main. Done = every acceptance criterion's verify command passes. Self-check: just typecheck, just test, diff-guard.sh, the ticket's verify command; Playwright screenshot diffs for web tickets.
- May touch: any path in the repo, including infra/ and .github/workflows/ (nothing deploys before merge); blocked: push or merge to main, force push, terraform apply, reading or printing secrets; append-only rules for applied migrations and persisted events still apply.
- Stops at: 120 turns, 3 failed validations, $25 budget, or completion promise. Result: agent-opened PR; its human approval (any team member except the driver) is the deploy gate.
- Headless example: `claude -p "/charmander-build <ticket>" --max-turns 120 --max-budget-usd 25 --permission-mode acceptEdits`
Watch for drift. After two failed attempts at the same fix, stop, summarise what you tried, and ask.

## Local notes

<!-- Team additions. Regeneration keeps this section. -->
