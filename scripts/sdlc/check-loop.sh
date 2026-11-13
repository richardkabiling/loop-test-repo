#!/usr/bin/env bash
# check-loop.sh: verify the generated AI-native SDLC loop is healthy. Read-only; CI-friendly.
#
# Checks:
#   - docs/sdlc/loop.json validates (python3 scripts/sdlc/validate-loop.py, if python3 exists)
#   - root AGENTS.md exists and stays lean (warn > 200 lines); all AGENTS.md files together fit
#     Codex's 32 KiB project-doc budget
#   - CLAUDE.md imports AGENTS.md (when claude-code is a selected tool)
#   - every skill in .agents/skills has valid portable frontmatter: name == folder, [a-z0-9-],
#     <= 64 chars, description present and <= 1024 chars, SKILL.md <= 500 lines; progressive
#     disclosure: warn > 150 lines, warn on references/ files no SKILL.md pointer reaches
#   - every rule in .agents/rules has paths: globs that match at least one tracked file (warn)
#   - no unfilled {{placeholders}} remain in generated files
#   - docs/sdlc/pr-tiers.json matches review.pr.tiers (when tiers are set)
#   - every eval suite detect-evals.sh finds is registered in review.evals.suites (warn when AI
#     features exist with no product suite)
#   - generated tool files are in sync (scripts/sdlc/sync-agent-files.sh --check)
#
# Usage: check-loop.sh [--root DIR] [--help]
# Output: one "ok|warn|fail: message" line per check. Exit 1 if any fail.
set -uo pipefail

ROOT="."
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="${2:?}"; shift 2 ;;
    -h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "check-loop: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
cd "$ROOT" || exit 2
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAILS=0
ok()   { echo "ok:   $1"; }
warn() { echo "warn: $1"; }
fail() { echo "fail: $1"; FAILS=$((FAILS + 1)); }

TOOLS="claude-code,cursor,codex"
PREFIX=sdlc
if [ -f docs/sdlc/loop.json ]; then
  t="$(tr -d '\n' < docs/sdlc/loop.json | grep -oE '"tools"[[:space:]]*:[[:space:]]*\[[^]]*\]' | grep -oE '"(claude-code|cursor|codex)"' | tr -d '"' | paste -sd, - || true)"
  [ -n "$t" ] && TOOLS="$t"
  p="$(tr -d '\n' < docs/sdlc/loop.json | grep -oE '"harness"[[:space:]]*:[[:space:]]*\{[^}]*\}' | grep -oE '"prefix"[[:space:]]*:[[:space:]]*"[a-z0-9-]+"' | sed -E 's/.*"([a-z0-9-]+)"$/\1/' | head -n1)"
  [ -n "$p" ] && PREFIX="$p"
  if command -v python3 >/dev/null 2>&1 && [ -f "$HERE/validate-loop.py" ]; then
    if out="$(python3 "$HERE/validate-loop.py" docs/sdlc/loop.json 2>&1)"; then ok "loop.json valid"
    else fail "loop.json invalid:"; printf '%s\n' "$out" | head -n 20 | sed 's/^/      /'; fi
  else warn "python3 not found; loop.json not validated"; fi
else
  fail "docs/sdlc/loop.json missing (run /setup-sdlc-loop)"
fi
has_tool() { case ",$TOOLS," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }

# Review policy
if [ -f REVIEW.md ]; then
  if grep -q '<!-- sdlc:review-core -->' REVIEW.md; then ok "REVIEW.md has a review-core section (emitted to AGENTS.md and BUGBOT.md)"
  else warn "REVIEW.md has no <!-- sdlc:review-core --> section, so Codex, Cursor and local /code-review won't get the policy"; fi
  nbots=$( (grep -rlsE 'claude-code-action|bugbot|codex.*review' .github/workflows 2>/dev/null || true) | wc -l | tr -d ' ')
  [ "$nbots" -gt 1 ] && warn "$nbots workflows look like AI PR reviewers; keep exactly one posting on PRs"
else
  fail "REVIEW.md missing (the single review policy)"
fi

# Persona lenses exist for every configured review point
if [ -f docs/sdlc/loop.json ] && command -v python3 >/dev/null 2>&1; then
  missing="$(python3 - <<'PY'
import json, os
d = json.load(open("docs/sdlc/loop.json"))
pts = ((d.get("review") or {}).get("personas") or {}).get("points") or {}
miss = set()
for lenses in pts.values():
    for l in lenses:
        name = ("target-user--" + os.path.splitext(os.path.basename(l.split(":", 1)[1]))[0]) if l.startswith("target-user:") else l
        if not os.path.isfile(f"docs/sdlc/lenses/{name}.md"):
            miss.add(name)
print(" ".join(sorted(miss)))
PY
)"
  if [ -n "$missing" ]; then fail "persona lens files missing in docs/sdlc/lenses/: $missing"
  elif grep -q '"personas"' docs/sdlc/loop.json; then ok "persona lens files present"; fi
fi

