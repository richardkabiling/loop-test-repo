#!/usr/bin/env bash
# repo-checks.sh: loop-test-repo's own PR checks, run after pr-checks.sh by `just pr-checks`.
# Each check runs only when its paths changed and skips (with a note) when its tool is missing.
# Repo-owned: setup regeneration never overwrites this file.
set -uo pipefail
BASE=main
while [ $# -gt 0 ]; do
  case "$1" in
    --base) BASE="$2"; shift 2 ;;
    -h|--help) sed -n '2,4p' "$0"; exit 0 ;;
    *) echo "repo-checks: unknown arg $1" >&2; exit 2 ;;
  esac
done
changed=$(git diff --name-only "$BASE"...HEAD 2>/dev/null || git diff --name-only "$BASE")
fail=0
has() { grep -qE "$1" <<<"$changed"; }
tool() { command -v "$1" >/dev/null 2>&1 || { echo "skip: $1 not installed ($2)"; return 1; }; }
run() { echo "run: $*"; "$@" || { echo "fail: $*"; fail=1; }; }

# 1. backend/core behaviour changes ship table-driven tests
if has '^backend/core/src/main/' && ! has '^backend/core/src/test/'; then
  echo "fail: backend/core/src/main changed without backend/core/src/test (table-driven tests required)"; fail=1
fi
# 2. infra or API runtime changes update the tech ops manual
if has '^(infra/|backend/Dockerfile|api/openapi\.yaml)' && ! has '^docs/ops/tech/'; then
  echo "fail: infra/API change without a docs/ops/tech/ update (ops-manual drift)"; fail=1
fi
# 3. OpenAPI contract: lint + breaking-change diff
if has '^api/openapi\.yaml$'; then
  tool npx "redocly lint" && run npx --yes @redocly/cli@1 lint api/openapi.yaml
  if tool oasdiff "breaking-change check" && git cat-file -e "$BASE:api/openapi.yaml" 2>/dev/null; then
    git show "$BASE:api/openapi.yaml" > /tmp/openapi-base.yaml
    run oasdiff breaking /tmp/openapi-base.yaml api/openapi.yaml --fail-on ERR
  fi
fi
# 4. Terraform
if has '^infra/'; then
  tool terraform "terraform fmt/validate" && run terraform -chdir=infra fmt -check -recursive
  tool tflint "terraform lint" && run tflint --chdir=infra --recursive
  tool checkov "terraform policy" && run checkov -d infra --quiet --compact
fi
# 5. GitHub Actions
if has '^\.github/workflows/'; then
  tool actionlint "workflow lint" && run actionlint
  tool zizmor "workflow security" && run zizmor .github/workflows
fi
# 6. Dockerfile
if has 'Dockerfile'; then
  tool hadolint "Dockerfile lint" && for f in $(grep -E 'Dockerfile' <<<"$changed"); do [ -f "$f" ] && run hadolint "$f"; done
fi
[ $fail -eq 0 ] && echo "ok: repo-checks passed" || echo "fail: repo-checks found problems"
exit $fail
