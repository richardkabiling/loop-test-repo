# Change classes

Read this in improve step 3. Ask the questions in order; the first "yes" wins. Then change only the canonical source; generated copies follow via the sync script.

| # | Question | Class | Canonical source | Then run | Prefer | Verify |
|---|---|---|---|---|---|---|
| 1 | Is it about *what the product should do*? | **product** | new `docs/work/<yyyy-mm-dd>-<slug>/intent.md` | `/charmander-intent` | the intent gate | the normal loop |
| 2 | Is it about *the loop's shape*: a phase or subphase added, removed or merged; a gate's type or owner; a strategy, interaction, autonomy level, review venue or exit criterion? | **phase** | `docs/sdlc/loop.json` (`loops`, `review`) | `/setup-sdlc-scaffold` to regenerate phase skills, LOOP.md and REVIEW.md | a validator-checked field | `python3 scripts/sdlc/validate-loop.py docs/sdlc/loop.json`; evals |
| 3 | Is it about *the machinery*: a hook, script, CI job, skill or subagent, settings, MCP server, guardrail knob, or a missing deterministic check? | **harness** | `.agents/skills/…`, `scripts/sdlc/…`, `.claude/settings.json`, `.github/workflows/…`, `loop.json` `guardrails` / `context` | `sync-agent-files.sh` | a deterministic check or hook | evals before and after; hook smoke test; `check-loop.sh` |
| 4 | Is it a *rule for the whole repo*: a coding convention, commit or versioning rule, review policy, or deliverable standard? | **convention** | linter or formatter config; `REVIEW.md`; `loop.json` `rules.global` / `rules.per_deliverable` → `AGENTS.md` managed block | `sync-agent-files.sh` | config/CI check > `REVIEW.md` > one AGENTS.md line | lint/CI green; AGENTS.md within budget |
| 5 | Is it a *rule for one part of the code*: a folder, package, generated or migration dir, or public API surface? | **code-part convention** | `.agents/rules/<name>.md` (`paths:` globs; `protect: true / existing / read` to enforce) | `sync-agent-files.sh` | `protect-paths.sh` or a scoped linter > scoped rule text | `sync-agent-files.sh --check`; the glob matches files; hook smoke test |
| 6 | Not worth its cost, or a one-off? | **no-op** | the findings file, with the reason | — | — | — |

## Choosing between neighbours

- **Rule vs harness:** if the rule must always hold, the fix is a harness change (a hook or check), and the rule text becomes a one-line pointer to it.
- **Convention vs code-part convention:** if the rule applies to fewer than all deliverables or folders, scope it. Always-loaded lines are the most expensive context there is.
- **Phase vs harness:** changing *when* or *whether* something happens (a gate, a subphase, an autonomy level) is a phase change. Changing *how* it is checked is a harness change.
- **Repeated product bugs of one kind** (e.g. missing loading states) are often a convention or design-subphase change, plus a product intent for the instances already shipped.
