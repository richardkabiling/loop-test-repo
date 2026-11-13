#!/usr/bin/env bash
# run-evals.sh: run the eval suites a change triggers, grade them, and report. Called by /<prefix>-review
# (and by /<prefix>-improve before and after a harness change). Needs python3 and git.
#
# Suites come from docs/sdlc/loop.json review.evals.suites. A suite runs when any changed file matches
# its `triggers` globs (or with --all / --suite). Two kinds:
#   product  a command (`run`), e.g. `npx promptfoo eval -c evals/promptfooconfig.yaml`; pass = exit 0
#            `where` says where it executes: local (default: this machine, with its keys and model access),
#            ci (the repo's existing CI runs it; this reads the named check with gh, never runs it), or
#            platform (a hosted eval tool's CLI runs it and uploads; `link` points to the results).
#            `secrets` lists env vars the suite needs; a missing one fails the run before it starts.
#   harness  a scenario file (`path`, Agent Skills evals shape: {"scenarios":[{id, prompt, checks?,
#            assertions?, setup_cmd?}]}). Each scenario runs headless in a throwaway git worktree with
#            the agent command, then is graded: every `checks` shell command must exit 0 in the worktree,
#            and every `assertions` line must be judged true by a separate grader session that sees only
#            the assertions, the agent's final message and the diff. Pass rate >= `threshold` passes.
# Runs fail closed: a run that can't start, times out or is skipped for budget counts as failed.
#
# Usage: run-evals.sh [--base REF | --all | --suite ID] [--ref REF] [--dry-run] [--out DIR]
#                     [--agent-cmd CMD] [--grader-cmd CMD] [--max-cost USD] [--help]
#   --base REF     changed files = REF...HEAD (default origin/HEAD, else main)
#   --ref REF      run harness scenarios against this commit (default HEAD); improve runs base, then head
#   --dry-run      list the suites that would run and why; run nothing (no cost)
#   --out DIR      results folder (default docs/sdlc/evals/results)
#   --agent-cmd    default review.evals.agent_cmd, else: claude -p --output-format json --max-turns 40 --permission-mode acceptEdits
#   --grader-cmd   default review.evals.grader_cmd, else: claude -p --output-format json --max-turns 1
#   --max-cost     stop starting runs past this total USD (default review.evals.max_cost_usd, else 10)
# Output: a Markdown summary on stdout (postable as-is) and a JSON results file.
# Exit codes: 0 every selected suite passed (or nothing selected), 1 a suite failed or was incomplete, 2 usage/IO.
set -uo pipefail

BASE=""; MODE="changed"; SUITE=""; REF="HEAD"; DRY=0; OUT=""; AGENT=""; GRADER=""; MAXCOST=""
while [ $# -gt 0 ]; do
  case "$1" in
    --base) BASE="${2:?}"; shift 2 ;;
    --all) MODE="all"; shift ;;
    --suite) MODE="suite"; SUITE="${2:?}"; shift 2 ;;
    --ref) REF="${2:?}"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --out) OUT="${2:?}"; shift 2 ;;
    --agent-cmd) AGENT="${2:?}"; shift 2 ;;
    --grader-cmd) GRADER="${2:?}"; shift 2 ;;
    --max-cost) MAXCOST="${2:?}"; shift 2 ;;
    -h|--help) sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "run-evals: unknown argument '$1' (try --help)" >&2; exit 2 ;;
  esac
done
command -v python3 >/dev/null 2>&1 || { echo "run-evals: python3 is required" >&2; exit 2; }
[ -f docs/sdlc/loop.json ] || { echo "run-evals: docs/sdlc/loop.json not found (run from the repo root)" >&2; exit 2; }
if [ -z "$BASE" ]; then
  BASE="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  [ -n "$BASE" ] || BASE=main
fi
CHANGED=""
[ "$MODE" = "changed" ] && { CHANGED="$(git diff --name-only "$BASE"...HEAD 2>/dev/null)" || { echo "run-evals: git diff against '$BASE' failed" >&2; exit 2; }; }

RE_CHANGED="$CHANGED" RE_MODE="$MODE" RE_SUITE="$SUITE" RE_REF="$REF" RE_DRY="$DRY" RE_OUT="$OUT" \
RE_AGENT="$AGENT" RE_GRADER="$GRADER" RE_MAXCOST="$MAXCOST" python3 - <<'PY'
import json, os, re, shlex, subprocess, sys, tempfile, time

