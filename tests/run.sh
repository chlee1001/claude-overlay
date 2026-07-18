#!/usr/bin/env bash
# claude-overlay/tests/run.sh — reabsorb flow test harness.
# Hermetic: builds all fixtures in a temp dir and points reabsorb.sh at them via
# env overrides (OMC_SOURCES_DIR / OMC_MARKETPLACES_DIR / OMC_INSTALLED_PLUGINS).
# NEVER touches the real ~/.claude. Deps: bash + python3 (jq optional).
#
# Covers (design §11.2): drift detect (+insane-design 3.1->3.2 regression),
# probe parsing, verdict schema (good/bad), bump idempotency, E2E golden
# (mock verdict, architect NOT called), exit-code matrix.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REABSORB="$ROOT/reabsorb.sh"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; }
# assert_eq <label> <expected> <actual>
assert_eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected [$2] got [$3])"; fi; }
# assert_contains <label> <needle> <haystack>
assert_contains() { case "$3" in *"$2"*) ok "$1";; *) bad "$1 (missing [$2])";; esac; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---- fixture builders ------------------------------------------------------
# build_source <dir> <schema_recorded> <ver_recorded>
mk_source() {
  mkdir -p "$1"
  cat > "$1/provenance.json" <<EOF
{"schema":1,"id":"demo","source_type":"installed-plugin",
 "locator":{"plugin_key":"demo@fix","plugin_path":"fixmp/plugins/demo"},
 "absorbed_version":{"plugin_version":"$3","contract":{"frontmatter_schema_version":"$2"}},
 "dependents":[{"asset":"patches/sample-dep/skill/sample-dep/SKILL.md",
   "depends_on":["리포트 schema_version 계약"],"break_if":["schema MAJOR bump"]}],
 "drift_probe":{"kind":"manifest_version + artifact_schema","schema_probe":{"file_glob":"docs/reports/*/design.md","field":"schema_version"}}}
EOF
}
# build marketplace with a report at <schema>
mk_mp() {
  mkdir -p "$TMP/mp/fixmp/plugins/demo/docs/reports/sample"
  printf -- '---\nschema_version: %s\nslug: sample\n---\n' "$1" > "$TMP/mp/fixmp/plugins/demo/docs/reports/sample/design.md"
}
# installed_plugins.json with demo@fix at <ver>
mk_installed() {
  printf '{"plugins":{"demo@fix":[{"installPath":"/x/cache/fixmp/demo/%s"}]}}\n' "$1" > "$TMP/installed.json"
}
run() { # run reabsorb against fixtures; echoes output, sets RC
  OMC_SOURCES_DIR="$TMP/sources" OMC_MARKETPLACES_DIR="$TMP/mp" OMC_INSTALLED_PLUGINS="$TMP/installed.json" \
    bash "$REABSORB" "$@"; }

echo "reabsorb test harness"
echo "1) syntax"
bash -n "$REABSORB" && ok "reabsorb.sh bash -n" || bad "reabsorb.sh bash -n"
bash -n "$ROOT/lib/omc-version.sh" && ok "lib/omc-version.sh bash -n" || bad "lib/omc-version.sh bash -n"
python3 -m py_compile "$ROOT/.reabsorb_core.py" && ok ".reabsorb_core.py compiles" || bad "py_compile core"
python3 -m py_compile "$ROOT/lib/omc_version.py" && ok "lib/omc_version.py compiles" || bad "py_compile omc_version"
python3 -c "import json;json.load(open('$ROOT/verdict.schema.json'))" && ok "verdict.schema.json parses" || bad "verdict.schema.json parses"

echo "1b) canonical parser lib/omc_version.py (single source for bash helper + core)"
printf '{"plugins":{"oh-my-claudecode@omc":[{"installPath":"/x/cache/omc/oh-my-claudecode/9.9.9"}]}}\n' > "$TMP/ip1.json"
got="$(OMC_INSTALLED_PLUGINS="$TMP/ip1.json" python3 "$ROOT/lib/omc_version.py")"
assert_eq "omc_version.py default key -> full installPath" "/x/cache/omc/oh-my-claudecode/9.9.9" "$got"
got="$(OMC_INSTALLED_PLUGINS="$TMP/ip1.json" python3 "$ROOT/lib/omc_version.py" nonexistent@plugin)"
assert_eq "omc_version.py unknown key -> empty" "" "$got"
got="$(OMC_INSTALLED_PLUGINS="$TMP/none.json" python3 "$ROOT/lib/omc_version.py")"
assert_eq "omc_version.py missing file -> empty (no error)" "" "$got"
# bash helper delegates to the same source -> same answer
got="$(OMC_INSTALLED_PLUGINS="$TMP/ip1.json" bash -c '. "'"$ROOT"'/lib/omc-version.sh"; omc_active_installpath')"
assert_eq "bash omc_active_installpath == python module" "/x/cache/omc/oh-my-claudecode/9.9.9" "$got"

