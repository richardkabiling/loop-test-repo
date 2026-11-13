#!/usr/bin/env bash
# diff-guard.sh: deterministic checks for common AI-coding failure modes in a diff.
#
#   size        diff larger than --max-lines / --max-files (lockfiles and generated files excluded)
#   test-skip   added .skip/.only/xit/@pytest.mark.skip/t.Skip/#[ignore]/@Disabled and similar
#   test-delete test files deleted
#   assert-drop test files lose more assertions than they gain (weakened tests)
#   lockfile    lockfile changed with no manifest change in the same folder
#   registry    (--check-registry) every newly added npm/PyPI dependency exists in its registry
#               (guards against hallucinated packages / slopsquatting; needs python3 + network)
#
# Usage: diff-guard.sh [--base REF | --staged | --worktree] [options]
#   --base REF            compare REF...HEAD (CI on a PR: --base origin/main)
#   --staged              staged changes (pre-commit)
#   --worktree            working tree vs HEAD, including untracked files (default; Stop hook)
#   --max-lines N         default 400 changed lines;  --max-files N  default 30
#   --size warn|fail      default warn (a big diff is a smell, not always wrong)
#   --check-registry      look up new dependencies (package.json, requirements*.txt, pyproject.toml)
#   --allow-test-changes  downgrade test-skip/test-delete/assert-drop to warnings (use when a human
#                         approved, e.g. a PR label `test-change-approved`)
#   --root DIR, --help
# Output: one "ok|warn|fail: ..." line per check. Exit 1 if any check fails, 2 on usage error.
set -uo pipefail

MODE="worktree"; BASE=""; MAXL=400; MAXF=30; SIZE="warn"; ALLOW=0; ROOT="."; REG=0
while [ $# -gt 0 ]; do
  case "$1" in
    --base) MODE="base"; BASE="${2:?}"; shift 2 ;;
    --staged) MODE="staged"; shift ;;
    --worktree) MODE="worktree"; shift ;;
    --max-lines) MAXL="${2:?}"; shift 2 ;;
    --max-files) MAXF="${2:?}"; shift 2 ;;
    --size) SIZE="${2:?}"; shift 2 ;;
    --allow-test-changes) ALLOW=1; shift ;;
    --check-registry) REG=1; shift ;;
    --root) ROOT="${2:?}"; shift 2 ;;
    -h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "diff-guard: unknown argument '$1' (try --help)" >&2; exit 2 ;;
  esac
done
cd "$ROOT" || exit 2
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "diff-guard: not a git repository" >&2; exit 2; }

case "$MODE" in
  base)     RANGE=("$BASE...HEAD") ;;
  staged)   RANGE=(--cached) ;;
  worktree) RANGE=(HEAD) ;;
esac
FAILS=0
ok()   { echo "ok:   $1"; }
warn() { echo "warn: $1"; }
fail() { echo "fail: $1"; FAILS=$((FAILS + 1)); }
tfail() { if [ "$ALLOW" -eq 1 ]; then warn "$1 (allowed by --allow-test-changes)"; else fail "$1"; fi; }

LOCK_RE='(^|/)(package-lock\.json|pnpm-lock\.yaml|yarn\.lock|bun\.lockb?|Cargo\.lock|poetry\.lock|uv\.lock|Pipfile\.lock|go\.sum|Gemfile\.lock|composer\.lock)$'
GEN_RE='(^|/)(gen|generated|__generated__|vendor|third_party|dist|build)/|\.pb\.go$|_pb2\.py$|\.generated\.|\.min\.(js|css)$|\.snap$'
TEST_RE='(^|/)(tests?|__tests__|spec|e2e)/|[._-](test|spec)\.[A-Za-z]+$|_test\.(go|py|rb|exs)$|(^|/)test_[^/]*\.py$'
SKIP_RE='(^|[^A-Za-z0-9_])(it|test|describe|context)\.(skip|only|todo)\(|(^|[^A-Za-z0-9_])(xit|xdescribe|xtest|fit|fdescribe)\(|@pytest\.mark\.(skip|xfail)|pytest\.skip\(|unittest\.skip|(^|[^A-Za-z0-9_])t\.Skip(Now|f)?\(|#\[ignore\]|@Disabled|@Ignore([^A-Za-z]|$)|(^|[^A-Za-z0-9_])skip:[[:space:]]*true'
ASSERT_RE='(^|[^A-Za-z0-9_])(expect|assert[A-Za-z_]*|should|require\.[A-Za-z]+|t\.(Error|Fatal)f?)([^A-Za-z0-9_]|$)|assert!|assert_eq!'

