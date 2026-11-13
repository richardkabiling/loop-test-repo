# Persona review

How context-less persona reviews run at every review point. Phase skills point here; lens files live in `docs/sdlc/lenses/`. Generated from `docs/sdlc/loop.json` (`review.personas`).

## Review points and lenses

| Review point | Inputs the reviewers get (nothing else) | Lenses |
|---|---|---|
| intent | `intent.md` only | naive-reader, end-user, pre-mortem |
| design:requirements | `spec.md` | qa-test-designer, naive-reader, intent-conformance |
| design:solution | `design/solution.md` + `spec.md` | skeptical-architect, security, design-critic |
| design:api | `design/api.md` + `spec.md` | api-consumer, backward-compat |
| design:data | `design/data.md` + `spec.md` | data-integrity, migration-compat |
| design:infra | `design/infra.md` + `spec.md` | sre, security, finops |
| design:ux | `design/ux.md` + `spec.md` | target-user, accessibility |
| design:docs | `design/docs.md` + `spec.md` | new-user, structure-style, domain-expert |
| review | PR diff + `spec.md` + `REVIEW.md` | correctness, spec-conformance, test-quality, silent-failure |

## Protocol

1. **Context-less.** Each lens runs in its own fresh subagent: Claude Code `lens-reviewer` (read-only tools, no CLAUDE.md); in Codex or Cursor, a fresh agent or session. A reviewer gets **only** the inputs listed for its review point plus its lens file. It never gets this conversation, the interview, your reasoning or your notes. If your tool can't start a fresh subagent or session, skip the persona review and say so in the Review log; never review in your own context.
2. **Parallel.** Start all lenses for the review point at once. Each writes JSON-lines findings to `<work item>/reviews/<point>-r<round>-<lens>.jsonl`.
3. **Dedupe.** Run `python3 scripts/sdlc/dedupe-findings.py <work item>/reviews/<point>-r<round>-*.jsonl --ledger <work item>/reviews/ledger.jsonl --update-ledger --round <round> --point <point>`. It merges duplicates across lenses (agreement raises confidence), drops anything already resolved or dismissed in earlier rounds or by the PR bot, and returns the merged list.
4. **Route** each merged finding:

   | Finding | Intent and design | Review (the PR) |
   |---|---|---|
   | major, answerable from repo facts | fix the artifact yourself | back to red → green for that issue |
   | major, needs a human decision (preference, trade-off, evidence only they have) | ask it as your **next interview question** | fix if within spec; otherwise ask the tier's human approvers on the PR |
   | major, but you can refute it with evidence the reviewer couldn't see | record it as settled (`--close KEY --status dismissed --reason "<evidence>"`) | same |
   | minor | fix it, log it | fix it or record why not |
   | nit | drop, or fix if trivial | within the `REVIEW.md` nit cap |

5. **Surface** the findings as this review point's mode says:

   | Point | Mode | Where findings appear |
   |---|---|---|
   | intent | silent | handled in the interview; ledger only |
   | design | ticket | one summary comment on the GitHub epic |
   | review | pr | one summary comment on the code PR, majors inline |

   - `silent`: nothing is posted. Findings are handled automatically: fixed, dismissed with evidence, or asked as ordinary questions (step 6). The ledger is the only record.
   - `pr`: post `dedupe-findings.py --summary --title "Charmander review" --ledger … --point <point>` as **one comment** on the PR (the docs PR for intent and design, the code PR for review), and edit that same comment after every round. On a code PR, majors also get an inline comment at their `file:line`. Reply in the thread when a finding is fixed or dismissed.
   - `ticket`: post the same summary as one comment on the tracker item (the epic for intent and design, the ticket's issue for review), edited in place after every round.
   - `auto`: use the place the artifact already lives. Epic → `ticket`; docs PR or code PR → `pr`; files only → `silent`.

   Posting never replaces handling. Majors are still fixed or asked, and a posted finding is closed in the ledger before the summary is updated.
6. **Keep the review invisible in interviews (intent and design).** Whatever the surface mode, persona-derived questions join the normal frontier round and share its cap of 4. Use the interviewer's voice: a concrete scenario, one decision, and a recommended answer in prose: *"If the import fails halfway through a 10k-row file, what should the user see? I'd suggest keeping the rows that succeeded and offering a download of the failed ones, because re-uploading everything is what users complain about."* Never mention reviewers, lenses, findings, severity or rounds.
7. **Close** each handled finding: `dedupe-findings.py --close <key> --status resolved --ledger …`.
8. **Stop.**
   - Intent and design: stop when a fresh round has no major findings, or after 2 rounds. Remaining majors become owned open questions.
   - Review (and build, if it runs lenses locally): stop when a fresh round has no major findings, or after 3 rounds. Remaining majors go to the tier's human approvers, listed in the PR summary comment.
9. **Log.** The `reviews/` folder is the audit trail for the gate approver and `/charmander-improve`. With `silent`, the user sees it only if they ask.

## Severity

- **major** at intent and design: it blocks acceptance (untestable or unobservable), contradicts a stated constraint, decision or the code, leaves a risk with no owner, lets two reasonable readers build different things, or targets the wrong problem or scope.
- **major** at review: a bug or gap that should be fixed before merging (wrong behaviour, a missing acceptance criterion, a security hole, a test that can't catch the regression).
- **minor:** should be fixed but doesn't change a decision. **nit:** wording, style, nice-to-have.

Sources:
- Elephant-Goldfish Model (fresh reviewers; Blocker/Major/Nit; contest/escalate/fix/decline; stop on clean rounds): <https://github.com/google/elephant-goldfish-model>.
- Narrow reviewers that must prove their findings: <https://claude.com/resources/articles/how-anthropic-secures-its-ai-native-software-development-lifecycle>.
- Lenses as checklists rather than character play: `docs/research/05-persona-review.md` in the sdlc-loop plugin.
