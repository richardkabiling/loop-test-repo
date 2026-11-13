#!/usr/bin/env python3
"""validate-loop.py: check docs/sdlc/loop.json for structural and referential errors.

Usage:
  validate-loop.py LOOP_JSON [--upto SECTION | --sections A,B] [--order]

  --upto SECTION  validate only the sections up to and including SECTION, in order:
                  discovery, loops, deliverables, review, skills, rules, context,
                  guardrails, setup.
                  Use this after each setup step.
  --sections A,B  validate only the named sections (the setup wizard fills them out of order;
                  each screen validates what it wrote).
  --order         print the deliverables in dependency (build/ship) order as JSON and exit.

Exit codes: 0 valid, 1 validation errors (listed on stderr, one per line), 2 usage/IO error.
Standard library only. Output is bounded: at most 50 errors are listed.
"""
import json
import re
import sys

SECTIONS = ["discovery", "loops", "deliverables", "review", "skills", "rules", "context", "guardrails", "setup"]
TOOLS = {"claude-code", "cursor", "codex"}
SOURCES = {"default", "intake", "research", "user"}
CHANGE_CLASSES = ["product", "phase", "harness", "convention", "code-part-convention", "no-op"]
VENUES = {"local", "pr", "both", "tracker"}
UPSTREAM_STORES = {"files", "epic", "pr"}
PR_HOSTS = {"github", "gitlab", "bitbucket", "azure-devops", "gerrit", "other", "none"}
REVIEWER_TYPES = {"ai", "human", "automated"}
TIER_AI = {"lenses", "pr-bot", "local-reviewer"}
CI_WORKFLOWS = {"sdlc-checks", "sdlc-signals", "claude-review"}
SURFACES = {"silent", "pr", "ticket", "auto"}
SLUG = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")


def topo_order(deliverables, errors):
    ids = {d.get("id") for d in deliverables}
    deps = {d.get("id"): [x for x in d.get("depends_on", []) or []] for d in deliverables}
    for d, ds in deps.items():
        for x in ds:
            if x not in ids:
                errors.append(f"deliverables.{d}.depends_on: unknown deliverable '{x}'")
    order, state = [], {}

    def visit(n, path):
        if state.get(n) == 2:
            return
        if state.get(n) == 1:
            errors.append("deliverables: dependency cycle " + " -> ".join(path + [n]))
            return
        state[n] = 1
        for m in deps.get(n, []):
            if m in ids:
                visit(m, path + [n])
        state[n] = 2
        order.append(n)

    for d in deliverables:
        visit(d.get("id"), [])
    return order


def need(obj, key, where, errors, kind=None):
    if not isinstance(obj, dict) or key not in obj or obj[key] in (None, "", [], {}):
        errors.append(f"{where}.{key}: missing or empty")
        return None
    if kind and not isinstance(obj[key], kind):
        errors.append(f"{where}.{key}: expected {kind.__name__}")
        return None
    return obj[key]


def check_source(obj, where, errors):
    src = obj.get("source") if isinstance(obj, dict) else None
    if src is not None and src not in SOURCES:
        errors.append(f"{where}.source: '{src}' not one of {sorted(SOURCES)}")
    rs = obj.get("researched") if isinstance(obj, dict) else None
    if rs is not None and not (isinstance(rs, str) and (rs.startswith("docs/sdlc/research/") or rs.startswith("http"))):
        errors.append(f"{where}.researched: path to a docs/sdlc/research/ note (or a URL)")