NUMSTAT="$(git diff --numstat --no-renames "${RANGE[@]}" 2>/dev/null)"
STATUS="$(git diff --name-status --no-renames "${RANGE[@]}" 2>/dev/null)"
PATCH="$(git diff -U0 --no-renames "${RANGE[@]}" 2>/dev/null)"
if [ "$MODE" = "worktree" ]; then
  UNTRACKED="$(git ls-files -o --exclude-standard)"
  for f in $UNTRACKED; do
    [ -f "$f" ] || continue
    n=$(wc -l < "$f" | tr -d ' ')
    NUMSTAT="$NUMSTAT"$'\n'"$n	0	$f"; STATUS="$STATUS"$'\n'"A	$f"
    PATCH="$PATCH"$'\n'"+++ b/$f"$'\n'"$(sed 's/^/+/' "$f")"
  done
fi

# size
read -r lines files <<< "$(printf '%s\n' "$NUMSTAT" | awk -F'\t' -v L="$LOCK_RE" -v G="$GEN_RE" \
  'NF>=3 && $3!~L && $3!~G { a=($1=="-"?0:$1); d=($2=="-"?0:$2); n+=a+d; f++ } END { print n+0, f+0 }')"
if [ "$lines" -gt "$MAXL" ] || [ "$files" -gt "$MAXF" ]; then
  msg="diff is $lines lines across $files files (caps: $MAXL lines, $MAXF files). Split into smaller tracer-bullet slices"
  if [ "$SIZE" = "fail" ]; then fail "$msg"; else warn "$msg"; fi
else ok "diff size $lines lines, $files files"; fi

# per-file added/removed lines from the patch: "file<TAB>sign<TAB>line"
LINES="$(printf '%s\n' "$PATCH" | awk '
  /^\+\+\+ b\// { f=substr($0,7); next } /^--- / { next } /^\+\+\+ / { next }
  /^\+/ && f!="" { print f "\t+\t" substr($0,2); next }
  /^-/  && f!="" { print f "\t-\t" substr($0,2) }')"

# test-skip
skips="$(printf '%s\n' "$LINES" | awk -F'\t' -v T="$TEST_RE" '$2=="+" && $1~T' | grep -E "$SKIP_RE" | awk -F'\t' '{print $1}' | sort -u | head -n 10 | paste -sd, -)"
if [ -n "$skips" ]; then tfail "skipped or focused tests added in: $skips. Fix the code, not the test"; else ok "no skipped or focused tests added"; fi

# test-delete
deleted="$(printf '%s\n' "$STATUS" | awk -F'\t' -v T="$TEST_RE" '$1 ~ /^D/ && $2 ~ T {print $2}' | head -n 10 | paste -sd, -)"
if [ -n "$deleted" ]; then tfail "test files deleted: $deleted"; else ok "no test files deleted"; fi

# assert-drop
drop="$(printf '%s\n' "$LINES" | awk -F'\t' -v T="$TEST_RE" -v A="$ASSERT_RE" '
  $1~T && $3~A { if ($2=="+") add[$1]++; else rem[$1]++; seen[$1]=1 }
  END { for (f in seen) if (rem[f] > add[f]+0) printf "%s(-%d/+%d) ", f, rem[f], add[f]+0 }')"
if [ -n "$drop" ]; then tfail "tests lost assertions: $drop. Check that no test was weakened"; else ok "no net assertion loss in tests"; fi

# lockfile without manifest
lockonly=""
for lf in $(printf '%s\n' "$STATUS" | awk -F'\t' -v L="$LOCK_RE" 'NF>=2 && $2~L {print $2}'); do
  d="$(dirname "$lf")"
  if ! printf '%s\n' "$STATUS" | awk -F'\t' '{print $2}' | grep -qE "^($d/)?(package\.json|Cargo\.toml|pyproject\.toml|go\.mod|Gemfile|composer\.json|Pipfile)$"; then
    lockonly="$lockonly $lf"
  fi
done
if [ -n "$lockonly" ]; then warn "lockfile changed without a manifest change:$lockonly (an unreviewed dependency bump?)"; else ok "lockfiles consistent with manifests"; fi