echo "2) REGRESSION: insane-design 3.1->3.2 schema drift (version unchanged)"
rm -rf "$TMP/sources"; mk_source "$TMP/sources/demo" "3.1" "1.0.0"; mk_mp "3.2"; mk_installed "1.0.0"
out="$(run 2>&1)"; rc=$?
assert_contains "detect DRIFTED on schema axis" "schema 3.1->3.2" "$out"
assert_contains "status DRIFTED" "DRIFTED" "$out"
assert_eq "exit 5 on drift" "5" "$rc"

echo "3) version-axis drift (schema same, plugin version moved)"
rm -rf "$TMP/sources"; mk_source "$TMP/sources/demo" "3.2" "1.0.0"; mk_mp "3.2"; mk_installed "1.1.0"
out="$(run 2>&1)"; assert_contains "detect version axis" "version 1.0.0->1.1.0" "$out"

echo "4) CURRENT (both axes match) -> exit 0"
rm -rf "$TMP/sources"; mk_source "$TMP/sources/demo" "3.2" "1.0.0"; mk_mp "3.2"; mk_installed "1.0.0"
out="$(run 2>&1)"; rc=$?
assert_contains "status CURRENT" "CURRENT" "$out"; assert_eq "exit 0 all current" "0" "$rc"

echo "5) UNKNOWN: plugin not installed -> exit 4"
rm -rf "$TMP/sources"; mk_source "$TMP/sources/demo" "3.2" "1.0.0"; mk_mp "3.2"
printf '{"plugins":{}}\n' > "$TMP/installed.json"
run >/dev/null 2>&1; assert_eq "exit 4 unknown" "4" "$?"

echo "6) ERROR: malformed provenance -> exit 3"
rm -rf "$TMP/sources"; mkdir -p "$TMP/sources/demo"; printf '{bad json' > "$TMP/sources/demo/provenance.json"
mk_mp "3.2"; mk_installed "1.0.0"
run >/dev/null 2>&1; assert_eq "exit 3 error" "3" "$?"

echo "7) probe parsing: schema_version extracted from frontmatter"
rm -rf "$TMP/sources"; mk_source "$TMP/sources/demo" "9.9" "1.0.0"; mk_mp "3.2"; mk_installed "1.0.0"
out="$(run 2>&1)"; assert_contains "current schema parsed = 3.2" "schema 3.2" "$out"

echo "8) --triage assembles packet, writes nothing, no architect"
rm -rf "$TMP/sources"; mk_source "$TMP/sources/demo" "3.1" "1.0.0"; mk_mp "3.2"; mk_installed "1.0.0"
before="$(cat "$TMP/sources/demo/provenance.json")"
out="$(run --triage demo 2>&1)"
assert_contains "packet has depends_on" "depends_on" "$out"
assert_contains "packet has dependent asset" "sample-dep" "$out"
assert_contains "packet requires verdict.schema" "verdict.schema.json" "$out"
assert_eq "triage writes nothing" "$before" "$(cat "$TMP/sources/demo/provenance.json")"

echo "9) --bump idempotency + --dry-run no-write"
rm -rf "$TMP/sources"; mk_source "$TMP/sources/demo" "3.1" "1.0.0"; mk_mp "3.2"; mk_installed "1.0.0"
before="$(cat "$TMP/sources/demo/provenance.json")"
run --bump --dry-run demo >/dev/null 2>&1
assert_eq "dry-run bump writes nothing" "$before" "$(cat "$TMP/sources/demo/provenance.json")"
run --bump demo >/dev/null 2>&1
after1="$(python3 -c "import json;print(json.load(open('$TMP/sources/demo/provenance.json'))['absorbed_version']['contract']['frontmatter_schema_version'])")"
assert_eq "bump advanced schema to 3.2" "3.2" "$after1"
run >/dev/null 2>&1; assert_eq "post-bump CURRENT exit 0 (idempotent)" "0" "$?"

echo "10) E2E golden: mock verdict validated (architect NOT called)"
cat > "$TMP/verdict_good.json" <<'EOF'
{"source_id":"demo","verdict":"compatible","confidence":"high",
 "depends_on_assessment":[{"aspect":"schema","changed":true,"evidence":"3.1->3.2 additive"}],
 "proposed_delta":{"asset":"skill.md","edits":[{"from":"3.1","to":"3.2","rationale":"additive"}]},
 "recommended_action":"apply-delta-then-bump"}
