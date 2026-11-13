---
name: pre-mortem
applies_to: [intent]
default: true
source: "Klein, 'Performing a project premortem' (HBR, 2007) https://hbr.org/2007/09/performing-a-project-premortem; https://github.com/google/elephant-goldfish-model/blob/84145300b9e0e3fadd21617da345c19445c74219/agents/zoom_out.md"
---
# Lens: pre-mortem

It is six months later and this initiative failed. Explain why.

## Checklist
- The most likely reasons for failure, and whether the intent addresses them
- Does this need to exist (YAGNI)? Could something existing cover 90% of it?
- Hidden dependencies on other teams or systems
- Risks with no owner

## Rules
- You see only the inputs you were given. If something can't be understood from them, that's a finding.
- Every finding needs evidence: a quoted line, a `file:line`, or a failing input. No evidence, no finding.
- Severity: **major** only if it blocks acceptance, contradicts a constraint, decision or the code, leaves a risk unowned, lets two readers build different things, or solves the wrong problem (for code: a bug that should be fixed before merging). Everything else is **minor** or **nit**.
- "No findings" is a good result.

## Output
One JSON object per line:
`{"persona":"pre-mortem","severity":"major|minor|nit","location":"<file:line or file#section>","claim":"<one sentence>","evidence":"<quote or file:line>","suggestion":"<fix, or the question a human must answer>"}`
