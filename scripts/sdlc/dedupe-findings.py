#!/usr/bin/env python3
"""dedupe-findings.py: merge persona-review findings and drop ones already handled.

Every context-less persona reviewer emits findings as JSON objects (one per line, or a JSON array):
  {"persona": "security", "severity": "major|minor|nit", "location": "src/a.ts:10-14" | "spec.md#acceptance-criteria",
   "claim": "one sentence", "evidence": "file:line, command output or spec clause", "suggestion": "concrete fix"}

This script:
  1. merges findings that point at the same place and say the same thing (same file/section, overlapping or
     nearby lines, similar claim), or that say nearly the same thing anywhere; it keeps the highest severity,
     the union of personas (agreement is a signal) and every distinct piece of evidence;
  2. drops findings that match a resolved or dismissed entry in the ledger (earlier rounds, the local review,
     or the PR bot), so a closed issue isn't raised again;
  3. with --update-ledger, appends the surviving findings to the ledger as "open".

Usage:
  dedupe-findings.py FINDINGS [FINDINGS...] [--ledger PATH] [--update-ledger] [--round N] [--threshold 0.35]
  dedupe-findings.py --close KEY --status resolved|dismissed --reason TEXT --ledger PATH
  dedupe-findings.py --summary --ledger PATH [--point P] [--title TEXT]

  --point P   with --update-ledger, tag new entries with the review point (intent, design:api, review, ...);
              with --summary, show only that point's entries
  --summary   print the ledger (latest status per finding) as one Markdown comment, ready to post on a PR,
              an epic or a ticket when the review point's findings are surfaced (not silent)

Output (stdout, JSON): {"findings": [...merged, sorted by severity then agreement], "suppressed": [...keys],
                        "stats": {"input": n, "merged": n, "suppressed": n, "major": n}}
Exit codes: 0 ok, 2 usage/IO error. Standard library only.
"""
import hashlib
import json
import re
import sys
import time

SEV = {"major": 3, "minor": 2, "nit": 1}
STOP = set("the a an and or of to in on for with is are be this that it its as at by from not no should must "
           "can could would will may might than then there their they them into over under when which while".split())


def tokens(text):
    return {w for w in re.findall(r"[a-z0-9_]+", (text or "").lower()) if len(w) > 2 and w not in STOP}


def jaccard(a, b):
    return len(a & b) / len(a | b) if a and b else 0.0


def parse_loc(loc):
    """'src/a.ts:10-14' -> ('src/a.ts', 10, 14); 'spec.md#ac' -> ('spec.md#ac', None, None)"""
    loc = (loc or "").strip()
    m = re.match(r"^(.*?):(\d+)(?:-(\d+))?$", loc)
    if m:
        a = int(m.group(2))
        return m.group(1), a, int(m.group(3) or a)
    return loc.lower(), None, None


def near(l1, l2, slack=3):
    f1, a1, b1 = l1
    f2, a2, b2 = l2
    if f1 != f2:
        return False
    if a1 is None or a2 is None:
        return True
    return a1 <= b2 + slack and a2 <= b1 + slack


def key_of(f):
    file_part = parse_loc(f.get("location"))[0]
    top = " ".join(sorted(tokens(f.get("claim")))[:8])
    return hashlib.sha1(f"{file_part}|{top}".encode()).hexdigest()[:12]


def same(f, g, thr):
    sim = jaccard(tokens(f.get("claim")), tokens(g.get("claim")))
    if near(parse_loc(f.get("location")), parse_loc(g.get("location"))) and sim >= thr:
        return True
    return sim >= max(0.6, thr + 0.25)


def load(paths):
    out = []
    for p in paths:
        text = open(p, encoding="utf-8").read().strip()
        if not text:
            continue
        if text.startswith("["):
            out.extend(json.loads(text))
        else:
            out.extend(json.loads(line) for line in text.splitlines() if line.strip())
    return out


def load_ledger(path):
    if not path:
        return []
    try:
        with open(path, encoding="utf-8") as fh:
            return [json.loads(line) for line in fh if line.strip()]
    except FileNotFoundError:
        return []


