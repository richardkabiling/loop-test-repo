---
name: charmander-design
description: Design phase. Turn an approved intent.md into spec.md (requirements with EARS acceptance criteria) plus the design subphases this work item needs (requirements, solution, api, data, infra, ux, docs), each reviewed by fresh-context personas, then the design gate. Use after the intent gate passes.
disable-model-invocation: true
---

# Design phase

**Input:** an approved `intent.md`. If it isn't approved, stop and say so.
**Output:** `spec.md` plus `design/<subphase>.md` for each selected subphase, beside the intent and stored as `.agents/skills/charmander-intent/references/store.md` says (epic).
**Gate:** human: team-member (not the driver) approves via 'design-approved' label or approval comment on the epic by any team member except the work item's driver.
**Exit:** EARS acceptance criteria; concerns flagged and resolved; fresh-context review passed

## Steps

1. **Read** `.agents/skills/charmander-intent/references/store.md` (where design lives, how the team answers, how the gate is recorded), then the intent, `docs/sdlc/MAP.md`, the deliverables table in `docs/sdlc/LOOP.md`, the relevant ADRs and the glossary. Start from the files, not chat history.
2. **Select subphases.** `requirements` always runs. Pick the others from which deliverables this work item touches:

   | Subphase | Run when | Artifact | Method |
   |---|---|---|---|
   | requirements | always | `spec.md` | inline, in the design steps (EARS acceptance criteria, testing seams, flagged concerns) |
   | solution | new component or service, crosses deliverables, changes a boundary, or needs an ADR; includes a STRIDE threat model when a change crosses a trust boundary (public API, IAM, data store) | `design/solution.md + docs/decisions/ ADR + threat model section` | references/solution.md (C4 context/container views, key flows, MADR decisions, quality attributes, STRIDE threat model at trust boundaries) |
   | api | changes api/openapi.yaml or the backend's HTTP surface | `design/api.md + OpenAPI diff` | references/api.md (contract-first in api/openapi.yaml, error model, compatibility classification, examples → contract tests) |
   | data | changes persisted Pekko events, serializers or the journal schema | `design/data.md` | references/data.md (Pekko event versioning, event adapters, golden fixtures, journal DDL, invariants) |
   | infra | changes infra/ (Terraform, AWS) or the backend container image; includes a STRIDE threat model for IAM/network changes | `design/infra.md` | references/infra.md (AWS resources, topology, SLOs, least-privilege IAM, cost, rollout, STRIDE for IAM/network) |
   | ux | touches frontend/ UI | `design/ux.md` | references/ux.md (flows, every screen state, content, WCAG 2.2 AA) |
   | docs | touches user-guide, tech-ops-manual or business-ops-manual | `design/docs.md` | references/docs.md (readers, Diátaxis placement, outlines, testable examples) |

   Tell the user your selection in one line, with the reason for each, e.g. "requirements + solution + ux, because it adds a screen and a new service". "Yes" accepts. Solution design runs first when selected; the others follow and can run in parallel subagents.
3. **Requirements → `spec.md`** (synthesize-then-goldfish-review). Synthesize from the intent without re-interviewing: problem, solution, user stories, **EARS acceptance criteria** (`WHEN … THE SYSTEM SHALL …`, one testable line each), testing decisions (the seam per criterion), **eval cases** when the intent has a quality bar (typical, edge and adversarial inputs with expected properties, grading, a threshold traced to the bar, and the product suite they belong to: `bash scripts/sdlc/detect-evals.sh` lists suites), flagged concerns (security, compliance, UX, ops, each with an owner), and out of scope. Use `/to-spec`.
4. **Each selected subphase → `design/<subphase>.md`.** Read the matching `references/<subphase>.md` (only for the subphases you selected) and follow it. Every design artifact traces back to acceptance criteria. Decisions that are hard to reverse become ADRs in `docs/decisions/`.
5. **Persona review, per artifact.** Run the review the way `docs/sdlc/personas.md` describes for this review point (`design:<subphase>`). Fold the results in as that file says: major issues become your next interview questions, minor issues are fixed and logged. Surface them as it says for `design` (ticket → the GitHub epic). Repeat until no major issues remain, or 2 rounds. Record the outcome in the spec's Review log. Venue: GitHub epic (one summary comment) + committed files
6. **Cross-check.** Every acceptance criterion is covered by the subphase artifacts that need it; subphases don't contradict each other; open questions have owners.
7. **Hand off to the gate.** Sync the work-item files to the GitHub epic, commit them on the work branch, say who must approve (team-member (not the driver)) and how ('design-approved' label or approval comment on the epic by any team member except the work item's driver), and stop. The approver sets `Status: approved`. Approvers by subphase: requirements: team-member; solution: team-member; api: team-member; data: team-member; infra: team-member; ux: team-member; docs: team-member (any team member except the driver).

Done when every acceptance criterion is testable and traced, every selected subphase artifact exists with no open major issues, the Review log is closed, and the gate has been requested (human) or passed (automated).

## Local notes

<!-- Team additions. Regeneration keeps this section. -->
