# Documentation design

Read this in design step 4 when `docs` is selected (user-facing behaviour changes, or a user guide is a deliverable). Output: `design/docs.md`.

## Sections

1. **Readers:** who needs to learn what (new user, admin, integrator, operator).
2. **Placement (Diátaxis):** which tutorial, how-to, reference or explanation pages are added or changed. One purpose per page.
3. **Outline:** headings per page, with the acceptance criteria each one explains.
4. **Examples:** the runnable snippets and screenshots needed, and how they stay in sync with the code.
5. **Release:** docs publish when the feature flag turns on.

## Defaults and sources

- Diátaxis: <https://diataxis.fr/>.
- Google developer documentation style guide: <https://developers.google.com/style>.
- Vale for prose lint: <https://vale.sh/>.

**Exit:** every user-visible acceptance criterion is explained somewhere; every page has a single Diátaxis type; the examples are testable.
