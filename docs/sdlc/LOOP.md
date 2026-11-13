# Charmander

Generated from `docs/sdlc/loop.json` by `/setup-sdlc-loop`. To change the loop, edit `loop.json` (or re-run a step such as `/setup-sdlc-rules`), then regenerate. Agents start at `/charmander`.

```
[intent · HUMAN]  →  [design · HUMAN]  →  [plan]  →  [build]  →  [review · HUMAN]  →  [ship]  →  [improve]  ↺
```

## Phases and gates

| Phase | Strategy | Interaction | Artifact | Exit | Gate (owner · mechanism) |
|---|---|---|---|---|---|
| intent | grilling | interview | `GitHub epic + docs/work/<slug>/intent.md` | Problem, outcome, affected users and systems, constraints and open questions all filled; PO approved | human · team-member (not the driver) · 'intent-approved' label or approval comment on the epic by any team member except the work item's driver |
| design | synthesize-then-goldfish-review | review | `docs/work/<slug>/spec.md` | EARS acceptance criteria; concerns flagged and resolved; fresh-context review passed | human · team-member (not the driver) · 'design-approved' label or approval comment on the epic by any team member except the work item's driver |
| plan | plan-mode-then-tracer-tickets | review | `docs/work/<slug>/plan.md` | plan.md has Files / Order / Risks / Proof; every ticket fits one context window and lists its blockers | automated · plan.md has Files / Order / Risks / Proof; every acceptance criterion maps to a ticket with a verify command; fresh-context AI plan review: no blocking findings |
| build | tdd-with-stop-hook | steer | `local branch with validation evidence in progress.md` | Every acceptance criterion of the ticket has a passing test; validate checks green; evidence in progress.md; nothing pushed for review yet | automated · validate checks green; ticket verify command passes; evidence recorded in progress.md |
| review | pr-first-tiered-review | review | `pull request with evidence, tier label and resolved findings` | Checks green; AI and lens findings resolved or dismissed with a reason; approvals meet the PR's tier | human · team-member (not the driver) · approvals per PR tier (review.pr.tiers) through branch protection or rulesets; conversation resolution; the authoring agent can't approve; this approval is the deploy gate: merge to main triggers deploys |
| ship | trunk-based-flags-progressive | automated | `release + release notes` | Deployed; health checks green; rollback path verified | automated · merged to main through an approved PR; CD pipeline green; deploy health checks; rollback path verified |
| improve | retro-plus-eval-suite | interview | `docs/sdlc/improve/<yyyy-mm-dd>-<slug>.md` | Every finding is an intent, a harness PR, or a recorded no-op; evals pass after harness changes | automated · product findings become intents (they pass the intent gate); harness changes ship as PRs (they pass the review phase gate); eval suite passes before and after a harness change |

The authoring agent never passes a gate. Gate approval sets `Status: approved` in the artifact (or merges its PR).

