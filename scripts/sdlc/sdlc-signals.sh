#!/usr/bin/env bash
# sdlc-signals.sh: collect loop-health signals for the improve phase. Read-only; JSON on stdout.
#
# From git and the work-item folders (always):
#   commits, reverts and "fix" commits in the window; work items shipped (all tickets passing);
#   work items waiting at a gate and for how long; tickets failing; harness files changed
# From GitHub (with --remote and an authenticated gh):
#   failed CI runs, PRs merged, PRs carrying the test-change override label
#
# Usage: sdlc-signals.sh [--since YYYY-MM-DD] [--root DIR] [--remote] [--override-label NAME] [--help]
#   --since  window start (default: 14 days ago)
# Exit codes: 0 ok, 2 usage error. Output is bounded (lists capped at 20).
set -uo pipefail

ROOT="."; SINCE=""; REMOTE=0; LABEL="test-change-approved"
while [ $# -gt 0 ]; do
  case "$1" in
    --since) SINCE="${2:?}"; shift 2 ;;
    --root) ROOT="${2:?}"; shift 2 ;;
    --remote) REMOTE=1; shift ;;
    --override-label) LABEL="${2:?}"; shift 2 ;;
    -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "sdlc-signals: unknown argument '$1' (try --help)" >&2; exit 2 ;;
  esac
done
cd "$ROOT" || exit 2
[ -n "$SINCE" ] || SINCE="$(date -u -d '14 days ago' +%F 2>/dev/null || date -u -v-14d +%F)"
js() { printf '"%s"' "$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr -d '\000-\037')"; }
arr() { local f=1 o="["; while IFS= read -r l; do [ -n "$l" ] || continue; [ $f -eq 1 ] || o="$o,"; o="$o$(js "$l")"; f=0; done; printf '%s]' "$o"; }

WORK="docs/work"
P=sdlc
if [ -f docs/sdlc/loop.json ]; then
  p="$(tr -d '\n' < docs/sdlc/loop.json | grep -oE '"harness"[[:space:]]*:[[:space:]]*\{[^}]*\}' | grep -oE '"prefix"[[:space:]]*:[[:space:]]*"[a-z0-9-]+"' | sed -E 's/.*"([a-z0-9-]+)"$/\1/' | head -n1)"
  [ -n "$p" ] && P="$p"
  w="$(tr -d '\n' < docs/sdlc/loop.json | grep -oE '"work"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n1 | sed -E 's/.*"([^"]*)"$/\1/')"
  [ -n "$w" ] && WORK="$w"
fi

commits=0; reverts=0; fixes=0; harness=""
if git rev-parse --is-inside-work-tree >/dev/null 2>&1 && git rev-parse HEAD >/dev/null 2>&1; then
  commits=$(git log --since="$SINCE" --oneline | wc -l | tr -d ' ')
  reverts=$(git log --since="$SINCE" --oneline -i --grep='^revert' | wc -l | tr -d ' ')
  fixes=$(git log --since="$SINCE" --oneline -E -i --grep='^fix(\(.+\))?!?:' | wc -l | tr -d ' ')
  harness="$(git log --since="$SINCE" --name-only --pretty=format: -- AGENTS.md CLAUDE.md REVIEW.md .agents .claude .cursor scripts/sdlc docs/sdlc/loop.json 2>/dev/null | sort | uniq -c | sort -rn | head -n 20 | awk '{print $2" ("$1" changes)"}')"
fi

now=$(date +%s); shipped=""; waiting=""; failing=0
if [ -d "$WORK" ]; then
  for d in "$WORK"/*/; do
    [ -d "$d" ] || continue
    slug="$(basename "$d")"
    if [ -f "$d/tickets.json" ]; then
      t=$(grep -oE '"passes"[[:space:]]*:' "$d/tickets.json" | wc -l | tr -d ' ')
      p=$(grep -oE '"passes"[[:space:]]*:[[:space:]]*true' "$d/tickets.json" | wc -l | tr -d ' ')
      failing=$((failing + t - p))
      if [ "$t" -gt 0 ] && [ "$p" -eq "$t" ]; then
        last=$(git log -1 --format=%ct -- "$d" 2>/dev/null); [ -n "$last" ] || last=$now
        since_ts=$(date -d "$SINCE" +%s 2>/dev/null || date -j -f %F "$SINCE" +%s 2>/dev/null || echo 0)
        if [ "$last" -ge "$since_ts" ]; then
          if ls docs/sdlc/improve/*"$slug"* >/dev/null 2>&1; then shipped="$shipped$slug"$'\n'
          else shipped="$shipped$slug (no retro yet)"$'\n'; fi
        fi
      fi
    fi
    for a in intent spec plan; do  # spec.md is the design phase's gate artifact
      f="$d/$a.md"; [ -f "$f" ] || continue
      if ! grep -qiE '^(\*\*)?status(\*\*)?:[[:space:]]*(\*\*)?approved' "$f"; then
        m=$(git log -1 --format=%ct -- "$f" 2>/dev/null); [ -n "$m" ] || m=$(date -r "$f" +%s 2>/dev/null || echo "$now")
        waiting="$waiting$slug: $a waiting $(( (now - m) / 86400 ))d"$'\n'
        break
      fi
    done
  done
fi

ci='null'; prs='null'; overrides='null'; note=""
if [ "$REMOTE" -eq 1 ]; then
  if command -v gh >/dev/null 2>&1; then
    ci="$(timeout 20 gh run list --status failure --created ">=$SINCE" --limit 100 --json name --jq 'length' 2>/dev/null || echo null)"
    prs="$(timeout 20 gh pr list --state merged --search "merged:>=$SINCE" --limit 200 --json number --jq 'length' 2>/dev/null || echo null)"
    overrides="$(timeout 20 gh pr list --state all --label "$LABEL" --search "created:>=$SINCE" --limit 100 --json number --jq 'length' 2>/dev/null || echo null)"
    [ "$ci$prs$overrides" = "nullnullnull" ] && note="gh calls failed (not authenticated, or no GitHub remote)"
  else note="gh not installed"; fi
fi

printf '{\n  "since": "%s",\n' "$SINCE"
printf '  "git": {"commits": %s, "reverts": %s, "fix_commits": %s},\n' "$commits" "$reverts" "$fixes"
printf '  "work_items": {"shipped_in_window": %s, "waiting_at_gate": %s, "failing_tickets": %s},\n' "$(printf '%s' "$shipped" | head -n 20 | arr)" "$(printf '%s' "$waiting" | head -n 20 | arr)" "$failing"
printf '  "harness_changes": %s,\n' "$(printf '%s\n' "$harness" | arr)"
printf '  "github": {"failed_ci_runs": %s, "merged_prs": %s, "override_label_prs": %s, "note": %s},\n' "$ci" "$prs" "$overrides" "$(js "$note")"
printf '  "hints": %s\n' "$( {
  [ "$reverts" -gt 0 ] && echo "reverts in window: run /$P-improve incident or retro on the reverted work"
  printf '%s' "$shipped" | grep -q 'no retro yet' && echo "shipped work items without a retro: run /$P-improve retro <slug>"
  printf '%s' "$waiting" | awk -F'waiting ' '{sub(/d$/,"",$2); if ($2+0 > 3) found=1} END{exit !found}' && echo "items waiting more than 3 days at a gate: check gate owners or consider gate changes"
  [ "$overrides" != "null" ] && [ "${overrides:-0}" -gt 2 ] 2>/dev/null && echo "test-change override used often: review test-tampering guardrail"
  true; } | arr)"
printf '}\n'
