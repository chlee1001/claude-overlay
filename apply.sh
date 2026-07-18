#!/usr/bin/env bash
# claude-overlay/apply.sh
# Re-apply local OMC patches onto the currently-active plugin version using a
# 3-way merge (git merge-file). Preserves upstream changes; surfaces conflicts.
#
# Model per patch (patches/<name>/):
#   baseline.md  pristine upstream file at the version we patched against
#   patched.md   baseline.md + our local edits
#   target       relative path of the file under each OMC root (e.g. agents/git-master.md)
#   marker       unique string proving our patch is already present
#
# 3-way merge:  current = NEW upstream (pristine)   base = baseline.md   other = patched.md
#   git merge-file exit code: 0 = clean, 1..127 = that many conflicts, <0 (>=128) = error
#
# Usage:
#   ./apply.sh                  # dry-run: report only, write nothing (DEFAULT)
#   ./apply.sh --write          # apply clean merges; write .merge-conflict for conflicts
#   ./apply.sh --write --update-baseline
#                               # after a clean apply where upstream drifted, advance
#                               # baseline.md := new pristine, patched.md := merged result
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCHES_DIR="${OMC_PATCHES_DIR:-$SCRIPT_DIR/patches}"
# shared installed-plugins resolver + version-core normalizer (honors OMC_INSTALLED_PLUGINS)
. "$SCRIPT_DIR/lib/omc-version.sh"
WRITE=0
UPDATE_BASELINE=0

for arg in "$@"; do
  case "$arg" in
    --write) WRITE=1 ;;
    --update-baseline) UPDATE_BASELINE=1; WRITE=1 ;;
    -h|--help) sed -n '2,30p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown arg: $arg" >&2; exit 64 ;;
  esac
done

# --- Resolve OMC roots: active cache install + marketplace source ---
# Active install path via the shared resolver (honors OMC_INSTALLED_PLUGINS for tests).
ACTIVE_CACHE="$(omc_active_installpath)"
MARKETPLACE="${OMC_MARKETPLACE:-$HOME/.claude/plugins/marketplaces/omc}"

# Version label (active cache folder name), stamped into baseline-version on advance.
# Captured from the resolved install path BEFORE the override clobbers ACTIVE_CACHE so it
# stays correct under OMC_PATCH_ROOTS testing; OMC_PATCH_VERSION can force it explicitly.
CURRENT_VERSION="${OMC_PATCH_VERSION:-}"
[ -z "$CURRENT_VERSION" ] && [ -n "$ACTIVE_CACHE" ] && [ -d "$ACTIVE_CACHE" ] && CURRENT_VERSION="$(basename "$ACTIVE_CACHE")"

ROOTS=()
if [ -n "${OMC_PATCH_ROOTS:-}" ]; then
  # testing/advanced override: colon-separated list of OMC roots
  IFS=':' read -r -a ROOTS <<< "$OMC_PATCH_ROOTS"
  ACTIVE_CACHE="(override)"
else
  [ -n "$ACTIVE_CACHE" ] && [ -d "$ACTIVE_CACHE" ] && ROOTS+=("$ACTIVE_CACHE")
  [ -d "$MARKETPLACE" ] && ROOTS+=("$MARKETPLACE")
fi

if [ "${#ROOTS[@]}" -eq 0 ]; then
  echo "ERROR: no OMC roots found (checked installed_plugins.json + marketplace)" >&2
  exit 1
fi

echo "mode: $([ $WRITE -eq 1 ] && echo WRITE || echo DRY-RUN)$([ $UPDATE_BASELINE -eq 1 ] && echo ' +update-baseline')"
echo "active cache: ${ACTIVE_CACHE:-<none>}"
# skew breadcrumb (DIAGNOSTIC ONLY — apply's on-disk dry-run is authoritative). See helper.
omc_print_versions "$MARKETPLACE"
echo "roots: ${#ROOTS[@]}"
echo

had_conflict=0
had_error=0
drift_names=()     # drifted + merged clean but baseline NOT advanced
missing_names=()   # target file absent in this version (agent removed or renamed)