EOF
bash "$REABSORB" --validate-verdict "$TMP/verdict_good.json" >/dev/null 2>&1
assert_eq "golden verdict VALID exit 0" "0" "$?"

echo "11) verdict schema guards (anti-rubber-stamp)"
cat > "$TMP/v_nodelta.json" <<'EOF'
{"source_id":"x","verdict":"compatible","confidence":"high","depends_on_assessment":[{"aspect":"a","changed":true,"evidence":"e"}],"recommended_action":"apply-delta-then-bump"}
EOF
bash "$REABSORB" --validate-verdict "$TMP/v_nodelta.json" >/dev/null 2>&1
assert_eq "compatible w/o delta REJECTED" "1" "$?"
cat > "$TMP/v_lowconf.json" <<'EOF'
{"source_id":"x","verdict":"breaking","confidence":"low","depends_on_assessment":[{"aspect":"a","changed":true,"evidence":"e"}],"break":{"what":"w","impact":"i","human_decision_needed":"h"},"recommended_action":"bump"}
EOF
bash "$REABSORB" --validate-verdict "$TMP/v_lowconf.json" >/dev/null 2>&1
assert_eq "non-irrelevant low-confidence REJECTED" "1" "$?"

echo "12) dual-path version skew: installed != manifest -> DRIFTED (design §4/§8)"
rm -rf "$TMP/sources" "$TMP/mp"; mkdir -p "$TMP/sources/demo" "$TMP/mp/fixmp/plugins/demo/.claude-plugin" "$TMP/mp/fixmp/plugins/demo/docs/reports/sample"
printf -- '---\nschema_version: 3.2\n---\n' > "$TMP/mp/fixmp/plugins/demo/docs/reports/sample/design.md"
printf '{"version":"1.1.0"}\n' > "$TMP/mp/fixmp/plugins/demo/.claude-plugin/plugin.json"   # manifest says 1.1.0
mk_installed "1.0.0"                                                                        # installed says 1.0.0
cat > "$TMP/sources/demo/provenance.json" <<'EOF'
{"schema":1,"id":"demo","source_type":"installed-plugin",
 "locator":{"plugin_key":"demo@fix","plugin_path":"fixmp/plugins/demo","manifest_path":"fixmp/plugins/demo/.claude-plugin/plugin.json"},
 "absorbed_version":{"plugin_version":"1.0.0","contract":{"frontmatter_schema_version":"3.2"}},
 "dependents":[{"asset":"a","depends_on":["x"],"break_if":["y"]}],
 "drift_probe":{"schema_probe":{"file_glob":"docs/reports/*/design.md","field":"schema_version"}}}
EOF
out="$(run 2>&1)"; rc=$?
assert_contains "version skew detected" "version skew (installed 1.0.0 / manifest 1.1.0)" "$out"
assert_contains "skew -> STATUS DRIFTED" "DRIFTED" "$out"    # T1: assert status, not just the note
assert_eq "skew -> rc 5" "5" "$rc"

echo "13) declared/sample cross-validation mismatch -> DRIFTED (decision #4)"
rm -rf "$TMP/sources" "$TMP/mp"
mkdir -p "$TMP/sources/demo" "$TMP/mp/fixmp/plugins/demo/docs/reports/sample" "$TMP/mp/fixmp/plugins/demo/refs"
printf -- '---\nschema_version: 3.2\n---\n' > "$TMP/mp/fixmp/plugins/demo/docs/reports/sample/design.md"  # sample=3.2
: > "$TMP/mp/fixmp/plugins/demo/refs/schema.v3.1.md"                                                        # declared=3.1
mk_installed "1.0.0"
cat > "$TMP/sources/demo/provenance.json" <<'EOF'
{"schema":1,"id":"demo","source_type":"installed-plugin",
 "locator":{"plugin_key":"demo@fix","plugin_path":"fixmp/plugins/demo"},
 "absorbed_version":{"plugin_version":"1.0.0","contract":{"frontmatter_schema_version":"3.2"}},
 "dependents":[{"asset":"a","depends_on":["x"],"break_if":["y"]}],
 "drift_probe":{"schema_probe":{"file_glob":"docs/reports/*/design.md","field":"schema_version"},
   "declared_probe":{"file_glob":"refs/schema.v*.md","version_regex":"v([0-9]+(?:\\.[0-9]+)*)"}}}
EOF
out="$(run 2>&1)"; rc=$?
assert_contains "declared/sample mismatch detected" "declared/sample mismatch (decl 3.1 / sample 3.2)" "$out"
assert_contains "mismatch -> STATUS DRIFTED" "DRIFTED" "$out"    # T1
assert_eq "mismatch -> rc 5" "5" "$rc"

