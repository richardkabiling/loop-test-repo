# Solution design

Read this in design step 4 when `solution` is selected. Output: `design/solution.md`.

**Run when:** the work adds a component or service, crosses deliverables, changes a boundary or a data flow, or contains a decision worth an ADR. Skip it for changes inside one module.

## Sections

1. **Context:** the system and its neighbours (C4 level 1), and what changes.
2. **Containers and components:** what's added or changed (C4 levels 2–3); a Mermaid diagram is fine.
3. **Key flows:** sequence for the main acceptance criteria, including failure paths.
4. **Decisions:** each with the options considered and the choice. Hard-to-reverse ones become MADR ADRs in `docs/decisions/`.
5. **Quality attributes:** performance, availability, security, cost and operability targets, with how each is verified.
6. **Deliverable impact:** which deliverables change, in the dependency order from `docs/sdlc/LOOP.md`. This feeds `plan.md`.
7. **Risks and rollout:** flags, migrations (expand–contract), rollback.

## Defaults and sources

- C4 model for diagrams at the right zoom level: <https://c4model.com/>.
- MADR for decisions: <https://github.com/adr/madr>.
- Elephant-Goldfish: draft section by section with full context, then review with fresh eyes: <https://github.com/google/elephant-goldfish-model>.
- Quality-attribute prompts: AWS Well-Architected pillars <https://aws.amazon.com/architecture/well-architected/>.

**Exit:** every acceptance criterion has a flow or component that satisfies it; every decision is recorded; there are no unowned risks.
