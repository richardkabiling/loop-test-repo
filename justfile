# Single entry point for humans and agents (see AGENTS.md "Verify your work").
# Recipes skip a package that doesn't exist yet, so the loop works from day one.
set shell := ["bash", "-uc"]

be := "backend"
fe := "frontend"

default:
    @just --list

install:
    if [ -d {{be}} ]; then (cd {{be}} && sbt -batch update); fi
    if [ -d {{fe}} ]; then (cd {{fe}} && pnpm install --frozen-lockfile); fi

build:
    if [ -d {{be}} ]; then (cd {{be}} && sbt -batch compile); fi
    if [ -d {{fe}} ]; then (cd {{fe}} && pnpm build); fi

test:
    if [ -d {{be}} ]; then (cd {{be}} && sbt -batch test); fi
    if [ -d {{fe}} ]; then (cd {{fe}} && pnpm test --run); fi

# One spec or test file: just test-single backend/core/src/test/scala/.../FooSpec.scala | frontend/src/foo.test.ts
test-single path:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{path}}" in
      {{be}}/*) spec=$(basename "{{path}}" .scala); (cd {{be}} && sbt -batch "testOnly *${spec}") ;;
      {{fe}}/*) (cd {{fe}} && pnpm vitest run "${PWD%/}/../{{path}}") ;;
      *) echo "test-single: expected a path under {{be}}/ or {{fe}}/" >&2; exit 2 ;;
    esac

# Fast tests for what changed (used by the Claude Stop hook).
test-changed:
    #!/usr/bin/env bash
    set -euo pipefail
    changed=$(git status --porcelain | awk '{print $2}')
    if [ -d {{be}} ] && grep -q "^{{be}}/" <<<"$changed"; then (cd {{be}} && sbt -batch testQuick); fi
    if [ -d {{fe}} ] && grep -q "^{{fe}}/" <<<"$changed"; then (cd {{fe}} && pnpm vitest run --changed); fi

lint:
    if [ -d {{be}} ]; then (cd {{be}} && sbt -batch scalafmtCheckAll "scalafixAll --check"); fi
    if [ -d {{fe}} ]; then (cd {{fe}} && pnpm lint); fi
    if [ -d infra ]; then terraform -chdir=infra fmt -check -recursive && (cd infra && tflint --recursive); fi

typecheck:
    if [ -d {{be}} ]; then (cd {{be}} && sbt -batch compile Test/compile); fi
    if [ -d {{fe}} ]; then (cd {{fe}} && pnpm typecheck); fi

dev:
    if [ -d {{be}} ]; then (cd {{be}} && sbt "~reStart") & fi
    if [ -d {{fe}} ]; then (cd {{fe}} && pnpm dev); fi

# Regenerate the typed API client from the OpenAPI contract.
gen-client:
    cd {{fe}} && pnpm exec openapi-typescript ../api/openapi.yaml -o src/api/gen/schema.ts

# Format one file (Claude PostToolUse hook). Never fails.
fmt-file path:
    #!/usr/bin/env bash
    case "{{path}}" in
      *.scala|*.sbt) command -v scalafmt >/dev/null && scalafmt --quiet "{{path}}" || true ;;
      *.ts|*.tsx|*.js|*.json|*.css|*.md|*.yaml|*.yml) [ -x {{fe}}/node_modules/.bin/prettier ] && {{fe}}/node_modules/.bin/prettier --write "{{path}}" >/dev/null || true ;;
      *.tf) command -v terraform >/dev/null && terraform fmt "{{path}}" >/dev/null || true ;;
    esac

# The loop's PR checks plus this repo's own (run by /charmander-review).
pr-checks base="main" labels="":
    bash scripts/sdlc/pr-checks.sh --base {{base}} {{ if labels != "" { "--labels " + labels } else { "" } }}
    bash scripts/sdlc/repo-checks.sh --base {{base}}