**Intent and design live in:** epic: GitHub epic issue holds the intent and design summaries and the approval; the full intent.md, spec.md and design/*.md are committed in docs/work/<date>-<slug>/ (agent syncs the epic and the files after each round). Grilling: solo. Each ticket then goes through build-validate (local, `/charmander-build`) and review (its own PR, `/charmander-review`).

**Autonomy:** plan-then-acceptEdits; unattended (AFK) for all ready-for-agent tickets with executable acceptance criteria: build-validate and review, up to merge to main; may touch any path in the repo, including infra/ and .github/workflows/ (nothing deploys before merge); blocked: push or merge to main, force push, terraform apply, reading or printing secrets; append-only rules for applied migrations and persisted events still apply; limits 120 turns, 3 failed validations, $25.

## Deliverables

Build, test and ship in this order: adr → infra → ci-cd → db-schema → api-contract → api → api-image → web → user-guide → tech-ops-manual → business-ops-manual → stakeholder-docs.

| Deliverable | Path | Depends on | Build | Test | Review | Ship |
|---|---|---|---|---|---|---|
| adr | `docs/decisions/` | — | MADR 4.0 in docs/decisions/NNNN-title.md | markdownlint + link check | 1 approval (team member, not the driver) | merge = accepted; supersede, never edit |
| infra | `infra/ (AWS)` | adr | terraform plan -out (AWS provider, S3 remote state) | terraform fmt -check, validate, tflint, checkov, terraform test | critical tier; plan output attached to the PR | terraform apply from GitHub Actions on merge to main via AWS OIDC role; the agent never applies |
| ci-cd | `.github/workflows/` | infra | GitHub Actions; actions pinned by SHA; minimal permissions | actionlint + zizmor | critical tier | merge to main |
| db-schema | `backend/src/main/resources/db/; backend/**/serialization/` | adr | Pekko Persistence versioned events + event adapters; journal DDL scripts in backend/src/main/resources/db/ | golden fixtures of every past event version must deserialize; journal replay against Testcontainers Postgres | critical tier + data-integrity and migration-compat lenses | expand -> migrate -> contract; never drop or change a persisted field |
| api-contract | `api/openapi.yaml` | adr | OpenAPI 3.1 in api/openapi.yaml | Redocly lint + oasdiff breaking-change check | critical tier; breaking change needs an ADR and a version bump | merge = published; frontend client regenerated (just gen-client) |
| api | `backend/` | adr, db-schema, api-contract, infra | sbt, Pekko HTTP, typed actors | ScalaTest table-driven tests (required in backend/core/), ScalaCheck properties, ActorTestKit, Testcontainers Postgres integration, contract test against api/openapi.yaml | persona lenses + 1 approval | CD on merge to main, behind feature flags; rehearsed rollback |
| api-image | `backend/Dockerfile (or sbt-native-packager)` | ci-cd, api | multi-stage Dockerfile, Temurin JRE base pinned by digest, non-root | hadolint, Trivy, container smoke test | critical tier | pushed to ECR and deployed by CD on merge to main |
| web | `frontend/` | api-contract, api | Vite + React; typed client generated from OpenAPI (openapi-typescript) | testing trophy: Vitest + Testing Library, Playwright E2E with toHaveScreenshot, axe (WCAG 2.2 AA) | screenshots in the PR + persona lenses + 1 approval | CD on merge to main (S3 + CloudFront), behind feature flags |
| user-guide | `README.md` | web | Diataxis Markdown | markdownlint, link check, Vale | low tier | published with the release |
| tech-ops-manual | `docs/ops/tech/` | api, api-image, infra, ci-cd | Diataxis runbooks: deploy, rollback, one per alert, incident, on-call | link check; runbook commands dry-run where possible | domain-expert lens + 1 approval | updated in the same PR as the infra/API change (doc-code drift check) |
| business-ops-manual | `docs/ops/business/` | web, api | Diataxis: business processes, support playbooks, admin procedures | markdownlint, Vale (plain language) | domain-expert + new-user lenses + 1 approval | published with the release |
| stakeholder-docs | `docs/work/` | user-guide, tech-ops-manual, business-ops-manual | intent, spec, status; release notes from Conventional Commits | link check | part of the gates they record | release notes on deploy |

## Review

Policy: `REVIEW.md` (copied into `AGENTS.md` and `.cursor/BUGBOT.md`). Noise controls: max 5 nits, verify before reporting, skip what tools enforce, conventional comments, max 3 rounds.

| Artifact | Venue | Reviewers | Findings live in | Blocking |
|---|---|---|---|---|
| intent | tracker | persona lenses (silent); team-member (not the driver) | approval label/comment on the GitHub epic; intent.md committed | human gate on the epic |
| design | tracker | fresh-context reviewer subagent + persona lenses; team-member (not the driver) | AI findings resolved in spec.md 'Review log' and one summary comment on the epic; human approval on the epic | human gate on the epic; AI review is advisory |
| plan | local | fresh-context plan reviewer subagent | plan.md 'Review log'; engineer notified with the plan link | automated gate: AI review must report no blocking findings; escalates to the team for high-risk plans |
| validate | local | typecheck, tests, diff-guard, ticket verify command | progress.md evidence | automated build gate; no AI or human review by default |
| code | pr | scripts/sdlc/pr-checks.sh (check-loop, protected paths, diff-guard, tier label) run by /charmander-review; persona lenses (context-less, deduped); team-member (not the driver) | lens findings in reviews/ ledger and one summary comment on the PR; resolved threads | approvals per PR tier via branch protection/rulesets; this approval is the deploy gate (merge to main deploys); AI reviewers never approve or block |
| release | pr | CD pipeline on merge to main: health checks, rollback | CD run on main | none beyond the approved PR; outside approvals are post-merge and out of scope |
| improve | pr | local reviewer subagent; team-member (not the driver) | harness PR with before/after eval results | review phase gate (approvals per PR tier) |

AI reviewers comment and never approve. The merge gate is the PR tier's human approvals, after `pr-checks.sh` passes.

### PR tiers

PRs live on GitHub; Open the PR first, as ready for review, then run the reviews on it. `scripts/sdlc/pr-tier.sh` computes the tier from the changed files (highest tier wins) and `pr-checks.sh` fails when the `tier:` label understates it.

| Tier | Matches | Humans | AI | Extra lenses |
|---|---|---|---|---|
   | critical | `infra/**`, `.github/workflows/**`, `backend/**/serialization/**`, `backend/src/main/resources/db/**`, `api/openapi.yaml`, `backend/Dockerfile`, `backend/**/auth/**`, `frontend/src/**/auth/**` | 2 (team-member (not the driver)) | lenses | security, sre, data-integrity, backward-compat |
   | standard | (default) | 1 (team-member (not the driver)) | lenses | — |
   | low | `docs/ops/**`, `docs/work/**`, `docs/decisions/**`, `README.md`, `GLOSSARY.md` | 1 (any team member) | none | — |

## Skills per phase

| Phase | Skills | Notes |
|---|---|---|
| intent | `/grill-with-docs`, `/domain-modeling` | mattpocock |
| design | `/to-spec` | mattpocock |
| plan | `/to-tickets` | mattpocock |
| build | `/tdd`, `/diagnosing-bugs`, `/codebase-design` | mattpocock |
| review | `/code-review`, `/pr` | mattpocock |
| ship | `/wizard` | mattpocock |
| improve | `/retro`, `/handoff`, `/improve-codebase-architecture` | mattpocock |

Cross-cutting: `typescript-lsp`, `metals-mcp`, `context7`, `playwright`, `github`, `terraform`, `security-guidance`

## Rules and enforcement

| Rule | Scope | Standard | Enforced by |
|---|---|---|---|
| commits | global | Conventional Commits 1.0.0 | commit-msg hook |
| commands | global | run everything through the root justfile (just test, just test-single, just lint, ...) | AGENTS.md |
| scala | global | Scala 3 LTS; scalafmt + scalafix; -Werror; no null/var/return; never block inside actors or streams | pre-commit + Stop check (just lint, just typecheck); scoped rule |
| typescript | global | strict tsconfig, no any; ESLint flat config + Prettier; tsc --noEmit | lint-staged + Stop check typecheck |
| terraform-style | infra | HashiCorp style; snake_case; main/variables/outputs/versions.tf | terraform fmt, tflint, checkov |
| actions-security | ci-cd | pin actions by SHA; minimal permissions; no pull_request_target with PR checkout | actionlint + zizmor |
| openapi | api-contract | OpenAPI 3.1; breaking change needs ADR + version | Redocly lint + oasdiff in pr-checks.sh |
| containers | api-image | multi-stage, base pinned by digest, non-root | hadolint + Trivy |
| accessibility | web | WCAG 2.2 AA; axe in E2E | playwright + @axe-core |
| decisions | adr | MADR 4.0 | markdownlint |
| docs | user-guide | Diataxis | markdownlint + Vale |
| docs | tech-ops-manual | Diataxis how-to runbooks | markdownlint + doc-code drift check |
| docs | business-ops-manual | Diataxis; plain language | markdownlint + Vale |
| backend | `backend/**` | Scala 3 + Pekko typed actors. Never block inside actors or streams. Run just test-single <spec> while iterating. | nested AGENTS.md; scalafmt/scalafix |
| core-data-driven-tests | `backend/core/**` | Domain core. Every behaviour change ships a table-driven ScalaTest (TableDrivenPropertyChecks) covering the cases. | pr-checks.sh fails when backend/core/src/main changes without backend/core/src/test; test-quality lens |
| persisted-events | `backend/**/serialization/**` | Persisted events are forever: add a new event version and an event adapter; never change or remove a persisted field; never edit existing golden fixtures. | protect-paths hook on existing fixtures; golden fixture test |
| journal-migrations | `backend/src/main/resources/db/**` | Append-only. Never edit an applied journal script; add a new one. | protect-paths hook blocks edits to existing files |
| api-contract | `api/openapi.yaml` | Contract-first: change the contract before the code. Breaking changes need an ADR and a version bump. | Redocly + oasdiff in pr-checks.sh |
| frontend | `frontend/**` | TypeScript strict, no any. Import the API only through the generated client. | nested AGENTS.md; ESLint + tsc |
| generated-client | `frontend/src/api/gen/**` | Generated. Regenerate with just gen-client; never hand-edit. | protect-paths hook; regenerate-and-diff check |
| infra | `infra/**` | Plan, never apply. Attach terraform plan output to the PR. | permissions deny terraform apply; tflint + checkov |
| workflows | `.github/workflows/**` | Pin actions by SHA; least-privilege permissions. | actionlint + zizmor |
| secrets | `.env*`, `**/*.pem`, `**/*.key` | Never read, print or commit (.env.example is fine). | protect-paths hook |
| lockfiles | `pnpm-lock.yaml` | Change only through pnpm. | protect-paths hook; diff-guard lockfile check |
| decisions | `docs/decisions/**` | ADRs are superseded, never rewritten. | protect-paths hook on accepted ADRs; review |

Must-hold rules are checks (git hooks, Claude hooks, `pr-checks.sh`, and CI only where the team opted in), not prose. Preferences live in `AGENTS.md`, scoped rules and skills.

## Guardrails (failure modes)

| Failure mode | Phases | Mitigation | Enforced by | Deterministic |
|---|---|---|---|---|
| test-tampering: Agent skips, deletes or weakens tests to go green | build | Block skipped/deleted tests and net assertion loss unless a human approves (ScalaTest ignore/pending, Vitest .skip/.only) | diff-guard.sh in the Stop hook, the pre-commit hook and pr-checks.sh | yes |
| premature-completion: Agent declares done without verifying | build | Exit criteria per phase; Stop hook runs typecheck + tests; validation evidence required before the PR | stop-check.sh + PR template | yes |
| scope-creep: Unrequested changes and giant diffs | plan, build | plan.md names files; one ticket per session; warn above 400 changed lines / 30 files | diff-guard.sh --max-lines 400 --max-files 30 --size warn | yes |
| nit-flood: Reviewer floods the PR with nits; real issues get lost | design, review | Cap nits at 5; review for correctness and spec gaps only; skip what linters enforce | REVIEW.md + reviewer prompt + dedupe-findings.py; one summary comment updated in place | no |
| self-approval: Authoring agent (or a lenient evaluator) approves its own work | design, review, ship | Fresh-context reviewer; AI never approves; approver is a team member other than the driver, via branch protection/rulesets | branch protection or rulesets; validator requires a human gate on the review phase and a human approval in every PR tier | yes |
| hallucinated-deps: Invented packages or APIs (slopsquatting) | build | New dependencies must exist in their registry; typecheck catches fake APIs | diff-guard.sh --check-registry in pr-checks.sh (review phase) | yes |
| runaway: Unbounded loops and cost in unattended runs | build | 120 turns, $25 budget, 3 failed validations; Stop-hook block cap 3 | loops.autonomy.limits; stop-check.sh --max-blocks 3 | yes |
| secret-leak: Secrets read, printed or committed | build | Block reads of .env (not .env.example); secret scanning (forge setting or the existing CI) | protect-paths.sh (protect: read); permissions.deny | yes |
| event-schema-break: A persisted Pekko event changes shape and old journals no longer replay | design, build, review | Golden fixtures for every past event version; append-only serialization folder | golden fixture test in just test; protect-paths hook | yes |
| silent-errors: Swallowed Future failures, empty catches, missing actor supervision hide failures | build, review | No swallowed failures; explicit supervision; validate only at boundaries | silent-failure lens + scalafix rules | no |
| doc-drift: Ops manuals go stale when infra or API changes | build, review | Infra/API change must touch docs/ops/tech/ in the same PR | doc-code drift check in pr-checks.sh | yes |
| unreviewed-dep-bump: Lockfile changes without a manifest change | build | Flag lockfile-only diffs | diff-guard.sh lockfile check | yes |
| review-loop: Agent and reviewer ping-pong forever | review | Max 3 review rounds, then escalate to a human | REVIEW.md + loops.autonomy | no |
| instruction-bloat: Long instructions get ignored | improve | Root AGENTS.md <= 200 lines; scoped rules and nested AGENTS.md | check-loop.sh | yes |

## Context strategy

- Strategies: subagents-for-research-and-review, progressive-disclosure, front-loaded-lead-lines, scripts-over-reasoning, lean-root-instructions, nested-agents-md, fresh-session-per-phase, doc-graph, repo-map, lsp-code-intelligence, read-deny-noise.
- Instructions: lean root `AGENTS.md`; nested `backend/AGENTS.md`, `frontend/AGENTS.md`, `infra/AGENTS.md`.
- Code graph: typescript-lsp + Metals MCP + docs/sdlc/REPO_MAP.md (repo-map.sh); no semantic graph. Doc graph: `docs/sdlc/MAP.md`.
- Read-deny: `**/target/**`, `frontend/dist/**`, `**/node_modules/**`, `frontend/src/api/gen/**`, `infra/.terraform/**`.
- State files: `docs/work/<slug>/progress.md`, `docs/work/<slug>/tickets.json`.

## Where things live

| What | Where |
|---|---|
| Canonical instructions | `AGENTS.md` (Claude reads it via `CLAUDE.md` → `@AGENTS.md`) |
| Canonical skills | `.agents/skills/` (Codex, Cursor) ← symlinked into `.claude/skills/` |
| Canonical scoped rules | `.agents/rules/` → `.claude/rules/`, `.cursor/rules/`, nested `AGENTS.md` |
| Sync and health | `scripts/sdlc/sync-agent-files.sh`, `scripts/sdlc/check-loop.sh` |
| Work items | `docs/work/<yyyy-mm-dd>-<slug>/` |
| Decisions | `docs/decisions/` |
| Research notes | `docs/sdlc/research/` |

## Sources

- docs/research/04-review-interaction-and-failure-modes.md
- docs/research/05-persona-review.md
- docs/research/07-pr-venues-and-tiering.md
- https://claude.com/resources/articles/the-ai-native-sdlc-playbook
- https://code.claude.com/docs/en/best-practices
- https://github.com/google-research/harness2
- https://github.com/google/elephant-goldfish-model
- https://github.com/google/eng-practices/blob/master/review/developer/small-cls.md
- https://github.com/mattpocock/skills/blob/main/skills/engineering/to-tickets/SKILL.md
- https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents
- https://www.anthropic.com/engineering/harness-design-long-running-apps
- outside approvals (security, architecture, demo, CAB) happen post-merge and are out of scope (user)
- propose.py
- setup-sdlc-context/references/strategies.md
- setup-sdlc-deliverables/references/deliverables.md
- setup-sdlc-discover/references/notable-folders.md
- setup-sdlc-evals
- setup-sdlc-guardrails/references/failure-modes.md
- setup-sdlc-loops/references/interaction.md#unattended-runs
- setup-sdlc-loops/references/upstream.md
- setup-sdlc-review/references/venues.md
- setup-sdlc-review/references/venues.md#pr-tiers
- setup-sdlc-rules/references/standards.md
- setup-sdlc-skills/references/catalog.md
