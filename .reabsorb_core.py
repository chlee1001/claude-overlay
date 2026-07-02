#!/usr/bin/env python3
"""claude-overlay re-absorption core. Driven by reabsorb.sh. Pure-stdlib.

Reads sources/<id>/provenance.json, detects drift on two axes (plugin version +
contract schema/hash), and supports triage-packet preview, version bump, and
architect-verdict validation. See docs/reabsorb-design.md.
"""
import datetime
import glob
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

SOURCES_DIR = os.environ["OMC_SOURCES_DIR"]
INSTALLED = os.path.expanduser(os.environ["OMC_INSTALLED_PLUGINS"])
MARKETPLACES = os.path.expanduser(os.environ["OMC_MARKETPLACES_DIR"])
DRYRUN = os.environ.get("REABSORB_DRYRUN", "0") == "1"

# ---- helpers ---------------------------------------------------------------


def load_json(path):
    with open(path) as f:
        return json.load(f)


def installed_version(plugin_key):
    """Current version of an installed plugin = basename of its installPath."""
    if not os.path.exists(INSTALLED):
        return None
    try:
        data = load_json(INSTALLED)
    except Exception:
        return None
    plugins = data.get("plugins", data)
    entries = plugins.get(plugin_key, [])
    for e in entries:
        p = e.get("installPath", "")
        if p:
            return os.path.basename(p.rstrip("/"))
    return None


def _frontmatter(text):
    """Return the leading YAML frontmatter block (between the first two '---'
    fences), or '' if the file has none. Prevents body prose that happens to
    contain 'schema_version:' from being read as the contract value (C3)."""
    m = re.match(r"^---\r?\n(.*?)\r?\n---\s*(?:\r?\n|$)", text, re.S)
    return m.group(1) if m else ""


def read_schema_version(plugin_path, schema_probe):
    """Read `field` from the FRONTMATTER of the first matching artifact only."""
    file_glob = schema_probe.get("file_glob", "")
    field = schema_probe.get("field", "schema_version")
    matches = sorted(glob.glob(os.path.join(MARKETPLACES, plugin_path, file_glob)))
    if not matches:
        return None
    try:
        with open(matches[0]) as fh:
            text = fh.read()
    except Exception:
        return None
    pat = re.compile(r"^%s:\s*['\"]?([^'\"\n]+)['\"]?\s*$" % re.escape(field), re.M)
    m = pat.search(_frontmatter(text))
    return m.group(1).strip() if m else None


