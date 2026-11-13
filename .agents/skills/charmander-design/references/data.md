# Data design

Read this in design step 4 when `data` is selected (schema, storage or data flow changes). Output: `design/data.md`.

## Sections

1. **Model change:** entities and fields added or changed (ERD snippet), with constraints and indexes.
2. **Migration plan:** expand → migrate/backfill → contract, each step deployable and reversible; how long each step runs on production-sized data.
3. **Integrity:** invariants and how they're enforced (constraints vs application code), and the invariant tests to add.
4. **Privacy:** PII fields, retention, access control, deletion and export paths.
5. **Performance:** query patterns, expected volume, indexes, locking risk during migration.

## Defaults and sources

- Expand–contract (parallel change): <https://martinfowler.com/bliki/ParallelChange.html>.
- Data minimisation and purpose limitation (GDPR Art. 5): <https://gdpr-info.eu/art-5-gdpr/>.
- Never edit applied migrations (scoped rule `migrations`, enforced by `protect-paths.sh`).

**Exit:** every migration step is reversible or has an explicit point of no return that a human approved; PII is identified; invariants have tests.
