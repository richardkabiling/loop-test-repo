#!/usr/bin/env bash
# pr-checks.sh: the loop's deterministic PR checks, run locally by /sdlc-review before review is
# requested. The same checks a CI job would run, so the loop needs no CI unless the team opts in.
#
# Runs, against BASE...HEAD:
#   1. check-loop.sh                      agent files healthy and in sync
#   2. protect-paths.sh --changes         no protected path modified
#   3. diff-guard.sh --base ... --check-registry   size, test tampering, lockfile drift, unknown deps
#   4. pr-tier.sh --check-label LABELS    (only with --labels) the tier label doesn't understate the tier
#
# Usage: pr-checks.sh [--base REF] [--labels "a,b"] [--diff-guard-args "..."] [--help]
# Exit codes: 0 all passed, 1 a check failed, 2 usage error.
set -uo pipefail

BASE=""; LABELS=""; LABELS_SET=0; DG_ARGS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --base) BASE="${2:?}"; shift 2 ;;
    --labels) LABELS="${2-}"; LABELS_SET=1; shift 2 ;;
    --diff-guard-args) DG_ARGS="${2-}"; shift 2 ;;
    -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "pr-checks: unknown argument '$1' (try --help)" >&2; exit 2 ;;
  esac
done
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -z "$BASE" ]; then
  BASE="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  [ -n "$BASE" ] || BASE=main
fi
FAILS=0
run() {
  local name="$1"; shift
  if out="$("$@" 2>&1)"; then echo "ok:   $name"
  else echo "fail: $name"; printf '%s\n' "$out" | tail -n 15 | sed 's/^/      /'; FAILS=$((FAILS + 1)); fi
}
CHANGES="$(mktemp)"; trap 'rm -f "$CHANGES"' EXIT
git diff --name-status --no-renames "$BASE"...HEAD > "$CHANGES" 2>/dev/null || { echo "pr-checks: git diff against '$BASE' failed" >&2; exit 2; }

run "agent files (check-loop)" bash "$HERE/check-loop.sh"
run "protected paths" bash "$HERE/protect-paths.sh" --changes "$CHANGES"
# shellcheck disable=SC2086
run "diff guard" bash "$HERE/diff-guard.sh" --base "$BASE" --check-registry $DG_ARGS
if [ "$LABELS_SET" -eq 1 ]; then run "PR tier label" bash "$HERE/pr-tier.sh" --base "$BASE" --check-label "$LABELS"; fi

if [ "$FAILS" -gt 0 ]; then echo "pr-checks: $FAILS failing check(s)"; exit 1; fi
echo "pr-checks: all passed"
