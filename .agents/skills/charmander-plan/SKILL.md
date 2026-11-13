---
name: charmander-plan
description: Plan phase. Turn an approved spec.md into plan.md (files, order, risks, proof) and tracer-bullet tickets with blocking edges, approved by an engineer. Use after the spec gate passes.
disable-model-invocation: true
---

# Plan phase

**Input:** an approved `spec.md` (read `.agents/skills/charmander-intent/references/store.md` for where it lives). **Output:** `plan.md` and `tickets.json` beside it, plus tracker tickets (GitHub sub-issues of the epic). Build-validate and review then run once per ticket.
**Gate:** automated: plan.md has Files / Order / Risks / Proof; every acceptance criterion maps to a ticket with a verify command; fresh-context AI plan review: no blocking findings; notify driver; escalate to team when the plan touches infra, ci or migrations, or the AI review reports blocking findings.
**Exit:** plan.md has Files / Order / Risks / Proof; every ticket fits one context window and lists its blockers

## Steps

1. **Plan mode.** Read the spec and the code it touches without editing anything (Claude Code: plan mode). Use a subagent to map unfamiliar areas.
2. **Write `plan.md`:** Files that change (grouped by deliverable), Order of work, Risks (with mitigations: flags, expand–contract, rollback), Proof (maps every acceptance criterion to a check).
3. **Order by deliverable dependencies:** adr → infra → ci-cd → db-schema → api-contract → api → api-image → web → user-guide → tech-ops-manual → business-ops-manual → stakeholder-docs. A slice that touches a later deliverable is blocked by its earlier ones.
4. **Slice tickets (plan-mode-then-tracer-tickets).** Tracer-bullet vertical slices: each demoable, each sized for one fresh context window, each with `blocked_by`, its acceptance criteria and a `verify` command. Write them to `tickets.json` (all `"passes": false`). Use `/to-tickets`.
5. **Eval cases.** Map every row of the spec's **Eval cases** to the ticket that builds the behaviour; that ticket's acceptance criteria include adding those cases to the named product suite (a new suite is registered in `docs/sdlc/loop.json`). If a ticket changes model calls, prompts or agent behaviour and the spec has no eval cases, stop: that's a design gap, back to `/charmander-design`.
6. **Label** the agent-ready tickets `ready-for-agent` and the rest `ready-for-human`. With a human gate, quiz the engineer on granularity and edges first.
7. **Run the automated gate.** Check: plan.md has Files / Order / Risks / Proof; every acceptance criterion maps to a ticket with a verify command; fresh-context AI plan review: no blocking findings. If all pass and no escalation condition holds, set `Status: approved (automated: <checks>)`, notify driver, and continue in a fresh session. If any check fails or can't run, or an escalation condition holds (the plan touches infra, ci or migrations, or the AI review reports blocking findings), stop and ask team.

Done when every acceptance criterion maps to at least one ticket, every ticket has a verify command and its blockers, and the gate has passed (automated) or been approved (human).

## Local notes

<!-- Team additions. Regeneration keeps this section. -->