# PR tiers file matches loop.json
if [ -f docs/sdlc/loop.json ] && command -v python3 >/dev/null 2>&1; then
  tiermsg="$(python3 - <<'PY'
import json, os
d = json.load(open("docs/sdlc/loop.json"))
t = ((d.get("review") or {}).get("pr") or {}).get("tiers")
if not t:
    print("")
elif not os.path.isfile("docs/sdlc/pr-tiers.json"):
    print("fail:docs/sdlc/pr-tiers.json missing (pr-tier.sh reads it; regenerate from review.pr.tiers)")
else:
    try:
        same = json.load(open("docs/sdlc/pr-tiers.json")) == t
    except ValueError:
        same = False
    print("ok:docs/sdlc/pr-tiers.json matches review.pr.tiers" if same else "fail:docs/sdlc/pr-tiers.json differs from review.pr.tiers in loop.json (regenerate it)")
PY
)"
  case "$tiermsg" in ok:*) ok "${tiermsg#ok:}" ;; fail:*) fail "${tiermsg#fail:}" ;; esac
fi

# Eval suites in the repo are registered in loop.json (re-discovery)
if [ -f "$HERE/detect-evals.sh" ] && [ -f docs/sdlc/loop.json ] && command -v python3 >/dev/null 2>&1; then
  evmsg="$(bash "$HERE/detect-evals.sh" 2>/dev/null | python3 -c '
import json, sys
try:
    found = json.load(sys.stdin)
except ValueError:
    sys.exit(0)
loop = json.load(open("docs/sdlc/loop.json"))
suites = ((loop.get("review") or {}).get("evals") or {}).get("suites") or []
known = " ".join(str(s.get("path", "")) + " " + str(s.get("run", "")) for s in suites)
missing = [p for p in found.get("harness_suites", []) if p not in known]
missing += [x["path"] for x in found.get("product_suites", []) if x.get("path") and x["path"] not in known]
if missing:
    print("fail:eval suites found but not in review.evals.suites (they would never run): " + ", ".join(sorted(set(missing))[:8]))
elif found.get("needs_product_evals") and not any(s.get("kind") == "product" for s in suites):
    print("warn:AI features found (" + "; ".join(found.get("ai_features", [])[:2]) + ") but no product eval suite; add one to review.evals.suites")
elif suites:
    print("ok:eval suites registered (" + ", ".join(s.get("id", "?") for s in suites) + ")")
')"
  case "$evmsg" in ok:*) ok "${evmsg#ok:}" ;; warn:*) warn "${evmsg#warn:}" ;; fail:*) fail "${evmsg#fail:}" ;; esac
fi

# Loop docs the agents are pointed at
for f in docs/sdlc/LOOP.md docs/sdlc/MAP.md $(grep -q '"personas"' docs/sdlc/loop.json 2>/dev/null && echo docs/sdlc/personas.md); do
  if [ -f "$f" ]; then ok "$f present"; else fail "$f missing (AGENTS.md and /$PREFIX point to it; re-run /setup-sdlc-scaffold)"; fi
done

# AGENTS.md budget
if [ -f AGENTS.md ]; then
  lines=$(wc -l < AGENTS.md | tr -d ' ')
  if [ "$lines" -gt 200 ]; then warn "AGENTS.md has $lines lines (aim for <= 200; move detail into scoped rules or skills)"
  else ok "AGENTS.md is $lines lines"; fi
else
  fail "AGENTS.md missing"
fi
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  AGENT_FILES="$(git ls-files -co --exclude-standard -- 'AGENTS.md' '**/AGENTS.md' 2>/dev/null | sort -u)"
  TRACKED="$(git ls-files -co --exclude-standard 2>/dev/null)"
else
  AGENT_FILES="$(find . -name AGENTS.md -not -path '*/node_modules/*' | sed 's#^\./##')"
  TRACKED="$(find . -type f -not -path '*/node_modules/*' -not -path './.git/*' | sed 's#^\./##')"
fi
bytes=0; for f in $AGENT_FILES; do [ -f "$f" ] && bytes=$((bytes + $(wc -c < "$f"))); done
if has_tool codex && [ "$bytes" -gt 32768 ]; then
  fail "AGENTS.md files total $bytes bytes; Codex truncates beyond 32768 by default"
else ok "AGENTS.md files total $bytes bytes"; fi

# CLAUDE.md bridge
if has_tool claude-code; then
  if [ -f CLAUDE.md ] && grep -qE '^@AGENTS\.md[[:space:]]*$' CLAUDE.md; then ok "CLAUDE.md imports @AGENTS.md"
  elif [ -f CLAUDE.md ]; then fail "CLAUDE.md exists but doesn't import @AGENTS.md, so Claude won't read AGENTS.md"
  else warn "no CLAUDE.md; Claude Code reads AGENTS.md natively only in recent versions. Add a CLAUDE.md containing @AGENTS.md"; fi
  if [ -f CLAUDE.local.md ]; then warn "CLAUDE.local.md present: harmless with the @AGENTS.md import, but it suppresses native AGENTS.md reading"; fi
fi

