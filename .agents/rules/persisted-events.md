---
paths:
  - "backend/**/serialization/**"
description: "Persisted events are forever: add a new event version and an event adapter; never change or remove a persisted field; never edit existing golden fixtures"
protect: existing
---
Persisted events are forever: add a new event version and an event adapter; never change or remove a persisted field; never edit existing golden fixtures.

Enforced by: protect-paths hook on existing fixtures; golden fixture test.

