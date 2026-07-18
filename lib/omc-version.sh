#!/usr/bin/env bash
# claude-overlay/lib/omc-version.sh — shared OMC install resolver (bash side).
# The installed_plugins.json PARSE itself lives once in lib/omc_version.py (the single
# source, also imported by .reabsorb_core.py); this file just wraps it for bash callers
# (apply.sh, doctor.sh, upstream-changes.sh) and adds the skew helpers. Honors
# OMC_INSTALLED_PLUGINS (read by omc_version.py) so tests inject a fixture.
#
# Usage:
#   . lib/omc-version.sh
#   path="$(omc_active_installpath)"   # FULL installPath, or "" if absent
#   ver="$(basename "$path")"          # callers basename as needed

_OMC_VERSION_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Print the full installPath of the active oh-my-claudecode@omc plugin, or "" if the
# file/entry is missing. Delegates to the canonical parser. Never errors.
omc_active_installpath() {
  python3 "$_OMC_VERSION_LIB_DIR/omc_version.py" oh-my-claudecode@omc 2>/dev/null || printf ''
}

# Normalize a version label to its release core for skew comparison: strip a leading
# 'v' and any git-describe suffix (v4.15.2-3-gabc -> 4.15.2). So a cache basename
# (4.15.2) and a marketplace tag (v4.15.2) compare equal on the same release, and only
# a genuine cross-release skew (4.15.2 vs 4.14.7) flags.
omc_version_core() { local v="${1#v}"; printf '%s' "${v%%-*}"; }

# Print a diagnostic "versions: active=<v>  marketplace-clone=<v>  [⚠ SKEW]" line.
# $1 = marketplace clone dir (for `git describe`). Skew is a breadcrumb — it means the
# marketplace git clone lags the active cache, which makes upstream-changes.sh's git view
# stale vs the live install (SKILL.md step 2); it is NOT an apply/doctor correctness signal.
# Prints nothing when the active cache is not a real dir (e.g. OMC_PATCH_ROOTS override).
omc_print_versions() {
  local mp="$1" active_path active_ver clone_ver skew=""
  active_path="$(omc_active_installpath)"
  [ -n "$active_path" ] && [ -d "$active_path" ] || return 0
  active_ver="$(basename "$active_path")"
  clone_ver="$(git -C "$mp" describe --tags --always 2>/dev/null || echo '?')"
  [ "$clone_ver" != "?" ] && \
    [ "$(omc_version_core "$active_ver")" != "$(omc_version_core "$clone_ver")" ] && \
    skew="  ⚠ SKEW (marketplace clone lags active cache — upstream-changes.sh may be stale)"
  printf 'versions: active=%s  marketplace-clone=%s%s\n' "$active_ver" "$clone_ver" "$skew"
}