echo "14) validator: edit missing from/to/rationale -> REJECTED (schema<->validator lockstep)"
cat > "$TMP/v_thinedit.json" <<'EOF'
{"source_id":"x","verdict":"compatible","confidence":"high",
 "depends_on_assessment":[{"aspect":"a","changed":true,"evidence":"e"}],
 "proposed_delta":{"asset":"a","edits":[{}]},"recommended_action":"apply-delta-then-bump"}
EOF
bash "$REABSORB" --validate-verdict "$TMP/v_thinedit.json" >/dev/null 2>&1
assert_eq "thin edit REJECTED" "1" "$?"

echo "15) validator: non-irrelevant + low confidence + escalate -> VALID (matches schema)"
cat > "$TMP/v_escalate.json" <<'EOF'
{"source_id":"x","verdict":"breaking","confidence":"low",
 "depends_on_assessment":[{"aspect":"a","changed":true,"evidence":"e"}],
 "break":{"what":"w","impact":"i","human_decision_needed":"h"},"recommended_action":"escalate"}
EOF
bash "$REABSORB" --validate-verdict "$TMP/v_escalate.json" >/dev/null 2>&1
assert_eq "low-conf+escalate VALID" "0" "$?"

echo "16) find_source guard: --triage on malformed provenance -> clean ERROR, no traceback"
rm -rf "$TMP/sources"; mkdir -p "$TMP/sources/demo"; printf '{bad' > "$TMP/sources/demo/provenance.json"
mk_mp "3.2"; mk_installed "1.0.0"
err="$(run --triage demo 2>&1)"; rc=$?
assert_eq "triage on malformed exits 3" "3" "$rc"
case "$err" in *Traceback*) bad "no python traceback leaked";; *) ok "no python traceback leaked";; esac

echo "17) validator hardening (V1-V4): schema<->validator lockstep on aspect/action/asset/break"
vgood='{"source_id":"x","verdict":"irrelevant","confidence":"high","depends_on_assessment":[{"aspect":"a","changed":false,"evidence":"e"}],"recommended_action":"bump"}'
mkv() { printf '%s' "$2" > "$TMP/$1.json"; }
mkv v1_noaspect '{"source_id":"x","verdict":"irrelevant","confidence":"high","depends_on_assessment":[{"changed":false,"evidence":"e"}],"recommended_action":"bump"}'
mkv v2_badaction '{"source_id":"x","verdict":"irrelevant","confidence":"high","depends_on_assessment":[{"aspect":"a","changed":false,"evidence":"e"}],"recommended_action":"nonsense"}'
mkv v3_noasset '{"source_id":"x","verdict":"compatible","confidence":"high","depends_on_assessment":[{"aspect":"a","changed":true,"evidence":"e"}],"proposed_delta":{"edits":[{"from":"a","to":"b","rationale":"r"}]},"recommended_action":"apply-delta-then-bump"}'
mkv v4_emptybreak '{"source_id":"x","verdict":"breaking","confidence":"high","depends_on_assessment":[{"aspect":"a","changed":true,"evidence":"e"}],"break":{"what":"","impact":"","human_decision_needed":""},"recommended_action":"escalate"}'
mkv vgood "$vgood"
bash "$REABSORB" --validate-verdict "$TMP/vgood.json" >/dev/null 2>&1;      assert_eq "V0 well-formed irrelevant VALID" "0" "$?"
bash "$REABSORB" --validate-verdict "$TMP/v1_noaspect.json" >/dev/null 2>&1; assert_eq "V1 missing aspect REJECTED" "1" "$?"
bash "$REABSORB" --validate-verdict "$TMP/v2_badaction.json" >/dev/null 2>&1;assert_eq "V2 bad recommended_action REJECTED" "1" "$?"
bash "$REABSORB" --validate-verdict "$TMP/v3_noasset.json" >/dev/null 2>&1;  assert_eq "V3 compatible missing asset REJECTED" "1" "$?"
bash "$REABSORB" --validate-verdict "$TMP/v4_emptybreak.json" >/dev/null 2>&1;assert_eq "V4 empty break fields REJECTED" "1" "$?"

echo "18) C3: body 'schema_version:' outside frontmatter is IGNORED (no false drift)"
rm -rf "$TMP/sources" "$TMP/mp"; mkdir -p "$TMP/sources/demo" "$TMP/mp/fixmp/plugins/demo/docs/reports/sample"
printf -- '---\nslug: sample\nschema_version: 3.2\n---\n# body\nschema_version: 9.9\n' > "$TMP/mp/fixmp/plugins/demo/docs/reports/sample/design.md"
mk_source "$TMP/sources/demo" "3.2" "1.0.0"; mk_installed "1.0.0"
out="$(run 2>&1)"; rc=$?
assert_contains "frontmatter 3.2 read (body 9.9 ignored)" "schema 3.2" "$out"
assert_eq "no false drift from body -> exit 0" "0" "$rc"

