#!/usr/bin/env bash
# stop-check.sh: Claude Code Stop hook that keeps the agent working until the repo's checks pass.
#
# Usage (in .claude/settings.json Stop hook):  bash scripts/sdlc/stop-check.sh -- <cmd> [&& <cmd>...]
#   e.g.  bash scripts/sdlc/stop-check.sh -- "pnpm -s typecheck && pnpm -s test --changed"
#
# Behaviour:
#   - Skips (exit 0) when the working tree has no changes: nothing to verify.
#   - Runs the command. On failure, prints the tail of its output to stderr and exits 2, which
#     makes Claude continue and fix it.
#   - After --max-blocks consecutive failures (default 3) it lets Claude stop, with a warning, so a
#     check the agent can't fix never loops forever. The counter resets on success.
# Options: --max-blocks N, --tail N (lines of output fed back; default 40), --help
set -uo pipefail

MAX=3; TAIL=40; CMD=""
while [ $# -gt 0 ]; do
  case "$1" in
    --max-blocks) MAX="${2:?}"; shift 2 ;;
    --tail) TAIL="${2:?}"; shift 2 ;;
    --) shift; CMD="$*"; break ;;
    -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "stop-check: unknown argument '$1'" >&2; exit 0 ;;
  esac
done
[ -n "$CMD" ] || { echo "stop-check: no command given after --" >&2; exit 0; }
cat >/dev/null  # drain hook JSON from stdin

ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT" || exit 0
if git rev-parse --is-inside-work-tree >/dev/null 2>&1 && [ -z "$(git status --porcelain 2>/dev/null)" ]; then
  exit 0
fi

STATE="$(git rev-parse --git-dir 2>/dev/null || echo .)/sdlc-stop-check.count"
OUT="$(bash -c "$CMD" 2>&1)"; RC=$?
if [ $RC -eq 0 ]; then rm -f "$STATE"; exit 0; fi

N=$(( $(cat "$STATE" 2>/dev/null || echo 0) + 1 )); echo "$N" > "$STATE"
if [ "$N" -gt "$MAX" ]; then
  rm -f "$STATE"
  echo "stop-check: checks still failing after $MAX attempts; stopping so a human can look. Last output:" >&2
  printf '%s\n' "$OUT" | tail -n "$TAIL" >&2
  exit 0
fi
{
  echo "Checks failed (attempt $N/$MAX): $CMD"
  printf '%s\n' "$OUT" | tail -n "$TAIL"
  echo "Fix the failures above before finishing. Don't skip or weaken tests."
} >&2
exit 2
