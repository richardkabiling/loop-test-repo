---
name: charmander-review
description: Review phase. Open the PR for a validated ticket, compute its tier, run the automated checks, AI reviews and context-less persona lenses that tier calls for, fix majors red-first on the same PR, answer every finding, and request the tier's human approvers. Use after /charmander-build validates a ticket.
disable-model-invocation: true
---

# Review phase

**Input:** a ticket validated by `/charmander-build` (`"passes": true`, evidence in `progress.md`). **Output:** a PR on GitHub with evidence, a tier label, resolved findings and the right approvers requested.
**Gate:** human: team-member (not the driver) approves via approvals per PR tier (review.pr.tiers) through branch protection or rulesets; conversation resolution; the authoring agent can't approve; this approval is the deploy gate: merge to main triggers deploys. You never approve your own change.
**Exit:** Checks green; AI and lens findings resolved or dismissed with a reason; approvals meet the PR's tier

## Steps

1. **Tier.** Run `bash scripts/sdlc/pr-tier.sh --base main`. It prints the tier, the files that set it, the human approvals and roles required, which AI reviewers run, and any extra lenses. Tiers:

   | Tier | Matches | Humans | AI | Extra lenses |
   |---|---|---|---|---|
   | critical | `infra/**`, `.github/workflows/**`, `backend/**/serialization/**`, `backend/src/main/resources/db/**`, `api/openapi.yaml`, `backend/Dockerfile`, `backend/**/auth/**`, `frontend/src/**/auth/**` | 2 (team-member (not the driver)) | lenses | security, sre, data-integrity, backward-compat |
   | standard | (default) | 1 (team-member (not the driver)) | lenses | — |
   | low | `docs/ops/**`, `docs/work/**`, `docs/decisions/**`, `README.md`, `GLOSSARY.md` | 1 (any team member) | none | — |

2. **Open the PR.** Open the PR first, as ready for review, then run the reviews on it. Title: Conventional Commits style, imperative (`feat(api): add order cancellation`). Body: the `/pr` skill's body: what and why, linked ticket and spec, validation evidence, tier and why, and for critical tier the `terraform plan` output or `oasdiff` report. Link the ticket and the spec, paste the validation evidence from `progress.md`, state the tier and why. Label it `tier:<id>`. Standards: Conventional Commits titles; squash merge; linked ticket Use `/pr` for the PR body.
3. **Automated checks.** Run `just pr-checks base=main labels=<the PR's labels>` (the loop's `pr-checks.sh` plus this repo's `scripts/sdlc/repo-checks.sh`). No CI is configured yet. A failed check is fixed before any AI or human review is requested.
4. **AI review, per tier.** For each AI reviewer the tier lists:
   - `lenses`: run the context-less persona review for the `review` point as `docs/sdlc/personas.md` describes, plus the tier's extra lenses (at most 5 in total). Each lens sees only the PR diff, `spec.md` and `REVIEW.md`. Findings are deduped against the work item's ledger (`--point review`). Surface them as `docs/sdlc/personas.md` says for `review` (pr → the code PR).
   - `pr-bot` (only if the repo has one): it reviews on open and update. Add its findings to the same ledger so nothing is answered twice.
5. **Evals.** Run `bash scripts/sdlc/run-evals.sh --base main --dry-run` to see which suites this PR triggers (harness (harness, local, runs when AGENTS.md, CLAUDE.md, REVIEW.md, .agents/**, …)). If any, run it without `--dry-run`. It runs each triggered suite where `loop.json` says (`local`: here, in throwaway worktrees or by the suite's command; `platform`: the hosted tool's CLI; `ci`: it reads the existing CI check instead of running it), grades them, and prints a summary. A missing secret fails the suite before it starts: ask the human to set it in the shell, never paste it. Surface the summary like the lens findings. A suite below its threshold is a **major** finding: fix and re-run, or a human accepts the regression with a reason. Also run `bash scripts/sdlc/detect-evals.sh`: if this PR adds an eval suite that `review.evals.suites` doesn't list, register it in `docs/sdlc/loop.json` in the same PR.
6. **Resolve.** A major finding sends you back to red → green on the same branch: a failing test first, then the fix, pushed to the PR. Fix minor findings or dismiss them with a reason; keep nits within the `REVIEW.md` cap. Reply to every finding (commit link or reason) and close it in the ledger. Re-run only the lenses whose areas the fix touched. After 3 rounds with majors still open, stop and ask a human.
7. **Request approvers.** When checks are green, triggered evals pass and no major is open, request the tier's humans: Approvals follow the PR's tier (critical: 2, standard: 1, low: 1; never the work item's driver); every conversation must be resolved. This approval is the deploy gate: merge to main deploys. Then stop. Humans approve; you answer their comments with fixes or reasons.
8. **Record.** Set the ticket's `"pr"` to the PR link; append the tier, rounds and outcome to `progress.md`. When the PR is merged (check with the forge CLI), set `"merged": true`. After merge, the next ticket starts with `/charmander-build`; when all tickets are merged, `/charmander-ship`.

Done when the PR is open with evidence and its tier label, checks are green, triggered evals pass (or a human accepted the result), every finding is answered and closed in the ledger, and the tier's approvers are requested (or have approved).

## Guardrails

- The tier only goes up. If a fix touches a path in a higher tier, re-run `pr-tier.sh`, relabel, add the new tier's reviewers, and re-run `pr-checks.sh`.
- AI reviewers comment; they never approve or block.
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

## Local notes

<!-- Team additions. Regeneration keeps this section. -->