echo "19) C1: git-repo real ls-remote probe (hermetic local repo)"
GR="$TMP/gitrepo"; mkdir -p "$GR"; ( cd "$GR" && git init -q && git config user.email t@t && git config user.name t && echo x > f && git add f && git commit -qm init ) 2>/dev/null
SHA="$(git -C "$GR" rev-parse HEAD)"
rm -rf "$TMP/sources"; mkdir -p "$TMP/sources/gsrc"
printf '{"schema":1,"id":"gsrc","source_type":"git-repo","locator":{"repo":"%s"},"absorbed_version":{"commit":"%s"},"dependents":[{"asset":"a","depends_on":["x"],"break_if":["y"]}],"drift_probe":{"ref":"HEAD"}}' "$GR" "$SHA" > "$TMP/sources/gsrc/provenance.json"
out="$(OMC_SOURCES_DIR="$TMP/sources" OMC_MARKETPLACES_DIR="$TMP/mp" OMC_INSTALLED_PLUGINS="$TMP/installed.json" bash "$REABSORB" 2>&1)"; rc=$?
assert_contains "git-repo matching commit -> CURRENT" "CURRENT" "$out"; assert_eq "git-repo current -> exit 0" "0" "$rc"
# now record a wrong commit -> DRIFTED
printf '{"schema":1,"id":"gsrc","source_type":"git-repo","locator":{"repo":"%s"},"absorbed_version":{"commit":"0000000000000000000000000000000000000000"},"dependents":[{"asset":"a","depends_on":["x"],"break_if":["y"]}],"drift_probe":{"ref":"HEAD"}}' "$GR" > "$TMP/sources/gsrc/provenance.json"
out="$(OMC_SOURCES_DIR="$TMP/sources" OMC_MARKETPLACES_DIR="$TMP/mp" OMC_INSTALLED_PLUGINS="$TMP/installed.json" bash "$REABSORB" 2>&1)"; rc=$?
assert_contains "git-repo stale commit -> DRIFTED" "DRIFTED" "$out"; assert_eq "git-repo drift -> exit 5" "5" "$rc"

echo "20) C1: unpinned git-repo (< placeholder) -> UNKNOWN"
printf '{"schema":1,"id":"gsrc","source_type":"git-repo","locator":{"repo":"https://github.com/<owner>/<repo>"},"absorbed_version":{"commit":"<sha>"},"dependents":[{"asset":"a","depends_on":["x"],"break_if":["y"]}],"drift_probe":{"ref":"HEAD"}}' > "$TMP/sources/gsrc/provenance.json"
out="$(OMC_SOURCES_DIR="$TMP/sources" OMC_MARKETPLACES_DIR="$TMP/mp" OMC_INSTALLED_PLUGINS="$TMP/installed.json" bash "$REABSORB" 2>&1)"
assert_contains "unpinned git-repo -> UNKNOWN" "UNKNOWN" "$out"

echo "21) C2: --bump advances absorbed_at"
rm -rf "$TMP/sources"; mk_source "$TMP/sources/demo" "3.1" "1.0.0"; mk_mp "3.2"; mk_installed "1.0.0"
python3 - "$TMP/sources/demo/provenance.json" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d["absorbed_at"]="2000-01-01"; json.dump(d,open(p,"w"))
PY
run --bump demo >/dev/null 2>&1
at="$(python3 -c "import json;print(json.load(open('$TMP/sources/demo/provenance.json')).get('absorbed_at'))")"
case "$at" in 2000-01-01) bad "absorbed_at advanced on bump (still 2000-01-01)";; "") bad "absorbed_at missing";; *) ok "absorbed_at advanced on bump ($at)";; esac

echo "22) C3 robustness: CRLF-fenced frontmatter still parses"
rm -rf "$TMP/sources" "$TMP/mp"; mkdir -p "$TMP/sources/demo" "$TMP/mp/fixmp/plugins/demo/docs/reports/sample"
printf -- '---\r\nslug: s\r\nschema_version: 3.2\r\n---\r\n# body\r\n' > "$TMP/mp/fixmp/plugins/demo/docs/reports/sample/design.md"
mk_source "$TMP/sources/demo" "3.2" "1.0.0"; mk_installed "1.0.0"
out="$(run 2>&1)"; rc=$?
assert_contains "CRLF frontmatter schema 3.2 read" "schema 3.2" "$out"
assert_eq "CRLF -> CURRENT exit 0" "0" "$rc"

