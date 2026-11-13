# UX design

Read this in design step 4 when `ux` is selected (web or mobile UI touched). Output: `design/ux.md`, plus a prototype link or screenshots.

## Sections

1. **Users and jobs:** who uses this screen or flow, and what they're trying to get done (from the intent).
2. **Flows:** the step-by-step path for each user story, with entry points and exits.
3. **Screens and states:** for every screen, the **empty, loading, error, partial and success** states, plus permissions variants.
4. **Content:** labels, messages and errors, in the product's voice; i18n needs.
5. **Accessibility:** WCAG 2.2 AA (keyboard path, focus order, contrast, labels, motion); how it will be tested (axe in E2E).
6. **Design system:** the existing components to reuse; any new ones, with a reason.
7. **Prototype:** for anything new or uncertain, a throwaway prototype (mattpocock `prototype`, or the `frontend-design` plugin) or a Figma link (Figma MCP if available). Attach screenshots.

## Defaults and sources

- Nielsen's 10 usability heuristics as the review lens: <https://www.nngroup.com/articles/ten-usability-heuristics/>.
- WCAG 2.2 AA: <https://www.w3.org/TR/WCAG22/>.
- Playwright visual snapshots make the approved screens a regression baseline: <https://playwright.dev/docs/test-snapshots>.

**Exit:** every user story has a flow; every screen lists all its states; accessibility checks are named; the prototype or screens are linked.
