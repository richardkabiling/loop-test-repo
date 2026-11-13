#!/usr/bin/env bash
# pr-tier.sh: compute a PR's review tier from the files it changes. Read-only.
#
# Tiers come from docs/sdlc/pr-tiers.json (generated from loop.json review.pr.tiers), listed
# highest first. Each changed file takes the first non-default tier whose `match` globs hit it,
# else the tier marked "default": true. The PR takes the highest tier among its files.
#
# Usage: pr-tier.sh [--base REF | --stdin] [--tiers FILE] [--check-label LABELS] [--json] [--help]
#   --base REF          changed files = git diff --name-only REF...HEAD (default: origin/HEAD, else main)
#   --stdin             read changed file paths from stdin, one per line
#   --tiers FILE        tiers JSON (default docs/sdlc/pr-tiers.json; falls back to docs/sdlc/loop.json)
#   --check-label L     comma-separated labels on the PR; exit 1 if a tier:<id> label names a lower
#                       tier than the files require (or is missing)
#   --json              print JSON instead of text
# Exit codes: 0 ok, 1 label understates the tier, 2 usage/IO error (or python3 missing).
set -uo pipefail

BASE=""; STDIN=0; TIERS=""; LABELS=""; LABELS_SET=0; JSON=0
while [ $# -gt 0 ]; do
  case "$1" in
    --base) BASE="${2:?}"; shift 2 ;;
    --stdin) STDIN=1; shift ;;
    --tiers) TIERS="${2:?}"; shift 2 ;;
    --check-label) LABELS="${2-}"; LABELS_SET=1; shift 2 ;;
    --json) JSON=1; shift ;;
    -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "pr-tier: unknown argument '$1' (try --help)" >&2; exit 2 ;;
  esac
done
command -v python3 >/dev/null 2>&1 || { echo "pr-tier: python3 is required" >&2; exit 2; }

if [ -z "$TIERS" ]; then
  if [ -f docs/sdlc/pr-tiers.json ]; then TIERS=docs/sdlc/pr-tiers.json
  elif [ -f docs/sdlc/loop.json ]; then TIERS=docs/sdlc/loop.json
  else echo "pr-tier: no docs/sdlc/pr-tiers.json or loop.json (use --tiers)" >&2; exit 2; fi
fi

if [ "$STDIN" -eq 1 ]; then FILES="$(cat)"
else
  if [ -z "$BASE" ]; then
    BASE="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)"
    [ -n "$BASE" ] || BASE=main
  fi
  FILES="$(git diff --name-only "$BASE"...HEAD 2>/dev/null)" || { echo "pr-tier: git diff against '$BASE' failed" >&2; exit 2; }
fi

PR_TIER_FILES="$FILES" python3 - "$TIERS" "$LABELS" "$LABELS_SET" "$JSON" <<'PY'
import json, os, re, sys
path, labels, labels_set, as_json = sys.argv[1], sys.argv[2], sys.argv[3] == "1", sys.argv[4] == "1"
try:
    d = json.load(open(path, encoding="utf-8"))
except (OSError, ValueError) as e:
    print(f"pr-tier: cannot read {path}: {e}", file=sys.stderr); sys.exit(2)
tiers = d if isinstance(d, list) else (((d.get("review") or {}).get("pr") or {}).get("tiers") or [])
if not tiers:
    print("pr-tier: no tiers defined (review.pr.tiers)", file=sys.stderr); sys.exit(2)
default = next((t for t in tiers if t.get("default")), tiers[-1])

def glob_re(g):
    out, i = "", 0
    while i < len(g):
        c = g[i]
        if g.startswith("**/", i): out += "(?:.*/)?"; i += 3; continue
        if g.startswith("**", i): out += ".*"; i += 2; continue
        if c == "*": out += "[^/]*"
        elif c == "?": out += "[^/]"
        elif c == "{":
            j = g.find("}", i)
            if j > i: out += "(?:" + "|".join(re.escape(x) for x in g[i+1:j].split(",")) + ")"; i = j + 1; continue
            out += re.escape(c)
        else: out += re.escape(c)
        i += 1
    if g.endswith("/"): out += ".*"
    return re.compile("^" + out + "$")

compiled = [(t, [glob_re(g) for g in (t.get("match") or [])]) for t in tiers]
rank = {t.get("id"): i for i, t in enumerate(tiers)}
files = [f for f in (l.strip() for l in os.environ.get("PR_TIER_FILES", "").splitlines()) if f]
per_file = []
for f in files:
    hit = next((t for t, res in compiled if not t.get("default") and any(r.match(f) for r in res)), default)
    per_file.append((f, hit.get("id")))
tier = min((tid for _, tid in per_file), key=lambda x: rank[x]) if per_file else default.get("id")
t = next(x for x in tiers if x.get("id") == tier)
setters = [f for f, tid in per_file if tid == tier][:10]
res = {"tier": tier, "files": len(files), "set_by": setters,
       "human_approvals": t.get("human_approvals"), "required_roles": t.get("required_roles") or [],
       "ai": t.get("ai") or [], "extra_lenses": t.get("extra_lenses") or [], "why": t.get("why", "")}
code = 0
if labels_set:
    claimed = [l.strip()[5:] for l in labels.split(",") if l.strip().startswith("tier:")]
    if not claimed:
        res["label_check"] = f"missing: add label tier:{tier}"; code = 1
    else:
        c = claimed[0]
        if c not in rank:
            res["label_check"] = f"unknown tier label tier:{c}"; code = 1
        elif rank[c] > rank[tier]:
            res["label_check"] = f"understated: label tier:{c}, files require tier:{tier}"; code = 1
        else:
            res["label_check"] = "ok"
if as_json:
    print(json.dumps(res))
else:
    print(f"tier: {tier}  ({len(files)} changed files)")
    if setters: print("set by: " + ", ".join(setters) + (" …" if len([1 for _, x in per_file if x == tier]) > 10 else ""))
    roles = ", ".join(res["required_roles"]) or "any"
    print(f"human approvals: {res['human_approvals']} (roles: {roles})")
    print("ai reviewers: " + (", ".join(res["ai"]) or "none"))
    if res["extra_lenses"]: print("extra lenses: " + ", ".join(res["extra_lenses"]))
    if res["why"]: print("why: " + res["why"])
    if "label_check" in res: print("label: " + res["label_check"])
sys.exit(code)
PY