def validate(loop, upto, only=None):
    errors = []
    if loop.get("version") != 1:
        errors.append("version: expected 1")
    tools = loop.get("tools") or []
    if not tools or not set(tools) <= TOOLS:
        errors.append(f"tools: expected a non-empty subset of {sorted(TOOLS)}")
    active = only or SECTIONS[: SECTIONS.index(upto) + 1]
    h = loop.get("harness")
    if h is not None:
        if not isinstance(h, dict) or not str(h.get("name", "")).strip():
            errors.append("harness.name: give the harness a display name (e.g. 'Acme Delivery Loop')")
        pfx = (h or {}).get("prefix", "sdlc")
        if not SLUG.match(str(pfx)) or len(str(pfx)) > 24:
            errors.append("harness.prefix: a lowercase-hyphen slug of at most 24 characters (it names /<prefix>, /<prefix>-build, ...)")
        elif str(pfx).startswith("setup-"):
            errors.append("harness.prefix: must not start with 'setup-' (clashes with the setup skills)")

    if "discovery" in active:
        d = need(loop, "discovery", "", errors, dict) or {}
        if d.get("mode") not in ("greenfield", "existing"):
            errors.append("discovery.mode: expected 'greenfield' or 'existing'")
        cmds = d.get("commands")
        if d.get("mode") == "existing":
            if not isinstance(cmds, dict) or not cmds.get("test"):
                errors.append("discovery.commands.test: an existing repo needs a test command (or 'none' stated explicitly)")
        for i, f in enumerate(d.get("notable_folders", []) or []):
            need(f, "path", f"discovery.notable_folders[{i}]", errors)
            need(f, "kind", f"discovery.notable_folders[{i}]", errors)
        dpr = d.get("pr")
        if dpr is not None and dpr.get("host") not in PR_HOSTS:
            errors.append(f"discovery.pr.host: expected one of {sorted(PR_HOSTS)}")
        check_source(d, "discovery", errors)

    phase_ids = set()
    if "loops" in active:
        lp = need(loop, "loops", "", errors, dict) or {}
        phases = need(lp, "phases", "loops", errors, list) or []
        seen = set()
        for i, p in enumerate(phases):
            pid = p.get("id", f"#{i}")
            if pid in seen:
                errors.append(f"loops.phases: duplicate id '{pid}'")
            seen.add(pid)
            if p.get("enabled"):
                phase_ids.add(pid)
                for k in ("strategy", "interaction", "artifact", "exit"):
                    need(p, k, f"loops.phases.{pid}", errors)
                g = need(p, "gate", f"loops.phases.{pid}", errors, dict)
                if g:
                    gt = g.get("type", "human")
                    if gt not in ("human", "automated"):
                        errors.append(f"loops.phases.{pid}.gate.type: expected 'human' or 'automated'")
                    elif gt == "human":
                        need(g, "owner", f"loops.phases.{pid}.gate", errors)
                        need(g, "mechanism", f"loops.phases.{pid}.gate", errors)
                    else:
                        need(g, "checks", f"loops.phases.{pid}.gate", errors, list)
                        if g.get("owner") in ("agent", "ai", "claude"):
                            errors.append(f"loops.phases.{pid}.gate.owner: an agent can't own a gate")
            if pid == "design" and p.get("enabled"):
                subs = p.get("subphases") or []
                ids = [x.get("id") for x in subs]
                if "requirements" not in ids:
                    errors.append("loops.phases.design.subphases: 'requirements' must be present (it produces spec.md)")
                if len(ids) != len(set(ids)):
                    errors.append("loops.phases.design.subphases: duplicate ids")
                for x in subs:
                    for k in ("when", "artifact"):
                        need(x, k, f"loops.phases.design.subphases.{x.get('id')}", errors)
            if pid == "improve" and p.get("enabled"):
                cc = set(p.get("change_classes") or [])
                missing = set(CHANGE_CLASSES) - cc
                if missing:
                    errors.append(f"loops.phases.improve.change_classes: missing {sorted(missing)} (every finding must be classifiable)")
                need(p, "modes", "loops.phases.improve", errors, list)
            check_source(p, f"loops.phases.{pid}", errors)
        if phases and not phase_ids:
            errors.append("loops.phases: no phase is enabled")
        bp = next((p for p in phases if p.get("id") == "build" and p.get("enabled")), None)
        rp = next((p for p in phases if p.get("id") == "review" and p.get("enabled")), None)
        if bp and not rp:
            errors.append("loops.phases: build is enabled without a review phase (build-validate is local; the PR and its review happen in 'review')")
        if bp:
            v = bp.get("validate") or {}
            if not v.get("checks"):
                errors.append("loops.phases.build.validate.checks: list what validates a ticket locally (tests, typecheck, ...)")
            if v.get("review", "none") not in ("none", "self", "lenses"):
                errors.append("loops.phases.build.validate.review: expected none | self | lenses")
        if rp:
            g = rp.get("gate") or {}
            if g.get("type", "human") != "human" and not g.get("human_review_waiver"):
                errors.append("loops.phases.review.gate: must be human (or record human_review_waiver with a reason)")
            if rp.get("pr_filed", "start") not in ("start", "after-ai-review"):
                errors.append("loops.phases.review.pr_filed: expected start | after-ai-review")
        up = lp.get("upstream")
        if up is not None:
            if up.get("store") not in UPSTREAM_STORES:
                errors.append(f"loops.upstream.store: expected one of {sorted(UPSTREAM_STORES)}")
            if up.get("grilling", "solo") not in ("solo", "team"):
                errors.append("loops.upstream.grilling: expected solo | team")
            if up.get("grilling") == "team":
                need(up, "team_protocol", "loops.upstream", errors)
            if up.get("store") in ("epic", "pr"):
                need(up, "where", "loops.upstream", errors)
    else:
        phase_ids = {p.get("id") for p in (loop.get("loops", {}) or {}).get("phases", []) if p.get("enabled")}

    design_subs = set()
    for p in (loop.get("loops", {}) or {}).get("phases", []) or []:
        if p.get("id") == "design" and p.get("enabled"):
            design_subs = {x.get("id") for x in p.get("subphases") or []}
    if "deliverables" in active:
        dels = loop.get("deliverables")
        if not isinstance(dels, list) or not dels:
            errors.append("deliverables: expected a non-empty list")
            dels = []
        seen = set()
        for i, d in enumerate(dels):
            did = d.get("id", f"#{i}")
            if not SLUG.match(str(did)):
                errors.append(f"deliverables[{i}].id: '{did}' must be a lowercase-hyphen slug")
            if did in seen:
                errors.append(f"deliverables: duplicate id '{did}'")
            seen.add(did)
            for k in ("kind", "test", "review", "ship"):
                need(d, k, f"deliverables.{did}", errors)
            ds = (d.get("design") or {}).get("subphase")
            if ds and ds != "none" and design_subs and ds not in design_subs:
                errors.append(f"deliverables.{did}.design.subphase: '{ds}' is not a subphase of the design phase")
            check_source(d, f"deliverables.{did}", errors)
        topo_order(dels, errors)

    if "review" in active:
        rv = need(loop, "review", "", errors, dict) or {}
        arts = need(rv, "artifacts", "review", errors, list) or []
        names = set()
        for i, a in enumerate(arts):
            an = a.get("artifact", f"#{i}")
            names.add(an)
            if a.get("venue") not in VENUES:
                errors.append(f"review.artifacts.{an}.venue: expected one of {sorted(VENUES)}")
            revs = a.get("reviewers") or []
            if not revs:
                errors.append(f"review.artifacts.{an}.reviewers: at least one reviewer")
            for r in revs:
                if r.get("type") not in REVIEWER_TYPES:
                    errors.append(f"review.artifacts.{an}.reviewers: type must be one of {sorted(REVIEWER_TYPES)}")
            need(a, "record", f"review.artifacts.{an}", errors)
            if an == "code" and not any(r.get("type") == "human" for r in revs) and not a.get("human_review_waiver"):
                errors.append("review.artifacts.code: needs a human reviewer (the authoring agent can't approve itself) or an explicit human_review_waiver reason")
        if "review" in phase_ids and "code" not in names:
            errors.append("review.artifacts: the review phase is enabled but no 'code' review is defined")
        rpr = rv.get("pr")
        if rpr is not None:
            if rpr.get("filed", "start-of-review") not in ("start-of-review", "after-ai-review", "start-of-build"):
                errors.append("review.pr.filed: expected start-of-review | after-ai-review | start-of-build")
            tiers = rpr.get("tiers") or []
            tids = [t.get("id") for t in tiers]
            if tiers:
                if len(tids) != len(set(tids)):
                    errors.append("review.pr.tiers: duplicate ids")
                if sum(1 for t in tiers if t.get("default")) != 1:
                    errors.append("review.pr.tiers: exactly one tier needs default: true (files no other tier matches)")
            for t in tiers:
                tid = t.get("id", "?")
                if not SLUG.match(str(tid)):
                    errors.append(f"review.pr.tiers[{tid}].id: must be a lowercase-hyphen slug")
                if not t.get("default") and not (isinstance(t.get("match"), list) and t.get("match")):
                    errors.append(f"review.pr.tiers.{tid}.match: a non-default tier needs globs")
                ha = t.get("human_approvals")
                if not isinstance(ha, int) or ha < 0:
                    errors.append(f"review.pr.tiers.{tid}.human_approvals: expected an integer >= 0")
                elif ha == 0 and not t.get("human_review_waiver"):
                    errors.append(f"review.pr.tiers.{tid}.human_approvals: 0 needs a human_review_waiver reason (the authoring agent can't approve itself)")
                bad = set(t.get("ai") or []) - TIER_AI
                if bad:
                    errors.append(f"review.pr.tiers.{tid}.ai: unknown {sorted(bad)} (use {sorted(TIER_AI)})")
                if t.get("extra_lenses") and len(t["extra_lenses"]) > 5:
                    errors.append(f"review.pr.tiers.{tid}.extra_lenses: at most 5")
        pr = rv.get("personas")
        if pr is not None:
            pts = pr.get("points") or {}
            for k, lenses in pts.items():
                base, _, sub = k.partition(":")
                if base not in ("intent", "design", "build", "review"):
                    errors.append(f"review.personas.points.{k}: review points are intent, design:<subphase>, build (optional, local), review")
                elif base == "design" and design_subs and sub not in design_subs:
                    errors.append(f"review.personas.points.{k}: '{sub}' is not a design subphase")
                if not isinstance(lenses, list) or not lenses:
                    errors.append(f"review.personas.points.{k}: at least one lens")
                elif len(lenses) > 5:
                    errors.append(f"review.personas.points.{k}: at most 5 lenses (narrow reviewers beat many)")
            sf = pr.get("surface") or {}
            for grp, mode in sf.items():
                if grp == "note":
                    continue
                if grp not in ("intent", "design", "build", "review"):
                    errors.append(f"review.personas.surface.{grp}: expected intent, design, build or review")
                elif mode not in SURFACES:
                    errors.append(f"review.personas.surface.{grp}: expected one of {sorted(SURFACES)}")
                elif mode == "pr" and ((loop.get("discovery") or {}).get("pr") or {}).get("host") == "none":
                    errors.append(f"review.personas.surface.{grp}: 'pr' needs a forge, but discovery.pr.host is none")
                elif mode == "ticket" and ((loop.get("setup") or {}).get("tracker") or {}).get("kind") == "local":
                    errors.append(f"review.personas.surface.{grp}: 'ticket' needs a tracker, but setup.tracker.kind is local")
            for need_pt, ph in (("intent", "intent"), ("review", "review")):
                if ph in phase_ids and need_pt not in pts:
                    errors.append(f"review.personas.points.{need_pt}: phase '{ph}' is enabled but has no persona lenses")
            bph = next((p for p in (loop.get("loops", {}) or {}).get("phases", []) if p.get("id") == "build"), {}) or {}
            if (bph.get("validate") or {}).get("review") == "lenses" and "build" not in pts:
                errors.append("review.personas.points.build: build.validate.review is 'lenses' but no build lenses are listed")
            for sub in design_subs:
                if "design" in phase_ids and f"design:{sub}" not in pts:
                    errors.append(f"review.personas.points.design:{sub}: design subphase has no persona lenses")
        rev = rv.get("evals")
        if rev is not None:
            if rev.get("run_in", "review") != "review":
                errors.append("review.evals.run_in: evals run in the review phase ('review')")
            sids = set()
            for i, s in enumerate(rev.get("suites") or []):
                sid = s.get("id", f"#{i}")
                if not SLUG.match(str(sid)) or sid in sids:
                    errors.append(f"review.evals.suites[{i}].id: '{sid}' must be a unique lowercase-hyphen slug")
                sids.add(sid)
                if s.get("kind") not in ("harness", "product"):
                    errors.append(f"review.evals.suites.{sid}.kind: expected harness | product")
                elif s.get("kind") == "harness" and not s.get("path"):
                    errors.append(f"review.evals.suites.{sid}.path: a harness suite needs its scenario file")
                elif s.get("kind") == "product" and not s.get("run"):
                    errors.append(f"review.evals.suites.{sid}.run: a product suite needs the command that runs it")
                if not (isinstance(s.get("triggers"), list) and s.get("triggers")):
                    errors.append(f"review.evals.suites.{sid}.triggers: list the globs whose changes run this suite")
                wh = s.get("where", "local")
                if wh not in ("local", "ci", "platform"):
                    errors.append(f"review.evals.suites.{sid}.where: expected local | ci | platform")
                elif wh == "ci" and not s.get("ci_check"):
                    errors.append(f"review.evals.suites.{sid}.ci_check: a ci suite names the existing CI check that runs it")
                if any(not re.match(r"^[A-Z][A-Z0-9_]*$", str(v)) for v in s.get("secrets") or []):
                    errors.append(f"review.evals.suites.{sid}.secrets: environment variable names only, never values")
                ms = s.get("max_scenarios")
                if ms is not None and (not isinstance(ms, int) or ms < 1):
                    errors.append(f"review.evals.suites.{sid}.max_scenarios: a positive integer (the harness suite's size cap)")
                t = s.get("threshold", 1.0)
                if not isinstance(t, (int, float)) or not 0 < t <= 1:
                    errors.append(f"review.evals.suites.{sid}.threshold: a pass rate in (0, 1]")
            ip = next((p for p in (loop.get("loops", {}) or {}).get("phases", []) if p.get("id") == "improve" and p.get("enabled")), None)
            if ip and not any(s.get("kind") == "harness" for s in rev.get("suites") or []):
                errors.append("review.evals.suites: improve is enabled, so a harness suite is needed (its gate compares evals before and after)")
        nc = rv.get("noise_controls") or {}
        mn = nc.get("max_nits")
        if mn is not None and (not isinstance(mn, int) or mn < 0):
            errors.append("review.noise_controls.max_nits: expected a non-negative integer")
        check_source(rv, "review", errors)

    if "skills" in active:
        sk = need(loop, "skills", "", errors, dict) or {}
        per = sk.get("per_phase", {}) or {}
        for ph in per:
            if phase_ids and ph not in phase_ids:
                errors.append(f"skills.per_phase.{ph}: not an enabled phase")
        for ph in phase_ids:
            if ph not in per:
                errors.append(f"skills.per_phase.{ph}: enabled phase has no skills listed (use [] to state none)")
        for i, inst in enumerate(sk.get("install", []) or []):
            need(inst, "name", f"skills.install[{i}]", errors)
            need(inst, "how", f"skills.install[{i}]", errors)
        check_source(sk, "skills", errors)

    if "rules" in active:
        rl = need(loop, "rules", "", errors, dict) or {}
        names = set()
        for i, r in enumerate(rl.get("scoped", []) or []):
            n = r.get("name", "")
            if not SLUG.match(n):
                errors.append(f"rules.scoped[{i}].name: '{n}' must be a lowercase-hyphen slug")
            if n in names:
                errors.append(f"rules.scoped: duplicate name '{n}'")
            names.add(n)
            if not isinstance(r.get("paths"), list) or not r.get("paths"):
                errors.append(f"rules.scoped.{n}.paths: expected a non-empty list of globs")
            need(r, "rule", f"rules.scoped.{n}", errors)
        dids = {d.get("id") for d in loop.get("deliverables", []) or []}
        for k in (rl.get("per_deliverable", {}) or {}):
            if dids and k not in dids:
                errors.append(f"rules.per_deliverable.{k}: unknown deliverable")
        check_source(rl, "rules", errors)

    if "context" in active:
        cx = need(loop, "context", "", errors, dict) or {}
        need(cx, "strategies", "context", errors, list)
        check_source(cx, "context", errors)

    if "guardrails" in active:
        gs = loop.get("guardrails")
        if not isinstance(gs, list) or not gs:
            errors.append("guardrails: expected a non-empty list")
            gs = []
        seen = set()
        for i, g in enumerate(gs):
            gid = g.get("id", f"#{i}")
            if not SLUG.match(str(gid)):
                errors.append(f"guardrails[{i}].id: '{gid}' must be a lowercase-hyphen slug")
            if gid in seen:
                errors.append(f"guardrails: duplicate id '{gid}'")
            seen.add(gid)
            for k in ("failure_mode", "mitigation", "enforced_by"):
                need(g, k, f"guardrails.{gid}", errors)
            for ph in g.get("phases", []) or []:
                if phase_ids and ph not in phase_ids:
                    errors.append(f"guardrails.{gid}.phases: '{ph}' is not an enabled phase")
            check_source(g, f"guardrails.{gid}", errors)

    if "setup" in active:
        st = need(loop, "setup", "", errors, dict) or {}
        tr = need(st, "tracker", "setup", errors, dict)
        if tr and tr.get("kind") not in ("github", "gitlab", "local", "other"):
            errors.append("setup.tracker.kind: expected github | gitlab | local | other")
        enf = st.get("enforcement") or {}
        ci = enf.get("ci")
        if ci is not None:
            mode = ci.get("mode", "none")
            if mode not in ("none", "workflows"):
                errors.append("setup.enforcement.ci.mode: expected none | workflows")
            elif mode == "workflows":
                adds = ci.get("add") or []
                bad = set(adds) - CI_WORKFLOWS
                if not adds:
                    errors.append("setup.enforcement.ci.add: list the workflows the user asked for")
                if bad:
                    errors.append(f"setup.enforcement.ci.add: unknown {sorted(bad)} (use {sorted(CI_WORKFLOWS)})")
                if ci.get("source") not in ("user", "intake"):
                    errors.append("setup.enforcement.ci.source: CI changes need the user's say-so (source user or intake)")
        docs = need(st, "docs", "setup", errors, dict)
        if docs:
            need(docs, "work", "setup.docs", errors)
        check_source(st, "setup", errors)

    return errors


