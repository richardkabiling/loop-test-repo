---
paths:
  - "backend/src/main/resources/db/**"
description: "Append-only"
protect: existing
---
Append-only. Never edit an applied journal script; add a new one.

Enforced by: protect-paths hook blocks edits to existing files.

