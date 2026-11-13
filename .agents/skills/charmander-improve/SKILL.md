---
name: charmander-improve
description: Improve phase. Turn signals, incidents and session lessons into classified findings (product, phase, harness, convention, code-part convention or no-op) and ship the smallest evidence-backed change for each, with research and evals. Modes: retro, incident, tune, scan. Use after a work item ships, after an incident, on the weekly signals report, or after a model or tool upgrade.
disable-model-invocation: true
---

# Improve phase (the meta-loop)

**Mode:** `$ARGUMENTS` if given (`retro <slug>`, `incident <ref>`, `tune <topic>`, `scan`); otherwise ask, recommending `retro` for the most recently shipped work item.
**Output:** `docs/sdlc/improve/<yyyy-mm-dd>-<slug>.md` from `docs/sdlc/templates/improve.md`.
**Gate:** automated: product findings become intents (they pass the intent gate); harness changes ship as PRs (they pass the review phase gate); eval suite passes before and after a harness change; notify team.
**Exit:** every finding is classified and dispositioned; every change is open as a PR at its canonical source, with before/after eval evidence.

## Steps

1. **Gather evidence before asking.** Run `bash scripts/sdlc/sdlc-signals.sh` (add `--since <date>` for the window). Read the mode's inputs listed in [references/modes.md](references/modes.md). Draft findings, each with its evidence (a file, PR thread, log line or metric). Describe the system, never a person.
2. **Interview the human (frontier style).** Present the draft findings with a recommended disposition each, at most 4 per round; "yes" accepts. Ask what hurt that the signals missed. The human decides; you propose.
3. **Classify every finding.** Read [references/change-classes.md](references/change-classes.md) and ask its questions in order: product → phase → harness → convention → code-part convention → no-op. The first "yes" wins. Record the class, the canonical source to change and the enforcement you'll use.
4. **Research before changing the loop.** For each phase, harness or convention finding, dispatch the `researcher` subagent with the finding, its evidence and the current rule, primary sources only. It writes `docs/sdlc/research/<topic>.md` and returns 1–3 options. Adopt new skills, reviewers or strategies in shadow mode first. Skip research for product findings and obvious one-line fixes.
5. **Make the smallest effective change at the canonical source,** deterministic first: a check or hook → a scoped rule → one line in an always-loaded file. Product findings become new intents via `/charmander-intent`. Remove instructions and checks that never fire or that duplicate a check.
6. **Promote to a harness scenario?** (retro only) Add this work item to `docs/sdlc/evals/evals.json` as a scenario only when (a) it exposed a loop problem, so the scenario guards the fix, or (b) it is the first of a kind of work the suite doesn't cover (first UI change, first migration, first AI feature). Write it as a prompt plus `checks` first, `assertions` only for what a check can't see. The suite is capped at 12 scenarios: over the cap, propose retiring the oldest scenario that always passes, and let the human decide.
7. **Verify.**
   - Before and after any phase, harness or convention change, run `bash scripts/sdlc/run-evals.sh --suite harness --ref <base>` and then `--ref HEAD`, and record both summaries. The harness PR then runs them again in `/charmander-review`, where the change's files trigger the suite.
   - Run `bash scripts/sdlc/sync-agent-files.sh` and `bash scripts/sdlc/check-loop.sh`.
   - For a new hook, smoke-test that it blocks what it should.
8. ****Run the automated gate.** Check: product findings become intents (they pass the intent gate); harness changes ship as PRs (they pass the review phase gate); eval suite passes before and after a harness change. If all pass and no escalation condition holds, set `Status: approved (automated: <checks>)`, notify team, and continue in a fresh session. If any check fails or can't run, or an escalation condition holds, stop and ask the team.** Proposals that remove a guardrail or a human gate always need a human at the review phase gate.

Done when the findings file lists every finding with its evidence, class, change (or no-op reason) and verification; check-loop is healthy; and each change is open as a PR or a new intent.

## Local notes

<!-- Team additions. Regeneration keeps this section. -->
