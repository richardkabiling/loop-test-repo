#!/usr/bin/env bash
# detect-evals.sh: find eval suites a repo already has, and AI features that should have one.
# Read-only. JSON on stdout. Used by setup step 1 and copied into the generated harness
# (scripts/sdlc/), where check-loop.sh uses it to flag suites missing from loop.json.
#
# Finds:
#   - harness: agent/skill eval suites (docs/sdlc/evals/*.json, evals/evals.json and
#     skills/*/evals/*.json in the Agent Skills shape, .claude/evals, .agents/evals)
#   - product: LLM eval frameworks by config file, file pattern or dependency:
#     promptfoo, Braintrust, Evalite, DeepEval, Ragas, Inspect AI, OpenAI Evals, LangSmith,
#     autoevals, vitest-evals; plus eval/evals/benchmarks folders next to an LLM SDK
#   - ai_features: LLM SDKs in manifests (Anthropic, OpenAI, Vercel AI SDK, LangChain,
#     LlamaIndex, Google GenAI, Mistral, Cohere, Bedrock) and prompt files/folders
#   - scripts: package.json / Makefile / justfile targets with "eval" in the name
#   - ci: existing CI steps that run an eval tool (read only)
#
# Usage: detect-evals.sh [--root DIR] [--help]
# Exit codes: 0 ok, 2 usage error.
set -uo pipefail

ROOT="."
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="${2:?}"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "detect-evals: unknown argument '$1' (try --help)" >&2; exit 2 ;;
  esac
done
cd "$ROOT" || { echo "detect-evals: cannot cd to '$ROOT'" >&2; exit 2; }

js() { printf '"%s"' "$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr -d '\000-\037')"; }
arr() { local first=1 out="["; while IFS= read -r l; do [ -n "$l" ] || continue; [ $first -eq 1 ] || out="$out,"; out="$out$(js "$l")"; first=0; done; printf '%s]' "$out"; }

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  FILES="$(git ls-files -co --exclude-standard 2>/dev/null | grep -vE '(^|/)(node_modules|vendor|dist|build|\.venv|venv)/' )"
else
  FILES="$(find . -type f -not -path '*/node_modules/*' -not -path './.git/*' -not -path '*/.venv/*' | sed 's#^\./##')"
fi
has() { printf '%s\n' "$FILES" | grep -E "$1" | head -n "${2:-5}"; }
MANIFESTS="$(has '(^|/)(package\.json|requirements[^/]*\.txt|pyproject\.toml|Pipfile|go\.mod|Gemfile|Cargo\.toml)$' 40)"
dep() { [ -n "$MANIFESTS" ] && printf '%s\n' "$MANIFESTS" | while IFS= read -r m; do grep -qiE "$1" "$m" 2>/dev/null && echo "$m"; done | head -n 3; }

# Harness suites
HARNESS="$( {
  has '^docs/sdlc/evals/[^/]+\.json$'
  has '^evals/evals\.json$'
  has '^(\.claude|\.agents)/(skills/[^/]+/)?evals/[^/]+\.json$'
  has '^(skills|\.claude/skills|\.agents/skills)/[^/]+/evals/[^/]+\.json$' 10
} | sort -u )"

# Product suites: "framework|path|run hint"
PRODUCT="$( {
  has '(^|/)promptfooconfig\.(ya?ml|json|js)$' | while IFS= read -r f; do echo "promptfoo|$f|npx promptfoo eval -c $f"; done
  for m in $(dep '"promptfoo"'); do echo "promptfoo|$m|npx promptfoo eval"; done
  has '\.eval\.(ts|js|mts|mjs)$' 3 | while IFS= read -r f; do
    if [ -n "$(dep '"evalite"')" ]; then echo "evalite|$f|npx evalite run"
    elif [ -n "$(dep '"braintrust"')" ]; then echo "braintrust|$f|npx braintrust eval $f"
    else echo "eval-file|$f|(unknown runner)"; fi
  done
  for m in $(dep 'deepeval'); do echo "deepeval|$m|deepeval test run <tests>"; done
  for m in $(dep '(^|["'"'"'[:space:]])ragas'); do echo "ragas|$m|(python script using ragas.evaluate)"; done
  for m in $(dep 'inspect[-_]ai'); do echo "inspect-ai|$m|inspect eval <task.py>"; done
  has '(^|/)evals/registry/' 1 | sed 's#^#openai-evals|#; s#$#|oaieval <completion_fn> <eval>#'
  for m in $(dep '"?langsmith"?'); do echo "langsmith|$m|(evaluate() script)"; done
  for m in $(dep '"autoevals"|autoevals'); do echo "autoevals|$m|(scorers inside an eval script)"; done
  for m in $(dep '"vitest-evals"'); do echo "vitest-evals|$m|npx vitest run <evals>"; done
} | sort -u | head -n 20 )"

