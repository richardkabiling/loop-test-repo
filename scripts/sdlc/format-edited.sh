#!/usr/bin/env bash
# format-edited.sh: Claude Code PostToolUse hook that formats only the file just edited.
#
# Usage (settings.json): bash scripts/sdlc/format-edited.sh -- <formatter command that takes a path>
#   e.g.  ... -- npx --no-install prettier --write
#         ... -- uvx ruff@0.8.0 format
# Reads the hook JSON on stdin, appends the edited file's path to the command, runs it.
# Always exits 0: formatting must never block the agent (CI and pre-commit enforce format).
set -uo pipefail
[ "${1:-}" = "--" ] && shift
[ $# -gt 0 ] || { cat >/dev/null; exit 0; }
case "${1:-}" in -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac
file="$(cat | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n1 | sed -E 's/.*"([^"]*)"$/\1/')"
[ -n "$file" ] && [ -f "$file" ] || exit 0
"$@" "$file" >/dev/null 2>&1 || true
exit 0