# registry: new dependencies must exist
if [ "$REG" -eq 1 ]; then
  if ! command -v python3 >/dev/null 2>&1; then warn "--check-registry needs python3; skipped"
  else
    case "$MODE" in
      base) OLDREF="$(git merge-base "$BASE" HEAD 2>/dev/null || echo "$BASE")"; NEWREF="HEAD" ;;
      staged) OLDREF="HEAD"; NEWREF=":" ;;
      worktree) OLDREF="HEAD"; NEWREF="" ;;
    esac
    MANIFESTS="$(printf '%s\n' "$STATUS" | awk -F'\t' 'NF>=2 && $1!~/^D/ && $2 ~ /(^|\/)(package\.json|requirements[^\/]*\.txt|pyproject\.toml)$/ {print $2}')"
    if [ -z "$MANIFESTS" ]; then ok "no dependency manifests changed"
    else
      out="$(OLDREF="$OLDREF" NEWREF="$NEWREF" python3 - $MANIFESTS <<'PY'
import json, os, re, subprocess, sys, urllib.request, urllib.error, urllib.parse
old_ref, new_ref = os.environ["OLDREF"], os.environ["NEWREF"]
def show(ref, path):
    if ref == "":
        try: return open(path, encoding="utf-8").read()
        except OSError: return ""
    spec = (":" + path) if ref == ":" else f"{ref}:{path}"
    r = subprocess.run(["git", "show", spec], capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else ""
def norm(n): return re.sub(r"[-_.]+", "-", n).lower()
def deps(path, text):
    if not text.strip(): return set(), None
    if path.endswith("package.json"):
        try: d = json.loads(text)
        except ValueError: return set(), None
        names = set()
        for k in ("dependencies", "devDependencies", "optionalDependencies", "peerDependencies"):
            for n, v in (d.get(k) or {}).items():
                if isinstance(v, str) and re.match(r"^(file:|link:|workspace:|git|github:|https?:|\.|/)", v): continue
                names.add(n)
        return names, "npm"
    names = set()
    if path.endswith(".txt"):
        for line in text.splitlines():
            line = line.split("#")[0].strip()
            if not line or line.startswith(("-", "git+", "http")) or "://" in line: continue
            m = re.match(r"^([A-Za-z0-9][A-Za-z0-9._-]*)", line)
            if m: names.add(norm(m.group(1)))
        return names, "pypi"
    try:
        import tomllib
        t = tomllib.loads(text)
    except Exception:
        return set(), None
    lst = list((t.get("project") or {}).get("dependencies") or [])
    for g in ((t.get("project") or {}).get("optional-dependencies") or {}).values(): lst += g
    for g in (t.get("dependency-groups") or {}).values(): lst += [x for x in g if isinstance(x, str)]
    for x in lst:
        m = re.match(r"^\s*([A-Za-z0-9][A-Za-z0-9._-]*)", x)
        if m: names.add(norm(m.group(1)))
    return names, "pypi"
def exists(name, eco):
    url = ("https://registry.npmjs.org/" + urllib.parse.quote(name, safe="@")) if eco == "npm" else f"https://pypi.org/pypi/{name}/json"
    try:
        with urllib.request.urlopen(urllib.request.Request(url, method="GET", headers={"Accept": "application/json"}), timeout=15) as r:
            return r.status == 200
    except urllib.error.HTTPError as e:
        return False if e.code == 404 else None
    except Exception:
        return None
for path in sys.argv[1:]:
    new, eco = deps(path, show(new_ref, path))
    old, _ = deps(path, show(old_ref, path))
    for n in sorted(new - old)[:40]:
        r = exists(n, eco)
        print(("missing" if r is False else "ok" if r else "unknown") + "\t" + eco + "\t" + n + "\t" + path)
PY
)"
      missing="$(printf '%s\n' "$out" | awk -F'\t' '$1=="missing"{printf "%s (%s, %s) ", $3, $2, $4}')"
      unknown="$(printf '%s\n' "$out" | awk -F'\t' '$1=="unknown"{printf "%s ", $3}')"
      added="$(printf '%s\n' "$out" | awk -F'\t' 'NF>=3' | wc -l | tr -d ' ')"
      if [ -n "$missing" ]; then fail "new dependencies not found in their registry: $missing. Possibly hallucinated; check the name"
      elif [ -n "$unknown" ]; then warn "couldn't reach the registry to verify: $unknown"
      else ok "$added new dependencies, all found in their registries"; fi
    fi
  fi
fi

[ "$FAILS" -gt 0 ] && { echo "diff-guard: $FAILS failing check(s)"; exit 1; }
echo "diff-guard: clean"
