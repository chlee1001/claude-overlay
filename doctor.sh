#!/usr/bin/env bash
# claude-overlay/doctor.sh — one read-only health verdict over the whole overlay.
# Consolidates the two authoritative drift engines:
#   apply.sh   (dry-run)  → OMC file patches + owned-asset deploy state
#   reabsorb.sh (detect)  → absorbed-source contract drift
# and a version-skew breadcrumb (active cache vs marketplace clone). READ-ONLY BY
# CONSTRUCTION: there is no --write path here — that is the whole point (a health check
# a SessionStart hook runs every session must never mutate anything).
#
# Usage:
#   ./doctor.sh            full audit — runs both children (reabsorb hits the network for
#                          git-repo sources); prints child reports + a combined verdict.
#   ./doctor.sh --quiet    one verdict line + exit code only, and passes --local-only to
#                          reabsorb (skips git-repo network probes). This is the fast,
#                          offline-safe path intended for the phase-2 SessionStart hook.
#
# Combined exit (severity, highest wins: error > hard > soft > info > ok):
#   3  tooling error        (apply 3 · reabsorb 3)
#   2  hard action now      (apply 2=CONFLICT · apply 4=MISSING customization)
#   5  soft drift           (apply 5 · reabsorb 5=DRIFTED)
#   4  informational        (reabsorb 4=UNKNOWN/SKIPPED — source not installed / probe deferred)
#   0  healthy
# A clean --quiet run exits 4 by design: its git-repo sources are structurally SKIPPED,
# so freshness is "unknown", not "healthy".
#
# simplification: the offline-never-3 guarantee is scoped to --quiet (SKIPPED never errors).
# A full ./doctor.sh that cannot reach the network surfaces reabsorb's ERROR as doctor 3
# (honest: it genuinely could not verify). Upgrade path: teach reabsorb a NETWORK_ERROR
# state distinct from ERROR, then map network→4 in the full path too.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib/omc-version.sh"

QUIET=0
for arg in "$@"; do
  case "$arg" in
    --quiet) QUIET=1 ;;
    -h|--help) sed -n '2,32p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown arg: $arg" >&2; exit 64 ;;
  esac
done

# Children inherit our env overrides (tests) or the real defaults. apply.sh reads
# OMC_PATCH_ROOTS/OMC_PATCHES_DIR/OMC_INSTALLED_PLUGINS/OMC_MARKETPLACE; reabsorb reads
# OMC_SOURCES_DIR/OMC_INSTALLED_PLUGINS/OMC_MARKETPLACES_DIR. Export all so both agree.
export OMC_INSTALLED_PLUGINS="${OMC_INSTALLED_PLUGINS:-$HOME/.claude/plugins/installed_plugins.json}"
export OMC_SOURCES_DIR="${OMC_SOURCES_DIR:-$SCRIPT_DIR/sources}"
export OMC_MARKETPLACE="${OMC_MARKETPLACE:-$HOME/.claude/plugins/marketplaces/omc}"
export OMC_MARKETPLACES_DIR="${OMC_MARKETPLACES_DIR:-$HOME/.claude/plugins/marketplaces}"
# OMC_PATCHES_DIR / OMC_PATCH_ROOTS pass through unchanged if the caller set them.

# --- run both children (read-only), capture output + rc -------------------------------
apply_out="$(bash "$SCRIPT_DIR/apply.sh" 2>&1)"; apply_rc=$?
reab_args=""; [ $QUIET -eq 1 ] && reab_args="--local-only"
reab_out="$(bash "$SCRIPT_DIR/reabsorb.sh" $reab_args 2>&1)"; reab_rc=$?

# --- map each child rc → a doctor severity token --------------------------------------
# apply: 0 ok · 2 CONFLICT=hard · 3 error · 4 MISSING=hard · 5 drift=soft
apply_sev() { case "$1" in 0) echo ok;; 2) echo hard;; 4) echo hard;; 5) echo soft;; 3) echo error;; *) echo error;; esac; }
# reabsorb: 0 ok · 2 BREAKING=hard · 3 error · 4 UNKNOWN/SKIPPED=info · 5 DRIFTED=soft
reab_sev()  { case "$1" in 0) echo ok;; 2) echo hard;; 4) echo info;; 5) echo soft;; 3) echo error;; *) echo error;; esac; }
sev_rank()  { case "$1" in ok) echo 0;; info) echo 1;; soft) echo 2;; hard) echo 3;; error) echo 4;; esac; }
sev_code()  { case "$1" in ok) echo 0;; info) echo 4;; soft) echo 5;; hard) echo 2;; error) echo 3;; esac; }
sev_text()  { case "$1" in
    ok)    echo "HEALTHY — patches applied, sources current";;
    info)  echo "OK (informational) — some sources not installed or probe deferred (--local-only)";;
    soft)  echo "DRIFT — a patch or source moved; re-baseline (apply.sh --update-baseline) or re-absorb";;
    hard)  echo "ACTION NEEDED — a CONFLICT, or a patch target MISSING (customization not applied)";;
    error) echo "ERROR — a child tool failed; verdict untrustworthy until resolved";;
  esac; }

sa="$(apply_sev "$apply_rc")"; sr="$(reab_sev "$reab_rc")"
worst="$sa"; [ "$(sev_rank "$sr")" -gt "$(sev_rank "$worst")" ] && worst="$sr"
doctor_rc="$(sev_code "$worst")"

# --- output ---------------------------------------------------------------------------
if [ $QUIET -eq 1 ]; then
  echo "overlay: $(sev_text "$worst")  [apply rc=$apply_rc · sources rc=$reab_rc → doctor $doctor_rc]"
  exit "$doctor_rc"
fi

echo "== claude-overlay doctor =="
omc_print_versions "$OMC_MARKETPLACE"
echo
echo "--- patches (apply.sh dry-run, rc=$apply_rc) ---"
printf '%s\n' "$apply_out" | grep -E '^(versions:|OK |APPLY |CLEAN |CONFLICT |ERROR |MISSING |INSTALL |UPDATE |REMINDER:|WARNING:)' | sed 's/^/  /' || true
echo
echo "--- sources (reabsorb.sh detect, rc=$reab_rc) ---"
printf '%s\n' "$reab_out" | sed 's/^/  /'
echo
echo "verdict: $(sev_text "$worst")"
echo "exit: $doctor_rc  (apply rc=$apply_rc, sources rc=$reab_rc)"
exit "$doctor_rc"
