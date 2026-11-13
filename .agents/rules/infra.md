---
paths:
  - "infra/**"
description: "Plan, never apply"
protect: false
---
Plan, never apply. Attach terraform plan output to the PR.

Enforced by: permissions deny terraform apply; tflint + checkov.