def file_hash(plugin_path, rel):
    full = os.path.join(MARKETPLACES, plugin_path, rel)
    if not os.path.exists(full):
        return None
    h = hashlib.sha256()
    with open(full, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return "sha256:" + h.hexdigest()


def manifest_version(manifest_path_rel):
    """Version declared in a plugin's .claude-plugin/plugin.json (marketplace side).
    Second, independent version axis vs installed_plugins.json basename (design §4/§8)."""
    if not manifest_path_rel:
        return None
    full = os.path.join(MARKETPLACES, manifest_path_rel)
    if not os.path.exists(full):
        return None
    try:
        v = load_json(full).get("version")
    except Exception:
        return None
    return str(v) if v is not None else None


def git_remote_commit(repo, ref):
    """Current commit of <ref> at a git remote via `git ls-remote` (C1).
    Returns (sha, None) on success, (None, error) on failure. Works with a
    local path / file:// URL too, so tests stay hermetic."""
    if not repo:
        return None, "no repo"
    try:
        out = subprocess.run(
            ["git", "ls-remote", repo, ref or "HEAD"],
            capture_output=True, text=True, timeout=20,
        )
    except Exception as ex:
        return None, "ls-remote failed: %s" % ex
    if out.returncode != 0:
        return None, "ls-remote rc=%d %s" % (out.returncode, (out.stderr or "").strip()[:80])
    stdout = out.stdout.strip()
    line = stdout.splitlines()[0] if stdout else ""
    sha = line.split()[0] if line else ""
    return (sha or None), (None if sha else "ref not found")


def git_remote_blob(repo, ref, path):
    """Content-addressed blob SHA of a single <path> at <ref> in a remote git repo.
    Tracks ONE file (the discipline we absorbed), not the whole repo HEAD — so drift
    fires only when that file changes, not on every unrelated upstream commit.
    Uses a blobless shallow clone + `git rev-parse HEAD:<path>` (reads the tree entry;
    the file content itself is never fetched). Returns (sha, None) or (None, error).
    Works for any git host and for a local repo (hermetic tests)."""
    if not repo or not path:
        return None, "no repo/path"
    tmp = tempfile.mkdtemp(prefix="reabsorb-blob-")
    try:
        clone = subprocess.run(
            ["git", "clone", "--filter=blob:none", "--depth=1", "--no-checkout",
             "--quiet", repo, tmp],
            capture_output=True, text=True, timeout=60,
        )
        if clone.returncode != 0:
            return None, "clone rc=%d %s" % (clone.returncode, (clone.stderr or "").strip()[:80])
        rp = subprocess.run(
            ["git", "-C", tmp, "rev-parse", "%s:%s" % (ref or "HEAD", path)],
            capture_output=True, text=True, timeout=20,
        )
        if rp.returncode != 0:
            return None, "path not found at %s: %s" % (ref or "HEAD", (rp.stderr or "").strip()[:60])
        sha = rp.stdout.strip()
        return (("blob:" + sha) if sha else None), (None if sha else "empty blob sha")
    except Exception as ex:
        return None, "git blob probe failed: %s" % ex
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def declared_schema(plugin_path, declared_probe):
    """Schema version the plugin DECLARES (intent), e.g. references/schema.v3.2.md filename.
    Cross-checked against the sample artifact (reality) per decision #4 / §8."""
    if not declared_probe:
        return None
    file_glob = declared_probe.get("file_glob", "")
    pat = re.compile(declared_probe.get("version_regex", r"v([0-9]+(?:\.[0-9]+)*)"))
    versions = []
    for p in glob.glob(os.path.join(MARKETPLACES, plugin_path, file_glob)):
        m = pat.search(os.path.basename(p))
        if m:
            v = m.group(1).strip(".")            # tolerate a greedy trailing dot (…v3.1.md)
            if v:
                versions.append(v)
    if not versions:
        return None

    def _key(v):                                 # numeric tuple, skip empty parts defensively
        return [int(x) for x in v.split(".") if x.isdigit()]

    return max(versions, key=_key)


def iter_sources():
    for pj in sorted(glob.glob(os.path.join(SOURCES_DIR, "*", "provenance.json"))):
        try:
            yield pj, load_json(pj)
        except Exception as ex:  # malformed provenance is a real ERROR
            yield pj, {"_error": str(ex), "id": os.path.basename(os.path.dirname(pj))}


# ---- probe: recorded vs current per source --------------------------------


def probe(prov):
    """Return dict: {status, axis, recorded, current, error}."""
    if "_error" in prov:
        return {"status": "ERROR", "recorded": "-", "current": "-",
                "axis": "malformed provenance: " + prov["_error"]}

    st = prov.get("source_type")
    av = prov.get("absorbed_version", {})
    dp = prov.get("drift_probe", {})
    loc = prov.get("locator", {})

    if st == "installed-plugin":
        rec_ver = av.get("plugin_version")
        plugin_path = loc.get("plugin_path", "")
        contract = av.get("contract", {})
        axes = []
        rec_parts = [str(rec_ver)]
        cur_parts = []

        # axis 1: version — DUAL PATH (design §4/§8): installed_plugins basename AND
        # marketplace plugin.json. Disagreement between the two = skew = drift signal.
        ver_installed = installed_version(loc.get("plugin_key", ""))
        ver_manifest = manifest_version(loc.get("manifest_path", ""))
        if ver_installed is None and ver_manifest is None:
            return {"status": "UNKNOWN", "recorded": str(rec_ver),
                    "current": "-", "axis": "plugin not installed (no version signal)"}
        effective_ver = ver_installed if ver_installed is not None else ver_manifest
        if ver_installed is not None and ver_manifest is not None and ver_installed != ver_manifest:
            axes.append("version skew (installed %s / manifest %s)" % (ver_installed, ver_manifest))
        if rec_ver != effective_ver:
            axes.append("version %s->%s" % (rec_ver, effective_ver))
        cur_parts.append(str(effective_ver))

        # axis 2: contract schema — CROSS-VALIDATE declared (intent) vs sample (reality),
        # decision #4 / §8. Recorded is compared to reality; declared/sample mismatch is a signal.
        sp = dp.get("schema_probe")
        if sp:
            rec_schema = contract.get("frontmatter_schema_version")
            sample_schema = read_schema_version(plugin_path, sp)
            decl_schema = declared_schema(plugin_path, dp.get("declared_probe"))
            if sample_schema is None and decl_schema is None:
                rec_parts.append("schema %s" % rec_schema)
                cur_parts.append("schema ?")
                return {"status": "ERROR", "recorded": " / ".join(rec_parts),
                        "current": " / ".join(cur_parts), "axis": "schema probe found no artifact/declaration"}
            effective_schema = sample_schema if sample_schema is not None else decl_schema
            rec_parts.append("schema %s" % rec_schema)
            if decl_schema is not None and sample_schema is not None and decl_schema != sample_schema:
                axes.append("declared/sample mismatch (decl %s / sample %s)" % (decl_schema, sample_schema))
                cur_parts.append("schema %s(sample)/%s(decl)" % (sample_schema, decl_schema))
            else:
                cur_parts.append("schema %s" % effective_schema)
            if rec_schema != effective_schema:
                axes.append("schema %s->%s" % (rec_schema, effective_schema))

        # axis 2b: contract hash
        hp = dp.get("hash_probe")
        if hp:
            rec_hash = contract.get(hp.get("record_key", "file_hash"))
            cur_hash = file_hash(plugin_path, hp.get("file", ""))
            rec_parts.append("hash %s" % (str(rec_hash)[:14]))
            cur_parts.append("hash %s" % (str(cur_hash)[:14] if cur_hash else "?"))
            if cur_hash is None:
                return {"status": "ERROR", "recorded": " / ".join(rec_parts),
                        "current": " / ".join(cur_parts), "axis": "hash probe target missing"}
            if rec_hash != cur_hash:
                axes.append("contract-hash changed")

        recorded = " / ".join(rec_parts)
        current = " / ".join(cur_parts)
        if axes:
            return {"status": "DRIFTED", "recorded": recorded, "current": current,
                    "axis": ", ".join(axes)}
        return {"status": "CURRENT", "recorded": recorded, "current": current, "axis": ""}

    if st == "git-repo":
        repo = loc.get("repo", "")
        if (not repo) or ("<" in repo):
            return {"status": "UNKNOWN", "recorded": str(av.get("commit", av.get("blob", "-"))),
                    "current": "-", "axis": "git-repo URL unpinned (fill locator.repo)"}
        # path-level tracking (a specific absorbed file) vs whole-repo HEAD tracking
        path = dp.get("path")
        if path:
            rec_blob = str(av.get("blob", "-"))
            cur_blob, err = git_remote_blob(repo, dp.get("ref", "HEAD"), path)
            if err:
                return {"status": "ERROR", "recorded": rec_blob[:19], "current": "-", "axis": err}
            if ("<" in rec_blob) or (rec_blob in ("-", "None")):
                return {"status": "UNKNOWN", "recorded": rec_blob, "current": cur_blob[:19],
                        "axis": "recorded blob unpinned (run --bump to record %s)" % cur_blob[:19]}
            if cur_blob != rec_blob:
                return {"status": "DRIFTED", "recorded": rec_blob[:19], "current": cur_blob[:19],
                        "axis": "file %s changed (%s->%s)" % (path, rec_blob[5:14], cur_blob[5:14])}
            return {"status": "CURRENT", "recorded": rec_blob[:19], "current": cur_blob[:19], "axis": ""}
        rec_commit = str(av.get("commit", "-"))
        cur_commit, err = git_remote_commit(repo, dp.get("ref", "HEAD"))
        if err:
            return {"status": "ERROR", "recorded": rec_commit, "current": "-", "axis": err}
        if ("<" in rec_commit) or (rec_commit in ("-", "None")):
            return {"status": "UNKNOWN", "recorded": rec_commit, "current": cur_commit[:12],
                    "axis": "recorded commit unpinned (run --bump to record %s)" % cur_commit[:12]}
        # startswith tolerates a hand-recorded short SHA (bump writes the full 40).
        if not cur_commit.startswith(rec_commit):
            return {"status": "DRIFTED", "recorded": rec_commit[:12], "current": cur_commit[:12],
                    "axis": "commit %s->%s" % (rec_commit[:12], cur_commit[:12])}
        return {"status": "CURRENT", "recorded": rec_commit[:12], "current": cur_commit[:12], "axis": ""}

    if st == "concept-source":
        return {"status": "UNKNOWN", "recorded": str(av.get("concept_ref", "-")),
                "current": "-", "axis": "manual review (staleness clock)"}

    return {"status": "ERROR", "recorded": "-", "current": "-",
            "axis": "unknown source_type: %s" % st}


# ---- modes -----------------------------------------------------------------

# status -> exit code (categorical, mirrors apply.sh's 0/2/3/4 family; NOT monotonic with
# severity — e.g. ERROR=3 < DRIFTED=5 numerically though ERROR outranks DRIFTED). Callers must
# switch on the specific code, not assume "higher = worse". STATUS_RANK is the true severity
# order used to pick which status' code wins when several coexist.
STATUS_CODE = {"CURRENT": 0, "BREAKING": 2, "ERROR": 3, "UNKNOWN": 4, "DRIFTED": 5}
STATUS_RANK = {"CURRENT": 0, "UNKNOWN": 1, "DRIFTED": 2, "BREAKING": 3, "ERROR": 4}


def mode_detect():
    rows = []
    worst_status = "CURRENT"
    for pj, prov in iter_sources():
        sid = prov.get("id", os.path.basename(os.path.dirname(pj)))
        st = prov.get("source_type", "-")
        r = probe(prov)
        rows.append((sid, st, r["recorded"], r["current"], r["status"], r["axis"]))
        if STATUS_RANK[r["status"]] > STATUS_RANK[worst_status]:
            worst_status = r["status"]
    if not rows:
        print("(no sources registered under %s)" % SOURCES_DIR)
        return 0
    hdr = ("SOURCE", "TYPE", "RECORDED", "CURRENT", "STATUS", "NOTE")
    allrows = [hdr] + rows
    w = [max(len(str(row[i])) for row in allrows) for i in range(6)]
    for i, row in enumerate(allrows):
        print("  ".join(str(row[j]).ljust(w[j]) for j in range(6)).rstrip())
    return STATUS_CODE[worst_status]


def find_source(sid):
    pj = os.path.join(SOURCES_DIR, sid, "provenance.json")
    if not os.path.exists(pj):
        print("ERROR: no such source '%s' (%s)" % (sid, pj), file=sys.stderr)
        return None, None
    try:
        return pj, load_json(pj)
    except Exception as ex:
        print("ERROR: malformed provenance %s (%s)" % (pj, ex), file=sys.stderr)
        return None, None


def mode_triage(sid):
    if not sid:
        print("ERROR: --triage requires <id>", file=sys.stderr)
        return 64
    pj, prov = find_source(sid)
    if prov is None:
        return 3
    r = probe(prov)
    if r["status"] != "DRIFTED":
        print("드리프트 없음: %s = %s (%s). triage 불필요." % (sid, r["status"], r["axis"] or "일치"))
        return 0
    print("=== TRIAGE PACKET (dry-run preview; architect 미호출, 무쓰기) ===")
    print("source_id: %s" % sid)
    print("drift: %s" % r["axis"])
    print("recorded: %s" % r["recorded"])
    print("current:  %s" % r["current"])
    print("\n-- 평가 루브릭 (provenance) --")
    for dep in prov.get("dependents", []):
        print("  asset: %s" % dep.get("asset"))
        for k in ("depends_on", "break_if"):
            for item in dep.get(k, []):
                print("    [%s] %s" % (k, item))
    print("\n-- architect 에게 넘길 입력 --")
    print("  1) 위 provenance depends_on/break_if (평가 루브릭)")
    print("  2) 각 dependent 자산 전문(아래 경로 읽기):")
    for dep in prov.get("dependents", []):
        print("       %s" % dep.get("asset"))
    print("  3) 업스트림 델타: %s 의 새 계약 표면(현재값=%s)" % (sid, r["current"]))
    print("\n-- 요구 verdict --  verdict.schema.json 준수 (irrelevant|compatible|breaking).")
    print("   compatible 은 반드시 구체 proposed_delta(from/to) 포함, 아니면 무효.")
    return 0


def mode_bump(sid):
    if not sid:
        print("ERROR: --bump requires <id>", file=sys.stderr)
        return 64
    pj, prov = find_source(sid)
    if prov is None:
        return 3
    st = prov.get("source_type")
    av = prov.setdefault("absorbed_version", {})
    changes = []
    if st == "installed-plugin":
        loc = prov.get("locator", {})
        dp = prov.get("drift_probe", {})
        # effective version = installed basename, else manifest (dual-path, design §4)
        cur_ver = installed_version(loc.get("plugin_key", ""))
        if cur_ver is None:
            cur_ver = manifest_version(loc.get("manifest_path", ""))
        if cur_ver and cur_ver != av.get("plugin_version"):
            changes.append("plugin_version %s->%s" % (av.get("plugin_version"), cur_ver))
            av["plugin_version"] = cur_ver
        contract = av.setdefault("contract", {})
        sp = dp.get("schema_probe")
        if sp:
            # effective schema = sample (reality), else declared (design §4 cross-validate)
            cur_schema = read_schema_version(loc.get("plugin_path", ""), sp)
            if cur_schema is None:
                cur_schema = declared_schema(loc.get("plugin_path", ""), dp.get("declared_probe"))
            if cur_schema and cur_schema != contract.get("frontmatter_schema_version"):
                changes.append("schema %s->%s" % (contract.get("frontmatter_schema_version"), cur_schema))
                contract["frontmatter_schema_version"] = cur_schema
        hp = dp.get("hash_probe")
        if hp:
            cur_hash = file_hash(loc.get("plugin_path", ""), hp.get("file", ""))
            rk = hp.get("record_key", "file_hash")
            if cur_hash and cur_hash != contract.get(rk):
                changes.append("hash updated")
                contract[rk] = cur_hash
    elif st == "git-repo":
        loc = prov.get("locator", {})
        dp = prov.get("drift_probe", {})
        repo = loc.get("repo", "")
        if (not repo) or ("<" in repo):
            print("bump: git-repo '%s' URL 미핀 — 먼저 locator.repo 채우기." % sid)
            return 0
        path = dp.get("path")
        if path:   # file-level: record the blob sha of the tracked file
            cur_blob, err = git_remote_blob(repo, dp.get("ref", "HEAD"), path)
            if err:
                print("bump: git blob probe 실패 (%s)" % err, file=sys.stderr)
                return 3
            if cur_blob and cur_blob != av.get("blob"):
                changes.append("blob %s->%s" % (str(av.get("blob"))[5:14], cur_blob[5:14]))
                av["blob"] = cur_blob
        else:
            cur_commit, err = git_remote_commit(repo, dp.get("ref", "HEAD"))
            if err:
                print("bump: git-repo probe 실패 (%s)" % err, file=sys.stderr)
                return 3
            if cur_commit and cur_commit != av.get("commit"):
                changes.append("commit %s->%s" % (str(av.get("commit"))[:12], cur_commit[:12]))
                av["commit"] = cur_commit
    else:
        print("bump: source_type '%s' 는 자동 bump 미지원(수동)." % st)
        return 0
    if not changes:
        print("bump: %s 변경 없음 (이미 current)." % sid)
        return 0
    if DRYRUN:
        print("would write [%s]: %s (+ absorbed_at)" % (sid, "; ".join(changes)))
        return 0
    prov["absorbed_at"] = datetime.date.today().isoformat()   # C2: advance audit date
    with open(pj, "w") as f:
        json.dump(prov, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print("bumped [%s]: %s; absorbed_at=%s" % (sid, "; ".join(changes), prov["absorbed_at"]))
    return 0


REQUIRED_VERDICT = ["source_id", "verdict", "confidence", "depends_on_assessment", "recommended_action"]


def mode_validate(path):
    if not path:
        print("ERROR: --validate-verdict requires <file>", file=sys.stderr)
        return 64
    if not os.path.exists(path):
        print("ERROR: no such file %s" % path, file=sys.stderr)
        return 3
    try:
        v = load_json(path)
    except Exception as ex:
        print("INVALID: not JSON (%s)" % ex)
        return 1
    errs = []
    for k in REQUIRED_VERDICT:
        if k not in v:
            errs.append("missing required field '%s'" % k)
    verdict = v.get("verdict")
    if verdict not in ("irrelevant", "compatible", "breaking"):
        errs.append("verdict must be irrelevant|compatible|breaking (got %r)" % verdict)
    conf = v.get("confidence")
    if conf not in ("high", "medium", "low"):
        errs.append("confidence must be high|medium|low (got %r)" % conf)
    action = v.get("recommended_action")
    if action not in ("bump", "apply-delta-then-bump", "escalate"):
        errs.append("recommended_action must be bump|apply-delta-then-bump|escalate (got %r)" % action)
    doa = v.get("depends_on_assessment")
    if not isinstance(doa, list) or len(doa) == 0:
        errs.append("depends_on_assessment must be a non-empty array")
    else:
        for i, a in enumerate(doa):
            if not a.get("aspect"):
                errs.append("depends_on_assessment[%d] missing 'aspect'" % i)
            if "changed" not in a:
                errs.append("depends_on_assessment[%d] missing 'changed'" % i)
            if not a.get("evidence"):
                errs.append("depends_on_assessment[%d] missing 'evidence'" % i)
    # anti-rubber-stamp guards (kept in lockstep with verdict.schema.json)
    if verdict == "compatible":
        pd = v.get("proposed_delta")
        if not pd or not pd.get("edits"):
            errs.append("compatible verdict requires a concrete proposed_delta.edits (anti-rubber-stamp)")
        else:
            if not pd.get("asset"):
                errs.append("compatible proposed_delta missing 'asset' (which bundled file to edit)")
            for i, e in enumerate(pd.get("edits", [])):
                for req in ("from", "to", "rationale"):
                    if not e.get(req):
                        errs.append("proposed_delta.edits[%d] missing '%s' (schema requires from/to/rationale)" % (i, req))
    if verdict == "breaking":
        br = v.get("break")
        if not br:
            errs.append("breaking verdict requires a 'break' object")
        else:
            for req in ("what", "impact", "human_decision_needed"):
                if not str(br.get(req, "")).strip():
                    errs.append("break.%s must be non-empty" % req)
    # non-irrelevant + low confidence is only valid if it escalates (matches verdict.schema.json)
    if verdict in ("compatible", "breaking") and conf == "low" and v.get("recommended_action") != "escalate":
        errs.append("non-irrelevant verdict with confidence:low must set recommended_action='escalate'")
    if errs:
        print("INVALID verdict (%d issue%s):" % (len(errs), "" if len(errs) == 1 else "s"))
        for e in errs:
            print("  - %s" % e)
        return 1
    print("VALID verdict: %s (%s, confidence=%s)" % (v.get("source_id"), verdict, conf))
    return 0


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "detect"
    arg = sys.argv[2] if len(sys.argv) > 2 else ""
    if mode == "detect":
        return mode_detect()
    if mode == "triage":
        return mode_triage(arg)
    if mode == "bump":
        return mode_bump(arg)
    if mode == "validate":
        return mode_validate(arg)
    print("unknown mode: %s" % mode, file=sys.stderr)
    return 64


if __name__ == "__main__":
    sys.exit(main())
