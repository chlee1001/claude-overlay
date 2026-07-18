#!/usr/bin/env bash
# claude-overlay/lib/omc-version.sh — shared OMC install resolver.
# Single canonical parse of installed_plugins.json, sourced by apply.sh + doctor.sh
# (rule-of-three: apply.sh, upstream-changes.sh, .reabsorb_core.py already each had
# their own copy). Honors OMC_INSTALLED_PLUGINS so tests inject a fixture instead of
# touching real ~/.claude.
#
# Usage:
#   . lib/omc-version.sh
#   path="$(omc_active_installpath)"   # FULL installPath, or "" if absent
#   ver="$(basename "$path")"          # callers basename as needed

# Print the full installPath of the active oh-my-claudecode@omc plugin, or "" if the
# file/entry is missing. Never errors — absence is empty output, exit 0.
omc_active_installpath() {
  local f="${OMC_INSTALLED_PLUGINS:-$HOME/.claude/plugins/installed_plugins.json}"
  [ -f "$f" ] || { printf ''; return 0; }
  python3 -c "
import json,sys
try:
    d=json.load(open('$f'))
except Exception:
    print(''); sys.exit(0)
plugins=d.get('plugins', d)
e=plugins.get('oh-my-claudecode@omc',[])
paths=[x.get('installPath','') for x in e if x.get('installPath')]
print(paths[0] if paths else '')
" 2>/dev/null || printf ''
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