for pdir in "$PATCHES_DIR"/*/; do
  [ -d "$pdir" ] || continue
  name="$(basename "$pdir")"
  # Folders with no `target` are pure owned-asset bundles (rules/ or skill/ only) —
  # the file-patch step is skipped; the owned-skills/rules passes below still handle them.
  [ -f "$pdir/target" ] || continue
  target_rel="$(cat "$pdir/target")"
  marker="$(cat "$pdir/marker")"
  baseline="$pdir/baseline.md"
  patched="$pdir/patched.md"

  found_on_any=0
  for root in "${ROOTS[@]}"; do
    target="$root/$target_rel"
    label="[$name] $target"

    if [ ! -f "$target" ]; then
      # A target may legitimately be absent on some roots (e.g. marketplace has no
      # skill-bodies/). Don't warn here — decide after all roots are checked.
      continue
    fi
    found_on_any=1
    if grep -qF "$marker" "$target"; then
      echo "OK    $label (already patched)"
      continue
    fi

    # target is pristine NEW upstream. detect drift vs our baseline.
    drift=0
    diff -q "$target" "$baseline" >/dev/null 2>&1 || drift=1

    merged="$(mktemp)"
    git merge-file -p --diff3 \
      -L "upstream-new" -L "baseline" -L "my-patch" \
      "$target" "$baseline" "$patched" > "$merged"
    status=$?

    if [ "$status" -eq 0 ]; then
      note="$([ $drift -eq 1 ] && echo 'upstream drifted, merged cleanly' || echo 'upstream unchanged')"
      if [ $WRITE -eq 1 ]; then
        pristine="$(mktemp)"; cp "$target" "$pristine"
        cp "$merged" "$target"
        echo "APPLY $label ($note)"
        if [ $drift -eq 1 ]; then
          if [ $UPDATE_BASELINE -eq 1 ]; then
            cp "$pristine" "$baseline"
            cp "$merged" "$patched"
            [ -n "$CURRENT_VERSION" ] && printf 'v%s' "$CURRENT_VERSION" > "$pdir/baseline-version"
            echo "      ↳ baseline advanced (baseline:=new upstream, patched:=merged, version:=v${CURRENT_VERSION:-?})"
          else
            echo "      ↳ baseline NOT advanced — still at old version; re-run with --update-baseline"
            drift_names+=("$name")
          fi
        fi
        rm -f "$pristine"
      else
        echo "CLEAN $label ($note) — would apply"
        if [ $drift -eq 1 ]; then
          echo "      ↳ note: upstream changed this file since baseline; review then --update-baseline"
          drift_names+=("$name")
        fi
      fi
    elif [ "$status" -ge 1 ] && [ "$status" -le 127 ]; then
      cfile="$target.merge-conflict"
      echo "CONFLICT $label — $status region(s); upstream touched patched lines"
      if [ $WRITE -eq 1 ]; then
        cp "$merged" "$cfile"
        echo "      ↳ wrote $cfile (resolve, then copy onto target)"
      else
        # dry-run must write NOTHING (docstring contract). Only --write materializes it.
        echo "      ↳ would write $cfile on --write (dry-run: nothing written)"
      fi
      had_conflict=1
    else
      echo "ERROR $label — git merge-file failed (status $status)"
      had_error=1
    fi
    rm -f "$merged"
  done
  if [ $found_on_any -eq 0 ]; then
    echo "MISSING [$name] target '$target_rel' not found in ANY root — removed or renamed upstream?"
    missing_names+=("$name")
  fi
done

# --- Install "owned" skills bundled with patches (patches/<name>/skill/<skillname>/) ---
# Unlike plugin files (3-way merged), these are files WE own: mirror them verbatim into
# the skills dir so a lost skill is restored by the same apply.sh run.
SKILLS_DIR="${OMC_SKILLS_DIR:-$HOME/.claude/skills}"
echo
echo "owned skills -> $SKILLS_DIR"
for sdir in "$PATCHES_DIR"/*/skill/*/; do
  [ -d "$sdir" ] || continue
  sname="$(basename "$sdir")"
  pname="$(basename "$(dirname "$(dirname "$sdir")")")"
  dest="$SKILLS_DIR/$sname"
  label="[$pname] skill:$sname"

  if [ -d "$dest" ] && diff -rq "$sdir" "$dest" >/dev/null 2>&1; then
    echo "OK    $label (skill up-to-date)"
    continue
  fi
  action="INSTALL"; [ -d "$dest" ] && action="UPDATE"
  if [ $WRITE -eq 1 ]; then
    mkdir -p "$dest"
    cp -R "$sdir." "$dest/"
    echo "$action $label -> $dest"
  else
    echo "$action $label -> $dest — would $(echo "$action" | tr '[:upper:]' '[:lower:]')"
  fi
done

# --- Install "owned" rule files bundled with patches (patches/<name>/rules/<file>) ---
# Rule docs WE fully own: mirror them verbatim into the rules dir, same model as owned skills.
RULES_DIR="${OMC_RULES_DIR:-$HOME/.claude/rules}"
echo
echo "owned rules -> $RULES_DIR"
for rfile in "$PATCHES_DIR"/*/rules/*; do
  [ -f "$rfile" ] || continue
  rname="$(basename "$rfile")"
  pname="$(basename "$(dirname "$(dirname "$rfile")")")"
  dest="$RULES_DIR/$rname"
  label="[$pname] rule:$rname"
  if [ -f "$dest" ] && diff -q "$rfile" "$dest" >/dev/null 2>&1; then
    echo "OK    $label (rule up-to-date)"
    continue
  fi
  action="INSTALL"; [ -f "$dest" ] && action="UPDATE"
  if [ $WRITE -eq 1 ]; then
    mkdir -p "$RULES_DIR"
    cp "$rfile" "$dest"
    echo "$action $label -> $dest"
  else
    echo "$action $label -> $dest — would $(echo "$action" | tr '[:upper:]' '[:lower:]')"
  fi
done

# --- Install "owned" hook files bundled with patches (patches/<name>/hooks/<file>) ---
# Hook scripts WE own: mirror them verbatim into the hooks dir, same model as owned skills/rules.
HOOKS_DIR="${OMC_HOOKS_DIR:-$HOME/.claude/hooks}"
echo
echo "owned hooks -> $HOOKS_DIR"
for hfile in "$PATCHES_DIR"/*/hooks/*; do
  [ -f "$hfile" ] || continue
  hname="$(basename "$hfile")"
  pname="$(basename "$(dirname "$(dirname "$hfile")")")"
  dest="$HOOKS_DIR/$hname"
  label="[$pname] hook:$hname"
  if [ -f "$dest" ] && diff -q "$hfile" "$dest" >/dev/null 2>&1; then
    echo "OK    $label (hook up-to-date)"
    continue
  fi
  action="INSTALL"; [ -f "$dest" ] && action="UPDATE"
  if [ $WRITE -eq 1 ]; then
    mkdir -p "$HOOKS_DIR"
    cp "$hfile" "$dest"
    chmod +x "$dest"
    echo "$action $label -> $dest"
  else
    echo "$action $label -> $dest — would $(echo "$action" | tr '[:upper:]' '[:lower:]')"
  fi
done

# --- Run per-patch deploy steps (patches/<name>/deploy.sh) ---
# Some assets need more than a verbatim copy — e.g. registering a hook in the shared,
# user-owned settings.json. A patch's deploy.sh does that idempotently; it runs only on
# --write (after assets are mirrored), is given OMC_HOOKS_DIR, and a re-run must be a safe
# no-op. Dry-run only reports that it would run.
echo
echo "deploy steps"
for dscript in "$PATCHES_DIR"/*/deploy.sh; do
  [ -f "$dscript" ] || continue
  pname="$(basename "$(dirname "$dscript")")"
  if [ $WRITE -eq 1 ]; then
    echo "RUN   [$pname] deploy.sh"
    if OMC_HOOKS_DIR="$HOOKS_DIR" bash "$dscript" 2>&1 | sed 's/^/      /'; then :; else
      echo "      ↳ deploy failed"; had_error=1
    fi
  else
    echo "PLAN  [$pname] deploy.sh — would run on --write"
  fi
