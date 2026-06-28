#!/usr/bin/env bash
# claude-overlay/patches/completion-gate/deploy.sh
# Post-deploy step for the completion-gate patch: idempotently register the
# completion-gate Stop hook in settings.json. Run by claude-overlay/apply.sh on
# --write, AFTER the hook file is mirrored into the hooks dir.
#
# settings.json is user-owned and survives OMC updates, so this is a one-time
# registration that stays put — re-running is a safe no-op (already-registered).
#
# Honors: OMC_HOOKS_DIR (where the hook was mirrored), OMC_SETTINGS (testing override).
set -euo pipefail

HOOKS_DIR="${OMC_HOOKS_DIR:-$HOME/.claude/hooks}"
SETTINGS="${OMC_SETTINGS:-$HOME/.claude/settings.json}"
DEST="$HOOKS_DIR/omc-completion-gate.mjs"
MARKER="omc-completion-gate.mjs"

# Resolve a concrete node binary (hooks may run without node on PATH).
NODE_BIN="$(command -v node || true)"
[ -z "$NODE_BIN" ] && NODE_BIN="node"

python3 - "$SETTINGS" "$NODE_BIN" "$DEST" "$MARKER" <<'PY'
import json, os, sys, shutil

settings_path, node_bin, dest, marker = sys.argv[1:5]

data = {}
if os.path.exists(settings_path):
    with open(settings_path) as f:
        data = json.load(f)

hooks = data.setdefault("hooks", {})
stop = hooks.setdefault("Stop", [])

def has_marker(arr):
    return any(marker in hk.get("command", "")
              for block in arr for hk in block.get("hooks", []))

if has_marker(stop):
    print("settings.json: already-registered")
    sys.exit(0)

stop.append({
    "matcher": "",
    "hooks": [{"type": "command", "command": f'"{node_bin}" "{dest}"', "timeout": 5}],
})
if os.path.exists(settings_path):
    shutil.copy2(settings_path, settings_path + ".bak")
os.makedirs(os.path.dirname(settings_path), exist_ok=True)
with open(settings_path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print("settings.json: registered (Stop hook)")
PY