env = os.environ
loop = json.load(open("docs/sdlc/loop.json", encoding="utf-8"))
ev = ((loop.get("review") or {}).get("evals")) or {}
suites = ev.get("suites") or []
name = (loop.get("harness") or {}).get("name", "Harness")
agent_cmd = env["RE_AGENT"] or ev.get("agent_cmd") or "claude -p --output-format json --max-turns 40 --permission-mode acceptEdits"
grader_cmd = env["RE_GRADER"] or ev.get("grader_cmd") or "claude -p --output-format json --max-turns 1"
max_cost = float(env["RE_MAXCOST"] or ev.get("max_cost_usd") or 10)
out_dir = env["RE_OUT"] or "docs/sdlc/evals/results"
ref = env["RE_REF"]

def glob_re(g):
    out, i = "", 0
    while i < len(g):
        if g.startswith("**/", i): out += "(?:.*/)?"; i += 3; continue
        if g.startswith("**", i): out += ".*"; i += 2; continue
        c = g[i]
        out += "[^/]*" if c == "*" else "[^/]" if c == "?" else re.escape(c)
        i += 1
    if g.endswith("/"): out += ".*"
    return re.compile("^" + out + "$")

changed = [f for f in env["RE_CHANGED"].splitlines() if f.strip() and not f.startswith(out_dir.rstrip("/") + "/")]
selected = []
for s in suites:
    if env["RE_MODE"] == "all": why = "--all"
    elif env["RE_MODE"] == "suite": why = "--suite" if s.get("id") == env["RE_SUITE"] else None
    else:
        res = [glob_re(g) for g in s.get("triggers") or []]
        hits = [f for f in changed if any(r.match(f) for r in res)]
        why = ("changed: " + ", ".join(hits[:5]) + (" …" if len(hits) > 5 else "")) if hits else None
    if why: selected.append((s, why))

if not selected:
    print(f"### {name} evals\n\nNo eval suite is triggered by this change.")
    sys.exit(0)
if env["RE_DRY"] == "1":
    print(f"### {name} evals (dry run)\n")
    for s, why in selected:
        print(f"- `{s.get('id')}` ({s.get('kind')}, {s.get('where', 'local')}): {why}")
    sys.exit(0)

