# Review guide

The single review policy for this repo. Claude Code Review reads this file directly. `scripts/sdlc/sync-agent-files.sh` copies the core section into `AGENTS.md` (`## Review guidelines`, read by Codex review and local `/code-review`) and the whole file into `.cursor/BUGBOT.md`. Edit only this file.

<!-- sdlc:review-core -->
Review against the spec and this repo's standards, not personal taste. Report only issues **introduced by this change**. "No blocking findings" is a valid, welcome result.

- **Important** (blocking; Codex P0–P1; `issue (blocking)`): breaks an acceptance criterion, loses or corrupts data (including a persisted Pekko event that no longer replays), opens a security hole, breaks the public OpenAPI contract, or deploys something unsafe on merge to main
- **Nit** (non-blocking; P2–P3; `nitpick (non-blocking)`): report **at most 5 nits per review**, and summarize the rest as a count.
- **Pre-existing** (`note (non-blocking)`): label it and never block on it.
- **Evidence**: every behaviour claim cites `file:line`, a failing command, or a spec clause. Cross-file impact must name the affected code. Verify before you report.
- **Do not report**: anything CI already enforces (scalafmt, scalafix, the Scala compiler (-Werror), ESLint, Prettier, tsc, tflint, checkov, actionlint, zizmor, hadolint, markdownlint, Vale), generated files, lockfiles, vendored code.
- AI reviewers comment; they never approve or block. Approvals follow the PR's tier (critical: 2, standard: 1, low: 1; never the work item's driver); every conversation must be resolved. This approval is the deploy gate: merge to main deploys.
<!-- /sdlc:review-core -->

## What Important means here

- **Persisted events**: any change to an existing event's fields or serializer, or an edited golden fixture.
- **Contract**: a breaking change to `api/openapi.yaml` without an ADR and version bump (`oasdiff` says breaking).
- **Deploys**: merge to main runs Terraform apply, image push and app deploys, so infra, IAM, network and CI changes are Important when wrong.
- **Core**: behaviour changes in `backend/core/` without a table-driven test.
- **Ops docs**: an infra or API change that leaves `docs/ops/tech/` stale.
- **Silent failures**: swallowed `Future` failures, empty catches, missing actor supervision.

## Always check

1. **Spec**: does the change do what `docs/work/<slug>/spec.md` and its acceptance criteria say, and nothing outside its scope?
2. **Tests**: is new behaviour covered at the seam named in the spec? Were tests skipped, deleted or weakened? (`diff-guard.sh` flags these.)
3. **Evidence**: does the PR show the commands run, their output, and screenshots for UI?
4. **Risk**: security (OWASP Top 10), data loss, migrations, public API or semver impact, secrets.
5. **Drift**: if behaviour changed, were `spec.md`, `plan.md` and the docs updated in the same PR?
6. **adr** (`docs/decisions/`): 1 approval (team member, not the driver); tests: markdownlint + link check.
6. **infra** (`infra/ (AWS)`): critical tier; plan output attached to the PR; tests: terraform fmt -check, validate, tflint, checkov, terraform test.
6. **ci-cd** (`.github/workflows/`): critical tier; tests: actionlint + zizmor.
6. **db-schema** (`backend/src/main/resources/db/; backend/**/serialization/`): critical tier + data-integrity and migration-compat lenses; tests: golden fixtures of every past event version must deserialize; journal replay against Testcontainers Postgres.
6. **api-contract** (`api/openapi.yaml`): critical tier; breaking change needs an ADR and a version bump; tests: Redocly lint + oasdiff breaking-change check.
6. **api** (`backend/`): persona lenses + 1 approval; tests: ScalaTest table-driven tests (required in backend/core/), ScalaCheck properties, ActorTestKit, Testcontainers Postgres integration, contract test against api/openapi.yaml.
6. **api-image** (`backend/Dockerfile (or sbt-native-packager)`): critical tier; tests: hadolint, Trivy, container smoke test.
6. **web** (`frontend/`): screenshots in the PR + persona lenses + 1 approval; tests: testing trophy: Vitest + Testing Library, Playwright E2E with toHaveScreenshot, axe (WCAG 2.2 AA).
6. **user-guide** (`README.md`): low tier; tests: markdownlint, link check, Vale.
6. **tech-ops-manual** (`docs/ops/tech/`): domain-expert lens + 1 approval; tests: link check; runbook commands dry-run where possible.
6. **business-ops-manual** (`docs/ops/business/`): domain-expert + new-user lenses + 1 approval; tests: markdownlint, Vale (plain language).
6. **stakeholder-docs** (`docs/work/`): part of the gates they record; tests: link check.

## Cap the nits

Report at most 5 nits per review. If you found more, write "and N more nits not listed".

## Do not report

- Formatting, lint and type issues that CI enforces: scalafmt, scalafix, the Scala compiler (-Werror), ESLint, Prettier, tsc, tflint, checkov, actionlint, zizmor, hadolint, markdownlint, Vale.
- Anything in generated or vendored paths: `**/target/**`, `frontend/dist/**`, `**/node_modules/**`, `frontend/src/api/gen/**`, `infra/.terraform/**`.
- Lockfile contents, snapshot files.
- Style preferences not written down in this repo's standards.

## Process

- **Venue:** persona lenses run locally as fresh subagents; one summary comment on the PR, majors inline at file:line; resolved in PR threads.
- **Rounds:** after 3 review rounds on the same PR, stop and ask a human to decide.
- **Format:** findings ranked by severity, each with location, problem, evidence and a concrete fix. End with `verdict: no blocking findings` or `verdict: N blocking findings`.
- **Humans:** prefix optional comments with `Nit:`, `Optional:` or `FYI:`; respond within one business day.