# Skills
if [ -d .agents/skills ]; then
  for d in .agents/skills/*/; do
    s="${d}SKILL.md"; n="$(basename "$d")"
    [ -f "$s" ] || { fail "$d has no SKILL.md"; continue; }
    fm="$(awk 'NR==1&&/^---/{f=1;next} f&&/^---/{exit} f' "$s")"
    name="$(printf '%s\n' "$fm" | sed -n 's/^name:[[:space:]]*//p' | tr -d '"'"'" | head -n1)"
    desc="$(printf '%s\n' "$fm" | sed -n 's/^description:[[:space:]]*//p' | head -n1)"
    lines=$(wc -l < "$s" | tr -d ' ')
    problems=""
    [ "$name" = "$n" ] || problems="$problems name '$name' != folder;"
    printf '%s' "$n" | grep -qE '^[a-z0-9]+(-[a-z0-9]+)*$' && [ ${#n} -le 64 ] || problems="$problems invalid name;"
    [ -n "$desc" ] || problems="$problems missing description;"
    [ ${#desc} -le 1024 ] || problems="$problems description > 1024 chars;"
    [ "$lines" -le 500 ] || problems="$problems SKILL.md $lines lines > 500;"
    if [ -n "$problems" ]; then fail "skill $n:$problems"; else ok "skill $n"; fi
    # progressive disclosure: lean body, every reference reachable from a "read when" pointer
    [ "$lines" -gt 150 ] && warn "skill $n: SKILL.md is $lines lines; move branch-specific detail into references/"
    if [ -d "${d}references" ]; then
      for ref in "${d}references"/*.md; do
        [ -f "$ref" ] || continue
        grep -q "references/$(basename "$ref")" "$s" || warn "skill $n: references/$(basename "$ref") isn't pointed to from SKILL.md, so agents won't reach it"
      done
    fi
  done
fi

# Rule globs match something
glob2re() {
  printf '%s' "$1" | sed -E -e 's/[].[^$()+|]/\\&/g' -e 's#\*\*/#@@D@@#g' -e 's#\*\*#@@A@@#g' \
    -e 's#\*#[^/]*#g' -e 's#\?#[^/]#g' -e 's#@@D@@#(.*/)?#g' -e 's#@@A@@#.*#g' \
    -e ':b' -e 's#\{([^{}]*),([^{}]*)\}#{\1|\2}#' -e 'tb' -e 's#\{([^{}]*)\}#(\1)#g'
}
if [ -d .agents/rules ]; then
  for r in .agents/rules/*.md; do
    [ -f "$r" ] || continue
    globs="$(awk 'NR==1&&/^---/{f=1;next} f&&/^---/{exit}
      f&&/^paths:[ \t]*\[/{s=$0; sub(/^paths:[ \t]*\[/,"",s); sub(/\][ \t]*$/,"",s); n=split(s,a,","); for(i=1;i<=n;i++){g=a[i]; gsub(/^[ \t"'\'']+|[ \t"'\'']+$/,"",g); print g}; next}
      f&&/^paths:[ \t]*$/{p=1;next} f&&p&&/^[ \t]*-/{g=$0; sub(/^[ \t]*-[ \t]*/,"",g); gsub(/^["'\'']|["'\'']$/,"",g); print g; next} {p=0}' "$r")"
    [ -n "$globs" ] || { fail "rule $(basename "$r"): no paths"; continue; }
    hit=0
    while IFS= read -r g; do printf '%s\n' "$TRACKED" | grep -qE "^$(glob2re "$g")$" && { hit=1; break; }; done <<< "$globs"
    if [ $hit -eq 1 ]; then ok "rule $(basename "$r" .md) matches files"
    else warn "rule $(basename "$r" .md): no tracked file matches its paths (typo, or folder not created yet?)"; fi
  done
fi

# Unfilled template placeholders in generated files
left=""
for f in AGENTS.md CLAUDE.md REVIEW.md docs/sdlc/LOOP.md docs/sdlc/MAP.md .claude/settings.json .claude/agents/*.md .agents/skills/"$PREFIX"*/SKILL.md .agents/skills/"$PREFIX"*/agents/openai.yaml .agents/rules/*.md .github/workflows/sdlc-checks.yml .github/workflows/claude-review.yml .cursor/BUGBOT.md; do
  [ -f "$f" ] || continue
  grep -qE '\{\{[a-z_]+\}\}' "$f" && left="$left $f"
done
if [ -n "$left" ]; then fail "unfilled {{placeholders}} in:$left"; else ok "no unfilled template placeholders"; fi

# Generated files in sync
if [ -x "$HERE/sync-agent-files.sh" ] || [ -f "$HERE/sync-agent-files.sh" ]; then
  if bash "$HERE/sync-agent-files.sh" --check --tools "$TOOLS" >/dev/null 2>&1; then ok "generated agent files in sync"
  else fail "generated agent files out of sync. Run scripts/sdlc/sync-agent-files.sh"; fi
fi

if [ "$FAILS" -gt 0 ]; then echo "check-loop: $FAILS failing check(s)"; exit 1; fi
echo "check-loop: healthy"
