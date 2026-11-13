---
name: charmander-intent
description: Intent phase. Turn an idea, request or signal into an approved intent.md by interviewing the originator (problem, outcome, users, constraints, open questions). Use to start any new piece of work.
disable-model-invocation: true
---

# Intent phase

**Output:** `intent.md` from `docs/sdlc/templates/intent.md`, stored as [references/store.md](references/store.md) says (epic).
**Gate:** human: team-member (not the driver) approves via 'intent-approved' label or approval comment on the epic by any team member except the work item's driver.
**Exit:** Problem, outcome, affected users and systems, constraints and open questions all filled; PO approved

## Steps

0. **Where it lives.** Read [references/store.md](references/store.md). It says where intent is stored, how the gate is recorded, and how the interview runs (solo).
1. **Explore first.** Read `docs/sdlc/MAP.md`, the glossary and relevant ADRs. Search the code and tracker for prior art (use a subagent for broad sweeps). Facts you can find yourself are never questions.
2. **Interview (grilling).** Ask the frontier of open decisions, at most 4 per round, each with a recommended answer the user can accept with "yes". With team grilling, post the frontier where `references/store.md` says and resume when answers arrive. Ask the human only about intent, priorities and trade-offs. Use `/grill-with-docs`, `/domain-modeling`.
3. **Draft** `intent.md`: problem (with evidence), proposed outcome (observable; when AI behaviour is part of it, a measurable quality bar: what good looks like and what must never happen), affected users and systems, constraints, open questions (each with an owner). No solution design.
4. **Persona review, then close the gaps.** Run the context-less persona review for the `intent` review point as `docs/sdlc/personas.md` describes. Ask the major issues it surfaces as your next interview questions, in the same frontier style with a recommended answer each; to the user (or the team, in the posted checklist) they are simply the next questions. Fix minor issues directly. Surface the findings as `personas.md` says for `intent` (silent). Repeat until no major issues remain, or 2 rounds. Then close the remaining open questions with the user, or assign each to a named person.
5. **Hand off to the gate.** Sync the work-item files to the GitHub epic, commit them on the work branch, say who must approve (team-member (not the driver)) and how ('intent-approved' label or approval comment on the epic by any team member except the work item's driver), and stop. The approver sets `Status: approved`. (Tracker flow: GitHub Issues via `gh`: epics are parent issues (`epic` label, `intent-approved` / `design-approved` gate labels), tickets are sub-issues; agent-ready label `ready-for-agent`..)

Done when every section is filled, no open question is unowned, and the gate has been requested (human) or passed (automated). The spec phase starts in a fresh session.

## Local notes

<!-- Team additions. Regeneration keeps this section. -->