echo "23) C1 robustness: hand-recorded SHORT commit prefix -> CURRENT (startswith)"
GR2="$TMP/gitrepo2"; mkdir -p "$GR2"; ( cd "$GR2" && git init -q && git config user.email t@t && git config user.name t && echo y > g && git add g && git commit -qm init ) 2>/dev/null
SHORT="$(git -C "$GR2" rev-parse --short=12 HEAD)"
rm -rf "$TMP/sources"; mkdir -p "$TMP/sources/g2"
printf '{"schema":1,"id":"g2","source_type":"git-repo","locator":{"repo":"%s"},"absorbed_version":{"commit":"%s"},"dependents":[{"asset":"a","depends_on":["x"],"break_if":["y"]}],"drift_probe":{"ref":"HEAD"}}' "$GR2" "$SHORT" > "$TMP/sources/g2/provenance.json"
out="$(OMC_SOURCES_DIR="$TMP/sources" OMC_MARKETPLACES_DIR="$TMP/mp" OMC_INSTALLED_PLUGINS="$TMP/installed.json" bash "$REABSORB" 2>&1)"; rc=$?
assert_contains "short-SHA prefix -> CURRENT" "CURRENT" "$out"; assert_eq "short-SHA -> exit 0" "0" "$rc"

echo "24) git-repo PATH probe: tracks one file (blob), not repo HEAD -> no noise from unrelated commits"
GR3="$TMP/gitrepo3"; mkdir -p "$GR3"
( cd "$GR3" && git init -q && git config user.email t@t && git config user.name t && \
  echo "discipline v1" > SKILL.md && echo other > x.md && git add . && git commit -qm init ) 2>/dev/null
BLOB="blob:$(git -C "$GR3" rev-parse HEAD:SKILL.md)"
rm -rf "$TMP/sources"; mkdir -p "$TMP/sources/sp"
mkprov() { printf '{"schema":1,"id":"sp","source_type":"git-repo","locator":{"repo":"%s"},"absorbed_version":{"blob":"%s"},"dependents":[{"asset":"a","depends_on":["x"],"break_if":["y"]}],"drift_probe":{"kind":"git_blob","ref":"HEAD","path":"SKILL.md"}}' "$GR3" "$1" > "$TMP/sources/sp/provenance.json"; }
runsp() { OMC_SOURCES_DIR="$TMP/sources" bash "$REABSORB" "$@"; }
mkprov "$BLOB"
out="$(runsp 2>&1)"; assert_contains "path-probe recorded=current -> CURRENT" "CURRENT" "$out"
( cd "$GR3" && echo changed > x.md && git commit -qam "unrelated commit" ) 2>/dev/null   # HEAD moves, SKILL.md unchanged
out="$(runsp 2>&1)"; rc=$?
assert_contains "unrelated commit -> still CURRENT (file-level, no noise)" "CURRENT" "$out"
assert_eq "unrelated commit -> exit 0" "0" "$rc"
( cd "$GR3" && echo "discipline v2" > SKILL.md && git commit -qam "change tracked file" ) 2>/dev/null
out="$(runsp 2>&1)"; rc=$?
assert_contains "tracked file changed -> DRIFTED" "DRIFTED" "$out"; assert_eq "tracked file drift -> exit 5" "5" "$rc"
runsp --bump sp >/dev/null 2>&1
out="$(runsp 2>&1)"; assert_contains "after --bump -> CURRENT (records new blob)" "CURRENT" "$out"
mkprov "<run --bump to record>"
out="$(runsp 2>&1)"; assert_contains "unpinned blob placeholder -> UNKNOWN" "UNKNOWN" "$out"

APPLY="$ROOT/apply.sh"
DOCTOR="$ROOT/doctor.sh"
# synthetic patch triplet: mk_patch <patches_dir> <name> <target_rel> <baseline> <patched> <marker>
mk_patch() { local pd="$1/$2"; mkdir -p "$pd"
  printf '%s' "$3" > "$pd/target"; printf '%s' "$6" > "$pd/marker"
  printf '%b' "$4" > "$pd/baseline.md"; printf '%b' "$5" > "$pd/patched.md"
  printf 'v0.0.0' > "$pd/baseline-version"; }
mk_target() { mkdir -p "$(dirname "$1/$2")"; printf '%b' "$3" > "$1/$2"; }
NONEJSON="$TMP/none.json"   # nonexistent installed_plugins -> helper returns "" (hermetic, no real ~/.claude read)