spent = 0.0
def run(cmd, cwd, timeout, stdin=None):
    try:
        p = subprocess.run(cmd, cwd=cwd, shell=isinstance(cmd, str), input=stdin, capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout, p.stderr
    except subprocess.TimeoutExpired:
        return 124, "", "timed out"

def agent_result(stdout):
    global spent
    try:
        j = json.loads(stdout.strip().splitlines()[-1])
        spent += float(j.get("total_cost_usd") or 0)
        return j.get("result") or ""
    except (ValueError, IndexError):
        return stdout[-4000:]

def grade(assertions, final, diff):
    prompt = ("You are grading an eval run. You see only the assertions, the agent's final message and the diff.\n"
              "Judge each assertion strictly from this evidence. Reply with JSON only: "
              '{"results":[{"assertion":"...","pass":true|false,"evidence":"..."}]}\n\n'
              "ASSERTIONS:\n" + "\n".join(f"- {a}" for a in assertions) +
              "\n\nFINAL MESSAGE:\n" + final[:6000] + "\n\nDIFF (truncated):\n" + diff[:20000])
    code, out, err = run(shlex.split(grader_cmd) + [prompt], ".", 300)
    if code != 0: return [{"assertion": a, "pass": False, "evidence": "grader failed: " + err[:200]} for a in assertions]
    text = agent_result(out)
    m = re.search(r"\{.*\}", text, re.S)
    try:
        return json.loads(m.group(0))["results"]
    except (AttributeError, ValueError, KeyError):
        return [{"assertion": a, "pass": False, "evidence": "grader reply unreadable"} for a in assertions]

report = {"harness": name, "ref": subprocess.run(["git", "rev-parse", "--short", ref], capture_output=True, text=True).stdout.strip(),
          "at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "suites": []}
for s, why in selected:
    sid, kind = s.get("id"), s.get("kind")
    thr = float(s.get("threshold", 1.0))
    runs = []
    where = s.get("where", "local")
    missing = [v for v in s.get("secrets") or [] if not os.environ.get(v)]
    if missing:
        runs.append({"id": sid, "pass": False, "detail": "missing secrets: " + ", ".join(missing) + " (set them in this shell; never commit them)"})
    elif where == "ci":
        chk = s.get("ci_check", "")
        code, out, err = run(["gh", "pr", "checks", "--json", "name,state"], ".", 60)
        try:
            states = {c["name"]: c["state"] for c in json.loads(out)}
        except ValueError:
            states = {}
        st = states.get(chk)
        runs.append({"id": sid, "pass": st == "SUCCESS",
                     "detail": f"CI check '{chk}': {st or 'not found (no PR yet, gh missing, or the check did not run)'}"})
    elif kind == "product":
        code, out, err = run(s.get("run", "false"), ".", int(s.get("timeout_min", 30)) * 60)
        detail = (out + err)[-1500:] + (f"\nresults: {s['link']}" if where == "platform" and s.get("link") else "")
        runs.append({"id": sid, "pass": code == 0, "detail": detail})
    else:
        try:
            scen = json.load(open(s["path"], encoding="utf-8")).get("scenarios") or []
        except (OSError, ValueError, KeyError) as e:
            scen = []; runs.append({"id": "load", "pass": False, "detail": f"cannot read {s.get('path')}: {e}"})
        for sc in scen:
            for rep in range(int(s.get("repeat", 1))):
                rid = f"{sc.get('id')}#{rep + 1}"
                if spent >= max_cost:
                    runs.append({"id": rid, "pass": False, "detail": f"skipped: budget {max_cost} USD spent"}); continue
                wt = tempfile.mkdtemp(prefix="evals-")
                if subprocess.run(["git", "worktree", "add", "--detach", wt, ref], capture_output=True).returncode != 0:
                    runs.append({"id": rid, "pass": False, "detail": "git worktree add failed"}); continue
                try:
                    if sc.get("setup_cmd"): run(sc["setup_cmd"], wt, 600)
                    code, out, err = run(shlex.split(agent_cmd) + [sc.get("prompt", "")], wt, int(s.get("timeout_min", 20)) * 60)
                    final = agent_result(out)
                    checks = [{"check": c, "pass": run(c, wt, 600)[0] == 0} for c in sc.get("checks") or []]
                    diff = run("git add -A >/dev/null 2>&1; git diff --cached HEAD", wt, 60)[1]
                    graded = grade(sc["assertions"], final, diff) if sc.get("assertions") else []
                    ok = code == 0 and all(c["pass"] for c in checks) and all(g.get("pass") for g in graded)
                    runs.append({"id": rid, "pass": ok, "agent_exit": code, "checks": checks, "assertions": graded})
                finally:
                    subprocess.run(["git", "worktree", "remove", "--force", wt], capture_output=True)
    passed = sum(1 for r in runs if r["pass"])
    rate = passed / len(runs) if runs else 0.0
    report["suites"].append({"id": sid, "kind": kind, "where": where, "why": why, "threshold": thr, "pass_rate": round(rate, 3),
                             "passed": bool(runs) and rate >= thr, "runs": runs})
report["cost_usd"] = round(spent, 2)

os.makedirs(out_dir, exist_ok=True)
path = os.path.join(out_dir, f"{report['at'][:10]}-{report['ref'] or 'ref'}.json")
json.dump(report, open(path, "w", encoding="utf-8"), indent=2)
ok = all(x["passed"] for x in report["suites"])
print(f"### {name} evals: {'pass' if ok else 'FAIL'}\n")
print(f"Ref `{report['ref']}` · cost ${report['cost_usd']} · results `{path}`\n")
print("| Suite | Kind | Where | Triggered by | Pass rate | Threshold | Result |\n|---|---|---|---|---|---|---|")
for x in report["suites"]:
    print(f"| `{x['id']}` | {x['kind']} | {x['where']} | {x['why']} | {x['pass_rate']:.0%} | {x['threshold']:.0%} | {'pass' if x['passed'] else '**fail**'} |")
fails = [(x["id"], r) for x in report["suites"] for r in x["runs"] if not r["pass"]]
if fails:
    print("\nFailed runs:")
    for sid, r in fails[:15]:
        why = r.get("detail") or "; ".join([c["check"] for c in r.get("checks", []) if not c["pass"]] +
                                           [g.get("assertion", "") for g in r.get("assertions", []) if not g.get("pass")])
        print(f"- `{sid}` {r['id']}: {why[:200]}")
sys.exit(0 if ok else 1)
PY