# AI features
SDKS='@anthropic-ai/sdk|"anthropic"|^anthropic|"openai"|^openai|"ai":|"@ai-sdk/|langchain|llama[-_]?index|@google/genai|google-genai|google-generativeai|@mistralai|mistralai|cohere|@aws-sdk/client-bedrock'
AI="$( {
  for m in $MANIFESTS; do
    hit="$(grep -oiE "$SDKS" "$m" 2>/dev/null | sort -u | tr '\n' ' ')"
    [ -n "$hit" ] && echo "$m: $hit"
  done
  has '(^|/)prompts?/|\.prompt(y)?$|\.prompt\.(md|txt)$' 5 | sed 's#$# (prompt file)#'
} | head -n 15 )"
EVAL_DIRS=""
[ -n "$AI" ] && EVAL_DIRS="$(printf '%s\n' "$FILES" | grep -oE '(^|.*/)(evals?|benchmarks?)/' | sort -u | head -n 5)"

# Scripts and CI (read only)
SCRIPTS="$( {
  printf '%s\n' "$MANIFESTS" | grep 'package\.json$' | while IFS= read -r m; do
    tr -d '\n' < "$m" 2>/dev/null | grep -oE '"scripts"[[:space:]]*:[[:space:]]*\{[^}]*\}' | grep -oE '"[^"]*eval[^"]*"[[:space:]]*:[[:space:]]*"[^"]*"' | sed "s#^#$m: #"
  done
  for f in Makefile justfile; do [ -f "$f" ] && grep -nE '^[A-Za-z0-9_.-]*eval[A-Za-z0-9_.-]*:' "$f" | sed "s#^#$f:#"; done
} | head -n 10 )"
CI="$( for f in .github/workflows/*.yml .github/workflows/*.yaml .gitlab-ci.yml; do
  [ -f "$f" ] || continue
  grep -nE 'promptfoo|deepeval|braintrust|evalite|inspect eval|oaieval|run-evals|langsmith' "$f" | head -n 3 | sed -E "s#^([0-9]+):[[:space:]]*(.{0,100}).*#$f:\1 \2#"
done | head -n 10 )"

printf '{\n'
printf '  "harness_suites": %s,\n' "$(printf '%s\n' "$HARNESS" | arr)"
printf '  "product_suites": ['
first=1
printf '%s\n' "$PRODUCT" | while IFS='|' read -r fw path hint; do
  [ -n "$fw" ] || continue
  [ $first -eq 1 ] || printf ','
  printf '{"framework": %s, "path": %s, "run_hint": %s}' "$(js "$fw")" "$(js "$path")" "$(js "$hint")"
  first=0
done
printf '],\n'
printf '  "ai_features": %s,\n' "$(printf '%s\n' "$AI" | arr)"
printf '  "eval_dirs": %s,\n' "$(printf '%s\n' "$EVAL_DIRS" | arr)"
printf '  "scripts": %s,\n' "$(printf '%s\n' "$SCRIPTS" | arr)"
printf '  "ci": %s,\n' "$(printf '%s\n' "$CI" | arr)"
printf '  "needs_product_evals": %s\n' "$( [ -n "$AI" ] && [ -z "$PRODUCT" ] && echo true || echo false)"
printf '}\n'