echo "25) apply.sh dry-run CONFLICT writes nothing (+ fossil-rot meta-guard) [BLOCKER fossil]"
AP="$TMP/ap_conf"; PR="$TMP/apr_conf"; rm -rf "$AP" "$PR"; mkdir -p "$AP" "$PR"
mk_patch "$AP" p1 "agents/x.md" 'a\nSHARED\nc\n' 'a\nMYEDIT\nc\n' 'MYEDIT'
mk_target "$PR" "agents/x.md" 'a\nUPSTREAM\nc\n'
out="$(OMC_PATCHES_DIR="$AP" OMC_PATCH_ROOTS="$PR" OMC_INSTALLED_PLUGINS="$NONEJSON" bash "$APPLY" 2>&1)"; rc=$?
assert_contains "apply dry-run detects CONFLICT" "CONFLICT" "$out"
[ -f "$PR/agents/x.md.merge-conflict" ] && bad "dry-run wrote .merge-conflict (BLOCKER regressed)" || ok "apply.sh dry-run CONFLICT writes nothing"
assert_eq "apply CONFLICT dry-run rc 2" "2" "$rc"
git merge-file -p "$PR/agents/x.md" "$AP/p1/baseline.md" "$AP/p1/patched.md" >/dev/null 2>&1; mrc=$?
[ "$mrc" -ge 1 ] && ok "fossil-rot meta-guard: fixture still triggers a real CONFLICT" || bad "fixture no longer conflicts (fossil rot)"
OMC_PATCHES_DIR="$AP" OMC_PATCH_ROOTS="$PR" OMC_INSTALLED_PLUGINS="$NONEJSON" bash "$APPLY" --write >/dev/null 2>&1
[ -f "$PR/agents/x.md.merge-conflict" ] && ok "apply.sh --write DOES write .merge-conflict" || bad "--write failed to write .merge-conflict"

echo "26) apply.sh clean-but-drifted -> exit 5 [rec-1 fossil]"
AP2="$TMP/ap_drift"; PR2="$TMP/apr_drift"; rm -rf "$AP2" "$PR2"; mkdir -p "$AP2" "$PR2"
mk_patch "$AP2" p1 "agents/y.md" 'a\nSHARED\nc\n' 'a\nSHARED\nMYEDIT\n' 'MYEDIT'
mk_target "$PR2" "agents/y.md" 'UPSTREAM\nSHARED\nc\n'   # upstream edits line1, patch edits line3 -> clean + drift
out="$(OMC_PATCHES_DIR="$AP2" OMC_PATCH_ROOTS="$PR2" OMC_INSTALLED_PLUGINS="$NONEJSON" bash "$APPLY" 2>&1)"; rc=$?
assert_contains "drift noted as CLEAN(drift)" "CLEAN" "$out"
assert_eq "apply drift exits 5 (not 0)" "5" "$rc"

echo "27) apply.sh skew breadcrumb: active basename vs marketplace clone tag"
CACHE="$TMP/cache/omc/oh-my-claudecode/4.15.2"; mkdir -p "$CACHE"
printf '{"plugins":{"oh-my-claudecode@omc":[{"installPath":"%s"}]}}\n' "$CACHE" > "$TMP/inst_skew.json"
mkskewmp() { local d="$1" tag="$2"; mkdir -p "$d"; ( cd "$d" && git init -q && git config user.email t@t && git config user.name t && echo x>f && git add f && git commit -qm init && git tag "$tag" ) 2>/dev/null; }
mkskewmp "$TMP/mp_old" "v4.14.7"; mkskewmp "$TMP/mp_same" "v4.15.2"
mkdir -p "$TMP/nopatch"
out="$(OMC_PATCHES_DIR="$TMP/nopatch" OMC_INSTALLED_PLUGINS="$TMP/inst_skew.json" OMC_MARKETPLACE="$TMP/mp_old" bash "$APPLY" 2>&1)"
assert_contains "skew flagged (4.15.2 vs v4.14.7)" "⚠ SKEW" "$out"
out="$(OMC_PATCHES_DIR="$TMP/nopatch" OMC_INSTALLED_PLUGINS="$TMP/inst_skew.json" OMC_MARKETPLACE="$TMP/mp_same" bash "$APPLY" 2>&1)"
case "$out" in *"⚠ SKEW"*) bad "false skew on equal release (v4.15.2)";; *) ok "no skew on equal release (v4.15.2)";; esac

