#!/usr/bin/env bash
# sdlc-status.sh: show where each work item stands in the loop and what comes next.
#
# Reads docs/sdlc/loop.json (enabled phases, work dir) and each work item folder
# (default docs/work/<slug>/). A phase counts as done when its artifact exists and contains
# "Status: approved" (intent, spec, plan). Per ticket in tickets.json: "passes": true means validated
# locally (build-validate); "merged": true means its PR passed review. A ticket that passes but isn't
# merged is waiting in review.
#
# Usage: sdlc-status.sh [--root DIR] [--json] [--item SLUG] [--help]
# Used by the /sdlc router skill and by the SessionStart(compact) hook. Read-only; output is bounded.
set -uo pipefail

ROOT="."; JSON=0; ITEM=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="${2:?}"; shift 2 ;;
    --json) JSON=1; shift ;;
    --item) ITEM="${2:?}"; shift 2 ;;
    -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "sdlc-status: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
cd "$ROOT" || exit 2
LOOP=docs/sdlc/loop.json
WORK="docs/work"
if [ -f "$LOOP" ]; then
  w="$(tr -d '\n' < "$LOOP" | grep -oE '"work"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n1 | sed -E 's/.*"([^"]*)"$/\1/')"
  [ -n "$w" ] && WORK="$w"
fi

LOOPTXT="$( [ -f "$LOOP" ] && tr -d '\n' < "$LOOP" || true)"
# Skill prefix from loop.json harness.prefix (default sdlc): commands are /<prefix>, /<prefix>-build, ...
P="$(printf '%s' "$LOOPTXT" | grep -oE '"harness"[[:space:]]*:[[:space:]]*\{[^}]*\}' | grep -oE '"prefix"[[:space:]]*:[[:space:]]*"[a-z0-9-]+"' | sed -E 's/.*"([a-z0-9-]+)"$/\1/' | head -n1)"
[ -n "$P" ] || P=sdlc
# A phase is enabled unless loop.json says "id": "<phase>", "enabled": false
enabled() { ! printf '%s' "$LOOPTXT" | grep -qE "\"id\"[[:space:]]*:[[:space:]]*\"$1\"[[:space:]]*,[[:space:]]*\"enabled\"[[:space:]]*:[[:space:]]*false"; }
approved() { [ -f "$1" ] && grep -qiE '^(\*\*)?status(\*\*)?:[[:space:]]*(\*\*)?approved' "$1"; }
next_for() {
  local d="$1"
  local ph
  for ph in intent design plan; do
    enabled "$ph" || continue
    case "$ph" in design) art="$d/spec.md" ;; *) art="$d/$ph.md" ;; esac
    if [ ! -f "$art" ]; then echo "$ph: run /$P-$ph"; return; fi
    if ! approved "$art"; then echo "$ph: awaiting gate ($(basename "$art") needs 'Status: approved')"; return; fi
  done
  if [ -f "$d/tickets.json" ]; then
    local total pass
    local merged hasmerged
    total=$(grep -oE '"passes"[[:space:]]*:' "$d/tickets.json" | wc -l | tr -d " ")
    pass=$(grep -oE '"passes"[[:space:]]*:[[:space:]]*true' "$d/tickets.json" | wc -l | tr -d " ")
    hasmerged=$(grep -oE '"merged"[[:space:]]*:' "$d/tickets.json" | wc -l | tr -d " ")
    merged=$(grep -oE '"merged"[[:space:]]*:[[:space:]]*true' "$d/tickets.json" | wc -l | tr -d " ")
    [ "$hasmerged" -gt 0 ] || merged=$pass
    if enabled review && [ "$pass" -gt "$merged" ]; then echo "review: $((pass - merged)) validated ticket(s) waiting; run /$P-review"; return; fi
    if [ "$total" -gt 0 ] && [ "$pass" -lt "$total" ]; then echo "build: $pass/$total tickets validated, $merged merged; run /$P-build"; return; fi
    if [ "$total" -gt 0 ]; then
      if [ -f "$d/progress.md" ] && grep -qE '^Shipped:' "$d/progress.md"; then
        if enabled improve && ! ls docs/sdlc/improve/*"$(basename "$d")"* >/dev/null 2>&1; then
          echo "improve: shipped; run /$P-improve retro $(basename "$d")"
        else echo "done: shipped"; fi
        return
      fi
      echo "ship: all $total tickets merged; run /$P-ship"; return
    fi
  fi
  echo "build: create tickets via /$P-plan, or run /$P-build"
}

items=()
if [ -n "$ITEM" ]; then items=("$WORK/$ITEM")
elif [ -d "$WORK" ]; then
  while IFS= read -r d; do items+=("$d"); done < <(find "$WORK" -mindepth 1 -maxdepth 1 -type d ! -name '.*' | sort | tail -n 20)
fi

if [ "$JSON" -eq 1 ]; then
  printf '{"work_dir":"%s","items":[' "$WORK"; first=1
  for d in "${items[@]+"${items[@]}"}"; do
    [ $first -eq 1 ] || printf ','; first=0
    printf '{"slug":"%s","next":"%s"}' "$(basename "$d")" "$(next_for "$d" | sed 's/"/\\"/g')"
  done
  printf ']}\n'
  exit 0
fi
if [ ${#items[@]} -eq 0 ]; then
  echo "No work items in $WORK/. Start one with /$P-intent."
  exit 0
fi
echo "Work items in $WORK/ (latest 20):"
for d in "${items[@]}"; do printf '  %-40s %s\n' "$(basename "$d")" "$(next_for "$d")"; done
