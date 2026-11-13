# Where intent and design live: tracker epic

Read this at the start of `/charmander-intent`, `/charmander-design` and `/charmander-plan`.

- **Home:** GitHub epic issue holds the intent and design summaries and the approval; the full intent.md, spec.md and design/*.md are committed in docs/work/<date>-<slug>/ (agent syncs the epic and the files after each round). The epic is the source of truth; `docs/work/<yyyy-mm-dd>-<slug>/` is your working copy for drafting and persona review.
- **Sync rule:** read the epic before every round and fold in human edits and answers (they win); push your working copy back to the epic after every round. Never overwrite a human's edit to the epic; propose the change in a comment instead.
- **Intent:** the epic description holds `intent.md`. Create the epic when the first draft exists, labelled `epic`.
- **Design:** `spec.md` goes in a comment titled "Spec" (edited in place), or a child issue when it outgrows a comment; each design subphase gets its own comment or child issue, linked from the spec.
- **Grilling:** solo. One person answers the frontier questions live in the session; the agent mirrors each round's decisions to the epic.
- **Gate:** the gate owner approves on the epic (label `intent-approved` / `design-approved`, or an approval comment). Record it as `Status: approved` in the working copy, with a link to the approval.
- **Tickets:** `/charmander-plan` creates each ticket as a child issue of the epic and writes its issue number into `tickets.json`. Build-validate and review then run per child issue.
