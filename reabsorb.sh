#!/usr/bin/env bash
# claude-overlay/reabsorb.sh
# Re-absorption drift detector for absorbed external sources (categories B/C).
# Sibling to apply.sh: apply.sh re-merges OMC-file patches; reabsorb.sh detects when
# an EXTERNAL source we derived an owned asset from has moved past what we recorded,
# and drives OMC-architect triage + human-gated re-absorption.
#
# Design: docs/reabsorb-design.md (8 decisions locked 2026-06-30).
#
# Modes (default = read-only dry-run; writes require explicit flags):
#   reabsorb.sh                      detect  — status table for every sources/*, no writes
#   reabsorb.sh --triage <id>        preview — assemble the architect triage packet, no writes/calls
#   reabsorb.sh --bump [--dry-run] <id>      advance recorded absorbed_version to current
#   reabsorb.sh --validate-verdict <file>    validate an architect triage verdict JSON
#   reabsorb.sh --local-only                 detect, but SKIP git-repo network probes
#                                            (git-repo sources report SKIPPED). Fast/offline —
#                                            used by doctor.sh --quiet for a per-session nudge.
#
# Testability (env overrides — never touch real ~/.claude in tests):
#   OMC_SOURCES_DIR        default: <script>/sources
#   OMC_INSTALLED_PLUGINS  default: ~/.claude/plugins/installed_plugins.json
#   OMC_MARKETPLACES_DIR   default: ~/.claude/plugins/marketplaces
#
# Exit codes (severity, highest wins): 0 all CURRENT · 2 ≥1 BREAKING · 3 probe ERROR
#   · 4 ≥1 UNKNOWN · 5 ≥1 DRIFTED (action needed).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export OMC_SOURCES_DIR="${OMC_SOURCES_DIR:-$SCRIPT_DIR/sources}"
export OMC_INSTALLED_PLUGINS="${OMC_INSTALLED_PLUGINS:-$HOME/.claude/plugins/installed_plugins.json}"
export OMC_MARKETPLACES_DIR="${OMC_MARKETPLACES_DIR:-$HOME/.claude/plugins/marketplaces}"

PYCORE="$SCRIPT_DIR/.reabsorb_core.py"
if [ ! -f "$PYCORE" ]; then
  echo "ERROR: missing core $PYCORE" >&2
  exit 3
fi

usage() { sed -n '2,26p' "${BASH_SOURCE[0]}"; }

MODE="detect"
ARG=""
DRYRUN=0
LOCAL_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --triage) MODE="triage"; ARG="${2:-}"; shift 2 || shift ;;
    --bump) MODE="bump"; shift ;;
    --dry-run) DRYRUN=1; shift ;;
    --local-only) LOCAL_ONLY=1; shift ;;
    --validate-verdict) MODE="validate"; ARG="${2:-}"; shift 2 || shift ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "unknown flag: $1" >&2; exit 64 ;;
    *) ARG="$1"; shift ;;
  esac
done

export REABSORB_DRYRUN="$DRYRUN"
export REABSORB_LOCAL_ONLY="$LOCAL_ONLY"
python3 "$PYCORE" "$MODE" "$ARG"
exit $?
