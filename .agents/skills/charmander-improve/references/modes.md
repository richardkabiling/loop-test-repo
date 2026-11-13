# Improve modes

Read this in improve step 1 for the inputs of the chosen mode.

| Mode | When | Read | Also |
|---|---|---|---|
| `retro <slug>` | a work item shipped | `docs/work/<slug>/` (`progress.md`, `tickets.json`, the review log in `spec.md`); its PRs' review threads; diff-guard and stop-check failures in CI logs; time spent at each gate | Note overrides used (e.g. the `test-change-approved` label) and why. Decide whether to promote the item to a harness scenario (SKILL.md step 6) |
| `incident <ref>` | an incident or rollback | timeline, alerts, the causing PR, rollback logs | Blameless; add a **regression eval** to `docs/sdlc/evals/evals.json`; usually yields a harness or code-part convention change plus a product intent |
| `tune <topic>` | the same failure 3+ times, or a model/tool upgrade | eval results, session traces, the guardrails table in `docs/sdlc/LOOP.md` | Propose → Probe → Compose (Harness²): try a candidate change on the same eval tasks, keep what measurably helps. After upgrades, remove one component at a time to test whether it is still load-bearing |
| `scan` | on demand (`/charmander-improve scan`), or the weekly `sdlc-signals` workflow if the team opted into it | `sdlc-signals.sh` output: reverts, stuck gates, review rounds, override use, escalations of automated gates | Also run `detect-evals.sh`: unregistered suites or AI features without product evals are findings. Open a `retro` only when something crossed a threshold; otherwise record "no findings" |

Signals that point at a **gate**: automated gates escalating often, or problems slipping past them, mean the gate should be promoted to human (a phase change). A human gate that never rejects anything may be ready for automation; propose that only with evidence, and only a human can approve it.