done

# --- Refresh the inventory map so it never goes stale after a deploy ---
# INVENTORY.md is derived from provenance + patches; regenerate on every --write so a newly
# absorbed skill shows up without anyone remembering to run inventory.sh by hand.
if [ $WRITE -eq 1 ] && [ -x "$SCRIPT_DIR/inventory.sh" ]; then
  echo
  "$SCRIPT_DIR/inventory.sh" >/dev/null 2>&1 && echo "inventory: INVENTORY.md refreshed"
fi

# --- Reminder: drifted patches whose baseline was left stale ---
if [ "${#drift_names[@]}" -gt 0 ]; then
  uniq_names="$(printf '%s\n' "${drift_names[@]}" | sort -u | tr '\n' ' ')"
  echo
  echo "REMINDER: upstream drifted on: ${uniq_names}"
  echo "          baseline is still pinned to the old version. Re-run with --update-baseline"
  echo "          so future merges stay trivial (a stale baseline invites needless conflicts)."
fi

# --- Warning: defined patches whose target file vanished (removed or renamed upstream) ---
if [ "${#missing_names[@]}" -gt 0 ]; then
  uniq_missing="$(printf '%s\n' "${missing_names[@]}" | sort -u | tr '\n' ' ')"
  echo
  echo "WARNING: target file missing for: ${uniq_missing}"
  echo "         These patches are defined but their target no longer exists in this version."
  echo "         The upstream agent/file was likely removed or renamed — our customization is"
  echo "         NOT being applied. Check the new version's tree, then retarget or retire the patch."
fi

# --- Exit code by severity: error(3) > conflict(2) > missing(4) > drift(5) > ok(0) ---
# Sequential assignment, last match wins; drift is FIRST so any harder state overrides it.
# drift(5) makes apply's rc honest for callers (doctor, a SessionStart hook) — a clean-but-
# drifted run used to exit 0 despite the REMINDER, hiding the need to --update-baseline.
rc=0
[ "${#drift_names[@]}" -gt 0 ] && rc=5
[ "${#missing_names[@]}" -gt 0 ] && rc=4
[ $had_conflict -eq 1 ] && rc=2
[ $had_error -eq 1 ] && rc=3
exit $rc
