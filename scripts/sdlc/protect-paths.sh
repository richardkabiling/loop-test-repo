#!/usr/bin/env bash
# protect-paths.sh: block changes to paths protected by .agents/rules/*.md (`protect:` frontmatter).
#
# Two modes, one rule source:
#   Claude Code PreToolUse hook (default): reads the hook JSON on stdin, exits 2 with the rule text
#     on stderr when the tool would touch a protected path. Matcher: Edit|Write|MultiEdit|NotebookEdit|Read
#   Git pre-commit (--staged): checks staged changes, so Cursor, Codex and humans are covered too.
#   CI (--changes FILE): checks `git diff --name-status --no-renames` output saved in FILE.
#
# protect values:  true      block edits and deletes of any matching path
#                  existing  block edits of files that already exist (new files allowed: migrations)
#                  read      like true, and also block reads (secrets)
#
# Usage: protect-paths.sh [--staged | --changes FILE] [--root DIR] [--help]
# Exit codes: 0 allowed, 2 blocked (hook protocol), 1 blocked (--staged), 3 usage error.
set -uo pipefail

MODE="hook"; ROOT="${CLAUDE_PROJECT_DIR:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --staged) MODE="staged"; shift ;;
    --changes) MODE="changes"; CHANGES="$(cd "$(dirname "${2:?}")" && pwd)/$(basename "$2")"; shift 2 ;;
    --root) ROOT="${2:?}"; shift 2 ;;
    -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "protect-paths: unknown argument '$1'" >&2; exit 3 ;;
  esac
done
[ -n "$ROOT" ] || ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT" || exit 0
[ -d .agents/rules ] || exit 0

glob2re() {
  printf '%s' "$1" | sed -E \
    -e 's/[].[^$()+|]/\\&/g' \
    -e 's#\*\*/#@@ANYDIR@@#g' -e 's#\*\*#@@ANY@@#g' \
    -e 's#\*#[^/]*#g' -e 's#\?#[^/]#g' \
    -e 's#@@ANYDIR@@#(.*/)?#g' -e 's#@@ANY@@#.*#g' \
    -e ':b' -e 's#\{([^{}]*),([^{}]*)\}#{\1|\2}#' -e 'tb' \
    -e 's#\{([^{}]*)\}#(\1)#g'
}

# Emit "name<TAB>protect<TAB>regex" for each protected glob.
RULES="$(for f in .agents/rules/*.md; do
  [ -f "$f" ] || continue
  awk -v name="$(basename "$f" .md)" '
    function trim(s){ sub(/^[ \t]+/,"",s); sub(/[ \t]+$/,"",s); if (s ~ /^".*"$/ || s ~ /^'\''.*'\''$/) s=substr(s,2,length(s)-2); return s }
    NR==1 && /^---/ { fm=1; next } fm==1 && /^---/ { exit }
    fm==1 && /^protect:/ { p=$0; sub(/^protect:/,"",p); prot=trim(p) }
    fm==1 && /^paths:[ \t]*\[/ { s=$0; sub(/^paths:[ \t]*\[/,"",s); sub(/\][ \t]*$/,"",s); n=split(s,a,","); for(i=1;i<=n;i++) g[++k]=trim(a[i]); inp=0; next }
    fm==1 && /^paths:[ \t]*$/ { inp=1; next }
    fm==1 && inp && /^[ \t]*-/ { x=$0; sub(/^[ \t]*-[ \t]*/,"",x); g[++k]=trim(x); next }
    fm==1 { inp=0 }
    END { if (prot!="" && prot!="false") for(i=1;i<=k;i++) print name "\t" prot "\t" g[i] }' "$f"
done)"
[ -n "$RULES" ] || exit 0

rule_body() { awk 'NR==1&&/^---/{fm=1;next} fm==1&&/^---/{fm=2;next} fm==2' ".agents/rules/$1.md" | sed -e '/./,$!d' | head -n 5; }

# check PATH ACTION(read|edit|delete|add) -> prints "name" of the blocking rule, if any
check() {
  local path="$1" action="$2"
  while IFS=$'\t' read -r name prot glob; do
    printf '%s\n' "$path" | grep -qE "^$(glob2re "$glob")$" || continue
    case "$prot:$action" in
      read:*|true:edit|true:delete|true:add|existing:edit|existing:delete) echo "$name"; return 0 ;;
    esac
  done <<< "$RULES"
  return 1
}

if [ "$MODE" = "staged" ] || [ "$MODE" = "changes" ]; then
  if [ "$MODE" = "staged" ]; then LIST="$(git diff --cached --name-status --no-renames)"; else LIST="$(cat "$CHANGES")"; fi
  blocked=0
  while IFS=$'\t' read -r st path; do
    [ -n "$path" ] || continue
    case "$st" in A*) act=add ;; D*) act=delete ;; *) act=edit ;; esac
    if name="$(check "$path" "$act")"; then
      echo "protect-paths: '$path' ($act) is protected by .agents/rules/$name.md:" >&2
      rule_body "$name" | sed 's/^/  /' >&2; blocked=1
    fi
  done <<< "$LIST"
  exit $blocked
fi

# Hook mode: parse the tool input without jq.
INPUT="$(cat)"
tool="$(printf '%s' "$INPUT" | grep -oE '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n1 | sed -E 's/.*"([^"]*)"$/\1/')"
file="$(printf '%s' "$INPUT" | grep -oE '"(file_path|notebook_path)"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n1 | sed -E 's/.*"([^"]*)"$/\1/')"
[ -n "$file" ] || exit 0
rel="${file#"$ROOT"/}"; rel="${rel#./}"
case "$tool" in
  Read) act=read ;;
  *) if [ -e "$file" ]; then act=edit; else act=add; fi ;;
esac
if name="$(check "$rel" "$act")"; then
  { echo "Blocked: '$rel' is protected by .agents/rules/$name.md."; rule_body "$name"; } >&2
  exit 2
fi
exit 0
