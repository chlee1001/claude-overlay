#!/usr/bin/env bash
# claude-overlay/upstream-changes.sh
# Show what changed UPSTREAM in the files we patch, since the version each baseline was
# captured at. Run this right after an OMC update and BEFORE patching, so you know what
# to expect — especially which patches will CONFLICT (upstream touched our region) or go
# MISSING (file removed/renamed).
#
# Source of truth: the marketplace git clone of Yeachan-Heo/oh-my-claudecode (offline,
# precise — real commit messages + diffs). For cache-generated files not tracked in the
# repo, there is no history; apply.sh's 3-way merge surfaces those changes instead. If the
# git clone is unavailable, a GitHub compare URL is printed as a fallback.
#
# Read-only. Touches nothing.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCHES_DIR="${OMC_PATCHES_DIR:-$SCRIPT_DIR/patches}"
MP="${OMC_MARKETPLACE:-$HOME/.claude/plugins/marketplaces/omc}"
REPO_URL="https://github.com/Yeachan-Heo/oh-my-claudecode"

# active version via the shared canonical resolver (honors OMC_INSTALLED_PLUGINS)
. "$SCRIPT_DIR/lib/omc-version.sh"
CUR_VER="$(omc_active_installpath)"; CUR_VER="${CUR_VER:+$(basename "$CUR_VER")}"

have_git=0
git -C "$MP" rev-parse --git-dir >/dev/null 2>&1 && have_git=1
MP_HEAD="$(git -C "$MP" describe --tags --always 2>/dev/null || echo '?')"

echo "active version : ${CUR_VER:-unknown}    marketplace HEAD: ${MP_HEAD}"
echo "upstream repo  : $REPO_URL"
echo

drift_found=0

for pdir in "$PATCHES_DIR"/*/; do
  [ -d "$pdir" ] || continue
  name="$(basename "$pdir")"
  # Asset-only patches (no target — owned skills/rules/hooks only) have no upstream
  # plugin file to track; skip them, same as apply.sh's file-patch loop does.
  [ -f "$pdir/target" ] || continue
  rel="$(cat "$pdir/target")"
  bver="$(cat "$pdir/baseline-version" 2>/dev/null || echo '?')"
  echo "===== [$name] $rel  (baseline @ $bver) ====="

  if [ $have_git -eq 1 ] && git -C "$MP" cat-file -e "HEAD:$rel" 2>/dev/null; then
    range="${bver}..HEAD"
    if ! git -C "$MP" rev-parse --verify --quiet "$bver" >/dev/null 2>&1; then
      echo "  (baseline ref '$bver' not in repo; showing the last 20 commits instead)"
      range="HEAD~20..HEAD"
    fi
    commits="$(git -C "$MP" log --oneline "$range" -- "$rel" 2>/dev/null)"
    if [ -z "$commits" ]; then
      echo "  no upstream commits touched this file since $bver — should re-apply cleanly."
    else
      drift_found=1
      echo "  upstream commits since $bver:"
      echo "$commits" | sed 's/^/    /'
      echo "  diffstat:"
      git -C "$MP" diff --stat "$range" -- "$rel" 2>/dev/null | sed 's/^/    /'
      echo "  full diff:  git -C \"$MP\" diff $range -- $rel"
    fi
  else
    echo "  not tracked in the marketplace repo (cache-generated) — no commit history."
    echo "  apply.sh's 3-way merge will show any change; for a raw view, diff this patch's"
    echo "  baseline.md against the new file directly."
  fi
  echo
done

if [ $have_git -eq 0 ]; then
  echo "NOTE: marketplace git clone not found at $MP."
  echo "      Inspect upstream changes on the web: $REPO_URL/compare/<oldtag>...<newtag>"
elif [ $drift_found -eq 0 ]; then
  echo "Summary: no upstream changes to any patched file since baseline. Patching should be clean."
else
  echo "Summary: some files drifted upstream (see above). Expect CLEAN(drift) or CONFLICT;"
  echo "         use the diffs above to resolve conflicts, then advance baselines."
fi