def main(argv):
    if len(argv) < 2 or argv[1] in ("-h", "--help"):
        print(__doc__.strip())
        return 0 if len(argv) >= 2 else 2
    args, files = argv[1:], []
    ledger_path, update, rnd, thr = None, False, None, 0.35
    close_key = status = reason = None
    point, summary, title = None, False, "Review findings"
    while args:
        a = args.pop(0)
        if a == "--ledger": ledger_path = args.pop(0)
        elif a == "--update-ledger": update = True
        elif a == "--round": rnd = int(args.pop(0))
        elif a == "--threshold": thr = float(args.pop(0))
        elif a == "--close": close_key = args.pop(0)
        elif a == "--status": status = args.pop(0)
        elif a == "--reason": reason = args.pop(0)
        elif a == "--point": point = args.pop(0)
        elif a == "--summary": summary = True
        elif a == "--title": title = args.pop(0)
        elif a.startswith("--"):
            print(f"dedupe-findings: unknown option {a}", file=sys.stderr); return 2
        else: files.append(a)

    if summary:
        if not ledger_path:
            print("dedupe-findings: --summary needs --ledger", file=sys.stderr); return 2
        latest = {}
        for e in load_ledger(ledger_path):
            latest[e.get("key")] = {**latest.get(e.get("key"), {}), **e}
        rows = [e for e in latest.values() if not point or e.get("point") == point]
        rows.sort(key=lambda e: (e.get("status") != "open", -SEV.get(e.get("severity"), 0)))
        cnt = {st: sum(1 for e in rows if e.get("status") == st) for st in ("open", "resolved", "dismissed")}
        out = [f"### {title}" + (f" ({point})" if point else ""), "",
               f"{len(rows)} findings: {cnt['open']} open, {cnt['resolved']} resolved, {cnt['dismissed']} dismissed.", ""]
        if rows:
            out += ["| Severity | Where | Finding | Lenses | Status |", "|---|---|---|---|---|"]
            for e in rows:
                cell = lambda v: str(v or "").replace("|", "\\|").replace("\n", " ")
                st = e.get("status", "open") + (f": {e.get('reason')}" if e.get("reason") else "")
                out.append(f"| {e.get('severity','')} | `{cell(e.get('location'))}` | {cell(e.get('claim'))} | "
                           f"{', '.join(e.get('personas') or [])} | {cell(st)} |")
        out += ["", "<sub>Context-less persona review, deduped across lenses and rounds. Updated in place.</sub>"]
        print("\n".join(out))
        return 0

    if close_key:
        if not (ledger_path and status in ("resolved", "dismissed")):
            print("dedupe-findings: --close needs --ledger and --status resolved|dismissed", file=sys.stderr); return 2
        entries = load_ledger(ledger_path)
        hit = [e for e in entries if e.get("key") == close_key]
        if not hit:
            print(f"dedupe-findings: no ledger entry {close_key}", file=sys.stderr); return 2
        with open(ledger_path, "a", encoding="utf-8") as fh:
            fh.write(json.dumps({**hit[-1], "status": status, "reason": reason or "", "at": int(time.time())}) + "\n")
        print(json.dumps({"closed": close_key, "status": status}))
        return 0

    try:
        raw = load(files)
    except (OSError, ValueError) as e:
        print(f"dedupe-findings: cannot read findings: {e}", file=sys.stderr); return 2

    groups = []
    for f in raw:
        f = {**f, "severity": f.get("severity", "minor") if f.get("severity") in SEV else "minor"}
        for g in groups:
            if same(f, g, thr):
                if SEV[f["severity"]] > SEV[g["severity"]]:
                    g.update({k: f.get(k, g.get(k)) for k in ("severity", "claim", "location", "suggestion")})
                g["personas"] = sorted(set(g["personas"]) | {f.get("persona", "?")})
                ev = f.get("evidence")
                if ev and ev not in g["evidence"]:
                    g["evidence"].append(ev)
                break
        else:
            groups.append({"severity": f["severity"], "claim": f.get("claim", ""), "location": f.get("location", ""),
                           "suggestion": f.get("suggestion", ""), "personas": [f.get("persona", "?")],
                           "evidence": [f["evidence"]] if f.get("evidence") else []})

    # latest status per key wins
    latest = {}
    for e in load_ledger(ledger_path):
        latest[e.get("key")] = e
    closed = [e for e in latest.values() if e.get("status") in ("resolved", "dismissed")]
    kept, suppressed = [], []
    for g in groups:
        g["key"] = key_of(g)
        g["agreement"] = len(g["personas"])
        match = next((e for e in closed if e.get("key") == g["key"] or same(g, e, thr)), None)
        # a dismissed minor that comes back as major is re-raised; everything else stays closed
        if match and not (match.get("status") == "dismissed" and SEV[g["severity"]] > SEV.get(match.get("severity"), 0)):
            suppressed.append(g["key"])
        else:
            kept.append(g)
    kept.sort(key=lambda g: (-SEV[g["severity"]], -g["agreement"]))

    if update and ledger_path:
        with open(ledger_path, "a", encoding="utf-8") as fh:
            for g in kept:
                if latest.get(g["key"], {}).get("status") != "open":
                    fh.write(json.dumps({"key": g["key"], "status": "open", "severity": g["severity"],
                                         "location": g["location"], "claim": g["claim"], "personas": g["personas"],
                                         "round": rnd, "point": point, "at": int(time.time())}) + "\n")

    print(json.dumps({"findings": kept, "suppressed": suppressed,
                      "stats": {"input": len(raw), "merged": len(kept), "suppressed": len(suppressed),
                                "major": sum(1 for g in kept if g["severity"] == "major")}}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
