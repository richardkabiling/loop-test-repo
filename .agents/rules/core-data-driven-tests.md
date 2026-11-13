---
paths:
  - "backend/core/**"
description: "Domain core"
protect: false
---
Domain core. Every behaviour change ships a table-driven ScalaTest (TableDrivenPropertyChecks) covering the cases.

Enforced by: pr-checks.sh fails when backend/core/src/main changes without backend/core/src/test; test-quality lens.