echo "28) doctor.sh matrix — combined exit per severity"
EMPTYSRC="$TMP/emptysrc"; mkdir -p "$EMPTYSRC"; NOPMP="$TMP/nomp"
dr() { OMC_INSTALLED_PLUGINS="$NONEJSON" OMC_MARKETPLACE="$NOPMP" OMC_MARKETPLACES_DIR="$NOPMP" bash "$DOCTOR" "$@"; }
# 28a: healthy — no patches, no sources -> 0
mkdir -p "$TMP/np" "$TMP/nr"
OMC_PATCHES_DIR="$TMP/np" OMC_PATCH_ROOTS="$TMP/nr" OMC_SOURCES_DIR="$EMPTYSRC" dr --quiet >/dev/null 2>&1; assert_eq "doctor healthy -> 0" "0" "$?"
# 28b: apply MISSING (patch target absent on root) -> doctor hard -> 2
APM="$TMP/ap_miss"; mkdir -p "$APM" "$TMP/nr2"; mk_patch "$APM" p1 "agents/gone.md" 'b\n' 'p\n' 'MARKER'
OMC_PATCHES_DIR="$APM" OMC_PATCH_ROOTS="$TMP/nr2" OMC_SOURCES_DIR="$EMPTYSRC" dr --quiet >/dev/null 2>&1; assert_eq "doctor apply-MISSING -> 2" "2" "$?"
# 28c: apply drift -> doctor soft -> 5
OMC_PATCHES_DIR="$AP2" OMC_PATCH_ROOTS="$PR2" OMC_SOURCES_DIR="$EMPTYSRC" dr --quiet >/dev/null 2>&1; assert_eq "doctor apply-drift -> 5" "5" "$?"
# 28d: source UNKNOWN (plugin not installed) -> doctor info -> 4  (NOT collapsed with MISSING)
USRC="$TMP/usrc"; mkdir -p "$USRC/demo"
printf '{"schema":1,"id":"demo","source_type":"installed-plugin","locator":{"plugin_key":"demo@x","plugin_path":"p"},"absorbed_version":{"plugin_version":"1.0.0"},"dependents":[{"asset":"a","depends_on":["x"],"break_if":["y"]}],"drift_probe":{}}' > "$USRC/demo/provenance.json"
printf '{"plugins":{}}\n' > "$TMP/inst_empty.json"
OMC_PATCHES_DIR="$TMP/np" OMC_PATCH_ROOTS="$TMP/nr" OMC_SOURCES_DIR="$USRC" OMC_INSTALLED_PLUGINS="$TMP/inst_empty.json" OMC_MARKETPLACE="$NOPMP" OMC_MARKETPLACES_DIR="$NOPMP" bash "$DOCTOR" --quiet >/dev/null 2>&1
assert_eq "doctor source-UNKNOWN -> 4 (not 2)" "4" "$?"

echo "29) doctor.sh --local-only SKIPPED + offline never-3"
GSRC="$TMP/gsrc_off"; mkdir -p "$GSRC/g"
printf '{"schema":1,"id":"g","source_type":"git-repo","locator":{"repo":"https://example.invalid/x"},"absorbed_version":{"commit":"deadbeef"},"dependents":[{"asset":"a","depends_on":["x"],"break_if":["y"]}],"drift_probe":{"ref":"HEAD"}}' > "$GSRC/g/provenance.json"
OMC_PATCHES_DIR="$TMP/np" OMC_PATCH_ROOTS="$TMP/nr" OMC_SOURCES_DIR="$GSRC" OMC_INSTALLED_PLUGINS="$NONEJSON" OMC_MARKETPLACE="$NOPMP" OMC_MARKETPLACES_DIR="$NOPMP" bash "$DOCTOR" --quiet >/dev/null 2>&1; rc=$?
assert_eq "doctor --local-only unreachable git-repo -> 4 (SKIPPED)" "4" "$rc"
[ "$rc" != "3" ] && ok "offline --quiet never exits 3" || bad "offline exited 3"

echo "30) doctor.sh is read-only: leaves sandbox (and thus real dirs) untouched"
SB="$TMP/sandbox"; rm -rf "$SB"; mkdir -p "$SB/patches" "$SB/root" "$SB/sources/demo"
printf '{"schema":1,"id":"demo","source_type":"installed-plugin","locator":{"plugin_key":"demo@x","plugin_path":"p"},"absorbed_version":{"plugin_version":"1.0.0"},"dependents":[{"asset":"a","depends_on":["x"],"break_if":["y"]}],"drift_probe":{}}' > "$SB/sources/demo/provenance.json"
snap() { find "$1" -type f -exec cksum {} \; | sort; }
before="$(snap "$SB")"
OMC_PATCHES_DIR="$SB/patches" OMC_PATCH_ROOTS="$SB/root" OMC_SOURCES_DIR="$SB/sources" OMC_INSTALLED_PLUGINS="$NONEJSON" OMC_MARKETPLACE="$NOPMP" OMC_MARKETPLACES_DIR="$NOPMP" bash "$DOCTOR" --quiet >/dev/null 2>&1
after="$(snap "$SB")"
assert_eq "doctor wrote nothing to sandbox" "$before" "$after"

echo
echo "== $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