def main(argv):
    if len(argv) < 2 or argv[1] in ("-h", "--help"):
        print(__doc__.strip())
        return 0 if len(argv) >= 2 else 2
    path, upto, order, only = argv[1], "setup", False, None
    rest = argv[2:]
    while rest:
        a = rest.pop(0)
        if a == "--upto" and rest:
            upto = rest.pop(0)
            if upto not in SECTIONS:
                print(f"validate-loop: --upto must be one of {SECTIONS}", file=sys.stderr)
                return 2
        elif a == "--sections" and rest:
            only = [x.strip() for x in rest.pop(0).split(",") if x.strip()]
            bad = [x for x in only if x not in SECTIONS]
            if bad:
                print(f"validate-loop: unknown sections {bad}; use {SECTIONS}", file=sys.stderr)
                return 2
        elif a == "--order":
            order = True
        else:
            print(f"validate-loop: unknown argument '{a}' (try --help)", file=sys.stderr)
            return 2
    try:
        with open(path, encoding="utf-8") as fh:
            loop = json.load(fh)
    except (OSError, json.JSONDecodeError) as e:
        print(f"validate-loop: cannot read {path}: {e}", file=sys.stderr)
        return 2
    if order:
        errs = []
        print(json.dumps(topo_order(loop.get("deliverables", []) or [], errs)))
        for e in errs[:50]:
            print(e, file=sys.stderr)
        return 1 if errs else 0
    errors = validate(loop, upto, only)
    for e in errors[:50]:
        print(e, file=sys.stderr)
    if len(errors) > 50:
        print(f"... and {len(errors) - 50} more", file=sys.stderr)
    if not errors:
        print(f"ok: loop.json valid for {', '.join(only)}" if only else f"ok: loop.json valid through '{upto}'")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
